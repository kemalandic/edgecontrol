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
