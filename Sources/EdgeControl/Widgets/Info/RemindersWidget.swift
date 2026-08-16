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
        // Empty means the system default list; any real list name works.
        ConfigSchemaEntry(key: "list", label: "List (empty = default)", type: .text, defaultValue: .string("")),
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
            configuredList: config.string("list"),
            isCompact: size.height <= 2
        )
    }
}

private struct RemindersWidgetView: View {
    @ObservedObject var service: RemindersService
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    let configuredList: String
    let isCompact: Bool

    @State private var draft = ""

    private var primary: Color { Theme.widgetPrimary("reminders", ts: ts, default: .orange) }

    var body: some View {
        VStack(spacing: isCompact ? 6 : 10) {
            if !isCompact {
                WidgetHeader(
                    title: configuredList.isEmpty ? "REMINDERS" : configuredList.uppercased(),
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
                            ForEach(service.items) { item in
                                reminderRow(item)
                            }
                        }
                    }
                }

                TextField("Add reminder…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onSubmit {
                        service.add(title: draft)
                        draft = ""
                    }
            }
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        // The service is shared; the placed widget's config decides the list.
        .onAppear { service.listName = configuredList }
        .onChange(of: configuredList) { _, newValue in service.listName = newValue }
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
                Text(Self.dueFormatter.string(from: due))
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
}
