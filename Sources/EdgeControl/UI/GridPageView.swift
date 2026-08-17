import SwiftUI

/// Renders a single page as a 20x6 grid with placed widgets.
/// Supports edit mode with drag-to-move and visual grid overlay.
struct GridPageView: View {
    let page: PageConfig
    let registry: WidgetRegistry
    let gridColumns: Int
    let gridRows: Int
    @Binding var editMode: Bool
    @ObservedObject var layoutEngine: LayoutEngine
    @EnvironmentObject private var model: AppModel

    // Drag state. Which widget is being dragged/resized is page state (it
    // changes once per gesture); where it would land lives in `targets`,
    // which only the highlight views observe — see EditTargets.
    @State private var draggingInstanceId: String?
    @State private var targets = EditTargets()

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    // Selection: with overlaps staged, the selected widget renders on top so
    // its resize handle and remove button are the reachable ones.
    @State private var selectedInstanceId: String?
    @State private var hoveredInstanceId: String?
    @State private var commandHeld = false
    // Modifier changes don't arrive as key events while the kiosk window
    // isn't key, so the gear's Cmd gate polls the hardware state instead;
    // state only changes (and re-renders) while a widget is hovered.
    private let modifierTick = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    // Resize state
    @State private var resizingInstanceId: String?

    var body: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / CGFloat(gridColumns)
            let cellH = geo.size.height / CGFloat(gridRows)
            // Overlaps are a legal staging state while editing, marked so the
            // user knows what still needs separating before edit mode can end.
            let overlappedIds = editMode ? layoutEngine.overlappingInstanceIds(pageId: page.id) : []

