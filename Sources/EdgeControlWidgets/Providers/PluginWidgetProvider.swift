import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Plugin Selection Intent

struct PluginSelectionIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Plugin"
    static let description: IntentDescription = "Choose which plugin to display"

    @Parameter(title: "Plugin")
    var plugin: PluginWidgetEntity?
}

struct PluginWidgetEntity: AppEntity {
    let id: String
    let name: String
    let icon: String?

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Plugin")

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = PluginWidgetQuery()
}

struct PluginWidgetQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PluginWidgetEntity] {
        let manifest = PluginWidgetManifest.read()
        return manifest?.plugins
            .filter { identifiers.contains($0.id) }
            .map { PluginWidgetEntity(id: $0.id, name: $0.name, icon: $0.icon) }
            ?? []
    }

    func suggestedEntities() async throws -> [PluginWidgetEntity] {
        let manifest = PluginWidgetManifest.read()
        return manifest?.plugins
            .map { PluginWidgetEntity(id: $0.id, name: $0.name, icon: $0.icon) }
            ?? []
    }

    func defaultResult() async -> PluginWidgetEntity? {
        let manifest = PluginWidgetManifest.read()
        guard let first = manifest?.plugins.first else { return nil }
        return PluginWidgetEntity(id: first.id, name: first.name, icon: first.icon)
    }
}

// MARK: - Timeline Entry

struct PluginWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let pluginId: String?
    let pluginName: String?
    let snapshotImage: NSImage?
    let isPlaceholder: Bool

    static let placeholder = PluginWidgetEntry(
        date: Date(), pluginId: nil, pluginName: "Plugin",
        snapshotImage: nil, isPlaceholder: true
    )
}

// MARK: - Timeline Provider

struct PluginWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PluginWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: PluginSelectionIntent, in context: Context) async -> PluginWidgetEntry {
        entry(for: configuration, family: context.family)
    }

    func timeline(for configuration: PluginSelectionIntent, in context: Context) async -> Timeline<PluginWidgetEntry> {
        let entry = entry(for: configuration, family: context.family)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func entry(for configuration: PluginSelectionIntent, family: WidgetFamily) -> PluginWidgetEntry {
        guard let plugin = configuration.plugin else {
            return .placeholder
        }

        let sizeLabel: String
        switch family {
        case .systemSmall: sizeLabel = "small"
        case .systemMedium: sizeLabel = "medium"
        case .systemLarge: sizeLabel = "large"
        default: sizeLabel = "medium"
        }

        let image = loadSnapshot(pluginId: plugin.id, size: sizeLabel)

        return PluginWidgetEntry(
            date: Date(),
            pluginId: plugin.id,
            pluginName: plugin.name,
            snapshotImage: image,
            isPlaceholder: false
        )
    }

    private func loadSnapshot(pluginId: String, size: String) -> NSImage? {
        guard let url = PluginWidgetManifest.snapshotURL(pluginId: pluginId, size: size),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }
}
