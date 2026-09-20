import SwiftUI

/// Main dashboard container. Replaces UnifiedDashboardView.
/// Handles page navigation (swipe), gear icon for settings, page indicator dots.
struct DashboardShell: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @EnvironmentObject private var history: MetricsHistory
    @State private var editMode = false
    // Live paging: finger travel applied on top of the index offset.
    @State private var pageDragOffset: CGFloat = 0
    @State private var lastLiveDX: CGFloat = 0

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        GeometryReader { geo in
            let grid = DynamicGrid.calculate(width: geo.size.width, height: geo.size.height)

            ZStack {
                // Sync dynamic grid to LayoutEngine
                Color.clear.onAppear {
                    layoutEngine.currentGrid = grid
                }
                .onChange(of: grid) { _, newGrid in
                    layoutEngine.currentGrid = newGrid
                }
                .frame(width: 0, height: 0)
                // Background gradient — themed
                LinearGradient(
                    colors: Theme.backgroundColors(layoutEngine.document.globalSettings.theme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if geo.size.width < DynamicGrid.minimumWidth || geo.size.height < DynamicGrid.minimumHeight {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Display too small")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(
                            "Minimum \(Int(DynamicGrid.minimumWidth))×\(Int(DynamicGrid.minimumHeight)) points required"
                        )
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    }
                } else if model.systemMetrics != nil {
                    // Current page content
                    let pages = layoutEngine.sortedPages

                    // iPhone-style paging: every page sits in one wide
                    // HStack offset by the current index plus the live finger
                    // travel, so the content is attached to the finger and the
                    // settle direction is pure geometry. Only the current page
                    // and its neighbors render real content.
                    let pageWidth = geo.size.width
                    HStack(spacing: 0) {
                        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                            Group {
                                if abs(index - layoutEngine.currentPageIndex) <= 1 {
                                    GridPageView(
                                        page: page,
                                        registry: registry,
                                        gridColumns: grid.columns,
                                        gridRows: grid.rows,
                                        editMode: $editMode,
                                        layoutEngine: layoutEngine
                                    )
                                    .padding(8)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: pageWidth, height: geo.size.height)
                        }
                    }
                    .frame(width: pageWidth, height: geo.size.height, alignment: .leading)
                    .offset(x: -CGFloat(layoutEngine.currentPageIndex) * pageWidth + pageDragOffset)
                    // Without this the swipe only starts on a widget card: the
                    // gaps between cards draw nothing, and SwiftUI delivers
                    // gestures only where content exists. Same reason
                    // TouchTappable, TouchButton and TouchScrollView all set it.
                    .contentShape(Rectangle())
                    .gesture(
                        editMode
                            ? nil
                            : DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                    pageDragOffset = rubberBand(value.translation.width, pageCount: pages.count)
                                }
                                .onEnded { value in
                                    settlePages(dx: value.translation.width, pageCount: pages.count)
                                }
                    )
                    // Hardware finger: track while down, settle on release.
                    .onReceive(model.touchService.$liveSwipeDX) { dx in
                        guard !editMode else { return }
                        if let dx {
                            lastLiveDX = dx
                            pageDragOffset = rubberBand(dx, pageCount: pages.count)
                        } else if pageDragOffset != 0 {
                            let released = lastLiveDX
                            lastLiveDX = 0
                            settlePages(dx: released, pageCount: pages.count)
                        }
                    }

                    // Page indicator dots
                    pageIndicator(pageCount: pages.count)

                    // Gear icon (top-right)
                    gearButton()

                    // One widget, the whole panel. Drawn last so it sits over
                    // the pages, the indicator and the gear alike.
                    if let focus = layoutEngine.focusedWidget,
                        let placement = layoutEngine.placement(
                            pageId: focus.pageId, instanceId: focus.instanceId)
                    {
                        focusLayer(placement: placement, pageId: focus.pageId, grid: grid, size: geo.size)
                    }

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
        .unitSystem(layoutEngine.document.globalSettings.units)
        .coordinateSpace(name: TouchCoordinate.name)
        .onChange(of: model.systemMetrics) { _, newMetrics in
            if let m = newMetrics {
                history.record(cpu: m.cpuLoadPercent, memory: m.memoryUsedPercent)
            }
        }
        .background(
            WindowAccessor { window in
                WindowPlacement.configure(
                    window,
                    display: model.selectedDisplay,
                    kioskMode: layoutEngine.document.globalSettings.kioskMode,
                    strictMonitorAffinity: layoutEngine.document.globalSettings.strictMonitorAffinity,
                    allowSystemPanels: layoutEngine.document.globalSettings.allowSystemPanels
                )
            }
        )
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    layoutEngine.navigate(to: clamped)
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
        // The engine owns the edit session (the widget catalog can start one
        // by parking a widget on a full page); the local flag just mirrors it
        // for gesture gating and overlays.
        .onChange(of: layoutEngine.isEditing) { _, editing in
            withAnimation(.easeInOut(duration: 0.2)) {
                editMode = editing
            }
        }
    }

    // MARK: - Paging

    /// Dragging past the first/last page moves at one-third rate, iPhone-style.
    // MARK: - Focus

    /// The focused widget over a dimmed dashboard.
    ///
    /// The widget is asked to draw itself at the size of the grid rather than
    /// of its cell, so anything that lays itself out by the space it has —
    /// the weather widget, the note editor — uses the room it has been given.
    /// The size is clamped to what the widget says it supports, because a
    /// widget built for six rows has nothing to do with twenty columns.
    @ViewBuilder
    private func focusLayer(
        placement: WidgetPlacement, pageId: String, grid: DynamicGrid, size: CGSize
    ) -> some View {
        if let widget = registry.widget(for: placement.widgetId) {
            let maximum = widget.supportedSizes.max
            let width = min(grid.columns, maximum.width)
            let height = min(grid.rows, maximum.height)

            ZStack {
                // The backdrop dismisses. It is the one gesture nobody has to
                // be told about, and on a panel with no keyboard it is the
                // only way out that does not need one.
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { layoutEngine.clearFocus() }

                AnyView(
                    widget.body(
                        size: WidgetSize(width: width, height: height),
                        config: focusConfig(for: placement, pageId: pageId)
                    )
                )
                .frame(width: max(0, size.width - 32), height: max(0, size.height - 32))
                .overlay(alignment: .topTrailing) {
                    Button {
                        layoutEngine.clearFocus()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
            .transition(.opacity)
        }
    }

    /// The placement's own configuration plus the identity keys a widget
    /// needs to write itself back — the same pair GridPageView injects.
    private func focusConfig(for placement: WidgetPlacement, pageId: String) -> WidgetConfig {
        var config = placement.config
        config["_pageId"] = .string(pageId)
        config["_instanceId"] = .string(placement.instanceId)
        return config
    }

    private func rubberBand(_ dx: CGFloat, pageCount: Int) -> CGFloat {
        let index = layoutEngine.currentPageIndex
        let overshooting = (index == 0 && dx > 0) || (index >= pageCount - 1 && dx < 0)
        return overshooting ? dx / 3 : dx
    }

    /// One decision point for both input paths: past the threshold pages,
    /// short of it springs back — a single animated transaction either way.
    private func settlePages(dx: CGFloat, pageCount: Int) {
        let index = layoutEngine.currentPageIndex
        var target = index
        if dx < -100, index < pageCount - 1 { target = index + 1 }
        if dx > 100, index > 0 { target = index - 1 }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            layoutEngine.navigate(to: target)
            pageDragOffset = 0
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            layoutEngine.navigate(to: index)
                        }
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
                // The zone registry runs actions on the main actor, but the
                // closure itself is @Sendable, so hop explicitly for Swift 6.
                Task { @MainActor in
                    if layoutEngine.isEditing {
                        // Staged overlaps cannot be saved: keep the session
                        // open and bring the first offending page into view.
                        if layoutEngine.hasOverlaps {
                            if let idx = layoutEngine.sortedPages.firstIndex(where: {
                                !layoutEngine.overlappingInstanceIds(pageId: $0.id).isEmpty
                            }) {
                                layoutEngine.navigate(to: idx)
                            }
                            return
                        }
                        layoutEngine.isEditing = false
                        layoutEngine.save()
                    } else {
                        layoutEngine.isEditing = true
                    }
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
