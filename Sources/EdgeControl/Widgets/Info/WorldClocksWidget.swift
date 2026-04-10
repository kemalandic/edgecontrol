import SwiftUI

public final class WorldClocksWidget: DashboardWidget {
    public let widgetId = "world-clocks"
    public let displayName = "World Clocks"
    public let description = "Multiple timezone clocks with city names and flags"
    public let iconName = "globe"
    public let category: WidgetCategory = .info
    public let supportedSizes = WidgetSizeRange(min: .size(4, 2), max: .size(10, 4))
    public let defaultSize = WidgetSize.size(6, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "use24h", label: "24-Hour Format", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        WorldClocksWidgetView(
            use24h: config.bool("use24h", default: true),
            isCompact: size.height <= 2,
            columns: size.width >= 8 ? 3 : 2
        )
    }
}

private struct WorldClocksWidgetView: View {
    let use24h: Bool
    let isCompact: Bool
    let columns: Int

    @Environment(\.themeSettings) private var ts
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let worldClocks: [(city: String, tz: String, flag: String)] = [
        ("Istanbul", "Europe/Istanbul", "\u{1F1F9}\u{1F1F7}"),
        ("New York", "America/New_York", "\u{1F1FA}\u{1F1F8}"),
        ("London", "Europe/London", "\u{1F1EC}\u{1F1E7}"),
        ("Tokyo", "Asia/Tokyo", "\u{1F1EF}\u{1F1F5}"),
        ("Sydney", "Australia/Sydney", "\u{1F1E6}\u{1F1FA}"),
        ("Dubai", "Asia/Dubai", "\u{1F1E6}\u{1F1EA}"),
    ]

    var body: some View {
        VStack(spacing: isCompact ? 4 : 10) {
            if !isCompact {
                WidgetHeader(title: "WORLD CLOCKS", color: Theme.widgetPrimary("world-clocks", ts: ts, default: .cyan))
            }

            let cols = Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(worldClocks, id: \.tz) { clock in
                    clockCard(clock)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        .onReceive(timer) { now = $0 }
    }

    private func clockCard(_ clock: (city: String, tz: String, flag: String)) -> some View {
        let tz = TimeZone(identifier: clock.tz) ?? .current
        let formatter = DateFormatter()
        formatter.timeZone = tz
        formatter.dateFormat = use24h ? "HH:mm" : "h:mm a"
        let timeStr = formatter.string(from: now)

        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(clock.flag)
                    .font(.system(size: (isCompact ? 14 : 18) * ts.fontScale))
                Text(clock.city)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .lineLimit(1)
            }
            Text(timeStr)
                .font(Theme.value(ts))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 4 : 8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
