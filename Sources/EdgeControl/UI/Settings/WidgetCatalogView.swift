import SwiftUI

struct WidgetCatalogView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @State private var selectedCategory: WidgetCategory?

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

                if isPlaced {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accentGreen.opacity(0.5))
                } else {
                    Button {
                        addWidgetToCurrentPage(widget)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accentGreen)
                    }
                    .buttonStyle(.plain)
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

    private func addWidgetToCurrentPage(_ widget: any DashboardWidget) {
        guard let page = currentPage else { return }
        let positions = layoutEngine.availablePositions(
            pageId: page.id,
            width: widget.defaultSize.width,
            height: widget.defaultSize.height
        )
        guard let pos = positions.first else { return }
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
