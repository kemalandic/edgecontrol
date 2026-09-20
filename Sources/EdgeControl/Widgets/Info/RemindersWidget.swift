import SwiftUI

public final class RemindersWidget: DashboardWidget {
    public let widgetId = "reminders"
    public let displayName = "Reminders"
    public let description = "Your real Reminders list — check off and add items in place"
    public let iconName = "checklist"
    public let category: WidgetCategory = .info
    public let requiredServices: Set<ServiceKey> = [.reminders]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(8, 6))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        // The page manager swaps this for a picker of real list names once
        // the service has discovered them; "default" = the system default.
        ConfigSchemaEntry(key: "list", label: "List", type: .text, defaultValue: .string("default")),
        // Items with due dates sort due-first (overdue on top); this orders
        // the undated remainder.
        ConfigSchemaEntry(key: "undatedSort", label: "Undated Sort", type: .picker,
                          defaultValue: .string("newest first"),
                          options: ["newest first", "oldest first", "recently updated", "least recently updated"]),
        ConfigSchemaEntry(key: "newDueToday", label: "New Reminders Due Today", type: .toggle,
                          defaultValue: .bool(false),
                          help: "Reminders added from this widget get a due date of today."),
        ConfigSchemaEntry(key: "dueTime", label: "Due Time", type: .time,
                          defaultValue: .string("18:00"),
                          help: "When Due Today is on and no \"in…\" offset is typed, "
                              + "new reminders come due — and notify — at this time. "
                              + "A typed offset like \":30\" or \"2:15\" always wins."),
    ]
    public let defaultColors = WidgetColors(primary: .orange)

    private let service: RemindersService

    public init(service: RemindersService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        RemindersWidgetView(
            service: service,
            configuredList: config.string("list", default: "default"),
            undatedSort: config.string("undatedSort", default: "newest first"),
            newDueToday: config.bool("newDueToday", default: false),
            dueTime: config.string("dueTime", default: "18:00"),
            isCompact: size.height <= 2
        )
    }
}

private struct RemindersWidgetView: View {
    @ObservedObject var service: RemindersService
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    let configuredList: String
    let undatedSort: String
    let newDueToday: Bool
    let dueTime: String
    let isCompact: Bool

    @State private var draft = ""
    @State private var remindIn = ""

    private var primary: Color { Theme.widgetPrimary("reminders", ts: ts, default: .orange) }

    var body: some View {
        VStack(spacing: isCompact ? 6 : 10) {
            if !isCompact {
                WidgetHeader(
                    title: (configuredList.isEmpty || configuredList == "default")
                        ? "REMINDERS" : configuredList.uppercased(),
                    color: primary
                )
            }

            switch service.access {
            case .unknown:
                centeredNote("Waiting for Reminders access…")
            case .denied:
                centeredNote("Grant access in System Settings → Privacy → Reminders")
            case .granted:
                if service.items.isEmpty {
                    centeredNote("All clear")
                } else {
                    TouchScrollView {
                        VStack(spacing: 2) {
                            ForEach(sortedItems) { item in
                                reminderRow(item)
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    TextField("Add reminder…", text: $draft)
                        .textFieldStyle(.plain)
                        .onSubmit { createReminder() }
                    // ":30" = 30 min, "2" = 2 hours, "2:15" = 2h15m.
                    TextField("in…", text: $remindIn)
                        .textFieldStyle(.plain)
                        .frame(width: 44)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { createReminder() }
                }
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text1(ts))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        // The service is shared; the placed widget's config decides the list.
        .onAppear { service.listName = configuredList }
        .onChange(of: configuredList) { _, newValue in service.listName = newValue }
    }

    private func createReminder() {
        let due = remindInInterval(remindIn).map { Date().addingTimeInterval($0) }
            ?? defaultDueDate()
        service.add(title: draft, due: due)
        draft = ""
        remindIn = ""
    }

    /// ":30" = 30 minutes, ":03" = 3 minutes, "2" = 2 hours, "2:15" = two
    /// hours fifteen. Empty or unparseable means no offset.
    private func remindInInterval(_ s: String) -> TimeInterval? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix(":") {
            return Int(t.dropFirst()).map { TimeInterval($0 * 60) }
        }
        if t.contains(":") {
            let parts = t.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
            return TimeInterval(h * 3600 + m * 60)
        }
        return Int(t).map { TimeInterval($0 * 3600) }
    }

    /// Today at the configured due time — the fallback when Due Today is on
    /// and no remind-in was given.
    private func defaultDueDate() -> Date? {
        guard newDueToday else { return nil }
        let parts = dueTime.split(separator: ":")
        let hour = parts.count == 2 ? Int(parts[0]) ?? 18 : 18
        let minute = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    /// Due items first, soonest (so overdue tops the list); the undated
    /// tail ordered by the configured secondary sort.
    private var sortedItems: [RemindersService.Item] {
        let items = service.items
        let dated = items.filter { $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        let undated = items.filter { $0.dueDate == nil }.sorted { a, b in
            switch undatedSort {
            case "oldest first":
                (a.created ?? .distantPast) < (b.created ?? .distantPast)
            case "recently updated":
                (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            case "least recently updated":
                (a.modified ?? .distantPast) < (b.modified ?? .distantPast)
            default:
                (a.created ?? .distantPast) > (b.created ?? .distantPast)
            }
        }
        return dated + undated
    }

    private func reminderRow(_ item: RemindersService.Item) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .font(.system(size: 15 * ts.fontScale))
                .foregroundStyle(primary)
                .touchTappable(id: "reminder-done-\(item.id)", registry: model.touchService.zoneRegistry) {
                    let id = item.id
                    Task { @MainActor in model.remindersService.complete(id: id) }
                }
            Text(item.title)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text1(ts))
                .lineLimit(1)
            Spacer()
            if let due = item.dueDate {
                // Same-day reminders show their time; others show the date.
                Text(Calendar.current.isDateInToday(due)
                    ? Self.timeFormatter.string(from: due)
                    : Self.dueFormatter.string(from: due))
                    .font(Theme.label(ts))
                    .foregroundStyle(due < Date() ? Theme.accentRed : Theme.text3(ts))
            }
        }
        .padding(.vertical, 4)
    }

    private func centeredNote(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text3(ts))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private static let dueFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()
}
