import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @State private var launchAtLogin: Bool = false

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("General")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            // Launch at login
            settingsToggle(
                "Launch at Login",
                subtitle: "Start EdgeControl when you log in",
                icon: "power",
                isOn: $launchAtLogin
            )
            .onChange(of: launchAtLogin) { _, newValue in
                var gs = layoutEngine.document.globalSettings
                gs.launchAtLogin = newValue
                layoutEngine.updateGlobalSettings(gs)
                // Update actual login item
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Silently fail — user can manage via System Settings
                }
            }

            // Debug mode
            settingsToggle(
                "Debug Mode",
                subtitle: "Show diagnostic overlays and touch zones",
                icon: "ant",
                isOn: Binding(
                    get: { layoutEngine.document.globalSettings.debugMode },
                    set: { newValue in
                        var gs = layoutEngine.document.globalSettings
                        gs.debugMode = newValue
                        layoutEngine.updateGlobalSettings(gs)
                    }
                )
            )

            Divider().background(Theme.borderSubtle)

            // Layout export/import
            HStack(spacing: 10) {
                Button {
                    exportLayout()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export Layout")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    importLayout()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Layout")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Divider().background(Theme.borderSubtle)

            // About
            VStack(alignment: .leading, spacing: 4) {
                Text("EdgeControl")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Version 0.1.0")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text("ai.pakslab.edgecontrol")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .onAppear {
            launchAtLogin = layoutEngine.document.globalSettings.launchAtLogin
        }
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

    private func exportLayout() {
        let store = LayoutStore()
        guard let data = store.exportData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "EdgeControl-Layout.json"
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard let data = try? Data(contentsOf: url) else { return }
            let store = LayoutStore()
            if let doc = store.importData(data) {
                layoutEngine.document = doc
            }
        }
    }
}
