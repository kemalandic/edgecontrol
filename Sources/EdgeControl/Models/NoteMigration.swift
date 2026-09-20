import Foundation

/// Moving a sticky note's text out of the layout document and into the note
/// store, one widget at a time.
///
/// Notes used to live inside the widget's own configuration as base64 RTF, so
/// the layout document carried every note's full body. Three things followed
/// from that and all three are why this exists: a note died with the widget
/// that displayed it, nothing could look at a note without loading the
/// dashboard, and every debounced keystroke rewrote the whole document.
///
/// Both the body and its plain mirror leave the configuration. Keeping the
/// mirror was tempting — it is small, and it was what the settings text field
/// edited — but a plain-text field that overwrites a rich note is a way to
/// lose formatting, not a feature, and leaving it would have meant the layout
/// document was still rewritten on every keystroke. The field goes with it.
public enum NoteMigration {

    public struct Plan: Equatable, Sendable {
        /// Identity the widget will point at from here on.
        public var noteId: String
        /// Body to seed the store with. Empty for a note that was never typed in.
        public var rtfBase64: String
        /// Plain mirror, which is all a pre-RTF note ever had.
        public var plainText: String
        /// The widget configuration to write back.
        public var config: WidgetConfig
    }

    /// The key a migrated widget carries instead of its text.
    public static let idKey = "noteId"
    /// The key the body used to live under.
    public static let bodyKey = "rtf"
    /// The key the plain mirror used to live under. Still read, never written.
    public static let plainKey = "note"

    /// What to do with one sticky note widget's configuration.
    ///
    /// Returns nil when the widget already points at a note, which is what
    /// makes this safe to run over every widget on every launch.
    ///
    /// - Parameter id: identity to give a widget that does not have one. Taken
    ///   as a parameter rather than generated here so the result is a pure
    ///   function of its inputs and a test can say what it expects.
    public static func plan(config: WidgetConfig, id: String) -> Plan? {
        guard config.string(idKey).isEmpty else { return nil }

        var migrated = config
        migrated[idKey] = .string(id)
        // Both move out. What stays is the pointer.
        migrated[bodyKey] = nil
        migrated[plainKey] = nil

        return Plan(
            noteId: id,
            rtfBase64: config.string(bodyKey),
            plainText: config.string(plainKey),
            config: migrated
        )
    }

    /// Whether a widget configuration still holds a body that belongs in the
    /// store — true for anything written before this change.
    public static func needsMigration(_ config: WidgetConfig) -> Bool {
        config.string(idKey).isEmpty
    }

    /// Every sticky note in a layout that still carries its own body, and the
    /// layout with those widgets pointing at notes instead.
    ///
    /// Walking the document here rather than in the layout engine keeps the
    /// decision — which widgets, what their new configuration is — a pure
    /// function of the document. The engine is left with applying it.
    ///
    /// - Parameter nextId: supplies identities, so a test can say what it
    ///   expects instead of matching a UUID.
    public static func plans(
        for document: LayoutDocument,
        nextId: () -> String = { UUID().uuidString }
    ) -> (document: LayoutDocument, plans: [Plan]) {
        var migrated = document
        var plans: [Plan] = []

        for pageIndex in migrated.pages.indices {
            for widgetIndex in migrated.pages[pageIndex].widgets.indices {
                let widget = migrated.pages[pageIndex].widgets[widgetIndex]
                guard widget.widgetId == stickyNoteWidgetId,
                    let plan = plan(config: widget.config, id: nextId())
                else { continue }
                migrated.pages[pageIndex].widgets[widgetIndex].config = plan.config
                plans.append(plan)
            }
        }

        return (migrated, plans)
    }

    /// The only widget this applies to. Spelled out rather than imported so a
    /// pure model does not reach into the widget layer for a constant.
    public static let stickyNoteWidgetId = "sticky-note"
}
