import SwiftUI

// MARK: - Clock Style Enum

public enum ClockStyle: String, Codable, CaseIterable, Sendable {
    case digital
    case analog
    case lcd
    case minimal
    case split
    case rings
    case dayBar
    case neon
    case binary
    case dotMatrix

    public var displayName: String {
        switch self {
        case .digital: "Digital"
        case .analog: "Analog"
        case .lcd: "LCD Retro"
        case .minimal: "Minimal"
        case .split: "Split"
        case .rings: "Rings"
        case .dayBar: "Day Bar"
        case .neon: "Neon"
        case .binary: "Binary"
        case .dotMatrix: "Dot Matrix"
        }
    }
}

// MARK: - Clock Widget

public final class ClockWidget: DashboardWidget {
    public let widgetId = "clock"
    public let displayName = "Clock"
    public let description = "Live clock with 10 visual themes"
    public let iconName = "clock"
    public let category: WidgetCategory = .info
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(8, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showSeconds", label: "Show Seconds", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "showDate", label: "Show Date", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "use24h", label: "24-Hour Format", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "clockStyle", label: "Style", type: .picker, defaultValue: .string("digital"), options: ClockStyle.allCases.map(\.rawValue)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        let style = ClockStyle(rawValue: config.string("clockStyle", default: "digital")) ?? .digital
        ClockContainer(
            style: style,
            showSeconds: config.bool("showSeconds", default: true),
            showDate: config.bool("showDate", default: true),
            use24h: config.bool("use24h", default: true),
            isCompact: size.height <= 2
        )
    }
}

// MARK: - Container

private struct ClockContainer: View {
    let style: ClockStyle
    let showSeconds: Bool
    let showDate: Bool
    let use24h: Bool
    let isCompact: Bool

    @Environment(\.themeSettings) private var ts
    @State private var now = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var primary: Color { Theme.widgetPrimary("clock", ts: ts, default: .cyan) }
    var cal: Calendar { Calendar.current }
    var hour: Int { cal.component(.hour, from: now) }
    var minute: Int { cal.component(.minute, from: now) }
    var second: Int { cal.component(.second, from: now) }
    var hour12: Int { let h = hour % 12; return h == 0 ? 12 : h }
    var weekday: Int { cal.component(.weekday, from: now) } // 1=Sun

    var hourStr: String { String(format: use24h ? "%02d" : "%d", use24h ? hour : hour12) }
    var minStr: String { String(format: "%02d", minute) }
    var secStr: String { String(format: "%02d", second) }
    var ampm: String { hour < 12 ? "AM" : "PM" }

