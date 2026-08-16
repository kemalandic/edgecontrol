import AppKit
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
        ConfigSchemaEntry(key: "color", label: "Color", type: .picker, defaultValue: .string("yellow"),
                          options: ["yellow", "orange", "pink", "red", "green", "mint", "blue", "purple", "gray"]),
        ConfigSchemaEntry(key: "opacity", label: "Opacity", type: .slider, defaultValue: .double(0.12),
                          minValue: 0.0, maxValue: 1.0, step: 0.05),
    ]
    public let defaultColors = WidgetColors(primary: .yellow)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        StickyNoteWidgetView(
            note: config.string("note"),
            colorName: config.string("color", default: "yellow"),
            tintOpacity: config.double("opacity", default: 0.12),
            pageId: config.string("_pageId"),
            instanceId: config.string("_instanceId"),
            baseConfig: config
        )
    }
}

/// Always-editable rich text: links live inline as styled, clickable titles.
/// Storage stays plain — links serialize to `[title](url)` in the config, so
/// notes round-trip through export/import and the settings field.
private struct StickyNoteWidgetView: View {
    let note: String
    let colorName: String
    let tintOpacity: Double
    let pageId: String
    let instanceId: String
    let baseConfig: WidgetConfig

    @EnvironmentObject private var layoutEngine: LayoutEngine
    @Environment(\.themeSettings) private var ts
    @State private var draft = ""
    @State private var seeded = false
    @State private var saveTask: Task<Void, Never>?

    private var primary: Color {
        switch colorName {
        case "orange": .orange
        case "pink": .pink
        case "red": .red
        case "green": .green
        case "mint": .mint
        case "blue": .blue
        case "purple": .purple
        case "gray": .gray
        default: Theme.widgetPrimary("sticky-note", ts: ts, default: .yellow)
        }
    }

    var body: some View {
        RichStickyTextView(
            markdown: $draft,
            font: NSFont.systemFont(ofSize: 13 * ts.fontScale),
            textColor: NSColor(Theme.text1(ts)),
            linkColor: NSColor(primary)
        )
        .padding(Theme.compactPadding)
        .background(primary.opacity(tintOpacity))
        .widgetCard()
        .onAppear {
            if !seeded {
                draft = note
                seeded = true
            }
        }
        // External edits (settings field, layout import) win over a stale
        // on-screen draft only when they actually differ.
        .onChange(of: note) { _, newValue in
            if newValue != draft { draft = newValue }
        }
        // Debounced: saving mutates the layout document, and doing that per
        // keystroke re-rendered every widget on the dashboard per character.
        .onChange(of: draft) { _, newValue in
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                save(newValue)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            save(draft)
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

// MARK: - Rich text view

/// NSTextView wrapper: rich in the view, `[title](url)` in storage. Pasting
/// a URL over selected text linkifies the selection; pasting a bare URL asks
/// for a title. Clicking a link opens it, even while editable.
private struct RichStickyTextView: NSViewRepresentable {
    @Binding var markdown: String
    let font: NSFont
    let textColor: NSColor
    let linkColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LinkPasteTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.focusRingType = .none
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        applyStyle(to: textView)
        textView.textStorage?.setAttributedString(
            Self.parse(markdown, font: font, textColor: textColor)
        )

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? LinkPasteTextView else { return }
        applyStyle(to: textView)
        // Only reload content on a genuine external change; echoing our own
        // keystrokes back through setAttributedString would fight the cursor.
        if Self.serialize(textView.attributedString()) != markdown {
            textView.textStorage?.setAttributedString(
                Self.parse(markdown, font: font, textColor: textColor)
            )
        }
    }

    private func applyStyle(to textView: LinkPasteTextView) {
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.defaultFont = font
        textView.defaultColor = textColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichStickyTextView
        init(_ parent: RichStickyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.markdown = RichStickyTextView.serialize(textView.attributedString())
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            if let url { NSWorkspace.shared.open(url) }
            return true
        }
    }

    // MARK: Markdown round-trip (links only, nothing else interpreted)

    static func serialize(_ attributed: NSAttributedString) -> String {
        var out = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            let text = attributed.attributedSubstring(from: range).string
            if let link = attrs[.link] {
                let url = (link as? URL)?.absoluteString ?? (link as? String ?? "")
                out += "[\(text)](\(url))"
            } else {
                out += text
            }
        }
        return out
    }

    static func parse(_ markdown: String, font: NSFont, textColor: NSColor) -> NSAttributedString {
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let result = NSMutableAttributedString()
        var rest = Substring(markdown)
        let pattern = /\[([^\]]+)\]\(([^)\s]+)\)/
        while let match = rest.firstMatch(of: pattern) {
            result.append(NSAttributedString(string: String(rest[rest.startIndex..<match.range.lowerBound]), attributes: plain))
            var linkAttrs = plain
            linkAttrs[.link] = String(match.2)
            result.append(NSAttributedString(string: String(match.1), attributes: linkAttrs))
            rest = rest[match.range.upperBound...]
        }
        result.append(NSAttributedString(string: String(rest), attributes: plain))
        return result
    }
}

/// The paste override that makes URLs become links instead of sprawling text.
private final class LinkPasteTextView: NSTextView {
    var defaultFont: NSFont = .systemFont(ofSize: 13)
    var defaultColor: NSColor = .white

    override func paste(_ sender: Any?) {
        guard let pasted = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            isLink(pasted)
        else {
            super.paste(sender)
            return
        }

        let range = selectedRange()
        if range.length > 0 {
            // Slack-style: the selected words become the link title.
            guard shouldChangeText(in: range, replacementString: nil) else { return }
            textStorage?.addAttribute(.link, value: pasted, range: range)
            didChangeText()
        } else if let title = Self.promptForTitle(defaultTitle: URL(string: pasted)?.host ?? "link") {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: defaultFont, .foregroundColor: defaultColor, .link: pasted,
            ]
            insertText(NSAttributedString(string: title, attributes: attrs), replacementRange: range)
            // Continued typing must not extend the link.
            typingAttributes[.link] = nil
        }
    }

    private func isLink(_ s: String) -> Bool {
        guard !s.contains(" "), let url = URL(string: s),
              let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private static func promptForTitle(defaultTitle: String) -> String? {
        let alert = NSAlert()
        alert.messageText = "Name this link"
        alert.informativeText = "The note shows the title; the link stays underneath."
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = defaultTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let typed = field.stringValue.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? defaultTitle : typed
    }
}
