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
        ConfigSchemaEntry(key: "textColor", label: "Text Color", type: .picker,
                          defaultValue: .string("soft white"),
                          options: ["soft white", "white", "gray", "black", "yellow", "orange",
                                    "pink", "red", "green", "mint", "blue", "purple"]),
        ConfigSchemaEntry(key: "opacity", label: "Opacity", type: .slider, defaultValue: .double(0.5),
                          minValue: 0.0, maxValue: 1.0, step: 0.05),
        ConfigSchemaEntry(key: "font", label: "Font", type: .picker, defaultValue: .string("mono"),
                          options: ["system", "rounded", "serif", "mono", "marker", "noteworthy"]),
        ConfigSchemaEntry(key: "fontSize", label: "Font Size", type: .slider, defaultValue: .double(18),
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
private struct StickyNoteWidgetView: View {
    let note: String
    let rtf: String
    let colorName: String
    let textColorName: String
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

    /// "soft white" is a touch darker than pure white — easier on the eyes
    /// against the tinted card.
    private var textNSColor: NSColor {
        switch textColorName {
        case "white": .white
        case "gray": .systemGray
        case "black": .black
        case "yellow": .systemYellow
        case "orange": .systemOrange
        case "pink": .systemPink
        case "red": .systemRed
        case "green": .systemGreen
        case "mint": .systemMint
        case "blue": .systemBlue
        case "purple": .systemPurple
        default: NSColor(white: 0.85, alpha: 1)
        }
    }

    var body: some View {
        RichStickyTextView(
            rtfBase64: $rtfDraft,
            plainText: $plainDraft,
            legacyMarkdown: note,
            baseFont: RichStickyTextView.makeFont(family: fontFamily, size: fontSize * ts.fontScale),
            textColor: textNSColor,
            linkColor: NSColor(primary),
            onFontSizeDelta: { delta in persistFontSize(fontSize + delta) },
            onFontSizeReset: { persistFontSize(18) }
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

    /// 18 is the schema default; Cmd+0 snaps back to it.
    private func persistFontSize(_ newSize: Double) {
        guard !instanceId.isEmpty else { return }
        var config = baseConfig
        config["fontSize"] = .double(min(24, max(10, newSize)))
        // Carry the live drafts so the size write can't clobber newer text
        // than the config snapshot holds.
        config["rtf"] = .string(rtfDraft)
        config["note"] = .string(plainDraft)
        config["_pageId"] = nil
        config["_instanceId"] = nil
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
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
    let onFontSizeDelta: (Double) -> Void
    let onFontSizeReset: () -> Void

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
        context.coordinator.appliedColorKey = colorKey

        if let restored = Self.fromRTF(rtfBase64) {
            textView.textStorage?.setAttributedString(restored)
        } else {
            textView.textStorage?.setAttributedString(
                Self.parseLegacy(legacyMarkdown, font: baseFont, textColor: textColor)
            )
        }
        textView.accentColor = linkColor
        textView.onFontSizeDelta = onFontSizeDelta
        textView.onFontSizeReset = onFontSizeReset
        textView.typingAttributes = [.font: baseFont, .foregroundColor: textColor]
        textView.normalizeCheckboxes()

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
        textView.accentColor = linkColor
        textView.onFontSizeDelta = onFontSizeDelta
        textView.onFontSizeReset = onFontSizeReset
        let fontChanged = context.coordinator.appliedFontKey != fontKey
        let colorChanged = context.coordinator.appliedColorKey != colorKey
        // Reload only on a genuine external change — and never on the pass
        // that changes the font or color: the binding still holds the
        // pre-restyle RTF then, and reloading from it would undo the reflow
        // or recolor (the bug that shipped first).
        if !fontChanged, !colorChanged,
           Self.rtfString(textView.attributedString()) != rtfBase64,
           let restored = Self.fromRTF(rtfBase64) {
            textView.textStorage?.setAttributedString(restored)
            textView.normalizeCheckboxes()
        }
        // Reflow when the configured family/size changes, preserving traits
        // and relative heading sizes; checkboxes redraw to match.
        if fontChanged {
            let ratio = baseFont.pointSize / textView.defaultFont.pointSize
            reapplyBaseFont(in: textView, ratio: ratio)
            textView.defaultFont = baseFont
            context.coordinator.appliedFontKey = fontKey
            textView.refreshCheckboxImages()
            textView.normalizeCheckboxes()
            // Push the scaled content on the next runloop tick: binding
            // writes during a SwiftUI update pass are unreliable.
            let coordinator = context.coordinator
            DispatchQueue.main.async { coordinator.pushChanges(from: textView) }
        }
        // Recolor when the configured text color changes: every non-link
        // run takes the new color (dimmed runs like rules keep their alpha),
        // and the checkboxes redraw their strokes to match.
        if colorChanged {
            textView.defaultColor = textColor
            recolorText(in: textView)
            context.coordinator.appliedColorKey = colorKey
            textView.refreshCheckboxImages()
            textView.normalizeCheckboxes()
            let coordinator = context.coordinator
            DispatchQueue.main.async { coordinator.pushChanges(from: textView) }
        }
    }

    private var fontKey: String { "\(baseFont.fontName)-\(baseFont.pointSize)" }
    private var colorKey: String { textColor.description }

    private func recolorText(in textView: LinkPasteTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if storage.attribute(.link, at: range.location, effectiveRange: nil) != nil { return }
            let alpha = (value as? NSColor)?.alphaComponent ?? 1
            let color = alpha < 1 ? textColor.withAlphaComponent(alpha) : textColor
            storage.addAttribute(.foregroundColor, value: color, range: range)
        }
        storage.endEditing()
        textView.typingAttributes[.foregroundColor] = textColor
    }

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
        var appliedColorKey = ""
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

    /// Drawn checkboxes live only in the view; storage keeps the glyph
    /// characters, so RTF, the plain mirror and pre-attachment notes all
    /// stay compatible.
    static func rtfString(_ attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let mapped = NSMutableAttributedString()
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attrs, range, _ in
            if let box = attrs[.attachment] as? CheckboxAttachment {
                var plain = attrs
                plain.removeValue(forKey: .attachment)
                plain.removeValue(forKey: .cursor)
                mapped.append(NSAttributedString(string: box.checked ? "☑" : "☐", attributes: plain))
            } else {
                mapped.append(attributed.attributedSubstring(from: range))
            }
        }
        let range = NSRange(location: 0, length: mapped.length)
        return mapped.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])?
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
            if let box = attrs[.attachment] as? CheckboxAttachment {
                out += box.checked ? "☑" : "☐"
            } else if let link = attrs[.link] {
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
    var defaultFont: NSFont = .systemFont(ofSize: 18)
    var defaultColor: NSColor = .white
    var accentColor: NSColor = .systemYellow
    var onFontSizeDelta: ((Double) -> Void)?
    var onFontSizeReset: (() -> Void)?
    private var isNormalizing = false

    @objc func increaseFontSize(_ sender: Any?) { onFontSizeDelta?(1) }
    @objc func decreaseFontSize(_ sender: Any?) { onFontSizeDelta?(-1) }
    @objc func resetFontSize(_ sender: Any?) { onFontSizeReset?() }

    /// Checkbox images are sized against the body font; redraw them when it
    /// changes so boxes and text scale together.
    func refreshCheckboxImages() {
        guard let storage = textStorage else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let box = value as? CheckboxAttachment else { return }
            let fresh = CheckboxAttachment.make(
                checked: box.checked, font: defaultFont,
                stroke: defaultColor, accent: accentColor
            )
            storage.addAttribute(.attachment, value: fresh, range: range)
        }
    }

    /// Marker Felt and Noteworthy set their letters so tight on the small
    /// panel that they blur together; a little tracking keeps them legible.
    private var noteKern: CGFloat {
        switch defaultFont.familyName {
        case "Marker Felt", "Noteworthy": return defaultFont.pointSize * 0.08
        default: return 0
        }
    }

    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: defaultFont, .foregroundColor: defaultColor,
         .paragraphStyle: bodyParagraph, .kern: noteKern]
    }

    /// Shared rhythm for body, bullet and checkbox lines.
    private var bodyParagraph: NSParagraphStyle {
        paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: 0)
    }

    /// Column where list text begins; markers sit before a tab. Wide
    /// enough for a two-digit number and its dot, whatever the note font —
    /// a marker wider than its column would push the tab a full extra
    /// column to the right.
    private var listTextIndent: CGFloat {
        let twoDigits = ("88." as NSString).size(withAttributes: [.font: defaultFont]).width
        return max((defaultFont.pointSize * 1.8).rounded(),
                   (twoDigits + defaultFont.pointSize * 0.5).rounded())
    }

    /// One Tab/Shift-Tab step — the width of the list column, so nested
    /// list text lands exactly one column further in.
    private var indentStep: CGFloat { listTextIndent }
    private let maxIndentLevel = 6

    /// Markers right-align to a shared edge just before the text column:
    /// number dots line up regardless of digit count, the checkbox's right
    /// side sits on that edge, and the narrow bullet is centered over the
    /// checkbox. Keeps every marker close to its text.
    private func markerInset(for line: String) -> CGFloat {
        let columnEnd = listTextIndent - defaultFont.pointSize * 0.45
        let boxWidth = defaultFont.pointSize * 1.2
        if line.hasPrefix("\u{FFFC}\t") { return max(0, (columnEnd - boxWidth).rounded()) }
        if line.hasPrefix("•\t") {
            let bulletWidth = ("•" as NSString).size(withAttributes: [.font: defaultFont]).width
            return max(0, (columnEnd - boxWidth + (boxWidth - bulletWidth) / 2).rounded())
        }
        guard let tab = line.firstIndex(of: "\t") else { return 0 }
        let width = (String(line[..<tab]) as NSString).size(withAttributes: [.font: defaultFont]).width
        return max(0, (columnEnd - width).rounded())
    }

    private var listParagraph: NSParagraphStyle {
        paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: 0)
    }

    /// Headings breathe a little more, especially above.
    private var headingParagraph: NSParagraphStyle {
        paragraphStyle(isHeading: true, isList: false, markerInset: 0, level: 0)
    }

    /// Single source of paragraph geometry: spacing rhythm per line kind
    /// plus the Tab/Shift-Tab indent level. List lines keep one shared
    /// text column (marker, tab, text) shifted right per level, with
    /// wrapped lines hanging under the text.
    private func paragraphStyle(isHeading: Bool, isList: Bool, markerInset: CGFloat, level: Int) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        let indent = CGFloat(level) * indentStep
        if isHeading {
            p.paragraphSpacing = defaultFont.pointSize * 0.3
            p.paragraphSpacingBefore = defaultFont.pointSize * 0.5
            p.firstLineHeadIndent = indent
            p.headIndent = indent
        } else if isList {
            p.paragraphSpacing = defaultFont.pointSize * 0.22
            p.firstLineHeadIndent = indent + markerInset
            p.tabStops = [NSTextTab(textAlignment: .left, location: indent + listTextIndent)]
            p.defaultTabInterval = listTextIndent
            p.headIndent = indent + listTextIndent
        } else {
            p.paragraphSpacing = defaultFont.pointSize * 0.22
            p.firstLineHeadIndent = indent
            p.headIndent = indent
        }
        return p
    }

    /// The indent level is never stored separately — it is recovered from
    /// the geometry of the line's current style, so it survives saves,
    /// loads and every re-normalization pass.
    private func indentLevel(of style: NSParagraphStyle?, isList: Bool) -> Int {
        guard let style else { return 0 }
        let base = isList
            ? (style.tabStops.first?.location ?? listTextIndent) - listTextIndent
            : style.firstLineHeadIndent
        return max(0, min(maxIndentLevel, Int((base / indentStep).rounded())))
    }

    /// Leading marker of a line — "•", a drawn checkbox, or "N." — with its
    /// trailing tab. 0 when the line is not a list item.
    private func markerLength(of line: String) -> Int {
        if line.hasPrefix("•\t") || line.hasPrefix("\u{FFFC}\t") { return 2 }
        guard let tab = line.firstIndex(of: "\t") else { return 0 }
        let head = line[..<tab]
        guard head.hasSuffix("."), head.count <= 6, !head.dropLast().isEmpty,
              Int(head.dropLast()) != nil else { return 0 }
        return (String(line[...tab]) as NSString).length
    }

    private var listAttributes: [NSAttributedString.Key: Any] {
        listAttributes(level: 0)
    }

    private func listAttributes(level: Int) -> [NSAttributedString.Key: Any] {
        var a = bodyAttributes
        a[.paragraphStyle] = paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: level)
        return a
    }

    override func didChangeText() {
        // Normalize BEFORE notifying: renumbering can rewrite characters,
        // and observers (the SwiftUI binding) must capture the final text.
        // A stale capture makes the next render reload the view from old
        // RTF, throwing the caret to the end of the note.
        if !isNormalizing {
            isNormalizing = true
            normalizeCheckboxes()
            isNormalizing = false
            // Deleting everything must also clear the invisible pen: with no
            // neighbor to inherit from, stale heading attributes would make
            // an emptied note type headings forever.
            if textStorage?.length == 0 {
                typingAttributes = bodyAttributes
            }
        }
        super.didChangeText()
    }

    /// Format > Body Text: strips heading size, bold/italic, underline and
    /// strikethrough from the selection (or the current line), keeping links.
    @objc func resetToBodyText(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let ns = string as NSString
        var range = selectedRange()
        if range.length == 0 {
            range = ns.lineRange(for: NSRange(location: range.location, length: 0))
        }
        guard range.length > 0 else {
            typingAttributes = bodyAttributes
            return
        }
        guard shouldChangeText(in: range, replacementString: nil) else { return }
        storage.addAttribute(.font, value: defaultFont, range: range)
        storage.addAttribute(.paragraphStyle, value: bodyParagraph, range: range)
        storage.removeAttribute(.strikethroughStyle, range: range)
        storage.removeAttribute(.underlineStyle, range: range)
        didChangeText()
        typingAttributes = bodyAttributes
    }

    /// One drawn checkbox (attachment) plus its following tab.
    private func checkboxMarker(checked: Bool, level: Int = 0) -> NSAttributedString {
        let s = NSMutableAttributedString(attributedString: checkboxOnly(checked: checked))
        s.append(NSAttributedString(string: "\t", attributes: listAttributes(level: level)))
        s.addAttribute(.paragraphStyle,
                       value: paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: level),
                       range: NSRange(location: 0, length: s.length))
        return s
    }

    private func checkboxOnly(checked: Bool) -> NSAttributedString {
        let attachment = CheckboxAttachment.make(
            checked: checked, font: defaultFont,
            stroke: defaultColor, accent: accentColor
        )
        let s = NSMutableAttributedString(attachment: attachment)
        s.addAttributes(
            [.cursor: NSCursor.pointingHand, .font: defaultFont],
            range: NSRange(location: 0, length: s.length)
        )
        return s
    }

    /// Storage carries ☐/☑ characters; the view draws them. Any glyph that
    /// appears (load, paste, legacy notes) becomes a drawn attachment.
    func normalizeCheckboxes() {
        guard let storage = textStorage else { return }
        var idx = storage.length - 1
        let ns = storage.string as NSString
        while idx >= 0 {
            let ch = ns.substring(with: NSRange(location: idx, length: 1))
            if ch == "☐" || ch == "☑" {
                let range = NSRange(location: idx, length: 1)
                storage.replaceCharacters(in: range, with: checkboxOnly(checked: ch == "☑"))
            }
            idx -= 1
        }
        applyParagraphSpacing()
        renumberOrderedLists()
        applyTracking()
    }

    /// Stamps the family's tracking over everything so loaded and pasted
    /// text is covered, and clears it when the family doesn't need it.
    private func applyTracking() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let all = NSRange(location: 0, length: storage.length)
        if noteKern > 0 {
            storage.addAttribute(.kern, value: noteKern, range: all)
        } else {
            storage.removeAttribute(.kern, range: all)
        }
    }

    /// Every paragraph gets its rhythm: heading-sized first characters get
    /// the heading spacing, everything else the body spacing. Runs as part
    /// of normalization so loaded and pasted content is covered too.
    private func applyParagraphSpacing() {
        guard let storage = textStorage, storage.length > 0 else { return }
        let headingThreshold = defaultFont.pointSize * 1.1
        var location = 0
        while location < (storage.string as NSString).length {
            let ns = storage.string as NSString
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }

            // Migrate legacy no-break-space separators to tabs so old notes
            // pick up the aligned list column; re-run the same paragraph.
            if line.count >= 2, line.hasPrefix("•\u{00A0}") || line.hasPrefix("\u{FFFC}\u{00A0}") {
                storage.replaceCharacters(
                    in: NSRange(location: paragraph.location + 1, length: 1), with: "\t"
                )
                continue
            }

            let isList = markerLength(of: line) > 0
            let firstFont = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let style = paragraphStyle(
                isHeading: !isList && (firstFont?.pointSize ?? 0) > headingThreshold,
                isList: isList,
                markerInset: markerInset(for: line),
                level: indentLevel(of: existing, isList: isList)
            )
            storage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            location = paragraph.location + paragraph.length
        }
    }

    /// Numbered items in a contiguous list block stay sequential per indent
    /// level: each one follows the previous number at its level (bullets and
    /// checkboxes between them don't break the count), and any non-list
    /// line — blank or plain text — ends the block and resets numbering.
    /// Runs on every change, so inserting, deleting or converting an item
    /// renumbers the rest of its list. The block's first number is kept
    /// as typed, so lists may start anywhere.
    private func renumberOrderedLists() {
        guard let storage = textStorage, storage.length > 0 else { return }
        var counters: [Int: Int] = [:]
        var location = 0
        while location < (storage.string as NSString).length {
            let ns = storage.string as NSString
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }
            if markerLength(of: line) == 0 {
                counters.removeAll()
                location = paragraph.location + paragraph.length
                continue
            }
            if let tab = line.firstIndex(of: "\t"), line[..<tab].hasSuffix("."),
               let n = Int(line[..<tab].dropLast()) {
                let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
                let level = indentLevel(of: existing, isList: true)
                counters = counters.filter { $0.key <= level }
                let expected = counters[level].map { $0 + 1 } ?? n
                counters[level] = expected
                if n != expected {
                    let headLength = (String(line[..<tab]) as NSString).length
                    storage.replaceCharacters(
                        in: NSRange(location: paragraph.location, length: headLength),
                        with: "\(expected)."
                    )
                    let fresh = (storage.string as NSString)
                        .lineRange(for: NSRange(location: paragraph.location, length: 0))
                    location = fresh.location + fresh.length
                    continue
                }
            }
            location = paragraph.location + paragraph.length
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
            // Enter with the cursor inside a link opens it instead of
            // breaking the line. Strictly inside: at the link's trailing
            // edge, return still makes a newline so writing can continue.
            if openLinkAtCursorInstead() { return }
            // Enter on an empty bullet/checkbox line ends the list: the
            // marker disappears instead of a new one being created.
            if removeBareListMarker() { return }
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

        // The bullet waits for the first character after "- ": converting on
        // the space itself created a confusing interstitial state and stole
        // the "[" that starts a checkbox.
        if str.count == 1, str != "[" {
            if (str == "-" || str == "*"), convertCheckboxToBullet() { return }
            convertDashIfPending()
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    /// Tab and Shift-Tab indent and unindent the line the caret is on (or
    /// every line the selection touches), wherever the caret sits in it.
    override func insertTab(_ sender: Any?) { changeIndent(by: 1) }
    override func insertBacktab(_ sender: Any?) { changeIndent(by: -1) }

    private func changeIndent(by delta: Int) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let lines = ns.lineRange(for: selectedRange())
        // The empty last line has no characters to restyle; move the pen.
        guard lines.length > 0 else {
            let existing = typingAttributes[.paragraphStyle] as? NSParagraphStyle
            let level = max(0, min(maxIndentLevel, indentLevel(of: existing, isList: false) + delta))
            typingAttributes[.paragraphStyle] = paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: level)
            return
        }
        guard shouldChangeText(in: lines, replacementString: nil) else { return }
        var location = lines.location
        while location < NSMaxRange(lines) {
            let paragraph = ns.lineRange(for: NSRange(location: location, length: 0))
            var line = ns.substring(with: paragraph)
            if line.hasSuffix("\n") { line.removeLast() }
            let isList = markerLength(of: line) > 0
            let firstFont = storage.attribute(.font, at: paragraph.location, effectiveRange: nil) as? NSFont
            let existing = storage.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil) as? NSParagraphStyle
            let level = max(0, min(maxIndentLevel, indentLevel(of: existing, isList: isList) + delta))
            storage.addAttribute(.paragraphStyle, value: paragraphStyle(
                isHeading: !isList && (firstFont?.pointSize ?? 0) > defaultFont.pointSize * 1.1,
                isList: isList,
                markerInset: markerInset(for: line),
                level: level
            ), range: paragraph)
            location = paragraph.location + paragraph.length
        }
        didChangeText()
    }

    /// Space-triggered conversions: "[ ]" forms → checkbox, "#" → heading,
    /// "N." → numbered item. On a line that is already a list item the
    /// typed marker replaces the existing one, so any list type turns into
    /// any other by typing its trigger right after the marker.
    private func convertLinePrefix() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        guard loc >= lineRange.location else { return false }
        var fullLine = ns.substring(with: lineRange)
        if fullLine.hasSuffix("\n") { fullLine.removeLast() }
        let markerLen = markerLength(of: fullLine)
        guard loc - lineRange.location >= markerLen else { return false }
        let typed = ns.substring(with: NSRange(
            location: lineRange.location + markerLen,
            length: loc - lineRange.location - markerLen
        ))
        // Replacements swallow the existing marker along with the trigger.
        let fullRange = NSRange(location: lineRange.location, length: loc - lineRange.location)
        let existing = textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: markerLen > 0)

        // Checkbox conversion waits for the CLOSING bracket — converting at
        // "[" would make "[x]" untypeable. Bare bracket forms need an
        // existing marker; on plain text the leading "- " is required.
        let boxForms: [String: Bool] = ["[ ]": false, "[]": false,
                                        "[x]": true, "[X]": true, "[ x]": true, "[ X]": true]
        let boxTyped = typed.hasPrefix("- ") ? String(typed.dropFirst(2)) : typed
        if let checked = boxForms[boxTyped], typed.hasPrefix("- ") || markerLen > 0 {
            replace(fullRange, with: checkboxMarker(checked: checked, level: level))
            return true
        }
        if typed == "#" || typed == "##" || typed == "###" {
            replace(fullRange, with: NSAttributedString(string: ""))
            var attrs = bodyAttributes
            attrs[.font] = headingFont(typed.count)
            attrs[.paragraphStyle] = headingParagraph
            typingAttributes = attrs
            return true
        }
        // "- "/"* " on a plain line stays deferred (convertDashIfPending);
        // on an existing list item it switches the item to a bullet now.
        if typed == "-" || typed == "*", markerLen > 0 {
            replace(fullRange, with: NSAttributedString(string: "•\t", attributes: listAttributes(level: level)))
            return true
        }
        // Ordered list: any number followed by "." and a space.
        if typed.hasSuffix("."), typed.count <= 5, !typed.dropLast().isEmpty,
           Int(typed.dropLast()) != nil {
            replace(fullRange, with: NSAttributedString(string: typed + "\t", attributes: listAttributes(level: level)))
            return true
        }
        return false
    }

    /// Pressing return inside a link's text opens the link. Both neighbors
    /// of the insertion point must carry the same link, so the boundaries
    /// (just before or just after the link) still insert a newline.
    private func openLinkAtCursorInstead() -> Bool {
        guard selectedRange().length == 0, let storage = textStorage else { return false }
        let loc = selectedRange().location
        guard loc > 0, loc < storage.length,
              let before = storage.attribute(.link, at: loc - 1, effectiveRange: nil),
              let after = storage.attribute(.link, at: loc, effectiveRange: nil)
        else { return false }
        let a = (after as? URL)?.absoluteString ?? (after as? String ?? "")
        let b = (before as? URL)?.absoluteString ?? (before as? String ?? "")
        guard !a.isEmpty, a == b, let url = URL(string: a) else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// A line whose full content is "- " becomes a bullet the moment a
    /// non-bracket character follows — no interstitial bullet while a
    /// checkbox is being typed.
    private func convertDashIfPending() {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        guard loc - lineRange.location == 2 else { return }
        let prefixRange = NSRange(location: lineRange.location, length: 2)
        let prefix = ns.substring(with: prefixRange)
        guard prefix == "- " || prefix == "* " else { return }
        let existing = textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: false)
        replace(prefixRange, with: NSAttributedString(string: "•\t", attributes: listAttributes(level: level)))
    }

    /// Typing "-" or "*" right after a fresh checkbox marker switches the
    /// item to a bullet — changing your mind shouldn't need deleting.
    private func convertCheckboxToBullet() -> Bool {
        guard let storage = textStorage else { return false }
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        let marker = ns.substring(with: NSRange(location: lineRange.location, length: min(2, ns.length - lineRange.location)))
        guard loc - lineRange.location == 2,
              marker == "\u{FFFC}\t" || marker == "\u{FFFC}\u{00A0}",
              storage.attribute(.attachment, at: lineRange.location, effectiveRange: nil) is CheckboxAttachment
        else { return false }
        let markerRange = NSRange(location: lineRange.location, length: 2)
        let existing = storage.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
        let level = indentLevel(of: existing, isList: true)
        replace(markerRange, with: NSAttributedString(string: "•\t", attributes: listAttributes(level: level)))
        return true
    }

    /// Pressing return on a line that is nothing but a list marker deletes
    /// the marker (ending the list) rather than continuing it.
    private func removeBareListMarker() -> Bool {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var content = ns.substring(with: lineRange)
        if content.hasSuffix("\n") { content.removeLast() }
        let markers = ["•\u{00A0}", "☐\u{00A0}", "☑\u{00A0}", "•", "☐", "☑",
                       "\u{FFFC}\u{00A0}", "\u{FFFC}", "•\t", "\u{FFFC}\t"]
        let bareNumber: Bool = {
            let head = content.hasSuffix("\t") ? String(content.dropLast()) : content
            return head.hasSuffix(".") && Int(head.dropLast()) != nil && !head.dropLast().isEmpty
        }()
        guard markers.contains(content) || bareNumber else { return false }
        let deleteRange = NSRange(location: lineRange.location, length: (content as NSString).length)
        replace(deleteRange, with: NSAttributedString(string: ""))
        typingAttributes = bodyAttributes
        return true
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
    private func listContinuation() -> NSAttributedString? {
        let ns = string as NSString
        let loc = selectedRange().location
        let lineRange = ns.lineRange(for: NSRange(location: loc, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }
        func hasContent(after marker: String) -> Bool {
            !line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces).isEmpty
        }
        // The new item continues at the same indent level as the current one.
        let existing = lineRange.length > 0
            ? textStorage?.attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil) as? NSParagraphStyle
            : nil
        let level = indentLevel(of: existing, isList: true)
        for sep in ["\t", "\u{00A0}"] {
            if line.hasPrefix("•" + sep) {
                return hasContent(after: "•" + sep)
                    ? NSAttributedString(string: "•\t", attributes: listAttributes(level: level)) : nil
            }
            if line.hasPrefix("\u{FFFC}" + sep) {
                return hasContent(after: "\u{FFFC}" + sep) ? checkboxMarker(checked: false, level: level) : nil
            }
        }
        // Numbered: "N.<tab>" continues as "N+1.<tab>".
        if let tab = line.firstIndex(of: "\t"), line[..<tab].hasSuffix("."),
           let n = Int(line[..<tab].dropLast()) {
            return hasContent(after: String(line[...tab]))
                ? NSAttributedString(string: "\(n + 1).\t", attributes: listAttributes(level: level)) : nil
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
        for candidate in [index, index - 1] where candidate >= 0 && candidate < (textStorage?.length ?? 0) {
            if let box = textStorage?.attribute(.attachment, at: candidate, effectiveRange: nil) as? CheckboxAttachment {
                let range = NSRange(location: candidate, length: 1)
                guard shouldChangeText(in: range, replacementString: nil) else { break }
                textStorage?.replaceCharacters(in: range, with: checkboxOnly(checked: !box.checked))
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

// MARK: - Drawn checkbox

/// Custom-drawn checkbox image the note renders in place of ☐/☑: a rounded
/// stroke square, filled with the note's accent plus a checkmark when done.
/// The attachment exists only in the view — serialization maps it back to
/// the glyph characters.
private final class CheckboxAttachment: NSTextAttachment {
    var checked = false

    static func make(checked: Bool, font: NSFont, stroke: NSColor, accent: NSColor) -> CheckboxAttachment {
        let side = (font.pointSize * 1.2).rounded()
        let attachment = CheckboxAttachment()
        attachment.checked = checked
        attachment.image = drawImage(checked: checked, side: side, stroke: stroke, accent: accent)
        // Center against the cap height so the box reads as part of the line.
        attachment.bounds = CGRect(
            x: 0, y: (font.capHeight - side) / 2, width: side, height: side
        )
        return attachment
    }

    private static func drawImage(checked: Bool, side: CGFloat, stroke: NSColor, accent: NSColor) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1)
            let radius = side * 0.24
            let path = NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius)
            if checked {
                accent.setFill()
                path.fill()
                // Checkmark in whichever of black/white reads against the accent.
                let rgb = accent.usingColorSpace(.deviceRGB)
                let luminance = rgb.map {
                    0.299 * $0.redComponent + 0.587 * $0.greenComponent + 0.114 * $0.blueComponent
                } ?? 1
                let mark = NSBezierPath()
                mark.move(to: NSPoint(x: side * 0.26, y: side * 0.52))
                mark.line(to: NSPoint(x: side * 0.44, y: side * 0.32))
                mark.line(to: NSPoint(x: side * 0.76, y: side * 0.70))
                mark.lineWidth = max(1.5, side * 0.14)
                mark.lineCapStyle = .round
                mark.lineJoinStyle = .round
                (luminance > 0.6 ? NSColor.black.withAlphaComponent(0.85) : .white).setStroke()
                mark.stroke()
            } else {
                stroke.withAlphaComponent(0.75).setStroke()
                path.lineWidth = max(1.5, side * 0.11)
                path.stroke()
            }
            return true
        }
    }
}
