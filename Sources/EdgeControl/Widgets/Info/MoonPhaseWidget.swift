import SwiftUI

public final class MoonPhaseWidget: DashboardWidget {
    public let widgetId = "moon-phase"
    public let displayName = "Moon Phase"
    public let description = "Current moon phase with illumination percentage"
    public let iconName = "moon.stars"
    public let category: WidgetCategory = .info
    public let supportedSizes = WidgetSizeRange(min: .size(2, 2), max: .size(5, 4))
    public let defaultSize = WidgetSize.size(3, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showIllumination", label: "Show Illumination", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .yellow)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        MoonPhaseWidgetView(
            showIllumination: config.bool("showIllumination", default: true),
            isCompact: size.width <= 2 && size.height <= 2
        )
    }
}

private struct MoonPhaseWidgetView: View {
    let showIllumination: Bool
    let isCompact: Bool

    @Environment(\.themeSettings) private var ts
    @State private var now = Date()
    private let timer = Timer.publish(every: 3600, on: .main, in: .common).autoconnect()

    // Simple moon phase calculation (synodic month = 29.53 days)
    private var moonAge: Double {
        let ref = DateComponents(calendar: .current, year: 2000, month: 1, day: 6, hour: 18, minute: 14).date!
        let days = now.timeIntervalSince(ref) / 86400
        return days.truncatingRemainder(dividingBy: 29.53)
    }

    private var illumination: Double {
        let angle = moonAge / 29.53 * 2 * .pi
        return (1 - cos(angle)) / 2
    }

    private var phaseName: String {
        let age = moonAge
        if age < 1.85 { return "New Moon" }
        if age < 7.38 { return "Waxing Crescent" }
        if age < 9.23 { return "First Quarter" }
        if age < 14.76 { return "Waxing Gibbous" }
        if age < 16.61 { return "Full Moon" }
        if age < 22.14 { return "Waning Gibbous" }
        if age < 23.99 { return "Last Quarter" }
        if age < 27.68 { return "Waning Crescent" }
        return "New Moon"
    }

    private var phaseEmoji: String {
        let age = moonAge
        if age < 1.85 { return "\u{1F311}" }
        if age < 7.38 { return "\u{1F312}" }
        if age < 9.23 { return "\u{1F313}" }
        if age < 14.76 { return "\u{1F314}" }
        if age < 16.61 { return "\u{1F315}" }
        if age < 22.14 { return "\u{1F316}" }
        if age < 23.99 { return "\u{1F317}" }
        if age < 27.68 { return "\u{1F318}" }
        return "\u{1F311}"
    }

    var body: some View {
        VStack(spacing: isCompact ? 4 : 10) {
            Text(phaseEmoji)
                .font(.system(size: (isCompact ? 36 : 64) * ts.fontScale))

            if !isCompact {
                Text(phaseName)
                    .font(Theme.body(ts))
                    .foregroundStyle(.white)
            }

            if showIllumination {
                Text(String(format: "%.0f%%", illumination * 100))
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.widgetPrimary("moon-phase", ts: ts, default: .yellow))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
        .onReceive(timer) { now = $0 }
    }
}
