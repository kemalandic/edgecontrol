import Foundation
import Testing
@testable import EdgeControl

@Suite("Theme settings")
struct ThemeSettingsTests {

    /// The defaults are a product decision — 14pt labels and 28pt values are the
    /// readability floor the project holds itself to. Pinning them means a
    /// change has to be deliberate.
    @Test("defaults match the documented readability floor")
    func defaultsAreStable() {
        let t = ThemeSettings()
        #expect(t.fontScale == 1.0)
        #expect(t.fontSizeTitle == 18)
        #expect(t.fontSizeValue == 28)
        #expect(t.fontSizeLabel == 14)
        #expect(t.fontSizeCaption == 11)
        #expect(t.fontSizeBody == 16)
        #expect(t.fontSizeMicro == 10)
        #expect(t.widgetOpacity == 0.04)
        #expect(t.widgetCornerRadius == 10)
        #expect(t.widgetGap == 4)
        #expect(t.fontFamily == .rounded)
        #expect(t.colorScheme == .dark)
        #expect(t.backgroundStyle == .gradient)
        #expect(t.widgetColorOverrides.isEmpty)
        #expect(t.customColorScheme == nil)
    }

    @Test("a round trip through JSON preserves every field")
    func codableRoundTrip() throws {
        var original = ThemeSettings(
            fontScale: 1.25,
            fontFamily: .monospaced,
            fontSizeTitle: 22,
            fontSizeValue: 34,
            widgetOpacity: 0.2,
            widgetCornerRadius: 16,
            widgetGap: 8,
            colorScheme: .neon,
            backgroundStyle: .solid
        )
        original.widgetColorOverrides["cpu-gauge"] = WidgetColors(primary: .green, secondary: .yellow)

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ThemeSettings.self, from: data)

        #expect(restored == original)
        #expect(restored.widgetColorOverrides["cpu-gauge"]?.secondary != nil)
    }

    /// Every scheme must resolve to a preset. A new case added without one would
    /// otherwise surface as a blank dashboard rather than a compile error.
    @Test("every colour scheme resolves to a preset", arguments: ColorSchemeName.allCases)
    func everySchemeResolves(scheme: ColorSchemeName) {
        var t = ThemeSettings()
        t.colorScheme = scheme
        _ = t.resolvedPreset  // must not trap
        #expect(t.resolvedPreset.backgroundColors.isEmpty == false)
    }

    /// Selecting "custom" without ever defining one is reachable through the
    /// settings UI; it must fall back rather than produce an empty theme.
    @Test("custom without a custom scheme falls back to the built-in preset")
    func customWithoutDefinitionFallsBack() {
        var t = ThemeSettings()
        t.colorScheme = .custom
        t.customColorScheme = nil
        #expect(t.resolvedPreset.backgroundColors.isEmpty == false)
    }

    @Test("a widget override is scoped to that widget alone")
    func overridesAreScoped() {
        var t = ThemeSettings()
        t.widgetColorOverrides["memory-gauge"] = WidgetColors(primary: .red)
        #expect(t.widgetColorOverrides["memory-gauge"] != nil)
        #expect(t.widgetColorOverrides["cpu-gauge"] == nil)
    }
}
