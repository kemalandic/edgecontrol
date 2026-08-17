import SwiftUI

/// Generic widget config editor — renders UI controls from configSchema automatically.
/// Supports: toggle, picker (with options), stepper, slider, text.
struct WidgetConfigEditor: View {
    let schema: [ConfigSchemaEntry]
    @Binding var config: WidgetConfig
    @EnvironmentObject private var layoutEngine: LayoutEngine

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(schema, id: \.key) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    configRow(entry)
                    if let help = entry.help {
                        Text(help)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func configRow(_ entry: ConfigSchemaEntry) -> some View {
        switch entry.type {
        case .toggle:
            toggleRow(entry)
        case .picker:
            pickerRow(entry)
        case .stepper:
            stepperRow(entry)
        case .slider:
            sliderRow(entry)
        case .text:
            textRow(entry)
        case .time:
            timeRow(entry)
        case .colorPicker:
            EmptyView()
        }
    }

    // MARK: - Toggle

    private func toggleRow(_ entry: ConfigSchemaEntry) -> some View {
        HStack {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { config.bool(entry.key, default: { if case .bool(let v) = entry.defaultValue { return v }; return false }()) },
                set: { config[entry.key] = .bool($0) }
            ))
            .toggleStyle(.switch)
            .tint(accent)
            .labelsHidden()
        }
    }

    // MARK: - Picker

    private func pickerRow(_ entry: ConfigSchemaEntry) -> some View {
        let currentValue = config.string(entry.key, default: { if case .string(let v) = entry.defaultValue { return v }; return "" }())
        let options = entry.options ?? []

        return HStack {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: Binding(
                get: { currentValue },
                set: { config[entry.key] = .string($0) }
            )) {
                ForEach(options, id: \.self) { option in
                    Text(option.capitalized.replacingOccurrences(of: "Daybar", with: "Day Bar").replacingOccurrences(of: "Dotmatrix", with: "Dot Matrix").replacingOccurrences(of: "Cpu", with: "CPU"))
                        .tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(accent)
            .frame(maxWidth: 160)
        }
    }

    // MARK: - Stepper

    private func stepperRow(_ entry: ConfigSchemaEntry) -> some View {
        let currentValue = config.int(entry.key, default: { if case .int(let v) = entry.defaultValue { return v }; return 0 }())

        return HStack {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("\(currentValue)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 40)
            Stepper("", value: Binding(
                get: { currentValue },
                set: { config[entry.key] = .int($0) }
            ), in: Int(entry.minValue ?? 0)...Int(entry.maxValue ?? 100), step: Int(entry.step ?? 1))
            .labelsHidden()
        }
    }

    // MARK: - Slider

    private func sliderRow(_ entry: ConfigSchemaEntry) -> some View {
        let currentValue = config.double(entry.key, default: { if case .double(let v) = entry.defaultValue { return v }; return 0 }())

        return HStack {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(String(format: "%.1f", currentValue))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(accent)
                .frame(width: 40)
            Slider(value: Binding(
                get: { currentValue },
                set: { config[entry.key] = .double($0) }
            ), in: (entry.minValue ?? 0)...(entry.maxValue ?? 100), step: entry.step ?? 1)
            .frame(width: 120)
            .tint(accent)
        }
    }

    // MARK: - Text

    private func textRow(_ entry: ConfigSchemaEntry) -> some View {
        let currentValue = config.string(entry.key, default: { if case .string(let v) = entry.defaultValue { return v }; return "" }())

        return HStack {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            TextField("", text: Binding(
                get: { currentValue },
                set: { config[entry.key] = .string($0) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)

            if entry.key == WidgetLaunch.configKey {
                Button("Browse…") { browseForApp(entry.key) }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
    }

    // MARK: - Time

    /// Time-of-day picker persisting as "HH:mm" — the stored form stays a
    /// plain string, so old configs and the text-field era round-trip.
    private func timeRow(_ entry: ConfigSchemaEntry) -> some View {
        let fallback: String = { if case .string(let v) = entry.defaultValue { return v }; return "18:00" }()
        let currentValue = config.string(entry.key, default: fallback)

        return HStack {
            Text(entry.label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            DatePicker("", selection: Binding(
                get: { Self.date(fromHHmm: currentValue) },
                set: { config[entry.key] = .string(Self.hhmm(from: $0)) }
            ), displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .labelsHidden()
        }
    }

    private static func date(fromHHmm s: String) -> Date {
        let parts = s.split(separator: ":")
        let hour = parts.count == 2 ? Int(parts[0]) ?? 18 : 18
        let minute = parts.count == 2 ? Int(parts[1]) ?? 0 : 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 18, c.minute ?? 0)
    }

    /// App picker for the launcher field, sheet-attached like every other
    /// panel so it cannot pop under the settings window.
    private func browseForApp(_ key: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose Application"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard let win = SettingsWindowController.shared.settingsWindow ?? NSApp.keyWindow else { return }
        panel.beginSheetModal(for: win) { response in
            guard response == .OK, let url = panel.url else { return }
            config[key] = .string(url.path)
        }
    }
}
