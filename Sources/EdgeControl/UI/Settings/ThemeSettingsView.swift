import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry

    private var theme: ThemeSettings {
        layoutEngine.document.globalSettings.theme
    }

    private var accent: Color {
        theme.accentColor.color
    }

    private func update(_ block: (inout ThemeSettings) -> Void) {
        var gs = layoutEngine.document.globalSettings
        block(&gs.theme)
        layoutEngine.updateGlobalSettings(gs)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Theme")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                // MARK: - Presets
                VStack(alignment: .leading, spacing: 8) {
                    Text("PRESETS")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(PredefinedTheme.allCases, id: \.self) { preset in
                            presetCard(preset)
                        }
                    }
                }

                Divider().background(Theme.borderSubtle)

                // MARK: - Font
                VStack(alignment: .leading, spacing: 10) {
                    Text("FONT")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    // Font family
                    HStack {
                        Text("Family")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { theme.fontFamily },
                            set: { val in update { $0.fontFamily = val } }
                        )) {
                            ForEach(FontFamily.allCases, id: \.self) { family in
                                Text(family.displayName).tag(family)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 300)
                    }

                    // Font scale
                    HStack {
                        Text("Size")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.0f%%", theme.fontScale * 100))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                            .frame(width: 50)
                        Slider(value: Binding(
                            get: { theme.fontScale },
                            set: { val in update { $0.fontScale = val } }
                        ), in: 0.7...1.5, step: 0.05)
                        .frame(width: 200)
                        .tint(accent)
                    }

                    // Font level sizes
                    DisclosureGroup {
                        fontSizeSlider("Title", keyPath: \.fontSizeTitle, range: 12...28, default: 18)
                        fontSizeSlider("Value", keyPath: \.fontSizeValue, range: 18...42, default: 28)
                        fontSizeSlider("Label", keyPath: \.fontSizeLabel, range: 10...22, default: 14)
                        fontSizeSlider("Caption", keyPath: \.fontSizeCaption, range: 8...16, default: 11)
                        fontSizeSlider("Body", keyPath: \.fontSizeBody, range: 12...24, default: 16)
                        fontSizeSlider("Micro", keyPath: \.fontSizeMicro, range: 7...14, default: 10)
                    } label: {
                        Text("FONT LEVELS")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .tint(accent)

                    // Preview
                    HStack(spacing: 12) {
                        Text("Aa")
                            .font(.system(size: theme.fontSizeValue * theme.fontScale, weight: .bold, design: theme.fontFamily.design))
                            .foregroundStyle(.white)
                        Text("The quick brown fox")
                            .font(.system(size: theme.fontSizeBody * theme.fontScale, weight: .medium, design: theme.fontFamily.design))
                            .foregroundStyle(Theme.textSecondary)
                        Text("123.4%")
                            .font(.system(size: theme.fontSizeLabel * theme.fontScale, weight: .bold, design: theme.fontFamily.design))
                            .foregroundStyle(accent)
                            .monospacedDigit()
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Divider().background(Theme.borderSubtle)

                // MARK: - Accent Color
                VStack(alignment: .leading, spacing: 10) {
                    Text("ACCENT COLOR")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    HStack(spacing: 8) {
                        ForEach(ThemeColor.allCases, id: \.self) { color in
                            Button {
                                update { $0.accentColor = WidgetColor(color) }
                            } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 28, height: 28)
                                    .overlay {
                                        if theme.accentColor == WidgetColor(color) {
                                            Circle().strokeBorder(.white, lineWidth: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }

                        // Custom color picker
                        AccentColorPicker(current: theme.accentColor) { newColor in
                            update { $0.accentColor = newColor }
                        }
                    }
                }

                Divider().background(Theme.borderSubtle)

                // MARK: - Color Scheme
                VStack(alignment: .leading, spacing: 10) {
                    Text("COLOR SCHEME")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    HStack(spacing: 6) {
                        ForEach(ColorSchemeName.allCases, id: \.self) { scheme in
                            Button {
                                update {
                                    $0.colorScheme = scheme
                                    if scheme == .custom && $0.customColorScheme == nil {
                                        $0.customColorScheme = CustomColorScheme()
                                    }
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(scheme == .custom
                                            ? LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : LinearGradient(colors: scheme.preset.backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                        .frame(height: 30)
                                        .overlay {
                                            if scheme == .custom {
                                                Image(systemName: "paintbrush")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(.white.opacity(0.5))
                                            }
                                        }
                                        .overlay {
                                            if theme.colorScheme == scheme {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .strokeBorder(accent, lineWidth: 2)
                                            }
                                        }
                                    Text(scheme.displayName)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(theme.colorScheme == scheme ? .white : Theme.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Custom scheme color editors
                    if theme.colorScheme == .custom {
                        customSchemeEditors()
                    }
                }

                Divider().background(Theme.borderSubtle)

                // MARK: - Widget Appearance
                VStack(alignment: .leading, spacing: 10) {
                    Text("WIDGET APPEARANCE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    // Widget opacity
                    HStack {
                        Text("Background Opacity")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.0f%%", theme.widgetOpacity * 100))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                            .frame(width: 50)
                        Slider(value: Binding(
                            get: { theme.widgetOpacity },
                            set: { val in update { $0.widgetOpacity = val } }
                        ), in: 0...0.2, step: 0.01)
                        .frame(width: 200)
                        .tint(accent)
                    }

                    // Corner radius
                    HStack {
                        Text("Corner Radius")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.0f", theme.widgetCornerRadius))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                            .frame(width: 50)
                        Slider(value: Binding(
                            get: { theme.widgetCornerRadius },
                            set: { val in update { $0.widgetCornerRadius = val } }
                        ), in: 0...20, step: 1)
                        .frame(width: 200)
                        .tint(accent)
                    }

                    // Widget gap
                    HStack {
                        Text("Widget Gap")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "%.0f", theme.widgetGap))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                            .frame(width: 50)
                        Slider(value: Binding(
                            get: { theme.widgetGap },
                            set: { val in update { $0.widgetGap = val } }
                        ), in: 0...12, step: 1)
                        .frame(width: 200)
                        .tint(accent)
                    }
                }

                Divider().background(Theme.borderSubtle)

                // MARK: - Widget Colors
                VStack(alignment: .leading, spacing: 10) {
                    Text("WIDGET COLORS")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)

                    ForEach(WidgetCategory.allCases.filter { $0 != .plugin }, id: \.self) { category in
                        let widgets = registry.widgets(in: category)
                        if !widgets.isEmpty {
                            widgetColorCategory(category: category, widgets: widgets)
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(16)
        }
    }

    // MARK: - Widget Color Helpers

    @ViewBuilder
    private func widgetColorCategory(category: WidgetCategory, widgets: [any DashboardWidget]) -> some View {
        DisclosureGroup {
            ForEach(widgets.map(\.widgetId), id: \.self) { widgetId in
                if let widget = registry.widget(for: widgetId) {
                    widgetColorRow(widget: widget)
                }
            }
        } label: {
            Text(category.displayName.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .tint(accent)
    }

    private func widgetColorRow(widget: any DashboardWidget) -> some View {
        let hasOverride = theme.widgetColorOverrides[widget.widgetId] != nil
        let colors = theme.widgetColorOverrides[widget.widgetId] ?? widget.defaultColors

        return HStack(spacing: 10) {
            Image(systemName: widget.iconName)
                .font(.system(size: 14))
                .foregroundStyle(hasOverride ? .white : Theme.textTertiary)
                .frame(width: 20)

            Text(widget.displayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(hasOverride ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Primary color circle
            colorCircle(
                currentColor: colors.primary,
                label: "P",
                isDefault: !hasOverride
            ) { newColor in
                var current = theme.widgetColorOverrides[widget.widgetId] ?? widget.defaultColors
                current.primary = newColor
                update { $0.widgetColorOverrides[widget.widgetId] = current }
            }

            // Secondary color circle
            if let sec = widget.defaultColors.secondary {
                colorCircle(
                    currentColor: colors.secondary ?? sec,
                    label: "S",
                    isDefault: !hasOverride
                ) { newColor in
                    var current = theme.widgetColorOverrides[widget.widgetId] ?? widget.defaultColors
                    current.secondary = newColor
                    update { $0.widgetColorOverrides[widget.widgetId] = current }
                }
            }

            // Tertiary color circle
            if let ter = widget.defaultColors.tertiary {
                colorCircle(
                    currentColor: colors.tertiary ?? ter,
                    label: "T",
                    isDefault: !hasOverride
                ) { newColor in
                    var current = theme.widgetColorOverrides[widget.widgetId] ?? widget.defaultColors
                    current.tertiary = newColor
                    update { $0.widgetColorOverrides[widget.widgetId] = current }
                }
            }

            // Reset button
            if hasOverride {
                Button {
                    update { $0.widgetColorOverrides.removeValue(forKey: widget.widgetId) }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            hasOverride ? accent.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    // MARK: - Font Size Slider

    private func fontSizeSlider(_ label: String, keyPath: WritableKeyPath<ThemeSettings, Double>, range: ClosedRange<Double>, default defaultVal: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(String(format: "%.0f", theme[keyPath: keyPath]))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 30)
            Slider(value: Binding(
                get: { theme[keyPath: keyPath] },
                set: { val in update { $0[keyPath: keyPath] = val } }
            ), in: range, step: 1)
            .frame(width: 140)
            .tint(accent)
            Button {
                update { $0[keyPath: keyPath] = defaultVal }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Custom Scheme Editors

    @ViewBuilder
    private func customSchemeEditors() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            schemeColorRow("Background 1", keyPath: \.background1)
            schemeColorRow("Background 2", keyPath: \.background2)
            schemeColorRow("Background 3", keyPath: \.background3)
            schemeColorRow("Card Background", keyPath: \.cardBackground)
            schemeColorRow("Text Primary", keyPath: \.textPrimary)
            schemeColorRow("Text Secondary", keyPath: \.textSecondary)
            schemeColorRow("Text Tertiary", keyPath: \.textTertiary)
            schemeColorRow("Border", keyPath: \.border)
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func schemeColorRow(_ label: String, keyPath: WritableKeyPath<CustomColorScheme, WidgetColor>) -> some View {
        let current = theme.customColorScheme?[keyPath: keyPath] ?? CustomColorScheme()[keyPath: keyPath]
        return SchemeColorRow(label: label, current: current) { newColor in
            var scheme = theme.customColorScheme ?? CustomColorScheme()
            scheme[keyPath: keyPath] = newColor
            update { $0.customColorScheme = scheme }
        }
    }

    private func colorCircle(currentColor: WidgetColor, label: String, isDefault: Bool, onChange: @escaping (WidgetColor) -> Void) -> some View {
        WidgetColorCircle(currentColor: currentColor, label: label, isDefault: isDefault, onChange: onChange)
    }

    // MARK: - Preset Card

    private func presetCard(_ preset: PredefinedTheme) -> some View {
        let isActive = theme == preset.settings
        return Button {
            var gs = layoutEngine.document.globalSettings
            gs.theme = preset.settings
            layoutEngine.updateGlobalSettings(gs)
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: preset.settings.colorScheme.preset.backgroundColors,
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(height: 36)
                    .overlay {
                        Circle()
                            .fill(preset.settings.accentColor.color)
                            .frame(width: 12, height: 12)
                    }
                    .overlay {
                        if isActive {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(accent, lineWidth: 2)
                        }
                    }
                Text(preset.rawValue)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .white : Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Widget Color Circle (native ColorPicker)

private struct WidgetColorCircle: View {
    let currentColor: WidgetColor
    let label: String
    let isDefault: Bool
    let onChange: (WidgetColor) -> Void

    @State private var pickerColor: Color = .white

    var body: some View {
        VStack(spacing: 2) {
            ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 22, height: 22)
                .opacity(isDefault ? 0.6 : 1.0)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .onAppear {
            pickerColor = currentColor.color
        }
        .onChange(of: pickerColor) { _, newColor in
            let nsColor = NSColor(newColor)
            let wc = WidgetColor(nsColor)
            onChange(wc)
        }
    }
}

// MARK: - Accent Color Picker (native ColorPicker for custom accent)

private struct AccentColorPicker: View {
    let current: WidgetColor
    let onChange: (WidgetColor) -> Void

    @State private var pickerColor: Color = .white

    var body: some View {
        ColorPicker("", selection: $pickerColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28, height: 28)
            .onAppear {
                pickerColor = current.color
            }
            .onChange(of: pickerColor) { _, newColor in
                let nsColor = NSColor(newColor)
                let wc = WidgetColor(nsColor)
                onChange(wc)
            }
    }
}

// MARK: - Scheme Color Row (label + native ColorPicker)

private struct SchemeColorRow: View {
    let label: String
    let current: WidgetColor
    let onChange: (WidgetColor) -> Void

    @State private var pickerColor: Color = .white

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            ColorPicker("", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 28, height: 28)
        }
        .onAppear {
            pickerColor = current.color
        }
        .onChange(of: pickerColor) { _, newColor in
            let nsColor = NSColor(newColor)
            onChange(WidgetColor(nsColor))
        }
    }
}
