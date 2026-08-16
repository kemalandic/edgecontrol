import EventKit
import Foundation

/// Live bridge to the system Reminders database (EventKit). Runs only while
/// a Reminders widget is placed, like every lazily-activated service. First
/// start triggers the system's Reminders-access prompt.
@MainActor
public final class RemindersService: ObservableObject, ServiceLifecycle {
    public struct Item: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let dueDate: Date?
    }

    public enum Access { case unknown, granted, denied }

    @Published public private(set) var access: Access = .unknown
    @Published public private(set) var listNames: [String] = []
    /// Incomplete reminders of the selected list, due-first then by title.
    @Published public private(set) var items: [Item] = []
    /// The list to show; empty means the system default list.
    @Published public var listName: String = "" {
        didSet { if listName != oldValue { refresh() } }
    }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var started = false

    public init() {}

    public func start() {
        guard !started else { return }
        started = true
        // The store posts one notification for any change made anywhere —
        // the Reminders app, Siri, another device syncing down.
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        store.requestFullAccessToReminders { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.access = granted ? .granted : .denied
                self.refresh()
            }
        }
    }

    public func stop() {
        guard started else { return }
        started = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private var selectedCalendar: EKCalendar? {
        let calendars = store.calendars(for: .reminder)
        if listName.isEmpty { return store.defaultCalendarForNewReminders() ?? calendars.first }
        return calendars.first { $0.title == listName } ?? store.defaultCalendarForNewReminders()
    }

    public func refresh() {
        guard access == .granted else { return }
        listNames = store.calendars(for: .reminder).map(\.title).sorted()
        guard let calendar = selectedCalendar else {
            items = []
            return
        }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [calendar]
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let mapped = (reminders ?? [])
                .map { reminder in
                    Item(
                        id: reminder.calendarItemIdentifier,
                        title: reminder.title ?? "",
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
                    )
                }
                .sorted {
                    switch ($0.dueDate, $1.dueDate) {
                    case let (a?, b?): return a < b
                    case (_?, nil): return true
                    case (nil, _?): return false
                    default: return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                }
            Task { @MainActor [weak self] in self?.items = mapped }
        }
    }

    /// Completes the reminder everywhere — this writes to the real database.
    public func complete(id: String) {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        refresh()
    }

    /// Creates a real reminder in the selected list.
    public func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let calendar = selectedCalendar else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = calendar
        try? store.save(reminder, commit: true)
        refresh()
    }
}
