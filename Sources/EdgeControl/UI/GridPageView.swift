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

    // Drag state
    @State private var draggingInstanceId: String?
    @State private var dragOffset: CGSize = .zero
    @State private var dragTargetCol: Int?
    @State private var dragTargetRow: Int?
    @State private var dragIsValid: Bool = false

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    // Selection: with overlaps staged, the selected widget renders on top so
    // its resize handle and remove button are the reachable ones.
    @State private var selectedInstanceId: String?

    // Resize state
    @State private var resizingInstanceId: String?
    @State private var resizeTargetW: Int?
    @State private var resizeTargetH: Int?
    @State private var resizeIsValid: Bool = false

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

                // Drop target highlight during drag
                if let targetCol = dragTargetCol, let targetRow = dragTargetRow,
                   let dragging = page.widgets.first(where: { $0.instanceId == draggingInstanceId }) {
                    // Green = free, orange = staged overlap, red = off-grid.
                    let targetRect = GridRect(col: targetCol, row: targetRow, width: dragging.width, height: dragging.height)
                    let tint: Color = !dragIsValid ? Theme.accentRed
                        : layoutEngine.wouldOverlap(pageId: page.id, rect: targetRect, excludeInstanceId: dragging.instanceId)
                            ? Theme.accentOrange : Theme.accentGreen
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    tint.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                                )
                        )
                        .frame(
                            width: CGFloat(dragging.width) * cellW,
                            height: CGFloat(dragging.height) * cellH
                        )
                        .position(
                            x: CGFloat(targetCol) * cellW + CGFloat(dragging.width) * cellW / 2,
                            y: CGFloat(targetRow) * cellH + CGFloat(dragging.height) * cellH / 2
                        )
                        .allowsHitTesting(false)
                }

                // Resize target highlight
                if let resId = resizingInstanceId,
                   let resPlacement = page.widgets.first(where: { $0.instanceId == resId }),
                   let tw = resizeTargetW, let th = resizeTargetH {
                    // Purple = free, orange = staged overlap, red = size the
                    // widget doesn't support (or off-grid).
                    let resRect = GridRect(col: resPlacement.col, row: resPlacement.row, width: tw, height: th)
                    let resTint: Color = !resizeIsValid ? Theme.accentRed
                        : layoutEngine.wouldOverlap(pageId: page.id, rect: resRect, excludeInstanceId: resId)
                            ? Theme.accentOrange : Theme.accentPurple
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(resTint.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    resTint.opacity(0.5),
                                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                                )
                        )
                        .frame(width: CGFloat(tw) * cellW, height: CGFloat(th) * cellH)
                        .position(
                            x: CGFloat(resPlacement.col) * cellW + CGFloat(tw) * cellW / 2,
                            y: CGFloat(resPlacement.row) * cellH + CGFloat(th) * cellH / 2
                        )
                        .allowsHitTesting(false)
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
                            AnyView(widget.body(
                                size: WidgetSize(width: placement.width, height: placement.height),
                                config: cfg
                            ))
                            .padding(CGFloat(layoutEngine.document.globalSettings.theme.widgetGap))
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

                                    // Remove button (top-right)
                                    VStack {
                                        HStack {
                                            Spacer()
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
                                    WidgetLaunch.launch(launchTarget(for: placement))
                                }
                            }
                        }
                        .offset(isDragging ? dragOffset : .zero)
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
    private func launchTarget(for placement: WidgetPlacement) -> String {
        guard !WidgetLaunch.excluded.contains(placement.widgetId) else { return "" }
        return placement.config.string(WidgetLaunch.configKey, default: WidgetLaunch.defaultApp(for: placement.widgetId))
    }

    // MARK: - Drag Gesture

    private func dragGesture(placement: WidgetPlacement, cellW: CGFloat, cellH: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                draggingInstanceId = placement.instanceId
                selectedInstanceId = placement.instanceId
                dragOffset = value.translation

                // Calculate target grid cell from drag position
                let newCol = placement.col + Int(round(value.translation.width / cellW))
                let newRow = placement.row + Int(round(value.translation.height / cellH))
                let clampedCol = max(0, min(newCol, gridColumns - placement.width))
                let clampedRow = max(0, min(newRow, gridRows - placement.height))

                dragTargetCol = clampedCol
                dragTargetRow = clampedRow
                dragIsValid = layoutEngine.isValidPlacement(
                    pageId: page.id,
                    col: clampedCol,
                    row: clampedRow,
                    width: placement.width,
                    height: placement.height,
                    excludeInstanceId: placement.instanceId
                )
            }
            .onEnded { value in
                // Apply move if valid
                if dragIsValid, let col = dragTargetCol, let row = dragTargetRow {
                    layoutEngine.moveWidget(
                        pageId: page.id,
                        instanceId: placement.instanceId,
                        toCol: col,
                        toRow: row
                    )
                }

                // Reset drag state
                withAnimation(.easeOut(duration: 0.2)) {
                    draggingInstanceId = nil
                    dragOffset = .zero
                    dragTargetCol = nil
                    dragTargetRow = nil
                    dragIsValid = false
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
                                resizingInstanceId = placement.instanceId
                                let deltaW = Int(round(value.translation.width / cellW))
                                let deltaH = Int(round(value.translation.height / cellH))
                                let newW = max(1, placement.width + deltaW)
                                let newH = max(1, placement.height + deltaH)
                                let clampedW = min(newW, gridColumns - placement.col)
                                let clampedH = min(newH, gridRows - placement.row)

                                resizeTargetW = clampedW
                                resizeTargetH = clampedH

                                // Check if widget supports this size
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
                                    resizeIsValid = sizeOk && noCollision
                                } else {
                                    resizeIsValid = false
                                }
                            }
                            .onEnded { _ in
                                if resizeIsValid, let tw = resizeTargetW, let th = resizeTargetH {
                                    layoutEngine.resizeWidget(
                                        pageId: page.id,
                                        instanceId: placement.instanceId,
                                        newWidth: tw,
                                        newHeight: th
                                    )
                                }
                                withAnimation(.easeOut(duration: 0.2)) {
                                    resizingInstanceId = nil
                                    resizeTargetW = nil
                                    resizeTargetH = nil
                                    resizeIsValid = false
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
