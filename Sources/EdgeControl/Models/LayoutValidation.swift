import Foundation

/// Checks on a decoded layout before it's trusted, kept as backup, or
/// imported.
enum LayoutValidation {
    /// Generous bounds for a grid position or span; anything outside them is
    /// damage, and arithmetic on huge values can trap.
    static let maxGridSpan = 500

    /// Drops widgets that can't be laid out (zero or negative size, negative
    /// or absurd position) and repeated ids, which the editor assumes are
    /// unique. Returns the layout and how many widgets or pages were dropped.
    static func sanitized(_ document: LayoutDocument) -> (document: LayoutDocument, dropped: Int) {
        var doc = document
        var dropped = 0
        var pageIDs: Set<String> = []
        var instanceIDs: Set<String> = []
        doc.pages = document.pages.compactMap { page in
            guard pageIDs.insert(page.id).inserted else {
                dropped += 1
                return nil
            }
            var page = page
            page.widgets = page.widgets.filter { w in
                let fits = (1...maxGridSpan).contains(w.width) && (1...maxGridSpan).contains(w.height)
                    && (0...maxGridSpan).contains(w.col) && (0...maxGridSpan).contains(w.row)
                guard fits, instanceIDs.insert(w.instanceId).inserted else {
                    dropped += 1
                    return false
                }
                return true
            }
            return page
        }
        return (doc, dropped)
    }

    /// Decodes a layout and reports whether it was read cleanly: no field
    /// replaced by a default, no page or widget skipped, every page with its
    /// own id. Nil when it isn't a layout at all.
    static func decode(_ data: Data) -> (document: LayoutDocument, clean: Bool)? {
        guard let (doc, fallbacks) = try? LenientDecodingReport.decode(LayoutDocument.self, from: data) else { return nil }
        return (doc, fallbacks == 0 && decodedCompletely(doc, from: data))
    }

    /// The `version` the file declares, read before anything else so a newer
    /// format is recognised even when little of it can be decoded.
    static func declaredVersion(_ data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int
    }

    /// Whether decoding kept every page and widget in the file (the lenient
    /// decoder skips unreadable ones).
    static func decodedCompletely(_ document: LayoutDocument, from data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let rawPages = object["pages"] as? [Any] ?? []
        guard rawPages.count == document.pages.count else { return false }
        for (raw, page) in zip(rawPages, document.pages) {
            // Every saved page has its id; one without was filled in by the
            // lenient decoder, so the page wasn't really read.
            guard let rawPage = raw as? [String: Any], rawPage["id"] is String else { return false }
            let rawWidgets = rawPage["widgets"] as? [Any] ?? []
            if rawWidgets.count != page.widgets.count { return false }
        }
        return true
    }
}
