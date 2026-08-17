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
        let maxByWidth = size.width >= 8 ? 3 : 2
        // Card rows the placement can hold: grid rows are ~120px, a clock card
        // plus grid spacing is ~88px, and header/padding overhead is ~60px.
        let rowsThatFit = max(1, (size.height * 120 - 60) / 88)
        // Fewer columns on tall placements so the 6 clocks span the height
        // instead of top-stacking; integer ceiling of 6 / rowsThatFit.
        let columns = min(maxByWidth, max(1, (6 + rowsThatFit - 1) / rowsThatFit))
        return WorldClocksWidgetView(
            use24h: config.bool("use24h", default: true),
            isCompact: size.height <= 2,
            columns: columns
        )
    }
}

private struct WorldClocksWidgetView: View {
    let use24h: Bool
    let isCompact: Bool
    let columns: Int

    @Environment(\.themeSettings) private var ts
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, tolerance: 0.1, on: .main, in: .common).autoconnect()

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

            // Explicit rows instead of LazyVGrid: grid rows hug their content,
            // which top-stacks the cards and leaves dead space on tall
            // placements. Stretching each row distributes the leftover height.
            VStack(spacing: 8) {
                ForEach(Array(clockRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.tz) { clock in
                            clockCard(clock)
                        }
                        if row.count < columns {
                            ForEach(0..<(columns - row.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        .onReceive(timer) { now = $0 }
    }

    private var clockRows: [[(city: String, tz: String, flag: String)]] {
        stride(from: 0, to: worldClocks.count, by: columns).map {
            Array(worldClocks[$0..<min($0 + columns, worldClocks.count)])
        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, isCompact ? 4 : 8)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
