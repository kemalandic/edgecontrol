import SwiftUI
import Testing
@testable import EdgeControl

/// The registry decides which services run: AppModel starts exactly what the
/// placed widgets ask for. Get requiredServices wrong and either a gauge shows
/// nothing, or a sensor keeps polling for a widget nobody has on screen.
@MainActor
@Suite("Widget registry")
struct WidgetRegistryTests {

    /// Stands in for a real widget. The protocol wants a view body; these tests
    /// never render one.
    private struct FakeWidget: DashboardWidget {
        let widgetId: String
        var displayName: String
        var category: WidgetCategory = .system
        var requiredServices: Set<ServiceKey> = []

        var description: String { "fake" }
        var iconName: String { "square" }
        var supportedSizes: WidgetSizeRange { WidgetSizeRange(min: .size(1, 1), max: .size(4, 4)) }
        var defaultSize: WidgetSize { .size(2, 2) }
        var isConfigurable: Bool { false }
        var configSchema: [ConfigSchemaEntry] { [] }
        var defaultColors: WidgetColors { WidgetColors(primary: .cyan) }

        func body(size: WidgetSize, config: WidgetConfig) -> any View { EmptyView() }
        func settingsBody(config: Binding<WidgetConfig>) -> any View { EmptyView() }
    }

    private func registry(_ widgets: [FakeWidget]) -> WidgetRegistry {
        let r = WidgetRegistry()
        widgets.forEach { r.register($0) }
        return r
    }

    private func document(_ placements: [(page: Int, widgetId: String)]) -> LayoutDocument {
        var pages: [PageConfig] = []
        for pageIndex in Set(placements.map(\.page)).sorted() {
            let widgets = placements.filter { $0.page == pageIndex }.enumerated().map {
                WidgetPlacement(widgetId: $1.widgetId, col: $0 * 2, row: 0, width: 2, height: 2)
            }
            pages.append(PageConfig(name: "p\(pageIndex)", order: pageIndex, widgets: widgets))
        }
        return LayoutDocument(pages: pages)
    }

    // MARK: required services

    @Test("only placed widgets contribute services")
    func onlyPlacedWidgetsCount() {
        let r = registry([
            FakeWidget(widgetId: "cpu", displayName: "CPU", requiredServices: [.metrics]),
            FakeWidget(widgetId: "temp", displayName: "Temp", requiredServices: [.smc]),
        ])
        let services = r.requiredServices(for: document([(0, "cpu")]))
        #expect(services == [.metrics], "an unplaced widget kept its service running")
    }

    @Test("services are collected across every page, not just the visible one")
    func servicesSpanPages() {
        let r = registry([
            FakeWidget(widgetId: "cpu", displayName: "CPU", requiredServices: [.metrics]),
            FakeWidget(widgetId: "net", displayName: "Net", requiredServices: [.network]),
        ])
        let services = r.requiredServices(for: document([(0, "cpu"), (1, "net")]))
        #expect(services == [.metrics, .network])
    }

    @Test("a service two widgets share is counted once")
    func sharedServiceDeduped() {
        let r = registry([
            FakeWidget(widgetId: "cpu", displayName: "CPU", requiredServices: [.metrics]),
            FakeWidget(widgetId: "mem", displayName: "Mem", requiredServices: [.metrics]),
        ])
        #expect(r.requiredServices(for: document([(0, "cpu"), (0, "mem")])) == [.metrics])
    }

    /// A layout can name a widget this build does not have — a plugin that was
    /// uninstalled, or a file from a newer version. It must be skipped, not
    /// crash the startup path that decides what to run.
    @Test("a placement naming an unknown widget is skipped")
    func unknownWidgetIsSkipped() {
        let r = registry([FakeWidget(widgetId: "cpu", displayName: "CPU", requiredServices: [.metrics])])
        #expect(r.requiredServices(for: document([(0, "cpu"), (0, "ghost")])) == [.metrics])
    }

    @Test("an empty layout needs no services")
    func emptyLayoutNeedsNothing() {
        let r = registry([FakeWidget(widgetId: "cpu", displayName: "CPU", requiredServices: [.metrics])])
        #expect(r.requiredServices(for: LayoutDocument()).isEmpty)
    }

    /// Self-contained widgets — a clock reads no sensor — must not pull a
    /// service in by being placed.
    @Test("a widget requiring nothing contributes nothing")
    func selfContainedWidget() {
        let r = registry([FakeWidget(widgetId: "clock", displayName: "Clock")])
        #expect(r.requiredServices(for: document([(0, "clock")])).isEmpty)
    }

    // MARK: catalog

    @Test("the catalog is ordered by display name")
    func catalogIsSorted() {
        let r = registry([
            FakeWidget(widgetId: "z", displayName: "Zebra"),
            FakeWidget(widgetId: "a", displayName: "Apple"),
            FakeWidget(widgetId: "m", displayName: "Mango"),
        ])
        #expect(r.allWidgets.map(\.displayName) == ["Apple", "Mango", "Zebra"])
    }

    @Test("only categories with widgets in them are listed")
    func categoriesReflectContents() {
        let r = registry([
            FakeWidget(widgetId: "cpu", displayName: "CPU", category: .system),
            FakeWidget(widgetId: "clock", displayName: "Clock", category: .info),
        ])
        #expect(Set(r.categories) == [.system, .info])
        #expect(r.widgets(in: .system).map(\.widgetId) == ["cpu"])
        #expect(r.widgets(in: .network).isEmpty)
    }

    @Test("unregistering removes a widget from lookup and the catalog")
    func unregisterRemoves() {
        let r = registry([FakeWidget(widgetId: "cpu", displayName: "CPU")])
        r.unregister(widgetId: "cpu")
        #expect(r.widget(for: "cpu") == nil)
        #expect(r.allWidgets.isEmpty)
    }

    @Test("metadata is nil for a widget that is not registered")
    func metadataForUnknown() {
        let r = registry([FakeWidget(widgetId: "cpu", displayName: "CPU")])
        #expect(r.metadata(for: "cpu") != nil)
        #expect(r.metadata(for: "ghost") == nil)
    }
}
