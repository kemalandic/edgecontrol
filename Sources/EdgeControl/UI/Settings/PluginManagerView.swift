import SwiftUI
import UniformTypeIdentifiers

struct PluginManagerView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var registry: WidgetRegistry

    @EnvironmentObject private var layoutEngine: LayoutEngine
    @EnvironmentObject private var pluginManager: PluginManager
    @State private var showInstallPanel = false
    @State private var selectedPluginId: String?

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: plugin list
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Plugins")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        showInstallPanel = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }

                if pluginManager.plugins.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.textTertiary)
                        Text("No plugins installed")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                        Text("Plugins add custom widgets to EdgeControl")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(pluginManager.plugins, id: \.id) { plugin in
                                pluginRow(plugin)
                            }
                        }
                    }
                }

                // Errors
                if !pluginManager.errors.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pluginManager.errors), id: \.key) { key, error in
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.accentOrange)
                                Text("\(key): \(error)")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.accentOrange)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        pluginManager.reload()
                        registry.registerPluginWidgets(pluginManager: pluginManager)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Reload")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(PluginManager.pluginsDirectory)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("Open Folder")
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 240)
            .padding(14)

            Rectangle().fill(Theme.borderSubtle).frame(width: 1)

            // Right: selected plugin detail
            if let pluginId = selectedPluginId,
               let plugin = pluginManager.plugin(for: pluginId) {
                pluginDetail(plugin)
            } else {
                VStack {
                    Spacer()
                    Text("Select a plugin for details")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            pluginManager.discoverAndLoad()
            registry.registerPluginWidgets(pluginManager: pluginManager)
        }
        .onChange(of: showInstallPanel) { _, show in
            if show {
                showInstallPanel = false
                let panel = NSOpenPanel()
                panel.title = "Install Plugin"
                panel.message = "Select a .ecplugin folder or .zip file"
                panel.allowedContentTypes = [.zip, .folder]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = true
                if panel.runModal() == .OK, let url = panel.url {
                    if pluginManager.installPlugin(from: url) {
                        registry.registerPluginWidgets(pluginManager: pluginManager)
                    }
                }
            }
        }
    }

    // MARK: - Plugin Row

    private func pluginRow(_ plugin: LoadedPlugin) -> some View {
        let isSelected = selectedPluginId == plugin.id

        return HStack(spacing: 8) {
            Circle()
                .fill(plugin.isEnabled ? Theme.accentGreen : Theme.textTertiary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(plugin.manifest.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                    .lineLimit(1)
                Text("\(plugin.manifest.widgets.count) widgets")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            Text(plugin.manifest.version)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? accent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedPluginId = plugin.id }
    }

    // MARK: - Plugin Detail

    private func pluginDetail(_ plugin: LoadedPlugin) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plugin.manifest.name)
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("by \(plugin.manifest.author)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { plugin.isEnabled },
                    set: { _ in pluginManager.togglePlugin(id: plugin.id); registry.registerPluginWidgets(pluginManager: pluginManager) }
                ))
                .toggleStyle(.switch)
                .tint(accent)
            }

            // Info
            HStack(spacing: 16) {
                infoTag("Version", value: plugin.manifest.version)
                infoTag("Widgets", value: "\(plugin.manifest.widgets.count)")
                infoTag("ID", value: plugin.manifest.id)
            }

            if let desc = plugin.manifest.description {
                Text(desc)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().background(Theme.borderSubtle)

            // Permissions
            Text("PERMISSIONS")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)

            if plugin.manifest.permissions.isEmpty {
                Text("No permissions required")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(plugin.manifest.permissions, id: \.self) { perm in
                        HStack(spacing: 4) {
                            Image(systemName: perm.iconName)
                                .font(.system(size: 10))
                            Text(perm.displayName)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.accentYellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accentYellow.opacity(0.1), in: Capsule())
                    }
                }
            }

            Divider().background(Theme.borderSubtle)

            // Widgets list
            Text("WIDGETS")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)

            ForEach(plugin.manifest.widgets) { widgetDef in
                HStack(spacing: 8) {
                    Image(systemName: widgetDef.icon ?? "puzzlepiece")
                        .font(.system(size: 14))
                        .foregroundStyle(accent)
                    Text(widgetDef.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(widgetDef.defaultSize[safe: 0] ?? 0)x\(widgetDef.defaultSize[safe: 1] ?? 0)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(8)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Spacer()

            // Remove button
            Button {
                pluginManager.removePlugin(id: plugin.id)
                registry.registerPluginWidgets(pluginManager: pluginManager)
                selectedPluginId = nil
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Remove Plugin")
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accentRed)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accentRed.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func infoTag(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Simple Flow Layout for permission tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
