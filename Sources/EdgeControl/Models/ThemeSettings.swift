import SwiftUI

// MARK: - Theme Settings (stored in layout.json globalSettings)

public struct ThemeSettings: Codable, Hashable, Sendable {
    public var fontScale: Double          // 0.7 - 1.5
    public var fontFamily: FontFamily
    public var fontSizeTitle: Double      // Widget headers
    public var fontSizeValue: Double      // Large displayed values
    public var fontSizeLabel: Double      // Medium labels
    public var fontSizeCaption: Double    // Small labels
    public var fontSizeBody: Double       // Normal text
    public var fontSizeMicro: Double      // Smallest text
    public var accentColor: WidgetColor
    public var widgetOpacity: Double       // 0.0 - 1.0
    public var widgetCornerRadius: Double  // 4 - 20
    public var widgetGap: Double           // 0 - 12
    public var colorScheme: ColorSchemeName
    public var backgroundStyle: BackgroundStyle
    public var widgetColorOverrides: [String: WidgetColors]
    public var customColorScheme: CustomColorScheme?

    /// Resolved preset — uses customColorScheme when colorScheme == .custom
    public var resolvedPreset: ThemePreset {
        if colorScheme == .custom, let custom = customColorScheme {
            return custom.toPreset()
        }
        return colorScheme.preset
    }

    public init(
        fontScale: Double = 1.0,
        fontFamily: FontFamily = .rounded,
        fontSizeTitle: Double = 18,
        fontSizeValue: Double = 28,
        fontSizeLabel: Double = 14,
        fontSizeCaption: Double = 11,
        fontSizeBody: Double = 16,
        fontSizeMicro: Double = 10,
        accentColor: WidgetColor = WidgetColor(ThemeColor.cyan),
        widgetOpacity: Double = 0.04,
        widgetCornerRadius: Double = 10,
        widgetGap: Double = 4,
        colorScheme: ColorSchemeName = .dark,
        backgroundStyle: BackgroundStyle = .gradient,
        widgetColorOverrides: [String: WidgetColors] = [:],
        customColorScheme: CustomColorScheme? = nil
    ) {
        self.fontScale = fontScale
        self.fontFamily = fontFamily
        self.fontSizeTitle = fontSizeTitle
        self.fontSizeValue = fontSizeValue
        self.fontSizeLabel = fontSizeLabel
        self.fontSizeCaption = fontSizeCaption
        self.fontSizeBody = fontSizeBody
        self.fontSizeMicro = fontSizeMicro
        self.accentColor = accentColor
        self.widgetOpacity = widgetOpacity
        self.widgetCornerRadius = widgetCornerRadius
        self.widgetGap = widgetGap
        self.colorScheme = colorScheme
        self.backgroundStyle = backgroundStyle
        self.widgetColorOverrides = widgetColorOverrides
        self.customColorScheme = customColorScheme
    }
}

// MARK: - Font Family

public enum FontFamily: String, Codable, CaseIterable, Sendable {
    case rounded
    case monospaced
    case standard
    case serif

    public var displayName: String {
        switch self {
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        case .standard: "System"
        case .serif: "Serif"
        }
    }

    public var design: Font.Design {
        switch self {
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .standard: .default
        case .serif: .serif
        }
    }
}

// MARK: - Theme Color (accent)

public enum ThemeColor: String, Codable, CaseIterable, Sendable {
    case cyan
    case blue
    case purple
    case green
    case yellow
    case orange
    case red
    case pink
    case white

    public var displayName: String { rawValue.capitalized }

    public var color: Color {
        switch self {
        case .cyan: Color(red: 0.00, green: 0.90, blue: 1.00)
        case .blue: Color(red: 0.20, green: 0.50, blue: 1.00)
        case .purple: Color(red: 0.55, green: 0.30, blue: 1.00)
        case .green: Color(red: 0.20, green: 0.90, blue: 0.50)
        case .yellow: Color(red: 0.96, green: 0.77, blue: 0.09)
        case .orange: Color(red: 1.00, green: 0.42, blue: 0.21)
        case .red: Color(red: 1.00, green: 0.18, blue: 0.18)
        case .pink: Color(red: 1.00, green: 0.30, blue: 0.60)
        case .white: Color.white
        }
    }
}

// MARK: - Color Scheme Presets

