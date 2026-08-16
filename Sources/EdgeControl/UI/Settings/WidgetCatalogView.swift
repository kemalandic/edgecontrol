import SwiftUI

struct WidgetCatalogView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @State private var selectedCategory: WidgetCategory?
    @State private var previewedWidget: PreviewItem?

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
                    let widgets = selectedCategory == nil ? registry.allWidgets : registry.widgets(in: selectedCategory!)
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
                if placedCount > 0 {
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
                    addWidgetToCurrentPage(widget)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accentGreen)
                }
                .buttonStyle(.plain)
                .help("Add to this page")
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
              let victim = page.widgets.last(where: { $0.widgetId == widgetId }) else { return }
        layoutEngine.removeWidget(pageId: page.id, instanceId: victim.instanceId)
    }

    private func addWidgetToCurrentPage(_ widget: any DashboardWidget) {
        guard let page = currentPage else { return }
        let positions = layoutEngine.availablePositions(
            pageId: page.id,
            width: widget.defaultSize.width,
            height: widget.defaultSize.height
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
            width: widget.defaultSize.width,
            height: widget.defaultSize.height,
            config: widget.defaultConfig()
        )
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
                Text("\(widget.displayName) — all supported sizes")
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
                    let range = widget.supportedSizes
                    ForEach(Array(range.min.height...range.max.height), id: \.self) { h in
                        ForEach(Array(range.min.width...range.max.width), id: \.self) { w in
                            // Narrow sizes get a larger scale — a 1-column
                            // preview at audit scale was an illegible sliver.
                            let s: CGFloat = w <= 3 ? 0.75 : scale
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(w)x\(h)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                                AnyView(widget.body(
                                    size: WidgetSize(width: w, height: h),
                                    config: widget.defaultConfig()
                                ))
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
