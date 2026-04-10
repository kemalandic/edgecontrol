import SwiftUI

enum SettingsTab: String, CaseIterable {
    case pages = "Pages"
    case widgets = "Widgets"
    case theme = "Theme"
    case plugins = "Plugins"
    case display = "Display"
    case general = "General"

    var icon: String {
        switch self {
        case .pages: "rectangle.stack"
        case .widgets: "square.grid.2x2"
        case .theme: "paintbrush"
        case .plugins: "puzzlepiece.extension"
        case .display: "display"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var registry: WidgetRegistry
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .pages

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 4) {
                Text("SETTINGS")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(tab.rawValue)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(selectedTab == tab ? .white : Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedTab == tab ? accent.opacity(0.15) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Close button
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Close")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 140)
            .padding(14)
            .background(Color.black.opacity(0.3))

            // Divider
            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(width: 1)

            // Content
            Group {
                switch selectedTab {
                case .pages:
                    PageManagerView()
                case .widgets:
                    WidgetCatalogView()
                case .theme:
                    ThemeSettingsView()
                case .plugins:
                    PluginManagerView()
                case .display:
                    DisplaySettingsView()
                case .general:
                    GeneralSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.backgroundPrimary)
    }
}
