import SwiftUI

struct DisplaySettingsView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var model: AppModel

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Display")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            // Target display picker
            VStack(alignment: .leading, spacing: 8) {
                Text("TARGET DISPLAY")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)

                ForEach(model.availableDisplays) { display in
                    let isSelected = model.selectedDisplay?.name == display.name
                    Button {
                        var gs = layoutEngine.document.globalSettings
                        gs.selectedDisplayName = display.name
                        layoutEngine.updateGlobalSettings(gs)
                        model.selectedDisplayName = display.name
                        model.refreshDisplays()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: display.isXenonEdge ? "rectangle.split.1x2" : "display")
                                .font(.system(size: 16))
                                .foregroundStyle(isSelected ? accent : Theme.textTertiary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(display.name)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                                Text(display.summary)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(accent)
                            }
                        }
                        .padding(10)
                        .background(
                            isSelected ? accent.opacity(0.08) : Color.white.opacity(0.03),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isSelected ? accent.opacity(0.3) : Theme.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().background(Theme.borderSubtle)

            // Kiosk mode toggle
            settingsToggle(
                "Kiosk Mode",
                subtitle: "Borderless fullscreen on target display",
                icon: "rectangle.dashed",
                isOn: Binding(
                    get: { layoutEngine.document.globalSettings.kioskMode },
                    set: { newValue in
                        var gs = layoutEngine.document.globalSettings
                        gs.kioskMode = newValue
                        layoutEngine.updateGlobalSettings(gs)
                    }
                )
            )

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func settingsToggle(_ title: String, subtitle: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .tint(accent)
        }
        .padding(10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