            ZStack(alignment: .topLeading) {
                // Grid lines — more visible in edit mode
                gridLines(cellW: cellW, cellH: cellH, size: geo.size)
                Color.clear.frame(width: 0, height: 0)
                    .onChange(of: editMode) { _, editing in
                        if !editing { selectedInstanceId = nil }
                    }
                    .onReceive(modifierTick) { _ in
                        let held = hoveredInstanceId != nil
                            && NSEvent.modifierFlags.contains(.command)
                        if commandHeld != held { commandHeld = held }
                    }
                    .background(EditKeyCatcher(layoutEngine: layoutEngine))

                // Drop / resize target highlights. These are the only views
                // that observe the live gesture targets, so a drag tick
                // re-renders a dashed rectangle and nothing else on the page.
                if let dragging = page.widgets.first(where: { $0.instanceId == draggingInstanceId }) {
                    TargetHighlight(
                        targets: targets, kind: .drag, placement: dragging,
                        pageId: page.id, layoutEngine: layoutEngine, cellW: cellW, cellH: cellH
                    )
                }
                if let resizing = page.widgets.first(where: { $0.instanceId == resizingInstanceId }) {
                    TargetHighlight(
                        targets: targets, kind: .resize, placement: resizing,
                        pageId: page.id, layoutEngine: layoutEngine, cellW: cellW, cellH: cellH
                    )
                }

                // Placed widgets
                ForEach(page.widgets) { placement in
                    if let widget = registry.widget(for: placement.widgetId) {
                        let isDragging = draggingInstanceId == placement.instanceId
                        let isResizing = resizingInstanceId == placement.instanceId
                        let isSelected = selectedInstanceId == placement.instanceId
                        let x = CGFloat(placement.col) * cellW
                        let y = CGFloat(placement.row) * cellH
                        let w = CGFloat(placement.width) * cellW
                        let h = CGFloat(placement.height) * cellH

                        ZStack {
                            // Placement identity rides along in the config so
                            // self-editing widgets (sticky note) can write
                            // their state back through the layout engine.
                            let cfg: WidgetConfig = {
                                var c = placement.config
                                c["_pageId"] = .string(page.id)
                                c["_instanceId"] = .string(placement.instanceId)
                                return c
                            }()
                            // Equatable wrapper: drag state changes re-render
                            // this page body ~60x/s, and rebuilding every
                            // widget's view tree each tick is what made
                            // dragging janky. The wrapper skips a widget's
                            // body unless its own inputs changed, so a drag
                            // only updates cheap transforms.
                            WidgetContentView(
                                registry: registry,
                                widgetId: placement.widgetId,
                                width: placement.width,
                                height: placement.height,
                                config: cfg,
                                gap: CGFloat(layoutEngine.document.globalSettings.theme.widgetGap)
                            )
                            .equatable()
                            // In edit mode the widget's own controls go
                            // inert: any point on the card drags it, and a
                            // tap selects it instead of poking the widget.
                            .allowsHitTesting(!editMode)
                        }
                        .frame(width: w, height: h)
                        // Compact layouts at large font scales can overflow a
                        // 1-row cell; never let a widget paint over neighbors.
                        .clipped()
                        .opacity(isDragging ? 0.5 : isResizing ? 0.7 : 1)
                        .overlay {
                            if editMode {
                                ZStack {
                                    // Edit mode border; overlapped widgets are
                                    // flagged orange until separated.
                                    let isOverlapped = overlappedIds.contains(placement.instanceId)
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? accent
                                                : isOverlapped ? Theme.accentOrange.opacity(0.9)
                                                : accent.opacity(0.4),
                                            lineWidth: isSelected ? 2.5 : isOverlapped ? 2.5 : 1.5
                                        )
                                        .allowsHitTesting(false)

                                    // Remove button (top-right); the
                                    // selected widget also gets stacking
                                    // controls so overlapped widgets can be
                                    // pulled out from under one another.
                                    VStack {
                                        HStack {
                                            Spacer()
                                            if isSelected {
                                                Button {
                                                    // Deselect too: selection
                                                    // floats the widget, which
                                                    // would keep hiding the
                                                    // one underneath.
                                                    layoutEngine.reorderWidget(
                                                        pageId: page.id,
                                                        instanceId: placement.instanceId,
                                                        toFront: false
                                                    )
                                                    selectedInstanceId = nil
                                                } label: {
                                                    Image(systemName: "square.3.layers.3d.bottom.filled")
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(.white.opacity(0.9))
                                                        .background(Circle().fill(Color.black.opacity(0.6)).padding(-4))
                                                }
                                                .buttonStyle(.plain)
                                                .help("Send to back")
                                                .padding(.trailing, 6)

                                                Button {
                                                    layoutEngine.reorderWidget(
                                                        pageId: page.id,
                                                        instanceId: placement.instanceId,
                                                        toFront: true
                                                    )
                                                } label: {
                                                    Image(systemName: "square.3.layers.3d.top.filled")
                                                        .font(.system(size: 15))
                                                        .foregroundStyle(.white.opacity(0.9))
                                                        .background(Circle().fill(Color.black.opacity(0.6)).padding(-4))
                                                }
                                                .buttonStyle(.plain)
                                                .help("Bring to front")
                                                .padding(.trailing, 6)
                                            }
                                            Button {
                                                layoutEngine.removeWidget(pageId: page.id, instanceId: placement.instanceId)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundStyle(Theme.accentRed)
                                                    .background(Circle().fill(Color.black.opacity(0.6)).padding(-2))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(6)
                                        }
                                        Spacer()
                                    }

                                    // Resize handle (bottom-right corner)
                                    resizeHandle(placement: placement, cellW: cellW, cellH: cellH)
                                }
                            }
                        }
                        // Mouse-only affordance: while Cmd is held, a gear
                        // fades in at the bottom right on hover and
                        // deep-links to this widget's settings. Hidden
                        // entirely (not just transparent) otherwise so it
                        // can't swallow touches.
                        .overlay(alignment: .bottomTrailing) {
                            if !editMode, commandHeld, hoveredInstanceId == placement.instanceId {
                                Button {
                                    openWidgetSettings(placement)
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .padding(5)
                                        .background(Circle().fill(Color.black.opacity(0.55)))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .transition(.opacity)
                            }
                        }
                        .onHover { inside in
                            // Hover only feeds the gear, which edit mode
                            // hides; tracking it there would re-render the
                            // page every time a drag crosses a card.
                            if inside, !editMode {
                                hoveredInstanceId = placement.instanceId
                            } else if hoveredInstanceId == placement.instanceId {
                                hoveredInstanceId = nil
                            }
                        }
                        .contextMenu {
                            Button("Edit This Widget's Settings") {
                                openWidgetSettings(placement)
                            }
                        }
                        // Tap: in edit mode selects (selection floats the
                        // widget above staged overlaps so its handles win);
                        // otherwise launches the widget's configured app.
                        // Widget-internal zones are smaller and win hit-tests.
                        // MUST precede .position: that wraps the card in a
                        // page-sized container, and a contentShape added after
                        // it would make every widget swallow the whole page's
                        // clicks.
                        .touchTappable(id: "widget-tap-\(placement.instanceId)", registry: model.touchService.zoneRegistry) {
                            Task { @MainActor in
                                if editMode {
                                    selectedInstanceId = placement.instanceId
                                } else {
                                    WidgetLaunch.launch(
                                        launchTarget(for: placement),
                                        tab: placement.config.string(WidgetLaunch.tabConfigKey, default: "CPU")
                                    )
                                }
                            }
                        }
                        .position(x: x + w / 2, y: y + h / 2)
                        .gesture(editMode ? dragGesture(placement: placement, cellW: cellW, cellH: cellH) : nil)
                        .zIndex(isDragging || isResizing ? 100 : isSelected && editMode ? 50 : 0)
                    }
                }

                // Edit mode label
                if editMode {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(overlappedIds.isEmpty ? accent : Theme.accentOrange)
                            .frame(width: 8, height: 8)
                        Text("EDIT MODE")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(overlappedIds.isEmpty ? accent : Theme.accentOrange)
                        Text(overlappedIds.isEmpty
                            ? "— drag widgets to reposition"
                            : "— separate overlapping widgets to finish")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.backgroundPrimary.opacity(0.8), in: Capsule())
                    .position(x: geo.size.width / 2, y: 14)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    /// The app a tap on this widget should open: explicit config first,
    /// per-widget default second; empty means no launcher.
    /// Deep link into Settings for one widget: Pages tab, its page
    /// selected, its config row scrolled into view.
    private func openWidgetSettings(_ placement: WidgetPlacement) {
        layoutEngine.settingsFocus = LayoutEngine.SettingsFocus(
            pageId: page.id, instanceId: placement.instanceId
        )
        SettingsWindowController.shared.show()
    }

    private func launchTarget(for placement: WidgetPlacement) -> String {
        guard !WidgetLaunch.excluded.contains(placement.widgetId) else { return "" }
        return placement.config.string(WidgetLaunch.configKey, default: WidgetLaunch.defaultApp(for: placement.widgetId))
    }

    // MARK: - Drag Gesture

    private func dragGesture(placement: WidgetPlacement, cellW: CGFloat, cellH: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                // Page state changes once, on the first tick; the equality
                // guards keep later ticks from re-rendering the page.
                if draggingInstanceId != placement.instanceId { draggingInstanceId = placement.instanceId }
                if selectedInstanceId != placement.instanceId { selectedInstanceId = placement.instanceId }

                // Calculate target grid cell from drag position
                let newCol = placement.col + Int(round(value.translation.width / cellW))
                let newRow = placement.row + Int(round(value.translation.height / cellH))
                let clampedCol = max(0, min(newCol, gridColumns - placement.width))
                let clampedRow = max(0, min(newRow, gridRows - placement.height))

                targets.setDrag(EditTargets.Target(
                    col: clampedCol, row: clampedRow,
                    width: placement.width, height: placement.height,
                    isValid: layoutEngine.isValidPlacement(
                        pageId: page.id,
                        col: clampedCol,
                        row: clampedRow,
                        width: placement.width,
                        height: placement.height,
                        excludeInstanceId: placement.instanceId
                    )
                ))
            }
            .onEnded { value in
                // Apply move if valid
                if let target = targets.drag, target.isValid {
                    layoutEngine.moveWidget(
                        pageId: page.id,
                        instanceId: placement.instanceId,
                        toCol: target.col,
                        toRow: target.row
                    )
                    // Anything the drop landed on steps aside to its
                    // nearest free spot; no room means it stays staged.
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        layoutEngine.resolveOverlaps(
                            pageId: page.id, keeping: placement.instanceId,
                            minSize: { registry.widget(for: $0)?.supportedSizes.min }
                        )
                    }
                }

                // Reset drag state (the card never moved — it dims in
                // place and jumps to its new cell on drop)
                withAnimation(.easeOut(duration: 0.2)) {
                    draggingInstanceId = nil
                    targets.setDrag(nil)
                }
            }
    }

