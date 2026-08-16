import SwiftUI

public final class StickyNoteWidget: DashboardWidget {
    public let widgetId = "sticky-note"
    public let displayName = "Sticky Note"
    public let description = "A free-form note, edited in place and saved with the layout"
    public let iconName = "note.text"
    public let category: WidgetCategory = .info
    public let requiredServices: Set<ServiceKey> = []
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(8, 6))
    public let defaultSize = WidgetSize.size(3, 2)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "note", label: "Note", type: .text, defaultValue: .string("")),
    ]
    public let defaultColors = WidgetColors(primary: .yellow)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        StickyNoteWidgetView(
            note: config.string("note"),
            pageId: config.string("_pageId"),
            instanceId: config.string("_instanceId"),
            baseConfig: config
        )
    }
}

private struct StickyNoteWidgetView: View {
    let note: String
    let pageId: String
    let instanceId: String
    let baseConfig: WidgetConfig

    @EnvironmentObject private var layoutEngine: LayoutEngine
    @Environment(\.themeSettings) private var ts
    @State private var draft = ""
    @State private var seeded = false

    private var primary: Color { Theme.widgetPrimary("sticky-note", ts: ts, default: .yellow) }

    var body: some View {
        TextEditor(text: $draft)
            .font(Theme.body(ts))
            .foregroundStyle(Theme.text1(ts))
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .padding(Theme.compactPadding)
            .background(primary.opacity(0.10))
            .widgetCard()
            .onAppear {
                if !seeded {
                    draft = note
                    seeded = true
                }
            }
            // External edits (settings field, layout import) win over a
            // stale on-screen draft only when they actually differ.
            .onChange(of: note) { _, newValue in
                if newValue != draft { draft = newValue }
            }
            .onChange(of: draft) { _, newValue in
                save(newValue)
            }
    }

    private func save(_ text: String) {
        guard !instanceId.isEmpty, text != note else { return }
        // Strip the injected identity keys: they describe the render pass,
        // not the widget's persistent state.
        var config = baseConfig
        config["note"] = .string(text)
        config["_pageId"] = nil
        config["_instanceId"] = nil
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
    }
}