public enum ColorSchemeName: String, Codable, CaseIterable, Sendable {
    case dark
    case oledBlack
    case midnightBlue
    case neon
    case arctic
    case ember
    case custom

    public var displayName: String {
        switch self {
        case .dark: "Dark"
        case .oledBlack: "OLED Black"
        case .midnightBlue: "Midnight Blue"
        case .neon: "Neon"
        case .arctic: "Arctic"
        case .ember: "Ember"
        case .custom: "Custom"
        }
    }

    public var preset: ThemePreset {
        switch self {
        case .dark:
            ThemePreset(
                backgroundColors: [
                    Color(red: 0.03, green: 0.03, blue: 0.05),
                    Color(red: 0.05, green: 0.05, blue: 0.08),
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                ],
                cardBackground: Color.white.opacity(0.04),
                textPrimary: Color.white.opacity(0.92),
                textSecondary: Color.white.opacity(0.58),
                textTertiary: Color.white.opacity(0.38),
                border: Color.white.opacity(0.08)
            )
        case .oledBlack:
            ThemePreset(
                backgroundColors: [Color.black, Color.black, Color.black],
                cardBackground: Color.white.opacity(0.03),
                textPrimary: Color.white.opacity(0.90),
                textSecondary: Color.white.opacity(0.50),
                textTertiary: Color.white.opacity(0.30),
                border: Color.white.opacity(0.06)
            )
        case .midnightBlue:
            ThemePreset(
                backgroundColors: [
                    Color(red: 0.02, green: 0.03, blue: 0.10),
                    Color(red: 0.04, green: 0.05, blue: 0.14),
                    Color(red: 0.02, green: 0.04, blue: 0.12)
                ],
                cardBackground: Color(red: 0.10, green: 0.12, blue: 0.22).opacity(0.5),
                textPrimary: Color.white.opacity(0.90),
                textSecondary: Color(red: 0.60, green: 0.65, blue: 0.85),
                textTertiary: Color(red: 0.40, green: 0.45, blue: 0.65),
                border: Color(red: 0.20, green: 0.25, blue: 0.45).opacity(0.3)
            )
        case .neon:
            ThemePreset(
                backgroundColors: [
                    Color(red: 0.02, green: 0.01, blue: 0.05),
                    Color(red: 0.04, green: 0.02, blue: 0.08),
                    Color(red: 0.02, green: 0.01, blue: 0.06)
                ],
                cardBackground: Color(red: 0.00, green: 0.90, blue: 1.00).opacity(0.04),
                textPrimary: Color.white,
                textSecondary: Color(red: 0.00, green: 0.90, blue: 1.00).opacity(0.7),
                textTertiary: Color(red: 0.55, green: 0.30, blue: 1.00).opacity(0.5),
                border: Color(red: 0.00, green: 0.90, blue: 1.00).opacity(0.15)
            )
        case .arctic:
            ThemePreset(
                backgroundColors: [
                    Color(red: 0.06, green: 0.08, blue: 0.12),
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.06, green: 0.09, blue: 0.14)
                ],
                cardBackground: Color(red: 0.70, green: 0.85, blue: 1.00).opacity(0.05),
                textPrimary: Color.white.opacity(0.95),
                textSecondary: Color(red: 0.70, green: 0.85, blue: 1.00).opacity(0.6),
                textTertiary: Color(red: 0.50, green: 0.65, blue: 0.80).opacity(0.4),
                border: Color(red: 0.70, green: 0.85, blue: 1.00).opacity(0.10)
            )
        case .ember:
            ThemePreset(
                backgroundColors: [
                    Color(red: 0.06, green: 0.02, blue: 0.02),
                    Color(red: 0.10, green: 0.03, blue: 0.03),
                    Color(red: 0.07, green: 0.02, blue: 0.02)
                ],
                cardBackground: Color(red: 1.00, green: 0.30, blue: 0.10).opacity(0.05),
                textPrimary: Color.white.opacity(0.92),
                textSecondary: Color(red: 1.00, green: 0.70, blue: 0.45),
                textTertiary: Color(red: 1.00, green: 0.55, blue: 0.35).opacity(0.7),
                border: Color(red: 1.00, green: 0.30, blue: 0.10).opacity(0.15)
            )
        case .custom:
            // Fallback for custom — actual colors come from ThemeSettings.customColorScheme
            ThemePreset(
                backgroundColors: [Color.black, Color.black, Color.black],
                cardBackground: Color.white.opacity(0.04),
                textPrimary: Color.white.opacity(0.92),
                textSecondary: Color.white.opacity(0.58),
                textTertiary: Color.white.opacity(0.38),
                border: Color.white.opacity(0.08)
            )
        }
    }
}

