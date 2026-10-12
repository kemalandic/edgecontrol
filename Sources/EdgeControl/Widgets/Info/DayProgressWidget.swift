import Combine
import SwiftUI

public final class DayProgressWidget: DashboardWidget {
    public let widgetId = "day-progress"
    public let displayName = "Day Progress"
    public let description = "Visual progress of the current day with time remaining"
    public let iconName = "sun.max"
    public let category: WidgetCategory = .info
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(6, 3))
    public let defaultSize = WidgetSize.size(4, 2)

    public let configSchema: [ConfigSchemaEntry] = []
    public let defaultColors = WidgetColors(primary: .yellow, secondary: .orange)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        // The ring needs two rows of height; a 1-row placement always gets the
        // linear title+bar layout, which fits a single 120px grid row.
        DayProgressWidgetView(isCompact: size.width <= 3 && size.height >= 2, isTall: size.height >= 2)
    }
}

private struct DayProgressWidgetView: View {
    let isCompact: Bool
    let isTall: Bool

    @Environment(\.themeSettings) private var ts
    @State private var now = Date()
    private let timer = Timer.publish(every: 30, tolerance: 5, on: .main, in: .common).autoconnect()

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
        VStack(spacing: isCompact ? 6 : (isTall ? 20 : 10)) {
            if isCompact {
                // Compact: the ring, and beside it what it measures, so a bare
                // percentage isn't left to explain itself.
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: dayProgress)
                            .stroke(
                                Theme.widgetPrimary("day-progress", ts: ts, default: .yellow),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))

                        Text(String(format: "%.0f%%", dayProgress * 100))
                            .font(Theme.value(ts))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .minimumScaleFactor(0.5)
                            .padding(10)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .padding(4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DAY PROGRESS")
                            .font(Theme.caption(ts))
                            .tracking(0.8)
                            .foregroundStyle(Theme.widgetPrimary("day-progress", ts: ts, default: .yellow))
                            .lineLimit(1)
                        Text(timeRemaining)
                            .font(Theme.title(ts))
                            .foregroundStyle(Theme.text1(ts))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("left today")
                            .font(Theme.caption(ts))
                            .foregroundStyle(Theme.text2(ts))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                // Center the linear stack in 2+ row cells; 1-row keeps its top-aligned fit.
                if isTall { Spacer(minLength: 0) }
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
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Theme.widgetPrimary("day-progress", ts: ts, default: .yellow),
                                        Theme.widgetSecondary("day-progress", ts: ts, default: .orange)
                                            ?? Theme.accentOrange,
                                    ],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * dayProgress)
                    }
                }
                .frame(height: isTall ? 14 : 10)

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

            if !isCompact { Spacer(minLength: 0) }
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        .onReceive(timer) { now = $0 }
    }
}