    // MARK: - Resize Handle

    private func resizeHandle(placement: WidgetPlacement, cellW: CGFloat, cellH: CGFloat) -> some View {
        // Bottom-right corner drag handle
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accentPurple)
                    .frame(width: 22, height: 22)
                    .background(Theme.accentPurple.opacity(0.2), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.accentPurple.opacity(0.4), lineWidth: 1)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if resizingInstanceId != placement.instanceId { resizingInstanceId = placement.instanceId }
                                let deltaW = Int(round(value.translation.width / cellW))
                                let deltaH = Int(round(value.translation.height / cellH))
                                let newW = max(1, placement.width + deltaW)
                                let newH = max(1, placement.height + deltaH)
                                let clampedW = min(newW, gridColumns - placement.col)
                                let clampedH = min(newH, gridRows - placement.row)

                                // Valid = a size the widget supports that
                                // also stays on the grid.
                                var isValid = false
                                if let meta = registry.metadata(for: placement.widgetId) {
                                    let sizeOk = meta.supportedSizes.contains(WidgetSize(width: clampedW, height: clampedH))
                                    let noCollision = layoutEngine.isValidPlacement(
                                        pageId: page.id,
                                        col: placement.col,
                                        row: placement.row,
                                        width: clampedW,
                                        height: clampedH,
                                        excludeInstanceId: placement.instanceId
                                    )
                                    isValid = sizeOk && noCollision
                                }
                                targets.setResize(EditTargets.Target(
                                    col: placement.col, row: placement.row,
                                    width: clampedW, height: clampedH, isValid: isValid
                                ))
                            }
                            .onEnded { _ in
                                if let target = targets.resize, target.isValid {
                                    layoutEngine.resizeWidget(
                                        pageId: page.id,
                                        instanceId: placement.instanceId,
                                        newWidth: target.width,
                                        newHeight: target.height
                                    )
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        layoutEngine.resolveOverlaps(
                                            pageId: page.id, keeping: placement.instanceId,
                                            minSize: { registry.widget(for: $0)?.supportedSizes.min }
                                        )
                                    }
                                }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    resizingInstanceId = nil
                                    targets.setResize(nil)
                                }
                            }
                    )
                    .padding(4)
            }
        }
    }

    // MARK: - Grid Lines

    private func gridLines(cellW: CGFloat, cellH: CGFloat, size: CGSize) -> some View {
        Canvas { context, _ in
            let opacity = editMode ? 0.12 : 0.02
            let lineWidth: CGFloat = editMode ? 1 : 0.5
            for col in 1..<gridColumns {
                let x = CGFloat(col) * cellW
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
            }
            for row in 1..<gridRows {
                let y = CGFloat(row) * cellH
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: lineWidth)
            }
        }
        .allowsHitTesting(false)
    }
}


