import Foundation

/// Manages grid layout: validates placements, detects collisions, finds available cells.
@MainActor
public final class LayoutEngine: ObservableObject {
    public struct SettingsFocus: Equatable {
        public let pageId: String
        public let instanceId: String
        public init(pageId: String, instanceId: String) {
            self.pageId = pageId
            self.instanceId = instanceId
        }
    }

    @Published public var document: LayoutDocument
    @Published public var currentPageIndex: Int = 0
    /// The one entry point for changing pages. With offset-based paging the
    /// travel direction is pure geometry, so this is a plain clamped set;
    /// callers wrap it in withAnimation when the move should slide.
    public func navigate(to target: Int) {
        let clamped = min(max(target, 0), max(pageCount - 1, 0))
        guard clamped != currentPageIndex else { return }
        currentPageIndex = clamped
    }
    /// Increments on every layout mutation (widget add/remove/move). Used to trigger service activation updates.
    @Published public var layoutVersion: Int = 0
    /// One-shot deep link from a widget's hover gear into Settings: the
    /// settings views consume it (Pages tab, page selected, widget row
    /// scrolled into view) and clear it.
    @Published public var settingsFocus: SettingsFocus?
    /// True while the dashboard is in edit mode. Placement rules relax so
    /// widgets can overlap as a staging state while rearranging; store writes
    /// pause until the session ends, and a session cannot end (or flush at
    /// quit) while overlaps remain, so an overlapping layout is never
    /// persisted.
    @Published public var isEditing: Bool = false {
        didSet {
            // Entering a session: persist the clean pre-session state first,
            // so a write debounced moments earlier can't be swallowed by the
            // session's write suppression.
            if isEditing && !oldValue { flushSave() }
        }
    }
    /// Current dynamic grid — updated from DashboardShell's GeometryReader.
    @Published public var currentGrid: DynamicGrid = .xeneonDefault

    private let store: LayoutStore

    public init(store: LayoutStore) {
        self.store = store
        self.document = store.load()
    }

    // MARK: - Current Page

    public var currentPage: PageConfig? {
        let sorted = sortedPages
        guard currentPageIndex >= 0, currentPageIndex < sorted.count else { return nil }
        return sorted[currentPageIndex]
    }

    public var sortedPages: [PageConfig] {
        document.pages.sorted { $0.order < $1.order }
    }

    public var pageCount: Int {
        document.pages.count
    }

    // MARK: - Page CRUD

    public func addPage(name: String) {
        let maxOrder = document.pages.map(\.order).max() ?? -1
        let page = PageConfig(name: name, order: maxOrder + 1)
        document.pages.append(page)
        save()
    }

    public func removePage(id: String) {
        document.pages.removeAll { $0.id == id }
        reindexPages()
        if currentPageIndex >= pageCount {
            currentPageIndex = max(0, pageCount - 1)
        }
        save()
    }

    public func renamePage(id: String, name: String) {
        guard let index = pageIndex(for: id) else { return }
        document.pages[index].name = name
        save()
    }

    public func movePage(id: String, toOrder: Int) {
        guard let index = pageIndex(for: id) else { return }
        // The dashboard tracks the current page by index into sortedPages, so
        // remember which page is showing and follow it to its new position —
        // otherwise reordering silently changes what's on screen.
        let activeId = currentPage?.id
        let page = document.pages.remove(at: index)
        // Normalize to order-sorted before inserting: array position and the
        // persisted `order` field are usually in lockstep (reindexPages), but
        // an imported or hand-edited document may disagree, and this method is
        // user-reachable now.
        var ordered = document.pages.sorted { $0.order < $1.order }
        let clampedOrder = min(max(toOrder, 0), ordered.count)
        ordered.insert(page, at: clampedOrder)
        document.pages = ordered
        reindexPages()
        if let activeId, let newIdx = sortedPages.firstIndex(where: { $0.id == activeId }),
           currentPageIndex != newIdx {
            currentPageIndex = newIdx
        }
        save()
    }

    // MARK: - Widget Placement

