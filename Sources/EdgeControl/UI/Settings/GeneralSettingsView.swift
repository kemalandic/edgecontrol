import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @State private var launchAtLogin: Bool = false

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    /// Read from the bundle rather than typed in here. project.yml is the one
    /// place the numbers live, and this line had sat at 0.1.0 through three
    /// releases because nothing tied it to them.
    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
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

            // Hide from Dock
            settingsToggle(
                "Hide from Dock",
                subtitle: "Menu bar only — no Dock icon, no Cmd-Tab entry",
                icon: "menubar.arrow.up.rectangle",
                isOn: Binding(
                    get: { layoutEngine.document.globalSettings.hideFromDock },
                    set: { newValue in
                        var gs = layoutEngine.document.globalSettings
                        gs.hideFromDock = newValue
                        layoutEngine.updateGlobalSettings(gs)
                        // Applied at once: asking for a relaunch to see a
                        // toggle take effect is a poor trade.
                        EdgeControlAppDelegate.applyActivationPolicy(
                            hideFromDock: newValue,
                            mainMenu: EdgeControlAppDelegate.defaultMainMenu()
                        )
                    }
                )
            )

            // Units
            HStack(spacing: 10) {
                Image(systemName: "ruler")
                    .font(.system(size: 16))
                    .foregroundStyle(accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Units")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(layoutEngine.document.globalSettings.units.detail)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

                Picker("", selection: Binding(
                    get: { layoutEngine.document.globalSettings.units },
                    set: { newValue in
                        var gs = layoutEngine.document.globalSettings
                        gs.units = newValue
                        layoutEngine.updateGlobalSettings(gs)
                    }
                )) {
                    ForEach(UnitSystem.allCases, id: \.self) { system in
                        Text(system.displayName).tag(system)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
            }
            .padding(10)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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
                Text(Self.versionText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(Bundle.main.bundleIdentifier ?? "ai.pakslab.edgecontrol")
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
        guard let data = store.exportData(layoutEngine.document) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "EdgeControl-Layout.json"
        panel.allowedContentTypes = [.json]
        guard let win = SettingsWindowController.shared.settingsWindow ?? NSApp.keyWindow else { return }
        panel.beginSheetModal(for: win) { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard let win = SettingsWindowController.shared.settingsWindow ?? NSApp.keyWindow else { return }
        panel.beginSheetModal(for: win) { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            let store = LayoutStore()
            if let doc = store.importData(data) {
                layoutEngine.document = doc
            }
        }
    }
}