/// Where an in-flight drag or resize would land. Deliberately not @State on
/// the page: a gesture publishes ~60 ticks a second, and each one written to
/// page state re-evaluated the whole page body — every card's gestures,
/// context menu and buttons included. That is merely wasteful on its own,
/// but once any accessibility client has queried the process (window
/// managers, screenshot tools, text-grabbers all do; the flag is sticky for
/// the process lifetime) SwiftUI also recomputes accessibility attachments
/// for every invalidated gesture, and a drag went from smooth to seconds
/// behind the finger. Only `TargetHighlight` observes this object, so a
/// tick now re-renders one dashed rectangle. Setters skip unchanged values
/// so a finger resting inside one cell publishes nothing.
@MainActor
final class EditTargets: ObservableObject {
    struct Target: Equatable {
        var col: Int
        var row: Int
        var width: Int
        var height: Int
        var isValid: Bool

        var rect: GridRect { GridRect(col: col, row: row, width: width, height: height) }
    }

    @Published private(set) var drag: Target?
    @Published private(set) var resize: Target?

    func setDrag(_ target: Target?) {
        if drag != target { drag = target }
    }

    func setResize(_ target: Target?) {
        if resize != target { resize = target }
    }
}


/// The dashed cell outline that follows a drag or resize. Green/purple =
/// free, orange = staged overlap, red = off-grid or an unsupported size.
private struct TargetHighlight: View {
    enum Kind { case drag, resize }

