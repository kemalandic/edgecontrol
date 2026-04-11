import SwiftUI

/// Main dashboard container. Replaces UnifiedDashboardView.
/// Handles page navigation (swipe), gear icon for settings, page indicator dots.
struct DashboardShell: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @EnvironmentObject private var history: MetricsHistory
    @State private var editMode = false

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background gradient — themed
                LinearGradient(
                    colors: Theme.backgroundColors(layoutEngine.document.globalSettings.theme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if model.systemMetrics != nil {
                    // Current page content
                    let pages = layoutEngine.sortedPages

                    ZStack {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            if index == layoutEngine.currentPageIndex {
                                GridPageView(
                                    page: page,
                                    registry: registry,
                                    gridColumns: layoutEngine.document.grid.columns,
                                    gridRows: layoutEngine.document.grid.rows,
                                    editMode: $editMode,
                                    layoutEngine: layoutEngine
                                )
                                .padding(8)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing),
                                    removal: .move(edge: .leading)
                                ))
                            }
                        }
                    }
                    .gesture(
                        editMode ? nil : DragGesture(minimumDistance: 60)
                            .onEnded { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                withAnimation {
                                    if value.translation.width < 0 && layoutEngine.currentPageIndex < pages.count - 1 {
                                        layoutEngine.currentPageIndex += 1
                                    } else if value.translation.width > 0 && layoutEngine.currentPageIndex > 0 {
                                        layoutEngine.currentPageIndex -= 1
                                    }
                                }
                            }
                    )
                    .animation(.easeInOut(duration: 0.3), value: layoutEngine.currentPageIndex)

                    // Page indicator dots
                    pageIndicator(pageCount: pages.count)

                    // Gear icon (top-right)
                    gearButton()

                } else {
                    // Loading state
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(accent)
                            .scaleEffect(1.5)
                        Text("COLLECTING SYSTEM DATA")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .themeSettings(layoutEngine.document.globalSettings.theme)
        .coordinateSpace(name: TouchCoordinate.name)
        .onChange(of: model.systemMetrics) { _, newMetrics in
            if let m = newMetrics {
                history.record(cpu: m.cpuLoadPercent, memory: m.memoryUsedPercent)
            }
        }
        .background(WindowAccessor { window in
            WindowPlacement.configure(
                window,
                display: model.selectedDisplay,
                kioskMode: layoutEngine.document.globalSettings.kioskMode,
                isDevKit: model.isDevKitMode
            )
        })
        .onAppear {
            model.startIfNeeded()
            // Sync initial page
            layoutEngine.currentPageIndex = model.currentPage
        }
        // Hardware touch swipe → model.currentPage → sync to layoutEngine
        .onChange(of: model.currentPage) { _, newPage in
            let clamped = min(max(newPage, 0), layoutEngine.pageCount - 1)
            if model.currentPage != clamped { model.currentPage = clamped }
            if layoutEngine.currentPageIndex != clamped {
                withAnimation(.easeInOut(duration: 0.3)) {
                    layoutEngine.currentPageIndex = clamped
                }
            }
        }
        // UI swipe → layoutEngine.currentPageIndex → sync back to model
        .onChange(of: layoutEngine.currentPageIndex) { _, newIndex in
            if model.currentPage != newIndex {
                model.currentPage = newIndex
            }
        }
        // Update active services when layout changes (widget add/remove)
        .onChange(of: layoutEngine.layoutVersion) { _, _ in
            let needed = registry.requiredServices(for: layoutEngine.document)
            model.updateActiveServices(neededServices: needed)
        }
    }

    // MARK: - Page Indicator

    private func pageIndicator(pageCount: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == layoutEngine.currentPageIndex ? accent : .white.opacity(0.20))
                    .frame(
                        width: index == layoutEngine.currentPageIndex ? 10 : 7,
                        height: index == layoutEngine.currentPageIndex ? 10 : 7
                    )
                    .animation(.easeInOut(duration: 0.2), value: layoutEngine.currentPageIndex)
                    .onTapGesture {
                        withAnimation { layoutEngine.currentPageIndex = index }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
    }

    // MARK: - Gear Button


    private func gearButton() -> some View {
        return HStack(spacing: 6) {
            // Edit mode toggle
            TouchButton(
                id: "edit_toggle",
                label: "\n",
                isActive: editMode,
                activeColor: accent,
                registry: model.touchService.zoneRegistry
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    editMode.toggle()
                }
            }
            .overlay {
                Image(systemName: editMode ? "checkmark" : "pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(editMode ? accent : .white.opacity(0.5))
                    .allowsHitTesting(false)
            }
            .frame(width: 36, height: 36)

            // Settings button
            TouchButton(
                id: "settings_gear",
                label: "\n",
                isActive: false,
                activeColor: accent,
                registry: model.touchService.zoneRegistry
            ) {
                DispatchQueue.main.async {
                    SettingsWindowController.shared.show()
                }
            }
            .overlay {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
                    .allowsHitTesting(false)
            }
            .frame(width: 36, height: 36)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 6)
        .padding(.trailing, 10)
    }
}

// TouchCoordinate is defined in TouchButton.swift
