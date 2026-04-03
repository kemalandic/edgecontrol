import SwiftUI

// MARK: - Design Tokens (iCUE-inspired dark dashboard theme)

enum Theme {

    // MARK: Backgrounds
    static let backgroundPrimary = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let backgroundWidget = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let backgroundWidgetInner = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let backgroundCard = Color(white: 1, opacity: 0.04)
    static let backgroundCardHover = Color(white: 1, opacity: 0.07)

    // MARK: Accents
    static let accentCyan = Color(red: 0.00, green: 0.90, blue: 1.00)
    static let accentBlue = Color(red: 0.20, green: 0.50, blue: 1.00)
    static let accentPurple = Color(red: 0.55, green: 0.30, blue: 1.00)
    static let accentGreen = Color(red: 0.20, green: 0.90, blue: 0.50)
    static let accentYellow = Color(red: 0.96, green: 0.77, blue: 0.09)
    static let accentOrange = Color(red: 1.00, green: 0.42, blue: 0.21)
    static let accentRed = Color(red: 1.00, green: 0.18, blue: 0.18)

    // MARK: Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: Borders & Dividers
    static let borderSubtle = Color.white.opacity(0.08)
    static let borderMedium = Color.white.opacity(0.14)
    static let shadowColor = Color.black.opacity(0.40)

    // MARK: Sizing
    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 10

    // MARK: Gradients

    /// Thermal gradient for gauges: cyan → green → orange → red
    static let thermalGradient = AngularGradient(
        stops: [
            .init(color: accentCyan, location: 0.0),
            .init(color: accentGreen, location: 0.25),
            .init(color: accentYellow, location: 0.55),
            .init(color: accentOrange, location: 0.75),
            .init(color: accentRed, location: 1.0)
        ],
        center: .center,
        startAngle: .degrees(135),
        endAngle: .degrees(405)
    )

    /// Widget card background gradient
    static let cardGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.06),
            Color.white.opacity(0.02),
            Color.black.opacity(0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Glow effect behind gauges
    static func glowGradient(_ color: Color) -> RadialGradient {
        RadialGradient(
            colors: [color.opacity(0.25), color.opacity(0.0)],
            center: .center,
            startRadius: 10,
            endRadius: 80
        )
    }
}

// MARK: - Reusable View Modifiers

struct ThemeCard: ViewModifier {
    var cornerRadius: CGFloat = Theme.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Theme.backgroundWidget
                    Theme.cardGradient
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Theme.shadowColor, radius: 12, x: 0, y: 4)
    }
}

extension View {
    func themeCard(cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(ThemeCard(cornerRadius: cornerRadius))
    }
}

// MARK: - Animated Number Display

struct AnimatedNumberView: View {
    let value: Double
    let format: String
    let font: Font
    let color: Color

    @State private var displayValue: Double = 0

    var body: some View {
        Text(String(format: format, displayValue))
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: displayValue))
            .onChange(of: value) { _, newValue in
                withAnimation(.easeInOut(duration: 0.6)) {
                    displayValue = newValue
                }
            }
            .onAppear {
                displayValue = value
            }
    }
}

// MARK: - Radial Gauge (iCUE-style 270° arc)

struct RadialGaugeView: View {
    let value: Double
    let maxValue: Double
    let label: String
    let displayValue: String
    let unit: String
    let accentColor: Color

    private let lineWidth: CGFloat = 12
    private let startAngle: Double = 135
    private let endAngle: Double = 405

    private var progress: Double {
        min(max(value / maxValue, 0), 1)
    }

    private var gaugeColor: Color {
        if progress < 0.5 { return Theme.accentCyan }
        if progress < 0.75 { return Theme.accentYellow }
        return Theme.accentRed
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Background glow
                Circle()
                    .fill(Theme.glowGradient(gaugeColor))
                    .scaleEffect(1.3)
                    .opacity(0.4)

                // Track arc
                ArcShape(startAngle: startAngle, endAngle: endAngle)
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Value arc with gradient
                ArcShape(startAngle: startAngle, endAngle: startAngle + (endAngle - startAngle) * progress)
                    .stroke(
                        AngularGradient(
                            stops: [
                                .init(color: Theme.accentCyan, location: 0.0),
                                .init(color: gaugeColor, location: 1.0)
                            ],
                            center: .center,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(startAngle + (endAngle - startAngle) * progress)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )

                // Center value
                VStack(spacing: 3) {
                    Text(displayValue)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
    }
}

// MARK: - Live Clock Widget

struct ClockWidgetView: View {
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 6) {
            Text(timeString)
                .font(.system(size: 72, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(dateString)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .minimumScaleFactor(0.5)
        }
        .onReceive(timer) { now = $0 }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: now)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM yyyy"
        return f.string(from: now)
    }
}

// MARK: - Arc Shape

struct ArcShape: Shape {
    var startAngle: Double
    var endAngle: Double

    var animatableData: Double {
        get { endAngle }
        set { endAngle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 4
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}
