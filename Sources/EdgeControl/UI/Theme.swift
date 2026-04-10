import SwiftUI

// MARK: - Design Tokens (iCUE-inspired dark dashboard theme)

enum Theme {

    // MARK: Default Backgrounds (fallback when no theme is resolved)
    static let backgroundPrimary = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let backgroundWidget = Color(red: 0.10, green: 0.10, blue: 0.14)
    static let backgroundWidgetInner = Color(red: 0.12, green: 0.12, blue: 0.16)
    static let backgroundCard = Color(white: 1, opacity: 0.04)
    static let backgroundCardHover = Color(white: 1, opacity: 0.07)

    // MARK: Accents (named colors always available)
    static let accentCyan = Color(red: 0.00, green: 0.90, blue: 1.00)
    static let accentBlue = Color(red: 0.20, green: 0.50, blue: 1.00)
    static let accentPurple = Color(red: 0.55, green: 0.30, blue: 1.00)
    static let accentGreen = Color(red: 0.20, green: 0.90, blue: 0.50)
    static let accentYellow = Color(red: 0.96, green: 0.77, blue: 0.09)
    static let accentOrange = Color(red: 1.00, green: 0.42, blue: 0.21)
    static let accentRed = Color(red: 1.00, green: 0.18, blue: 0.18)

    // MARK: Default Text
    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.58)
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: Borders & Dividers
    static let borderSubtle = Color.white.opacity(0.08)
    static let borderMedium = Color.white.opacity(0.14)
    static let shadowColor = Color.black.opacity(0.40)

    // MARK: Sizing (legacy — prefer semantic spacing below)
    static let cornerRadius: CGFloat = 14
    static let cornerRadiusSmall: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 10

    // MARK: Semantic Spacing
    /// Standard widget internal padding
    static let widgetPadding: CGFloat = 14
    /// Compact mode internal padding
    static let compactPadding: CGFloat = 8
    /// Between items in a list/row
    static let itemSpacing: CGFloat = 8
    /// Between major sections
    static let sectionSpacing: CGFloat = 12

    // MARK: - Resolved Theme (from ThemeSettings)

    /// Create a scaled font using theme settings.
    static func font(size: CGFloat, weight: Font.Weight = .regular, settings: ThemeSettings) -> Font {
        let scaled = size * settings.fontScale
        return .system(size: scaled, weight: weight, design: settings.fontFamily.design)
    }

    // MARK: Semantic Font Levels

    /// Widget headers — "NETWORK", "STORAGE", "CPU USAGE"
    static func title(_ ts: ThemeSettings) -> Font {
        .system(size: ts.fontSizeTitle * ts.fontScale, weight: .heavy, design: ts.fontFamily.design)
    }

    /// Large displayed values — "23%", "124 KB/s", "9°"
    static func value(_ ts: ThemeSettings) -> Font {
        .system(size: ts.fontSizeValue * ts.fontScale, weight: .bold, design: ts.fontFamily.design)
    }

    /// Medium labels — "CPU", "DOWN", "READ", column headers
    static func label(_ ts: ThemeSettings) -> Font {
        .system(size: ts.fontSizeLabel * ts.fontScale, weight: .heavy, design: ts.fontFamily.design)
    }

    /// Small labels — "USED", "FREE", "TOTAL", "Mbps"
    static func caption(_ ts: ThemeSettings) -> Font {
        .system(size: ts.fontSizeCaption * ts.fontScale, weight: .heavy, design: ts.fontFamily.design)
    }

    /// Normal text — process names, SSID, device names
    static func body(_ ts: ThemeSettings) -> Font {
        .system(size: ts.fontSizeBody * ts.fontScale, weight: .semibold, design: ts.fontFamily.design)
    }

    /// Smallest text — position info, monospaced details
    static func micro(_ ts: ThemeSettings) -> Font {
        .system(size: ts.fontSizeMicro * ts.fontScale, weight: .medium, design: ts.fontFamily.design)
    }

    /// Resolve accent color from theme settings.
    static func accent(_ settings: ThemeSettings) -> Color {
        settings.accentColor.color  // WidgetColor.color returns SwiftUI Color
    }

    /// Resolve a widget's primary color: user override → widget default.
    static func widgetPrimary(_ widgetId: String, ts: ThemeSettings, default defaultColor: ThemeColor) -> Color {
        if let override = ts.widgetColorOverrides[widgetId]?.primary {
            return override.color
        }
        return defaultColor.color
    }

    /// Resolve a widget's secondary color: user override → widget default.
    static func widgetSecondary(_ widgetId: String, ts: ThemeSettings, default defaultColor: ThemeColor?) -> Color? {
        if let override = ts.widgetColorOverrides[widgetId]?.secondary {
            return override.color
        }
        return defaultColor?.color
    }

    /// Resolve a widget's tertiary color: user override → widget default.
    static func widgetTertiary(_ widgetId: String, ts: ThemeSettings, default defaultColor: ThemeColor?) -> Color? {
        if let override = ts.widgetColorOverrides[widgetId]?.tertiary {
            return override.color
        }
        return defaultColor?.color
    }

    /// Resolve background colors from theme preset.
    static func backgroundColors(_ settings: ThemeSettings) -> [Color] {
        settings.resolvedPreset.backgroundColors
    }

    /// Resolve card background with theme opacity.
    static func cardBg(_ settings: ThemeSettings) -> Color {
        Color.white.opacity(settings.widgetOpacity)
    }

    /// Resolve text colors from theme preset.
    static func text1(_ settings: ThemeSettings) -> Color {
        settings.resolvedPreset.textPrimary
    }

    static func text2(_ settings: ThemeSettings) -> Color {
        settings.resolvedPreset.textSecondary
    }

    static func text3(_ settings: ThemeSettings) -> Color {
        settings.resolvedPreset.textTertiary
    }

    /// Resolve border color from theme preset.
    static func border(_ settings: ThemeSettings) -> Color {
        settings.resolvedPreset.border
    }

    /// Resolve corner radius from theme settings.
    static func radius(_ settings: ThemeSettings) -> CGFloat {
        CGFloat(settings.widgetCornerRadius)
    }

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
