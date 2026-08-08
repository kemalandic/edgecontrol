import SwiftUI

// MARK: - Theme Environment Key

/// Allows widgets to access current ThemeSettings via @Environment(\.themeSettings)
private struct ThemeSettingsKey: EnvironmentKey {
    static let defaultValue = ThemeSettings()
}

extension EnvironmentValues {
    var themeSettings: ThemeSettings {
        get { self[ThemeSettingsKey.self] }
        set { self[ThemeSettingsKey.self] = newValue }
    }
}

extension View {
    func themeSettings(_ settings: ThemeSettings) -> some View {
        environment(\.themeSettings, settings)
    }
}

// MARK: - Unit System Environment Key

/// Lets a widget format a reading without reaching for LayoutEngine. Same shape
/// as the theme above: set once on the dashboard, read wherever a value is drawn.
private struct UnitSystemKey: EnvironmentKey {
    static let defaultValue = UnitSystem.metric
}

extension EnvironmentValues {
    var unitSystem: UnitSystem {
        get { self[UnitSystemKey.self] }
        set { self[UnitSystemKey.self] = newValue }
    }
}

extension View {
    func unitSystem(_ units: UnitSystem) -> some View {
        environment(\.unitSystem, units)
    }
}

// MARK: - Widget Card ViewModifier

/// Applies themed background, corner radius, and border to a widget.
/// Replaces the repeated 4-line boilerplate across all widgets.
struct WidgetCardModifier: ViewModifier {
    @Environment(\.themeSettings) private var ts

    func body(content: Content) -> some View {
        content
            .background(Theme.cardBg(ts), in: RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius(ts), style: .continuous)
                    .strokeBorder(Theme.border(ts), lineWidth: 1)
            )
    }
}

extension View {
    /// Apply themed widget card background + border.
    func widgetCard() -> some View {
        modifier(WidgetCardModifier())
    }
}
