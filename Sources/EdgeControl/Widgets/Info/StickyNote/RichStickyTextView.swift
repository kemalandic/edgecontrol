import AppKit
import SwiftUI

// The bridge to AppKit, and the attributed-string storage the note is saved as.

struct RichStickyTextView: NSViewRepresentable {
    @Binding var rtfBase64: String
    @Binding var plainText: String
    let legacyMarkdown: String
    let baseFont: NSFont
    let textColor: NSColor
    let linkColor: NSColor
    let onFontSizeDelta: (Double) -> Void
    let onFontSizeReset: () -> Void
    /// Stores pasted image data beside the note and answers with the name to
    /// reference it by, or nil when it will not take it. The store and the
    /// note's identity live a layer up; the editor only needs the answer.
    let writeMedia: (Data) -> String?
    /// Reads an image back for drawing.
    let readMedia: (String) -> Data?
    /// Promotes to-do titles into Reminders and answers with what to show.
    let promoteToReminders: ([String]) -> String

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
        textView.writeMedia = writeMedia
        textView.readMedia = readMedia
        textView.promoteToReminders = promoteToReminders
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
        textView.writeMedia = writeMedia
        textView.readMedia = readMedia
        textView.promoteToReminders = promoteToReminders
        let fontChanged = context.coordinator.appliedFontKey != fontKey
        let colorChanged = context.coordinator.appliedColorKey != colorKey
        // Reload only on a genuine external change — and never on the pass
        // that changes the font or color: the binding still holds the
        // pre-restyle RTF then, and reloading from it would undo the reflow
        // or recolor (the bug that shipped first).
        if !fontChanged, !colorChanged,
            Self.rtfString(textView.attributedString()) != rtfBase64,
            let restored = Self.fromRTF(rtfBase64)
        {
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
        storage.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: storage.length)) {
            value, range, _ in
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
            let newFont =
                NSFont(descriptor: descriptor, size: old.pointSize * ratio)
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
            } else if let media = attrs[.attachment] as? MediaAttachment {
                // RTF has nowhere to put an image, so what goes in the file is
                // the link that names the one sitting beside it.
                var plain = attrs
                plain.removeValue(forKey: .attachment)
                plain.removeValue(forKey: .cursor)
                plain[.link] = NoteMedia.link(forFile: media.filename)
                mapped.append(
                    NSAttributedString(
                        string: NoteMedia.placeholderText(for: media.filename), attributes: plain))
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
            result.append(
                NSAttributedString(string: String(rest[rest.startIndex..<match.range.lowerBound]), attributes: plain))
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
