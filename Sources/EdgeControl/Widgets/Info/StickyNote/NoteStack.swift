import Foundation

/// Several notes in one widget, reachable by their names.
///
/// Space on the panel is the scarce thing: a sticky note worth writing in is
/// three or four cells, and three notes worth having open is most of a page.
/// A stack is the way to keep one cell and still have somewhere to put the
/// shopping list.
///
/// The stack is a list of shortcuts, not a second idea of what the widget is
/// showing. Choosing a tab writes the widget's own note id, so everything
/// downstream — the editor, the images, promotion, the store — keeps reading
/// the one key it always read. There is no state here that can disagree with
/// what is on screen.
public enum NoteStack {

    /// The configuration key holding the stack.
    public static let key = "noteIds"

    public struct Tab: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let isActive: Bool
    }

    /// The tabs to draw.
    ///
    /// - Parameters:
    ///   - ids: the stack as configured, in the order it was arranged.
    ///   - active: the note the widget is showing.
    ///   - title: what to call a note, by id. Notes are named by their first
    ///     line, which lives in the store — so the caller supplies it rather
    ///     than this reaching for one.
    public static func tabs(
        ids: [String], active: String, title: (String) -> String?
    ) -> [Tab] {
        // The shown note is always a tab, even when it is not in the list.
        // Otherwise pointing a stacked widget at something through the note
        // picker leaves every tab looking unselected, with no way back to
        // what is actually on screen.
        var ordered = ids.filter { !$0.isEmpty }
        if !active.isEmpty, !ordered.contains(active) { ordered.append(active) }

        var seen = Set<String>()
        return ordered.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return Tab(id: id, title: title(id) ?? "Untitled note", isActive: id == active)
        }
    }

    /// Whether the strip is worth the room it takes.
    ///
    /// One tab is not a stack, it is a label — and on a cell that can be a
    /// hundred points tall, a row of chrome naming the only thing present is
    /// a row of chrome.
    public static func showsStrip(_ tabs: [Tab]) -> Bool {
        tabs.count > 1
    }

    /// The stack with a note added, if it is not already there.
    public static func adding(_ id: String, to ids: [String]) -> [String] {
        guard !id.isEmpty, !ids.contains(id) else { return ids }
        return ids + [id]
    }

    /// The stack with a note taken out, and the note to show afterwards.
    ///
    /// Removing a tab takes it off the widget, never off the disk: a stack is
    /// a list of shortcuts, and deleting somebody's shopping list because
    /// they closed a tab would be indefensible.
    public static func removing(
        _ id: String, from ids: [String], active: String
    ) -> (ids: [String], active: String) {
        let remaining = ids.filter { $0 != id }
        guard id == active else { return (remaining, active) }

        // Land on the neighbour, preferring the one to the left, which is
        // where the eye already is.
        let index = ids.firstIndex(of: id) ?? 0
        let replacement =
            remaining.indices.contains(index - 1)
            ? remaining[index - 1]
            : remaining.first
        return (remaining, replacement ?? "")
    }
}