// MARK: - Custom Color Scheme

public struct CustomColorScheme: Codable, Hashable, Sendable {
    public var background1: WidgetColor
    public var background2: WidgetColor
    public var background3: WidgetColor
    public var cardBackground: WidgetColor
    public var textPrimary: WidgetColor
    public var textSecondary: WidgetColor
    public var textTertiary: WidgetColor
    public var border: WidgetColor

    public init(
        background1: WidgetColor = WidgetColor(red: 0.03, green: 0.03, blue: 0.05),
        background2: WidgetColor = WidgetColor(red: 0.05, green: 0.05, blue: 0.08),
        background3: WidgetColor = WidgetColor(red: 0.03, green: 0.04, blue: 0.06),
        cardBackground: WidgetColor = WidgetColor(red: 1.0, green: 1.0, blue: 1.0),
        textPrimary: WidgetColor = WidgetColor(red: 1.0, green: 1.0, blue: 1.0),
        textSecondary: WidgetColor = WidgetColor(red: 0.6, green: 0.6, blue: 0.6),
        textTertiary: WidgetColor = WidgetColor(red: 0.4, green: 0.4, blue: 0.4),
        border: WidgetColor = WidgetColor(red: 0.3, green: 0.3, blue: 0.3)
    ) {
        self.background1 = background1
        self.background2 = background2
        self.background3 = background3
        self.cardBackground = cardBackground
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.border = border
    }

    public func toPreset() -> ThemePreset {
        ThemePreset(
            backgroundColors: [background1.color, background2.color, background3.color],
            cardBackground: cardBackground.color,
            textPrimary: textPrimary.color,
            textSecondary: textSecondary.color,
            textTertiary: textTertiary.color,
            border: border.color
        )
    }
}

// MARK: - Theme Preset (resolved colors)

public struct ThemePreset: Sendable {
    public let backgroundColors: [Color]
    public let cardBackground: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let border: Color
}

// MARK: - Background Style

public enum BackgroundStyle: String, Codable, CaseIterable, Sendable {
    case gradient
    case solid
    case transparent

    public var displayName: String {
        switch self {
        case .gradient: "Gradient"
        case .solid: "Solid"
        case .transparent: "Transparent"
        }
    }
}

// MARK: - Predefined Full Themes

public enum PredefinedTheme: String, CaseIterable {
    case defaultDark = "Default Dark"
    case oledBlack = "OLED Black"
    case midnightBlue = "Midnight Blue"
    case neonCyan = "Neon Cyan"
    case neonPurple = "Neon Purple"
    case arctic = "Arctic"
    case ember = "Ember"
    case terminal = "Terminal"

    public var settings: ThemeSettings {
        switch self {
        case .defaultDark:
            ThemeSettings()
        case .oledBlack:
            ThemeSettings(accentColor: WidgetColor(ThemeColor.white), widgetOpacity: 0.02, colorScheme: .oledBlack)
        case .midnightBlue:
            ThemeSettings(accentColor: WidgetColor(ThemeColor.blue), widgetOpacity: 0.06, colorScheme: .midnightBlue)
        case .neonCyan:
            ThemeSettings(accentColor: WidgetColor(ThemeColor.cyan), widgetOpacity: 0.04, colorScheme: .neon)
        case .neonPurple:
            ThemeSettings(accentColor: WidgetColor(ThemeColor.purple), widgetOpacity: 0.04, colorScheme: .neon)
        case .arctic:
            ThemeSettings(accentColor: WidgetColor(ThemeColor.cyan), widgetOpacity: 0.05, colorScheme: .arctic)
        case .ember:
            ThemeSettings(accentColor: WidgetColor(ThemeColor.orange), widgetOpacity: 0.05, widgetCornerRadius: 8, colorScheme: .ember)
        case .terminal:
            ThemeSettings(fontFamily: .monospaced, accentColor: WidgetColor(ThemeColor.green), widgetOpacity: 0.03, widgetCornerRadius: 4, colorScheme: .oledBlack)
        }
    }
}
