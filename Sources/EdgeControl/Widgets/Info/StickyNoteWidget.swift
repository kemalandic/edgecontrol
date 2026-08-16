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
        ConfigSchemaEntry(key: "font", label: "Font", type: .picker, defaultValue: .string("system"),
                          options: ["system", "rounded", "serif", "mono", "marker", "noteworthy"]),
        ConfigSchemaEntry(key: "fontSize", label: "Font Size", type: .slider, defaultValue: .double(13),
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
            tintOpacity: config.double("opacity", default: 0.12),
            fontFamily: config.string("font", default: "system"),
            fontSize: config.double("fontSize", default: 13),
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
private struct StickyNoteWidgetView: View {
    let note: String
    let rtf: String
    let colorName: String
    let tintOpacity: Double
    let fontFamily: String
    let fontSize: Double
    let pageId: String
    let instanceId: String
    let baseConfig: WidgetConfig

    @EnvironmentObject private var layoutEngine: LayoutEngine
    @Environment(\.themeSettings) private var ts
    @State private var rtfDraft = ""
    @State private var plainDraft = ""
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
            rtfBase64: $rtfDraft,
            plainText: $plainDraft,
            legacyMarkdown: note,
            baseFont: RichStickyTextView.makeFont(family: fontFamily, size: fontSize * ts.fontScale),
            textColor: NSColor(Theme.text1(ts)),
            linkColor: NSColor(primary)
        )
        .padding(Theme.compactPadding)
        .background(primary.opacity(tintOpacity))
        .widgetCard()
        .onAppear {
            if !seeded {
                rtfDraft = rtf
                plainDraft = note
                seeded = true
            }
        }
        // External edits (settings field, layout import) win over a stale
        // on-screen draft only when they actually differ.
        .onChange(of: rtf) { _, newValue in
            if newValue != rtfDraft { rtfDraft = newValue }
        }
        // Debounced: saving mutates the layout document, and doing that per
        // keystroke re-rendered every widget on the dashboard per character.
        .onChange(of: rtfDraft) { _, _ in
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            save()
        }
    }

    private func save() {
        guard !instanceId.isEmpty, rtfDraft != rtf else { return }
        // Strip the injected identity keys: they describe the render pass,
        // not the widget's persistent state.
        var config = baseConfig
        config["rtf"] = .string(rtfDraft)
        config["note"] = .string(plainDraft)
        config["_pageId"] = nil
        config["_instanceId"] = nil
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
    }
}

// MARK: - Rich text view

private struct RichStickyTextView: NSViewRepresentable {
    @Binding var rtfBase64: String
    @Binding var plainText: String
    let legacyMarkdown: String
    let baseFont: NSFont
    let textColor: NSColor
    let linkColor: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let textView = LinkPasteTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFontPanel = true
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
        textView.defaultFont = baseFont
        textView.defaultColor = textColor
        textView.insertionPointColor = textColor
        context.coordinator.appliedFontKey = fontKey