    var body: some View {
        Group {
            switch style {
            case .digital: digitalStyle
            case .analog: analogStyle
            case .lcd: lcdStyle
            case .minimal: minimalStyle
            case .split: splitStyle
            case .rings: ringsStyle
            case .dayBar: dayBarStyle
            case .neon: neonStyle
            case .binary: binaryStyle
            case .dotMatrix: dotMatrixStyle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.widgetPadding)
        .widgetCard()
        .onReceive(timer) { now = $0 }
    }

    // MARK: - Date Helpers

    var shortDate: String {
        Self.shortDateFormatter.string(from: now)
    }
    var fullDate: String {
        Self.fullDateFormatter.string(from: now)
    }
    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, d MMM"; return f
    }()
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, d MMMM yyyy"; return f
    }()
    var dayNames: [String] { ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 1. Digital
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var digitalStyle: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    timeRow(size: isCompact ? ts.fontSizeValue * 2.2 : ts.fontSizeValue * 2.5, weight: .thin)
                    if showDate {
                        Text(isCompact ? shortDate : fullDate)
                            .font(isCompact ? Theme.label(ts) : Theme.title(ts))
                            .foregroundStyle(Theme.text2(ts))
                            .textCase(.uppercase)
                    }
                }
                if isCompact { Spacer(minLength: 8); compactInfoChips }
            }
            Spacer(minLength: 0)
            if showSeconds { secondsBar }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 2. Analog
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var analogStyle: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                let r = size / 2 - 4

                ZStack {
                    // Face
                    Circle().stroke(primary.opacity(0.2), lineWidth: 2)
                    // Hour ticks
                    ForEach(0..<12, id: \.self) { i in
                        let angle = Double(i) / 12 * 2 * .pi - .pi / 2
                        let inner = r * (i % 3 == 0 ? 0.75 : 0.85)
                        Path { p in
                            p.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                            p.addLine(to: CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r))
                        }
                        .stroke(i % 3 == 0 ? primary.opacity(0.6) : Theme.text3(ts), lineWidth: i % 3 == 0 ? 2 : 1)
                    }
                    // Hour hand
                    clockHand(center: center, length: r * 0.5, width: 3,
                              angle: (Double(hour % 12) + Double(minute) / 60) / 12 * 360,
                              color: Theme.text1(ts))
                    // Minute hand
                    clockHand(center: center, length: r * 0.7, width: 2,
                              angle: (Double(minute) + Double(second) / 60) / 60 * 360,
                              color: Theme.text1(ts))
                    // Second hand
                    if showSeconds {
                        clockHand(center: center, length: r * 0.8, width: 1,
                                  angle: Double(second) / 60 * 360,
                                  color: primary)
                    }
                    // Center dot
                    Circle().fill(primary).frame(width: 6, height: 6).position(center)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            if !isCompact && showDate {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hourStr + ":" + minStr)
                        .font(Theme.value(ts))
                        .foregroundStyle(Theme.text1(ts))
                        .monospacedDigit()
                    Text(fullDate)
                        .font(Theme.caption(ts))
                        .foregroundStyle(Theme.text2(ts))
                        .textCase(.uppercase)
                }
            }
        }
    }

    private func clockHand(center: CGPoint, length: CGFloat, width: CGFloat, angle: Double, color: Color) -> some View {
        let rad = (angle - 90) * .pi / 180
        return Path { p in
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + cos(rad) * length, y: center.y + sin(rad) * length))
        }
        .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 3. LCD Retro
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var lcdStyle: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            // Day of week bar
            HStack(spacing: 4) {
                ForEach(Array(dayNames.enumerated()), id: \.offset) { i, name in
                    Text(name)
                        .font(.system(size: (isCompact ? 8 : 10) * ts.fontScale, weight: weekday == i + 1 ? .black : .medium, design: .monospaced))
                        .foregroundStyle(weekday == i + 1 ? primary : Theme.text3(ts))
                }
            }

            // LCD time
            HStack(spacing: 2) {
                Text(hourStr)
                    .foregroundStyle(Theme.text1(ts))
                Text(":")
                    .foregroundStyle(primary)
                    .opacity(second % 2 == 0 ? 1 : 0.3)
                Text(minStr)
                    .foregroundStyle(Theme.text1(ts))
                if showSeconds {
                    Text(":")
                        .foregroundStyle(primary)
                        .opacity(second % 2 == 0 ? 1 : 0.3)
                    Text(secStr)
                        .foregroundStyle(Theme.text2(ts))
                }
                if !use24h {
                    Text(ampm)
                        .font(Theme.font(size: ts.fontSizeLabel, weight: .bold, settings: ts))
                        .foregroundStyle(primary.opacity(0.6))
                }
            }
            .font(Theme.font(size: isCompact ? ts.fontSizeValue * 2.0 : ts.fontSizeValue * 2.5, weight: .bold, settings: ts))
            .monospacedDigit()
            .minimumScaleFactor(0.3)
            .lineLimit(1)

            if showDate && !isCompact {
                Text(fullDate)
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .textCase(.uppercase)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 4. Minimal
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var minimalStyle: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(hourStr + ":" + minStr)
                .font(Theme.font(size: isCompact ? ts.fontSizeValue * 3.0 : ts.fontSizeValue * 4.0, weight: .ultraLight, settings: ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
                .minimumScaleFactor(0.2)
                .lineLimit(1)
            Spacer()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 5. Flip
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var splitStyle: some View {
        let fontSize = isCompact ? ts.fontSizeValue * 2.0 : ts.fontSizeValue * 2.8
        return HStack(spacing: isCompact ? 4 : 6) {
            splitCard(hourStr, fontSize: fontSize)
            splitColon
            splitCard(minStr, fontSize: fontSize)
            if showSeconds {
                splitColon
                splitCard(secStr, fontSize: fontSize)
            }
        }
        .minimumScaleFactor(0.3)
    }

    private func splitCard(_ text: String, fontSize: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
            VStack(spacing: 0) {
                Color.white.opacity(0.02)
                Color.black.opacity(0.08)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1.5)
            Text(text)
                .font(Theme.font(size: fontSize, weight: .bold, settings: ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
        }
        .aspectRatio(0.75, contentMode: .fit)
    }

    private var splitColon: some View {
        VStack(spacing: isCompact ? 6 : 10) {
            Circle().fill(primary).frame(width: isCompact ? 4 : 6, height: isCompact ? 4 : 6)
            Circle().fill(primary).frame(width: isCompact ? 4 : 6, height: isCompact ? 4 : 6)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 6. Rings
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var ringsStyle: some View {
        HStack(spacing: 12) {
            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height)
                let lw: CGFloat = isCompact ? 6 : 8

                ZStack {
                    // Hour ring (outer)
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: lw)
                    Circle().trim(from: 0, to: Double(hour % 12) / 12)
                        .stroke(primary, style: StrokeStyle(lineWidth: lw, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    // Minute ring (middle)
                    Circle().stroke(Color.white.opacity(0.06), lineWidth: lw)
                        .padding(lw + 4)
                    Circle().trim(from: 0, to: Double(minute) / 60)
                        .stroke(primary.opacity(0.6), style: StrokeStyle(lineWidth: lw, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(lw + 4)

                    // Second ring (inner)
                    if showSeconds {
                        Circle().stroke(Color.white.opacity(0.06), lineWidth: lw * 0.6)
                            .padding((lw + 4) * 2)
                        Circle().trim(from: 0, to: Double(second) / 60)
                            .stroke(primary.opacity(0.3), style: StrokeStyle(lineWidth: lw * 0.6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding((lw + 4) * 2)
                    }

                    // Center time
                    VStack(spacing: 0) {
                        Text(hourStr + ":" + minStr)
                            .font(Theme.font(size: size * 0.18, weight: .bold, settings: ts))
                            .foregroundStyle(Theme.text1(ts))
                            .monospacedDigit()
                        if showDate {
                            Text(shortDate)
                                .font(Theme.font(size: size * 0.06, weight: .semibold, settings: ts))
                                .foregroundStyle(Theme.text3(ts))
                                .textCase(.uppercase)
                        }
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .aspectRatio(1, contentMode: .fit)

            if !isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    ringLegend("H", value: hour, max: 12, color: primary)
                    ringLegend("M", value: minute, max: 60, color: primary.opacity(0.6))
                    if showSeconds {
                        ringLegend("S", value: second, max: 60, color: primary.opacity(0.3))
                    }
                }
            }
        }
    }

    private func ringLegend(_ label: String, value: Int, max: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
            Text("\(value)")
                .font(Theme.label(ts))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 7. Day Bar
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var dayBarStyle: some View {
        VStack(spacing: isCompact ? 6 : 10) {
            // Day bar
            HStack(spacing: 0) {
                ForEach(Array(dayNames.enumerated()), id: \.offset) { i, name in
                    Text(name)
                        .font(.system(size: (isCompact ? 9 : 11) * ts.fontScale, weight: .heavy, design: ts.fontFamily.design))
                        .foregroundStyle(weekday == i + 1 ? .white : Theme.text3(ts))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, isCompact ? 3 : 5)
                        .background(
                            weekday == i + 1 ? primary.opacity(0.3) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }

            // Time
            timeRow(size: isCompact ? ts.fontSizeValue * 2.0 : ts.fontSizeValue * 2.5, weight: .semibold)

            if showDate && !isCompact {
                Text(fullDate)
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .textCase(.uppercase)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 8. Neon
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var neonStyle: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            Spacer(minLength: 0)
            timeRow(size: isCompact ? ts.fontSizeValue * 2.2 : ts.fontSizeValue * 2.8, weight: .bold)
                .shadow(color: primary.opacity(0.8), radius: 12)
                .shadow(color: primary.opacity(0.4), radius: 24)

            if showDate {
                Text(isCompact ? shortDate : fullDate)
                    .font(isCompact ? Theme.caption(ts) : Theme.title(ts))
                    .foregroundStyle(primary.opacity(0.7))
                    .shadow(color: primary.opacity(0.5), radius: 8)
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 9. Binary
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var binaryStyle: some View {
        let digits = showSeconds
            ? [hour / 10, hour % 10, minute / 10, minute % 10, second / 10, second % 10]
            : [hour / 10, hour % 10, minute / 10, minute % 10]
        let labels = showSeconds ? ["H", "H", "M", "M", "S", "S"] : ["H", "H", "M", "M"]
        let dotSize: CGFloat = isCompact ? 10 : 14

        return VStack(spacing: 4) {
            HStack(spacing: isCompact ? 8 : 12) {
                ForEach(Array(digits.enumerated()), id: \.offset) { i, digit in
                    VStack(spacing: 3) {
                        ForEach((0..<4).reversed(), id: \.self) { bit in
                            Circle()
                                .fill((digit >> bit) & 1 == 1 ? primary : Color.white.opacity(0.08))
                                .frame(width: dotSize, height: dotSize)
                        }
                        Text(labels[i])
                            .font(.system(size: 8 * ts.fontScale, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.text3(ts))
                    }

                    if i == 1 || (showSeconds && i == 3) {
                        if i < digits.count - 1 {
                            VStack(spacing: isCompact ? 8 : 12) {
                                Circle().fill(primary.opacity(0.4)).frame(width: 4, height: 4)
                                Circle().fill(primary.opacity(0.4)).frame(width: 4, height: 4)
                            }
                        }
                    }
                }
            }

            if showDate && !isCompact {
                Text(shortDate)
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .textCase(.uppercase)
                    .padding(.top, 4)
            }
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: 10. Dot Matrix
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private var dotMatrixStyle: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            Spacer(minLength: 0)

            // Simulated dot matrix with actual text + dot grid overlay
            ZStack {
                timeRow(size: isCompact ? ts.fontSizeValue * 2.0 : ts.fontSizeValue * 2.5, weight: .heavy)
                    .opacity(0.9)

                // Scanline effect
                VStack(spacing: 2) {
                    ForEach(0..<20, id: \.self) { _ in
                        Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
                        Spacer(minLength: 0).frame(maxHeight: 2)
                    }
                }
                .allowsHitTesting(false)
            }

            if showDate {
                Text(isCompact ? shortDate : fullDate)
                    .font(Theme.font(size: isCompact ? ts.fontSizeCaption : ts.fontSizeLabel, weight: .bold, settings: ts))
                    .foregroundStyle(primary.opacity(0.6))
                    .textCase(.uppercase)
            }
            Spacer(minLength: 0)
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Shared Components
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    private func timeRow(size: Double, weight: Font.Weight) -> some View {
        HStack(spacing: 0) {
            Text(hourStr).foregroundStyle(Theme.text1(ts))
            Text(":").foregroundStyle(primary)
            Text(minStr).foregroundStyle(Theme.text1(ts))
            if showSeconds {
                Text(":").foregroundStyle(primary.opacity(0.4))
                Text(secStr).foregroundStyle(Theme.text3(ts))
            }
            if !use24h {
                Text(" " + ampm)
                    .font(Theme.font(size: size * 0.4, weight: .semibold, settings: ts))
                    .foregroundStyle(primary.opacity(0.6))
            }
        }
        .font(Theme.font(size: size, weight: weight, settings: ts))
        .monospacedDigit()
        .minimumScaleFactor(0.2)
        .lineLimit(1)
    }

    private var secondsBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 2).fill(primary.opacity(0.6))
                    .frame(width: geo.size.width * Double(second) / 60.0)
            }
        }
        .frame(height: 3)
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var compactInfoChips: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.system(size: 10 * ts.fontScale)).foregroundStyle(primary.opacity(0.5))
                Text("W\(cal.component(.weekOfYear, from: now))").font(Theme.caption(ts)).foregroundStyle(primary.opacity(0.7))
            }
            HStack(spacing: 4) {
                Image(systemName: "globe").font(.system(size: 10 * ts.fontScale)).foregroundStyle(Theme.text3(ts))
                Text(TimeZone.current.abbreviation() ?? "UTC").font(Theme.caption(ts)).foregroundStyle(Theme.text3(ts))
            }
        }
    }
}

