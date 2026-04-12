import SwiftUI
import WidgetKit

struct PluginDesktopWidget: Widget {
    let kind = "PluginWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PluginSelectionIntent.self, provider: PluginWidgetProvider()) { entry in
            PluginWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Plugin")
        .description("Display a plugin as a desktop widget")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PluginWidgetView: View {
    let entry: PluginWidgetEntry

    var body: some View {
        if let image = entry.snapshotImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else if entry.isPlaceholder || entry.pluginId == nil {
            VStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 28))
                    .foregroundStyle(WidgetColors.textTertiary)
                Text(entry.pluginName ?? "Select Plugin")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
                Text("Long press to configure")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary.opacity(0.6))
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 24))
                    .foregroundStyle(WidgetColors.textTertiary)
                Text(entry.pluginName ?? "Plugin")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(WidgetColors.textSecondary)
                Text("Waiting for snapshot...")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
            }
        }
    }
}
