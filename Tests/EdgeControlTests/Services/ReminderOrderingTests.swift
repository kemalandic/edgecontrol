import Foundation
import Testing
@testable import EdgeControl

/// The order the Reminders widget shows its list in. Extracted from the EventKit
/// fetch so it can be exercised without a reminders database — the widget shows
/// what this returns, so the ordering is the behaviour worth pinning.
@Suite("Reminder ordering")
struct ReminderOrderingTests {

    private func item(_ title: String, due: Date? = nil) -> RemindersService.Item {
        RemindersService.Item(id: title, title: title, dueDate: due, created: nil, modified: nil)
    }

    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("dated reminders come before undated ones")
    func datedBeforeUndated() {
        let ordered = RemindersService.ordered([
            item("no date"),
            item("due later", due: noon.addingTimeInterval(86_400)),
        ])
        #expect(ordered.map(\.title) == ["due later", "no date"])
    }

    @Test("earlier due dates come first")
    func earliestFirst() {
        let ordered = RemindersService.ordered([
            item("tomorrow", due: noon.addingTimeInterval(86_400)),
            item("now", due: noon),
            item("next week", due: noon.addingTimeInterval(7 * 86_400)),
        ])
        #expect(ordered.map(\.title) == ["now", "tomorrow", "next week"])
    }

    /// Without a tiebreak the order of undated reminders would be whatever
    /// EventKit happened to return, so the list would reshuffle on every
    /// refresh for no visible reason.
    @Test("undated reminders fall back to title order, ignoring case")
    func undatedSortByTitle() {
        let ordered = RemindersService.ordered([
            item("zebra"), item("Apple"), item("mango"),
        ])
        #expect(ordered.map(\.title) == ["Apple", "mango", "zebra"])
    }

    @Test("a mixed list puts every dated item above every undated one")
    func mixedList() {
        let ordered = RemindersService.ordered([
            item("b undated"),
            item("late", due: noon.addingTimeInterval(86_400)),
            item("a undated"),
            item("early", due: noon),
        ])
        #expect(ordered.map(\.title) == ["early", "late", "a undated", "b undated"])
    }

    @Test("an empty list stays empty")
    func emptyList() {
        #expect(RemindersService.ordered([]).isEmpty)
    }
}
