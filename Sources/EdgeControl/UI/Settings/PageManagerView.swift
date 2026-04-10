import SwiftUI

struct PageManagerView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @State private var editingPageId: String?
    @State private var editingName: String = ""
    @State private var selectedPageId: String?
    @State private var showAddPage = false
    @State private var newPageName = ""

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: page list
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pages")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        newPageName = ""
                        showAddPage = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(layoutEngine.sortedPages) { page in
                            pageRow(page)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: 220)
            .padding(14)

            Rectangle().fill(Theme.borderSubtle).frame(width: 1)

            // Right: selected page widget list
            if let pageId = selectedPageId,
               let page = layoutEngine.document.pages.first(where: { $0.id == pageId }) {
                pageWidgetList(page)
            } else {
                VStack {
                    Spacer()
                    Text("Select a page to manage widgets")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .alert("New Page", isPresented: $showAddPage) {
            TextField("Page Name", text: $newPageName)
            Button("Add") {
                if !newPageName.isEmpty {
                    layoutEngine.addPage(name: newPageName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            // Auto-select active page
            if selectedPageId == nil, let page = layoutEngine.currentPage {
                selectedPageId = page.id
            }
        }
    }

    // MARK: - Page Row

    private func pageRow(_ page: PageConfig) -> some View {
        let isSelected = selectedPageId == page.id
        let isActive = layoutEngine.sortedPages.firstIndex(where: { $0.id == page.id }) == layoutEngine.currentPageIndex

        return HStack(spacing: 8) {
            if editingPageId == page.id {
                TextField("Name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .onSubmit {
                        layoutEngine.renamePage(id: page.id, name: editingName)
                        editingPageId = nil
                    }
            } else {
                Text(page.name)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(page.widgets.count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)

            if isActive {
                Circle()
                    .fill(Theme.accentGreen)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? accent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedPageId = page.id
        }
        .onTapGesture(count: 2) {
            editingPageId = page.id
            editingName = page.name
        }
        .contextMenu {
            Button("Rename") {
                editingPageId = page.id
                editingName = page.name
            }
            if layoutEngine.pageCount > 1 {
                Button("Delete", role: .destructive) {
                    layoutEngine.removePage(id: page.id)
                    if selectedPageId == page.id {
                        selectedPageId = layoutEngine.currentPage?.id
                    }
                }
            }
        }
    }

    // MARK: - Page Widget List

    private func pageWidgetList(_ page: PageConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(page.name)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("(\(page.widgets.count) widgets)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()

                // Navigate to this page
                Button {
                    if let idx = layoutEngine.sortedPages.firstIndex(where: { $0.id == page.id }) {
                        layoutEngine.currentPageIndex = idx
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eye")
                        Text("View")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accent.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if page.widgets.isEmpty {
                Spacer()
                Text("No widgets on this page")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(page.widgets) { placement in
                            widgetRow(pageId: page.id, placement: placement)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Widget Row

    private func widgetRow(pageId: String, placement: WidgetPlacement) -> some View {
        let meta = registry.metadata(for: placement.widgetId)
        let cols = layoutEngine.document.grid.columns
        let rows = layoutEngine.document.grid.rows

        return VStack(spacing: 0) {
        HStack(spacing: 10) {
            // Widget icon + name
            Image(systemName: meta?.iconName ?? "square")
                .font(.system(size: 14))
                .foregroundStyle(accent)
                .frame(width: 20)

            Text(meta?.displayName ?? placement.widgetId)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            // Position controls
            HStack(spacing: 3) {
                Text("Col")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                stepperButton(systemName: "minus", size: 10) {
                    if placement.col > 0 {
                        layoutEngine.moveWidget(pageId: pageId, instanceId: placement.instanceId, toCol: placement.col - 1, toRow: placement.row)
                    }
                }
                Text("\(placement.col)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accentYellow)
                    .frame(width: 18)
                stepperButton(systemName: "plus", size: 10) {
                    if placement.col + placement.width < cols {
                        layoutEngine.moveWidget(pageId: pageId, instanceId: placement.instanceId, toCol: placement.col + 1, toRow: placement.row)
                    }
                }

                Rectangle().fill(Theme.borderSubtle).frame(width: 1, height: 14).padding(.horizontal, 2)

                Text("Row")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                stepperButton(systemName: "minus", size: 10) {
                    if placement.row > 0 {
                        layoutEngine.moveWidget(pageId: pageId, instanceId: placement.instanceId, toCol: placement.col, toRow: placement.row - 1)
                    }
                }
                Text("\(placement.row)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accentYellow)
                    .frame(width: 18)
                stepperButton(systemName: "plus", size: 10) {
                    if placement.row + placement.height < rows {
                        layoutEngine.moveWidget(pageId: pageId, instanceId: placement.instanceId, toCol: placement.col, toRow: placement.row + 1)
                    }
                }
            }

            Rectangle().fill(Theme.borderSubtle).frame(width: 1, height: 20).padding(.horizontal, 2)

            // Resize picker
            if let meta {
                Menu {
                    let minW = meta.supportedSizes.min.width
                    let maxW = meta.supportedSizes.max.width
                    let minH = meta.supportedSizes.min.height
                    let maxH = meta.supportedSizes.max.height
                    ForEach(minW...maxW, id: \.self) { w in
                        ForEach(minH...maxH, id: \.self) { h in
                            Button("\(w)x\(h)") {
                                layoutEngine.resizeWidget(pageId: pageId, instanceId: placement.instanceId, newWidth: w, newHeight: h)
                            }
                        }
                    }
                } label: {
                    Text("\(placement.width)x\(placement.height)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accentPurple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accentPurple.opacity(0.1), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }

            // Remove button
            Button {
                layoutEngine.removeWidget(pageId: pageId, instanceId: placement.instanceId)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.accentRed.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)

        // Widget config editor (if widget has configurable options)
        if let widget = registry.widget(for: placement.widgetId), !widget.configSchema.isEmpty {
            WidgetConfigEditor(
                schema: widget.configSchema,
                config: Binding(
                    get: { placement.config },
                    set: { newConfig in
                        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: placement.instanceId, config: newConfig)
                    }
                )
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        } // VStack end
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func stepperButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
