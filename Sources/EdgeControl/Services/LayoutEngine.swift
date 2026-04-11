import Foundation

/// Manages grid layout: validates placements, detects collisions, finds available cells.
@MainActor
public final class LayoutEngine: ObservableObject {
    @Published public var document: LayoutDocument
    @Published public var currentPageIndex: Int = 0
    /// Increments on every layout mutation (widget add/remove/move). Used to trigger service activation updates.
    @Published public var layoutVersion: Int = 0

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
        let page = document.pages.remove(at: index)
        let clampedOrder = min(max(toOrder, 0), document.pages.count)
        document.pages.insert(page, at: clampedOrder)
        reindexPages()
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
        guard rect.fitsInGrid(columns: document.grid.columns, rows: document.grid.rows) else { return nil }

        let existing = document.pages[pageIdx].widgets
        guard !existing.contains(where: { $0.gridRect.intersects(rect) }) else { return nil }

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

        guard newRect.fitsInGrid(columns: document.grid.columns, rows: document.grid.rows) else { return false }

        // Check collision with all other widgets on the page
        let others = document.pages[pageIdx].widgets.filter { $0.instanceId != instanceId }
        guard !others.contains(where: { $0.gridRect.intersects(newRect) }) else { return false }

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

        guard newRect.fitsInGrid(columns: document.grid.columns, rows: document.grid.rows) else { return false }

        let others = document.pages[pageIdx].widgets.filter { $0.instanceId != instanceId }
        guard !others.contains(where: { $0.gridRect.intersects(newRect) }) else { return false }

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
        let cols = document.grid.columns
        let rows = document.grid.rows

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
    public func isValidPlacement(pageId: String, col: Int, row: Int, width: Int, height: Int, excludeInstanceId: String? = nil) -> Bool {
        guard let pageIdx = pageIndex(for: pageId) else { return false }

        let rect = GridRect(col: col, row: row, width: width, height: height)
        guard rect.fitsInGrid(columns: document.grid.columns, rows: document.grid.rows) else { return false }

        let widgets = document.pages[pageIdx].widgets.filter { $0.instanceId != excludeInstanceId }
        return !widgets.contains(where: { $0.gridRect.intersects(rect) })
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
            self.store.save(self.document)
        }
    }

    /// Immediately save pending changes (called on app quit).
    public func flushSave() {
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
