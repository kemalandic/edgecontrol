import SwiftUI

struct WidgetCatalogView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @State private var selectedCategory: WidgetCategory?
    @State private var previewedWidget: PreviewItem?
    /// The widget whose size picker is open.
    @State private var sizingWidgetId: String?

    private struct PreviewItem: Identifiable {
        let id: String
    }

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    private var currentPage: PageConfig? {
        layoutEngine.currentPage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Widget Catalog")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                if let page = currentPage {
                    Text("Adding to: \(page.name)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.1), in: Capsule())
                }
            }

            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, label: "All")
                    ForEach(registry.categories, id: \.self) { cat in
                        categoryChip(cat, label: cat.displayName)
                    }
                }
            }

            // Widget grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    let widgets =
                        selectedCategory == nil ? registry.allWidgets : registry.widgets(in: selectedCategory!)
                    ForEach(widgets, id: \.widgetId) { widget in
                        widgetCard(widget)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .sheet(item: $previewedWidget) { item in
            if let widget = registry.widget(for: item.id) {
                WidgetSizePreviewSheet(widget: widget) { previewedWidget = nil }
            }
        }
    }

    private func categoryChip(_ category: WidgetCategory?, label: String) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 4) {
                if let cat = category {
                    Image(systemName: cat.iconName)
                        .font(.system(size: 12))
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? .white : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? accent.opacity(0.2) : Color.white.opacity(0.05),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private func widgetCard(_ widget: any DashboardWidget) -> some View {
        let isPlaced = isWidgetOnCurrentPage(widgetId: widget.widgetId)
        let placedCount = placedCountOnCurrentPage(widgetId: widget.widgetId)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: widget.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(isPlaced ? Theme.accentGreen : accent)
                Text(widget.displayName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                // The checkmark already says "placed"; the count badge
                // only earns its pixels once there's more than one.
                if placedCount > 1 {
                    Text("x\(placedCount)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accentGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.accentGreen.opacity(0.15), in: Capsule())
                }
            }

            Text(widget.description)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)

            HStack {
                Text("\(widget.defaultSize.width)x\(widget.defaultSize.height)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()

                // Renders the widget at every supported size — an audit
                // surface for layout regressions.
                Button {
                    previewedWidget = PreviewItem(id: widget.widgetId)
                } label: {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(accent.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Preview at all supported sizes")

                if isPlaced {
                    Button {
                        removeOneFromCurrentPage(widgetId: widget.widgetId)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accentGreen)
                    }
                    .buttonStyle(.plain)
                    .help("Remove one from this page")
                }

                Button {
                    sizingWidgetId = widget.widgetId
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accentGreen)
                }
                .buttonStyle(.plain)
                .help("Choose a size and add to this page")
                .popover(
                    isPresented: Binding(
                        get: { sizingWidgetId == widget.widgetId },
                        set: { if !$0 { sizingWidgetId = nil } }
                    ),
                    arrowEdge: .bottom
                ) {
                    WidgetSizePicker(
                        widget: widget,
                        pageName: currentPage?.name ?? "this page",
                        columns: layoutEngine.currentGrid.columns,
                        rows: layoutEngine.currentGrid.rows,
                        accent: accent,
                        occupied: (currentPage?.widgets ?? []).map {
                            CGRect(x: $0.col, y: $0.row, width: $0.width, height: $0.height)
                        },
                        freeSpot: { size in
                            guard let page = currentPage else { return nil }
                            return layoutEngine.availablePositions(
                                pageId: page.id, width: size.width, height: size.height
                            ).first
                        },
                        onPick: { size in
                            sizingWidgetId = nil
                            addWidgetToCurrentPage(widget, size: size)
                        }
                    )
                }
            }
        }
        .padding(10)
        .background(
            isPlaced ? Theme.accentGreen.opacity(0.04) : Color.white.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isPlaced ? Theme.accentGreen.opacity(0.2) : Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func isWidgetOnCurrentPage(widgetId: String) -> Bool {
        guard let page = currentPage else { return false }
        return page.widgets.contains { $0.widgetId == widgetId }
    }

    private func placedCountOnCurrentPage(widgetId: String) -> Int {
        guard let page = currentPage else { return 0 }
        return page.widgets.filter { $0.widgetId == widgetId }.count
    }

    /// The checkmark removes one instance per click, most recent first.
    private func removeOneFromCurrentPage(widgetId: String) {
        guard let page = currentPage,
            let victim = page.widgets.last(where: { $0.widgetId == widgetId })
        else { return }
        layoutEngine.removeWidget(pageId: page.id, instanceId: victim.instanceId)
    }

    private func addWidgetToCurrentPage(_ widget: any DashboardWidget, size: WidgetSize) {
        guard let page = currentPage else { return }
        let positions = layoutEngine.availablePositions(
            pageId: page.id,
            width: size.width,
            height: size.height
        )
        // A full page no longer blocks adding: park the widget at the origin
        // as a staged overlap. Entering edit mode makes the overlap legal and
        // visible, and the edit session cannot end until it's resolved.
        let pos: GridCell
        if let free = positions.first {
            pos = free
        } else {
            layoutEngine.isEditing = true
            pos = GridCell(col: 0, row: 0)
        }
        layoutEngine.placeWidget(
            pageId: page.id,
            widgetId: widget.widgetId,
            col: pos.col,
            row: pos.row,
            width: size.width,
            height: size.height,
            config: widget.defaultConfig()
        )
    }
}

// MARK: - Size Picker

/// Shown from the catalog's + button. Each choice is one row: a map of the
/// current page with the new widget drawn where it will actually land, its
/// name and size, and a plain note when the page has no room. Clicking a row
/// adds the widget; Custom covers any other size the widget supports.
private struct WidgetSizePicker: View {
    let widget: any DashboardWidget
    let pageName: String
    let columns: Int
    let rows: Int
    let accent: Color
    /// Existing widgets on the page, in grid cells.
    let occupied: [CGRect]
    /// First free top-left cell for a size, or nil when the page is full.
    let freeSpot: (WidgetSize) -> GridCell?
    let onPick: (WidgetSize) -> Void

    @State private var customWidth = 1
    @State private var customHeight = 1
    @State private var hovered: String?

    private var options: [WidgetSizeOption] {
        WidgetSizeOptions.options(
            range: widget.supportedSizes, defaultSize: widget.defaultSize, columns: columns, rows: rows)
    }
    private var maxWidth: Int { max(widget.supportedSizes.min.width, min(widget.supportedSizes.max.width, columns)) }
    private var maxHeight: Int { max(widget.supportedSizes.min.height, min(widget.supportedSizes.max.height, rows)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add \(widget.displayName)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Choose a size. The map shows where it will go on \(pageName).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    optionRow(option)
                }
            }

            Divider()

            customRow
        }
        .padding(18)
        .frame(width: 420)
        .onAppear {
            customWidth = min(max(widget.defaultSize.width, widget.supportedSizes.min.width), maxWidth)
            customHeight = min(max(widget.defaultSize.height, widget.supportedSizes.min.height), maxHeight)
        }
    }

    private func optionRow(_ option: WidgetSizeOption) -> some View {
        let spot = freeSpot(option.size)
        let isDefault = option.size == widget.defaultSize
        let key = "\(option.name)-\(option.size.width)x\(option.size.height)"
        return Button {
            onPick(option.size)
        } label: {
            HStack(spacing: 14) {
                PageMap(
                    columns: columns, rows: rows, occupied: occupied,
                    size: option.size, spot: spot, accent: accent)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.name)
                            .font(.system(size: 13, weight: .semibold))
                        if isDefault {
                            Text("Default")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(accent.opacity(0.2), in: Capsule())
                        }
                    }
                    Text(sizeText(option.size))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if spot == nil {
                        Text("Not enough free space: it will overlap, and edit mode opens so you can make room.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accentOrange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(hovered == key ? accent : Color.secondary.opacity(0.5))
            }
            .padding(10)
            .background(
                hovered == key ? accent.opacity(0.14) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? key : (hovered == key ? nil : hovered) }
        .accessibilityLabel("\(option.name), \(sizeText(option.size))\(spot == nil ? ", not enough free space" : "")")
    }

    private var customRow: some View {
        let size = WidgetSize(width: customWidth, height: customHeight)
        return HStack(spacing: 14) {
            PageMap(
                columns: columns, rows: rows, occupied: occupied,
                size: size, spot: freeSpot(size), accent: accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 12) {
                    Stepper(value: $customWidth, in: widget.supportedSizes.min.width...maxWidth) {
                        Text("\(customWidth) wide").font(.system(size: 11)).monospacedDigit()
                    }
                    Stepper(value: $customHeight, in: widget.supportedSizes.min.height...maxHeight) {
                        Text("\(customHeight) tall").font(.system(size: 11)).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Add") { onPick(size) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 10)
    }

    private func sizeText(_ size: WidgetSize) -> String {
        "\(size.width) \(size.width == 1 ? "column" : "columns") × \(size.height) \(size.height == 1 ? "row" : "rows")"
    }
}

/// A small map of the page: grid, existing widgets in grey, and the new
/// widget in the accent colour at its landing spot (orange at the top-left
/// when it will have to overlap).
private struct PageMap: View {
    let columns: Int
    let rows: Int
    let occupied: [CGRect]
    let size: WidgetSize
    let spot: GridCell?
    let accent: Color

    private static let maxSize = CGSize(width: 132, height: 48)

    var body: some View {
        let cell = min(Self.maxSize.width / CGFloat(max(columns, 1)), Self.maxSize.height / CGFloat(max(rows, 1)))
        let board = CGSize(width: cell * CGFloat(columns), height: cell * CGFloat(rows))
        Canvas { context, _ in
            let page = CGRect(origin: .zero, size: board)
            context.fill(Path(roundedRect: page, cornerRadius: 3), with: .color(.black.opacity(0.35)))
            for widget in occupied {
                let r = CGRect(
                    x: widget.minX * cell, y: widget.minY * cell,
                    width: widget.width * cell, height: widget.height * cell
                ).insetBy(dx: 0.75, dy: 0.75)
                context.fill(Path(roundedRect: r, cornerRadius: 1.5), with: .color(.white.opacity(0.16)))
            }
            let origin = spot ?? GridCell(col: 0, row: 0)
            let new = CGRect(
                x: CGFloat(origin.col) * cell, y: CGFloat(origin.row) * cell,
                width: CGFloat(size.width) * cell, height: CGFloat(size.height) * cell
            ).insetBy(dx: 0.75, dy: 0.75)
            context.fill(
                Path(roundedRect: new, cornerRadius: 1.5),
                with: .color(spot == nil ? Theme.accentOrange.opacity(0.85) : accent))
            context.stroke(Path(roundedRect: page, cornerRadius: 3), with: .color(.white.opacity(0.25)), lineWidth: 1)
        }
        .frame(width: board.width, height: board.height)
        .frame(width: Self.maxSize.width, height: Self.maxSize.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Size Preview

/// Renders a widget at every size its range allows, at true cell geometry
/// scaled down — the audit surface for per-size layout regressions.
private struct WidgetSizePreviewSheet: View {
    let widget: any DashboardWidget
    let dismiss: () -> Void

    private let cell: CGFloat = 120
    private let scale: CGFloat = 0.45

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: widget.iconName)
                Text("\(widget.displayName) — min, default and max sizes")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Spacer()
                Text("Widgets without their service running show placeholder data")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Button("Close", action: dismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .foregroundStyle(.white)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    // Extents only: the full width x height cross product
                    // ran to dozens of near-identical tiles for wide-ranged
                    // widgets and scrolled forever.
                    let range = widget.supportedSizes
                    let widths = Array(Set([range.min.width, widget.defaultSize.width, range.max.width])).sorted()
                    let heights = Array(Set([range.min.height, widget.defaultSize.height, range.max.height])).sorted()
                    ForEach(heights, id: \.self) { h in
                        ForEach(widths, id: \.self) { w in
                            // Narrow sizes get a larger scale — a 1-column
                            // preview at audit scale was an illegible sliver.
                            let s: CGFloat = w <= 3 ? 0.75 : scale
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(w)x\(h)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                                AnyView(
                                    widget.body(
                                        size: WidgetSize(width: w, height: h),
                                        config: widget.defaultConfig()
                                    )
                                )
                                .frame(width: CGFloat(w) * cell, height: CGFloat(h) * cell)
                                .clipped()
                                .scaleEffect(s, anchor: .topLeading)
                                .frame(
                                    width: CGFloat(w) * cell * s,
                                    height: CGFloat(h) * cell * s,
                                    alignment: .topLeading
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 460)
        .background(Theme.backgroundPrimary)
    }
}
