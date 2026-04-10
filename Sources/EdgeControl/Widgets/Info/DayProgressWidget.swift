import SwiftUI

public final class DayProgressWidget: DashboardWidget {
    public let widgetId = "day-progress"
    public let displayName = "Day Progress"
    public let description = "Visual progress of the current day with time remaining"
    public let iconName = "sun.max"
    public let category: WidgetCategory = .info
    public let supportedSizes = WidgetSizeRange(min: .size(2, 2), max: .size(6, 3))
    public let defaultSize = WidgetSize.size(4, 2)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .yellow, secondary: .orange)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        DayProgressWidgetView(isCompact: size.width <= 3)
    }
}

private struct DayProgressWidgetView: View {
    let isCompact: Bool

    @Environment(\.themeSettings) private var ts
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var dayProgress: Double {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let elapsed = now.timeIntervalSince(startOfDay)
        return min(elapsed / 86400, 1)
    }

    private var timeRemaining: String {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        let remaining = 86400 - now.timeIntervalSince(startOfDay)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    var body: some View {
        VStack(spacing: isCompact ? 6 : 10) {
            if isCompact {
                // Compact: circular progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: dayProgress)
                        .stroke(Theme.widgetPrimary("day-progress", ts: ts, default: .yellow), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Text(String(format: "%.0f%%", dayProgress * 100))
                        .font(Theme.value(ts))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .aspectRatio(1, contentMode: .fit)
                .padding(4)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 18 * ts.fontScale))
                        .foregroundStyle(Theme.widgetPrimary("day-progress", ts: ts, default: .yellow))
                    Text("DAY PROGRESS")
                        .font(Theme.body(ts))
                        .foregroundStyle(Theme.text2(ts))
                    Spacer()
                    Text(String(format: "%.0f%%", dayProgress * 100))
                        .font(Theme.value(ts))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [Theme.widgetPrimary("day-progress", ts: ts, default: .yellow), Theme.widgetSecondary("day-progress", ts: ts, default: .orange) ?? Theme.accentOrange],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * dayProgress)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("REMAINING")
                        .font(Theme.caption(ts))
                        .foregroundStyle(Theme.text3(ts))
                    Spacer()
                    Text(timeRemaining)
                        .font(Theme.body(ts))
                        .foregroundStyle(Theme.text2(ts))
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        .onReceive(timer) { now = $0 }
    }
}