    /// Place a widget on a page. Returns the instance ID on success, nil if invalid.
    @discardableResult
    public func placeWidget(
        pageId: String,
        widgetId: String,
        col: Int,
        row: Int,
        width: Int,
        height: Int,
        config: WidgetConfig = WidgetConfig()
    ) -> String? {
        guard let pageIdx = pageIndex(for: pageId) else { return nil }

        let rect = GridRect(col: col, row: row, width: width, height: height)
        guard rect.fitsInGrid(columns: currentGrid.columns, rows: currentGrid.rows) else { return nil }

        let existing = document.pages[pageIdx].widgets
        guard isEditing || !existing.contains(where: { $0.gridRect.intersects(rect) }) else { return nil }

        let placement = WidgetPlacement(
            widgetId: widgetId,
            col: col,
            row: row,
            width: width,
            height: height,
            config: config
        )
        document.pages[pageIdx].widgets.append(placement)
        save()
        return placement.instanceId
    }

    /// Remove a widget instance from a page.
    public func removeWidget(pageId: String, instanceId: String) {
        guard let pageIdx = pageIndex(for: pageId) else { return }
        document.pages[pageIdx].widgets.removeAll { $0.instanceId == instanceId }
        save()
    }

    /// Move a widget to a new position. Returns true on success.
    @discardableResult
    public func moveWidget(pageId: String, instanceId: String, toCol: Int, toRow: Int) -> Bool {
        guard let pageIdx = pageIndex(for: pageId),
              let widgetIdx = widgetIndex(pageIndex: pageIdx, instanceId: instanceId) else { return false }

        let widget = document.pages[pageIdx].widgets[widgetIdx]
        let newRect = GridRect(col: toCol, row: toRow, width: widget.width, height: widget.height)

        guard newRect.fitsInGrid(columns: currentGrid.columns, rows: currentGrid.rows) else { return false }

        // Check collision with all other widgets on the page
        let others = document.pages[pageIdx].widgets.filter { $0.instanceId != instanceId }
        guard isEditing || !others.contains(where: { $0.gridRect.intersects(newRect) }) else { return false }

        document.pages[pageIdx].widgets[widgetIdx].col = toCol
        document.pages[pageIdx].widgets[widgetIdx].row = toRow
        save()
        return true
    }

    /// Resize a widget. Returns true on success.
    @discardableResult
    public func resizeWidget(pageId: String, instanceId: String, newWidth: Int, newHeight: Int) -> Bool {
        guard let pageIdx = pageIndex(for: pageId),
              let widgetIdx = widgetIndex(pageIndex: pageIdx, instanceId: instanceId) else { return false }

        let widget = document.pages[pageIdx].widgets[widgetIdx]
        let newRect = GridRect(col: widget.col, row: widget.row, width: newWidth, height: newHeight)

        guard newRect.fitsInGrid(columns: currentGrid.columns, rows: currentGrid.rows) else { return false }

        let others = document.pages[pageIdx].widgets.filter { $0.instanceId != instanceId }
        guard isEditing || !others.contains(where: { $0.gridRect.intersects(newRect) }) else { return false }

        document.pages[pageIdx].widgets[widgetIdx].width = newWidth
        document.pages[pageIdx].widgets[widgetIdx].height = newHeight
        save()
        return true
    }

    /// Update widget config.
    public func updateWidgetConfig(pageId: String, instanceId: String, config: WidgetConfig) {
        guard let pageIdx = pageIndex(for: pageId),
              let widgetIdx = widgetIndex(pageIndex: pageIdx, instanceId: instanceId) else { return }
        document.pages[pageIdx].widgets[widgetIdx].config = config
        save()
    }

    // MARK: - Grid Queries

    /// Returns all occupied cells on a page as a set of (col, row) tuples.
    public func occupiedCells(pageId: String) -> Set<GridCell> {
        guard let pageIdx = pageIndex(for: pageId) else { return [] }
        var cells = Set<GridCell>()
        for widget in document.pages[pageIdx].widgets {
            for c in widget.col..<(widget.col + widget.width) {
                for r in widget.row..<(widget.row + widget.height) {
                    cells.insert(GridCell(col: c, row: r))
                }
            }
        }
        return cells
    }

