import SwiftUI

public final class BatteriesWidget: DashboardWidget {
    public let widgetId = "batteries"
    public let displayName = "Batteries"
    public let description = "This Mac, AirPods and Magic accessories' battery levels, like the macOS widget"
    public let iconName = "battery.100percent"
    public let category: WidgetCategory = .system
    public let requiredServices: Set<ServiceKey> = [.batteries]
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(20, 6))
    /// Four rings in a row, as the macOS widget's medium size has.
    public let defaultSize = WidgetSize.size(5, 2)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(
            key: "style", label: "Show", type: .picker, defaultValue: .string("Rings"), options: ["Rings", "List"],
            help: "Rings shows each battery round its icon. List adds names and a bar each."),
        ConfigSchemaEntry(
            key: "showNames", label: "Show Names", type: .toggle, defaultValue: .bool(false),
            help: "Rings only: the list always names them."),
    ]
    public let defaultColors = WidgetColors(primary: .green)

    private let service: BatteryService

    public init(service: BatteryService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        BatteriesWidgetView(
            service: service, list: config.string("style", default: "Rings") == "List",
            showNames: config.bool("showNames", default: false))
    }
}

/// Rings sized to fill the tile: as many to a row as makes them biggest.
struct BatteryRingLayout: Equatable {
    var columns: Int
    var rows: Int
    var ring: CGFloat

    /// Bigger than this looks like a gauge, not a battery.
    static let largest: CGFloat = 150
    /// Smaller than this, a ring's percentage is wider than the ring.
    static let smallest: CGFloat = 44

    /// `label` is the height under each ring for its percentage (and name).
    static func fit(count: Int, width: CGFloat, height: CGFloat, spacing: CGFloat, label: CGFloat) -> Self {
        var best = Self(columns: max(1, count), rows: 1, ring: 0)
        guard count > 0, width > 0, height > 0 else { return best }
        for rows in 1...count {
            let columns = (count + rows - 1) / rows
            // Rows that would sit empty are no better than fewer rows.
            guard (columns * rows) - count < columns else { continue }
            let cellWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (height - spacing * CGFloat(rows - 1)) / CGFloat(rows) - label
            let ring = min(cellWidth, cellHeight, largest).rounded(.down)
            if ring > best.ring { best = Self(columns: columns, rows: rows, ring: ring) }
        }
        return best
    }

    /// As many batteries as fit at a readable size, the first ones first, as
    /// the macOS widget's small size shows four.
    static func fitting(
        count: Int, width: CGFloat, height: CGFloat, spacing: CGFloat, label: CGFloat
    ) -> (
        layout: Self, shown: Int
    ) {
        var shown = count
        while shown > 1 {
            let layout = fit(count: shown, width: width, height: height, spacing: spacing, label: label)
            if layout.ring >= smallest { return (layout, shown) }
            shown -= 1
        }
        return (fit(count: shown, width: width, height: height, spacing: spacing, label: label), shown)
    }
}

private struct BatteriesWidgetView: View {
    @ObservedObject var service: BatteryService
    let list: Bool
    let showNames: Bool

    @Environment(\.themeSettings) private var ts

    private var primary: Color { Theme.widgetPrimary("batteries", ts: ts, default: .green) }

    var body: some View {
        content
            .padding(Theme.compactPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetCard()
    }

    @ViewBuilder
    private var content: some View {
        let readings = service.readings
        if readings.isEmpty {
            if service.hasRead { empty } else { ProgressView().controlSize(.small).tint(primary) }
        } else if list {
            rows(readings)
        } else {
            GeometryReader { geo in
                let fitted = BatteryRingLayout.fitting(
                    count: readings.count, width: geo.size.width, height: geo.size.height, spacing: spacing,
                    label: labelHeight)
                rings(Array(readings.prefix(fitted.shown)), layout: fitted.layout, in: geo.size)
            }
        }
    }

    private var spacing: CGFloat { max(8, CGFloat(ts.widgetGap) * 2) }

    /// The percentage line, and the name line when names show.
    private var labelHeight: CGFloat {
        let percent = ts.fontSizeLabel * ts.fontScale * 1.3 + 6
        return CGFloat(showNames ? percent + ts.fontSizeCaption * ts.fontScale * 1.3 : percent)
    }

    // MARK: - Rings

    private func rings(_ readings: [BatteryReading], layout: BatteryRingLayout, in size: CGSize) -> some View {
        let columns = Array(
            repeating: GridItem(.fixed(layout.ring), spacing: spacing), count: layout.columns)
        return LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(readings) { reading in
                VStack(spacing: 6) {
                    BatteryRing(reading: reading, size: layout.ring, color: color(for: reading), ts: ts)
                    VStack(spacing: 1) {
                        percent(reading)
                        if showNames {
                            Text(reading.name)
                                .font(Theme.caption(ts))
                                .foregroundStyle(Theme.text3(ts))
                                .lineLimit(1)
                                .frame(width: layout.ring + spacing)
                        }
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func percent(_ reading: BatteryReading) -> some View {
        HStack(spacing: 2) {
            if reading.charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: ts.fontSizeCaption * ts.fontScale, weight: .bold))
                    .foregroundStyle(color(for: reading))
            }
            Text("\(reading.level)%")
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: - List

    private func rows(_ readings: [BatteryReading]) -> some View {
        GeometryReader { geo in
            TouchScrollView {
                VStack(spacing: 0) {
                    ForEach(readings) { reading in
                        row(reading)
                    }
                }
                .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
    }

    private func row(_ reading: BatteryReading) -> some View {
        HStack(spacing: 10) {
            Image(systemName: reading.symbol)
                .font(.system(size: 17 * ts.fontScale))
                .foregroundStyle(Theme.text1(ts))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(reading.name)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
                if let detail = reading.detail {
                    Text(detail)
                        .font(Theme.caption(ts))
                        .foregroundStyle(Theme.text3(ts))
                        .monospacedDigit()
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            bar(reading)
            percent(reading)
                .frame(minWidth: 52, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }

    private func bar(_ reading: BatteryReading) -> some View {
        let color = color(for: reading)
        return Capsule()
            .fill(color.opacity(0.2))
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(color)
                        .frame(width: max(6, geo.size.width * CGFloat(reading.level) / 100))
                }
            }
            .frame(minWidth: 40, maxWidth: 120)
            .frame(height: 6)
    }

    // MARK: - States

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "battery.0percent")
                .font(.system(size: 26 * ts.fontScale))
                .foregroundStyle(Theme.text3(ts))
            Text("NO BATTERIES")
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
            Text("Connect AirPods, or a Magic Keyboard, Mouse or Trackpad")
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Red when low, yellow in Low Power Mode, as the macOS widget does.
    private func color(for reading: BatteryReading) -> Color {
        if reading.isLow { return Theme.accentRed }
        if reading.lowPower { return Theme.accentYellow }
        return primary
    }
}

/// A battery's level round its device's icon.
private struct BatteryRing: View {
    let reading: BatteryReading
    let size: CGFloat
    let color: Color
    let ts: ThemeSettings

    var body: some View {
        let line = max(3, (size * 0.085).rounded())
        ZStack {
            Circle()
                .strokeBorder(color.opacity(0.22), lineWidth: line)
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: CGFloat(reading.level) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: reading.symbol)
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(Theme.text1(ts))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.4), value: reading.level)
    }
}
