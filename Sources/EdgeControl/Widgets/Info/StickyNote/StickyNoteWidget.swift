import AppKit
import SwiftUI

// The widget: identity, sizes and the configuration the dashboard offers.

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
        ConfigSchemaEntry(
            key: "color", label: "Color", type: .picker, defaultValue: .string("yellow"),
            options: ["yellow", "orange", "pink", "red", "green", "mint", "blue", "purple", "gray"]),
        ConfigSchemaEntry(
            key: "textColor", label: "Text Color", type: .picker,
            defaultValue: .string("soft white"),
            options: [
                "soft white", "white", "gray", "black", "yellow", "orange",
                "pink", "red", "green", "mint", "blue", "purple",
            ]),
        ConfigSchemaEntry(
            key: "opacity", label: "Opacity", type: .slider, defaultValue: .double(0.5),
            minValue: 0.0, maxValue: 1.0, step: 0.05),
        ConfigSchemaEntry(
            key: "font", label: "Font", type: .picker, defaultValue: .string("mono"),
            options: ["system", "rounded", "serif", "mono", "marker", "noteworthy"]),
        ConfigSchemaEntry(
            key: "fontSize", label: "Font Size", type: .slider, defaultValue: .double(18),
            minValue: 10, maxValue: 24, step: 1),
    ]
    public let defaultColors = WidgetColors(primary: .yellow)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        StickyNoteWidgetView(
            note: config.string("note"),
            rtf: config.string("rtf"),
            colorName: config.string("color", default: "yellow"),
            textColorName: config.string("textColor", default: "soft white"),
            tintOpacity: config.double("opacity", default: 0.5),
            fontFamily: config.string("font", default: "mono"),
            fontSize: config.double("fontSize", default: 18),
            pageId: config.string("_pageId"),
            instanceId: config.string("_instanceId"),
            baseConfig: config
        )
    }
}

/// A markdown-lite rich note: type "- ", "- [ ] ", "# " or "---" and they
/// convert to bullets, checkboxes, headings and rules on the spot — the note
/// is rich text from then on, never markdown. Links paste as titled links.
/// Storage is RTF (with a plain-text mirror in "note" for the settings field
/// and for pre-RTF notes).