    /// Find all positions where a widget of given size can be placed.
    public func availablePositions(pageId: String, width: Int, height: Int) -> [GridCell] {
        let occupied = occupiedCells(pageId: pageId)
        var positions: [GridCell] = []
        let cols = currentGrid.columns
        let rows = currentGrid.rows

        for c in 0...(cols - width) {
            for r in 0...(rows - height) {
                let rect = GridRect(col: c, row: r, width: width, height: height)
                var fits = true
                outerLoop: for dc in 0..<width {
                    for dr in 0..<height {
                        if occupied.contains(GridCell(col: c + dc, row: r + dr)) {
                            fits = false
                            break outerLoop
                        }
                    }
                }
                if fits && rect.fitsInGrid(columns: cols, rows: rows) {
                    positions.append(GridCell(col: c, row: r))
                }
            }
        }
        return positions
    }

    /// Check if a specific placement is valid (no collision, within bounds).
    /// While editing, overlap is a permitted staging state, so only bounds
    /// disqualify; use `wouldOverlap` to color-code staged collisions.
    public func isValidPlacement(pageId: String, col: Int, row: Int, width: Int, height: Int, excludeInstanceId: String? = nil) -> Bool {
        guard pageIndex(for: pageId) != nil else { return false }

        let rect = GridRect(col: col, row: row, width: width, height: height)
        guard rect.fitsInGrid(columns: currentGrid.columns, rows: currentGrid.rows) else { return false }

        return isEditing || !wouldOverlap(pageId: pageId, rect: rect, excludeInstanceId: excludeInstanceId)
    }

    /// Pure collision query, independent of edit mode.
    public func wouldOverlap(pageId: String, rect: GridRect, excludeInstanceId: String? = nil) -> Bool {
        guard let pageIdx = pageIndex(for: pageId) else { return false }
        let widgets = document.pages[pageIdx].widgets.filter { $0.instanceId != excludeInstanceId }
        return widgets.contains(where: { $0.gridRect.intersects(rect) })
    }

    /// Instance ids of widgets that overlap another widget on the page.
    public func overlappingInstanceIds(pageId: String) -> Set<String> {
        guard let pageIdx = pageIndex(for: pageId) else { return [] }
        let widgets = document.pages[pageIdx].widgets
        var result: Set<String> = []
        for (i, a) in widgets.enumerated() {
            for b in widgets[(i + 1)...] where a.gridRect.intersects(b.gridRect) {
                result.insert(a.instanceId)
                result.insert(b.instanceId)
            }
        }
        return result
    }

    /// Whether any page holds overlapping widgets. Document-wide because page
    /// switching stays live during edit mode, so staged overlaps can sit on a
    /// page other than the visible one.
    public var hasOverlaps: Bool {
        document.pages.contains { !overlappingInstanceIds(pageId: $0.id).isEmpty }
    }

    // MARK: - Global Settings

    public func updateGlobalSettings(_ settings: GlobalSettings) {
        document.globalSettings = settings
        save()
    }

    // MARK: - Persistence

    private var saveScheduled = false

    public func save() {
        layoutVersion += 1
        guard !saveScheduled else { return }
        saveScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            self.saveScheduled = false
            // Mid-edit the document may legally hold overlaps; the write
            // happens when the edit session ends (the exit path calls save()
            // with isEditing already false).
            guard !self.isEditing else { return }
            self.store.save(self.document)
        }
    }

    /// Immediately save pending changes (called on app quit). Refuses while
    /// overlaps exist so a quit mid-edit cannot persist an overlapping
    /// layout — the file keeps its pre-session state instead.
    public func flushSave() {
        guard !hasOverlaps else { return }
        store.save(document)
        saveScheduled = false
    }

    public func reload() {
        document = store.load()
    }

    // MARK: - Private Helpers

    private func pageIndex(for id: String) -> Int? {
        document.pages.firstIndex { $0.id == id }
    }

    private func widgetIndex(pageIndex: Int, instanceId: String) -> Int? {
        document.pages[pageIndex].widgets.firstIndex { $0.instanceId == instanceId }
    }

    private func reindexPages() {
        for i in document.pages.indices {
            document.pages[i].order = i
        }
    }
}

// MARK: - Grid Cell

public struct GridCell: Hashable, Sendable {
    public let col: Int
    public let row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}