        if let restored = Self.fromRTF(rtfBase64) {
            textView.textStorage?.setAttributedString(restored)
        } else {
            textView.textStorage?.setAttributedString(
                Self.parseLegacy(legacyMarkdown, font: baseFont, textColor: textColor)
            )
        }
        textView.typingAttributes = [.font: baseFont, .foregroundColor: textColor]
        textView.applyCheckboxCursors()

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? LinkPasteTextView else { return }
        textView.insertionPointColor = textColor
        // Reflow the whole note when the configured font family/size changes,
        // preserving bold/italic traits and relative (heading) sizes.
        if context.coordinator.appliedFontKey != fontKey {
            let ratio = baseFont.pointSize / textView.defaultFont.pointSize
            reapplyBaseFont(in: textView, ratio: ratio)
            textView.defaultFont = baseFont
            context.coordinator.appliedFontKey = fontKey
            context.coordinator.pushChanges(from: textView)
        }
        // Reload only on a genuine external change; echoing our own
        // keystrokes back through setAttributedString would fight the cursor.
        if Self.rtfString(textView.attributedString()) != rtfBase64,
           let restored = Self.fromRTF(rtfBase64) {
            textView.textStorage?.setAttributedString(restored)
            textView.applyCheckboxCursors()
        }
    }

    private var fontKey: String { "\(baseFont.fontName)-\(baseFont.pointSize)" }

    private func reapplyBaseFont(in textView: LinkPasteTextView, ratio: CGFloat) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let old = value as? NSFont else { return }
            let traits = old.fontDescriptor.symbolicTraits
            var descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
            if NSFont(descriptor: descriptor, size: 0) == nil { descriptor = baseFont.fontDescriptor }
            let newFont = NSFont(descriptor: descriptor, size: old.pointSize * ratio)
                ?? baseFont
            storage.addAttribute(.font, value: newFont, range: range)
        }
        storage.endEditing()
        textView.typingAttributes[.font] = baseFont
    }

    static func makeFont(family: String, size: Double) -> NSFont {
        let s = CGFloat(size)
        switch family {
        case "mono":
            return .monospacedSystemFont(ofSize: s, weight: .regular)
        case "rounded":
            let d = NSFont.systemFont(ofSize: s).fontDescriptor.withDesign(.rounded)
            return d.flatMap { NSFont(descriptor: $0, size: s) } ?? .systemFont(ofSize: s)
        case "serif":
            let d = NSFont.systemFont(ofSize: s).fontDescriptor.withDesign(.serif)
            return d.flatMap { NSFont(descriptor: $0, size: s) } ?? .systemFont(ofSize: s)
        case "marker":
            return NSFont(name: "Marker Felt", size: s) ?? .systemFont(ofSize: s)
        case "noteworthy":
            return NSFont(name: "Noteworthy", size: s) ?? .systemFont(ofSize: s)
        default:
            return .systemFont(ofSize: s)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichStickyTextView
        var appliedFontKey = ""
        init(_ parent: RichStickyTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            pushChanges(from: textView)
        }

        func pushChanges(from textView: NSTextView) {
            let attributed = textView.attributedString()
            parent.rtfBase64 = RichStickyTextView.rtfString(attributed)
            parent.plainText = RichStickyTextView.plainMirror(attributed)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            if let url { NSWorkspace.shared.open(url) }
            return true
        }
    }

    // MARK: Storage

    static func rtfString(_ attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let range = NSRange(location: 0, length: attributed.length)
        return attributed.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])?
            .base64EncodedString() ?? ""
    }

    static func fromRTF(_ base64: String) -> NSAttributedString? {
        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return nil }
        return NSAttributedString(rtf: data, documentAttributes: nil)
    }

    /// Plain mirror for the settings field / export readability: links keep
    /// their [title](url) form, formatting is dropped.
    static func plainMirror(_ attributed: NSAttributedString) -> String {
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

    /// Pre-RTF notes stored `[title](url)` markdown; parse once on load.
    static func parseLegacy(_ markdown: String, font: NSFont, textColor: NSColor) -> NSAttributedString {
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

// MARK: - The editor

/// Markdown-lite conversions at the keystroke, links on paste, glyph
/// checkboxes that toggle on click, and a strikethrough action for the
/// Format menu.
private final class LinkPasteTextView: NSTextView {
    var defaultFont: NSFont = .systemFont(ofSize: 13)
    var defaultColor: NSColor = .white

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: defaultColor]
    }

    /// Checkbox glyphs behave like controls, so hovering shows the hand, not
    /// the I-beam. The .cursor attribute is hover-only and never serializes
    /// into the RTF.
    override func didChangeText() {
        super.didChangeText()
        applyCheckboxCursors()
    }

    func applyCheckboxCursors() {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        var idx = 0
        while idx < ns.length {
            let ch = ns.substring(with: NSRange(location: idx, length: 1))
            if ch == "☐" || ch == "☑" {
                storage.addAttribute(.cursor, value: NSCursor.pointingHand,
                                     range: NSRange(location: idx, length: 1))
            }
            idx += 1
        }
    }

    private func headingFont(_ level: Int) -> NSFont {
        let scale: CGFloat = level == 1 ? 1.6 : level == 2 ? 1.35 : 1.15
        let descriptor = defaultFont.fontDescriptor.withSymbolicTraits(
            defaultFont.fontDescriptor.symbolicTraits.union(.bold)
        )
        return NSFont(descriptor: descriptor, size: defaultFont.pointSize * scale)
            ?? .boldSystemFont(ofSize: defaultFont.pointSize * scale)
    }

    // MARK: Typing conversions

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let str = (insertString as? String)
            ?? (insertString as? NSAttributedString)?.string ?? ""

        if str == " ", convertLinePrefix() { return }

        if str == "\n" {
            if convertHorizontalRule() { return }
            let continuation = listContinuation()
            super.insertText(insertString, replacementRange: replacementRange)
            // A heading ends at the line break; typing resumes as body text.
            typingAttributes = bodyAttributes
            if let continuation {
                super.insertText(continuation, replacementRange: selectedRange())
            }
            return
        }

        super.insertText(insertString, replacementRange: replacementRange)
    }

    /// "- " → bullet, "- [ ] " → checkbox, "# "/"## "/"### " → heading.
    /// Called when a space is typed; returns true when the space is consumed.
    private func convertLinePrefix() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        guard loc >= lineRange.location else { return false }
        let prefixRange = NSRange(location: lineRange.location, length: loc - lineRange.location)
        let prefix = ns.substring(with: prefixRange)

        switch prefix {
        case "-":
            replace(prefixRange, with: NSAttributedString(string: "•\u{00A0}", attributes: bodyAttributes))
            return true
        // "- " already became a bullet by the time "[ ]" is typed, so the
        // checkbox forms chain off the bullet. Conversion waits for the
        // CLOSING bracket — converting at "[" would make "[x]" untypeable.
        case "- [ ]", "- []", "•\u{00A0}[ ]", "•\u{00A0}[]":
            replace(prefixRange, with: NSAttributedString(string: "☐\u{00A0}", attributes: bodyAttributes))
            return true
        case "- [x]", "- [X]", "•\u{00A0}[x]", "•\u{00A0}[X]",
             "•\u{00A0}[ x]", "•\u{00A0}[ X]":
            replace(prefixRange, with: NSAttributedString(string: "☑\u{00A0}", attributes: bodyAttributes))
            return true
        case "#", "##", "###":
            replace(prefixRange, with: NSAttributedString(string: ""))
            var attrs = bodyAttributes
            attrs[.font] = headingFont(prefix.count)
            typingAttributes = attrs
            return true
        default:
            return false
        }
    }

    /// A line reading exactly "---" becomes a dim horizontal rule on return.
    private func convertHorizontalRule() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard line == "---" else { return false }
        var attrs = bodyAttributes
        attrs[.foregroundColor] = defaultColor.withAlphaComponent(0.35)
        let rule = NSMutableAttributedString(
            string: String(repeating: "─", count: 24) + "\n", attributes: attrs
        )
        replace(lineRange, with: rule)
        typingAttributes = bodyAttributes
        return true
    }

    /// Pressing return on a bullet/checkbox line continues the list; on an
    /// empty list line it ends it (handled by the caller inserting nothing —
    /// the empty marker line stays until deleted, matching most editors).
    private func listContinuation() -> String? {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        let line = ns.substring(with: lineRange)
        if line.hasPrefix("•\u{00A0}"), line.trimmingCharacters(in: .whitespacesAndNewlines) != "•" {
            return "•\u{00A0}"
        }
        if line.hasPrefix("☐\u{00A0}") || line.hasPrefix("☑\u{00A0}") {
            let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if stripped != "☐" && stripped != "☑" { return "☐\u{00A0}" }
        }
        return nil
    }

    private func replace(_ range: NSRange, with attributed: NSAttributedString) {
        guard shouldChangeText(in: range, replacementString: attributed.string) else { return }
        textStorage?.replaceCharacters(in: range, with: attributed)
        didChangeText()
    }

    // MARK: Checkbox toggling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let ns = string as NSString
        for candidate in [index, index - 1] where candidate >= 0 && candidate < ns.length {
            let char = ns.substring(with: NSRange(location: candidate, length: 1))
            if char == "☐" || char == "☑" {
                let range = NSRange(location: candidate, length: 1)
                let flipped = char == "☐" ? "☑" : "☐"
                guard shouldChangeText(in: range, replacementString: flipped) else { break }
                textStorage?.replaceCharacters(in: range, with: flipped)
                didChangeText()
                return
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Strikethrough (Format menu)

    @objc func toggleStrikethrough(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, let storage = textStorage else {
            let current = typingAttributes[.strikethroughStyle] as? Int ?? 0
            typingAttributes[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
        if current == 0 {
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        } else {
            storage.removeAttribute(.strikethroughStyle, range: range)
        }
        didChangeText()
    }

    // MARK: Link paste

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
            var attrs = bodyAttributes
            attrs[.link] = pasted
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
