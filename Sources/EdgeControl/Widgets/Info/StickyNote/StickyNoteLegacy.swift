import AppKit

/// Bringing a pre-RTF note into the store.
///
/// Notes were plain markdown-ish text before the rich editor, and those notes
/// are still out there. The editor could read them because it parsed the plain
/// text whenever it found no RTF to restore — but that path only ran when the
/// text was sitting in the widget's configuration, where it is no longer.
///
/// So the conversion happens once, at migration, and every note in the store
/// is rich text from then on. One representation to read, one to write, and
/// the legacy parser is reached from exactly one place.
enum StickyNoteLegacy {

    /// The note's text as base64 RTF, styled the way the widget was
    /// configured to show it — the same font and colour the editor would have
    /// used, so converting changes nothing a person can see.
    /// Main-actor bound because the parser it delegates to belongs to the
    /// editor's view type. The one caller is the launch migration, which runs
    /// there anyway.
    @MainActor
    static func rtfBase64(fromPlainText text: String, config: WidgetConfig) -> String {
        guard !text.isEmpty else { return "" }
        let font = RichStickyTextView.makeFont(
            family: config.string("font", default: "mono"),
            size: config.double("fontSize", default: 18)
        )
        let attributed = RichStickyTextView.parseLegacy(
            text,
            font: font,
            textColor: StickyNotePalette.text(config.string("textColor", default: "soft white"))
        )
        return RichStickyTextView.rtfString(attributed)
    }
}
