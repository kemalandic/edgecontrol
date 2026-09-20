import WidgetKit

struct NotesEntry: TimelineEntry, Sendable {
    let date: Date
    let title: String
    let items: [WidgetNoteItem]
    let isStale: Bool
    /// Why there is nothing to show, when there is nothing to show. An empty
    /// tile with no explanation is the thing this avoids.
    let statusNote: String?

    static let placeholder = NotesEntry(
        date: Date(),
        title: "Inbox",
        items: [
            WidgetNoteItem(id: "0", text: "call the bank", done: false),
            WidgetNoteItem(id: "1", text: "post the letter", done: false),
            WidgetNoteItem(id: "2", text: "book the table", done: true),
        ],
        isStale: false,
        statusNote: nil
    )

    /// Also covers the schema-mismatch case: `WidgetData.read()` returns nil
    /// for a snapshot written by a different app version.
    static let noData = NotesEntry(
        date: Date(), title: "Notes", items: [], isStale: true,
        statusNote: "Open EdgeControl to refresh")
}

struct NotesProvider: TimelineProvider {
    func placeholder(in context: Context) -> NotesEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NotesEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NotesEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        // A note changes when somebody writes in it, not on a clock. Fifteen
        // minutes is often enough to be current without spending the budget
        // the system gives a widget on redrawing an unchanged list.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> NotesEntry {
        guard let data else { return .noData }
        guard let items = data.noteItems, let title = data.noteTitle else {
            return NotesEntry(
                date: data.timestamp, title: "Notes", items: [], isStale: data.isStale,
                statusNote: "Choose a note in EdgeControl settings")
        }
        return NotesEntry(
            date: data.timestamp,
            title: title,
            items: items,
            isStale: data.isStale,
            statusNote: items.isEmpty ? "Nothing to do" : nil)
    }
}