    @ObservedObject var targets: EditTargets
    let kind: Kind
    let placement: WidgetPlacement
    let pageId: String
    let layoutEngine: LayoutEngine
    let cellW: CGFloat
    let cellH: CGFloat

    var body: some View {
        if let target = kind == .drag ? targets.drag : targets.resize {
            let free: Color = kind == .drag ? Theme.accentGreen : Theme.accentPurple
            let tint: Color = !target.isValid ? Theme.accentRed
                : layoutEngine.wouldOverlap(pageId: pageId, rect: target.rect, excludeInstanceId: placement.instanceId)
                    ? Theme.accentOrange : free
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(kind == .drag ? 0.15 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            tint.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                )
                .frame(width: CGFloat(target.width) * cellW, height: CGFloat(target.height) * cellH)
                .position(
                    x: CGFloat(target.col) * cellW + CGFloat(target.width) * cellW / 2,
                    y: CGFloat(target.row) * cellH + CGFloat(target.height) * cellH / 2
                )
                .allowsHitTesting(false)
        }
    }
}


/// The widget's rendered body behind an explicit Equatable gate: SwiftUI
/// skips re-evaluating it unless the placement's own inputs change, which
/// keeps edit-mode drags from rebuilding every widget on the page per tick.
private struct WidgetContentView: View, Equatable {
    let registry: WidgetRegistry
    let widgetId: String
    let width: Int
    let height: Int
    let config: WidgetConfig
    let gap: CGFloat

    // The registry is a process-wide singleton, so identity of the value
    // fields is the whole story; touching the non-Sendable registry here
    // would also violate the nonisolated Equatable requirement.
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.widgetId == b.widgetId
            && a.width == b.width && a.height == b.height
            && a.config == b.config && a.gap == b.gap
    }

    var body: some View {
        if let widget = registry.widget(for: widgetId) {
            AnyView(widget.body(
                size: WidgetSize(width: width, height: height),
                config: config
            ))
            .padding(gap)
        }
    }
}


/// Edit-session keyboard: Esc cancels back to the last saved layout,
/// Cmd+Z / Shift+Cmd+Z step through the session's changes. A local event
/// monitor rather than key-view plumbing, because the kiosk's SwiftUI tree
/// never takes first responder for these. Claims events only while editing
/// and only in its own window, before menu dispatch sees them.
private struct EditKeyCatcher: NSViewRepresentable {
    let layoutEngine: LayoutEngine

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.engine = layoutEngine
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.engine = layoutEngine
    }

    final class CatcherView: NSView {
        weak var engine: LayoutEngine?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self, let engine = self.engine, engine.isEditing,
                          event.window === self.window else { return event }
                    if event.keyCode == 53 { // Esc
                        engine.cancelEditing()
                        return nil
                    }
                    if event.modifierFlags.contains(.command),
                       event.charactersIgnoringModifiers?.lowercased() == "z" {
                        if event.modifierFlags.contains(.shift) {
                            engine.redoLayout()
                        } else {
                            engine.undoLayout()
                        }
                        return nil
                    }
                    return event
                }
            }
        }
    }
}
