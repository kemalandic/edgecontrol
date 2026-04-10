import Foundation

/// Manages plugin discovery, loading, lifecycle, and state persistence.
/// Scans ~/Library/Application Support/EdgeControl/Plugins/ for .ecplugin bundles.
@MainActor
public final class PluginManager: ObservableObject {
    @Published public private(set) var plugins: [LoadedPlugin] = []
    @Published public private(set) var errors: [String: String] = [:] // pluginId → error

    public static let pluginsDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("EdgeControl/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let stateURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("EdgeControl/plugin_state.json")
    }()

    private var savedState: PluginSavedState

    public init() {
        self.savedState = Self.loadState()
    }

    // MARK: - Discovery & Loading

    /// Scan plugins directory and load all valid .ecplugin bundles.
    public func discoverAndLoad() {
        plugins.removeAll()
        errors.removeAll()

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: Self.pluginsDirectory, includingPropertiesForKeys: nil) else { return }

        for url in contents where url.pathExtension == "ecplugin" {
            loadPlugin(at: url)
        }
    }

    /// Load a single plugin from a bundle path.
    public func loadPlugin(at bundlePath: URL) {
        let manifestURL = bundlePath.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            errors[bundlePath.lastPathComponent] = "Missing manifest.json"
            return
        }

        guard let data = try? Data(contentsOf: manifestURL) else {
            errors[bundlePath.lastPathComponent] = "Cannot read manifest.json"
            return
        }

        let manifest: PluginManifest
        do {
            manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        } catch {
            errors[bundlePath.lastPathComponent] = "Invalid manifest: \(error.localizedDescription)"
            return
        }

        // Validate widgets have HTML files
        for widgetDef in manifest.widgets {
            let htmlURL = bundlePath.appendingPathComponent(widgetDef.htmlFile)
            if !FileManager.default.fileExists(atPath: htmlURL.path) {
                errors[manifest.id] = "Missing widget HTML: \(widgetDef.htmlFile)"
                return
            }
        }

        // Check for duplicate plugin IDs
        if plugins.contains(where: { $0.manifest.id == manifest.id }) {
            errors[manifest.id] = "Duplicate plugin ID"
            return
        }

        let isEnabled = savedState.enabledPlugins[manifest.id] ?? true
        let loaded = LoadedPlugin(manifest: manifest, bundlePath: bundlePath, isEnabled: isEnabled)
        plugins.append(loaded)
    }

    // MARK: - Plugin Lifecycle

    public func enablePlugin(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].isEnabled = true
        savedState.enabledPlugins[id] = true
        saveState()
    }

    public func disablePlugin(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].isEnabled = false
        savedState.enabledPlugins[id] = false
        saveState()
    }

    public func togglePlugin(id: String) {
        guard let plugin = plugins.first(where: { $0.id == id }) else { return }
        if plugin.isEnabled { disablePlugin(id: id) } else { enablePlugin(id: id) }
    }

    /// Remove a plugin bundle from disk.
    public func removePlugin(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        let plugin = plugins[index]
        try? FileManager.default.removeItem(at: plugin.bundlePath)
        plugins.remove(at: index)
        savedState.enabledPlugins.removeValue(forKey: id)
        saveState()
    }

    /// Install a plugin from a URL — supports both .ecplugin directories and .zip files.
    public func installPlugin(from sourceURL: URL) -> Bool {
        if sourceURL.pathExtension == "zip" {
            return installFromZip(sourceURL)
        } else if sourceURL.pathExtension == "ecplugin" {
            return installFromDirectory(sourceURL)
        } else {
            // Try as directory anyway
            return installFromDirectory(sourceURL)
        }
    }

    private func installFromDirectory(_ sourceURL: URL) -> Bool {
        let destURL = Self.pluginsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            loadPlugin(at: destURL)
            return true
        } catch {
            errors["install"] = "Install failed: \(error.localizedDescription)"
            return false
        }
    }

    private func installFromZip(_ zipURL: URL) -> Bool {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            // Unzip using ditto (built-in macOS)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-xk", zipURL.path, tempDir.path]
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                errors["install"] = "Failed to extract zip file"
                return false
            }

            // Find .ecplugin directory in extracted contents
            let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let pluginDir = contents.first(where: { $0.pathExtension == "ecplugin" }) else {
                // Maybe the zip contains the plugin contents directly (no wrapper dir)
                // Check if manifest.json exists in tempDir
                let directManifest = tempDir.appendingPathComponent("manifest.json")
                if FileManager.default.fileExists(atPath: directManifest.path) {
                    // Wrap in .ecplugin directory
                    let name = zipURL.deletingPathExtension().lastPathComponent
                    let wrappedDir = tempDir.appendingPathComponent("\(name).ecplugin")
                    try FileManager.default.moveItem(at: tempDir, to: wrappedDir)
                    return installFromDirectory(wrappedDir)
                }
                errors["install"] = "No .ecplugin bundle found in zip"
                return false
            }

            return installFromDirectory(pluginDir)
        } catch {
            errors["install"] = "Install failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Reload all plugins (hot reload).
    public func reload() {
        discoverAndLoad()
    }

    // MARK: - Queries

    public var enabledPlugins: [LoadedPlugin] {
        plugins.filter(\.isEnabled)
    }

    public func plugin(for id: String) -> LoadedPlugin? {
        plugins.first { $0.id == id }
    }

    /// Get all widget definitions from enabled plugins.
    public func allWidgetDefs() -> [(LoadedPlugin, PluginWidgetDef)] {
        enabledPlugins.flatMap { plugin in
            plugin.manifest.widgets.map { (plugin, $0) }
        }
    }

    /// Get HTML file URL for a plugin widget.
    public func htmlURL(pluginId: String, widgetHtmlFile: String) -> URL? {
        guard let plugin = plugin(for: pluginId) else { return nil }
        let url = plugin.bundlePath.appendingPathComponent(widgetHtmlFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Check if a plugin has a specific permission.
    public func hasPermission(_ permission: PluginPermission, pluginId: String) -> Bool {
        guard let plugin = plugin(for: pluginId) else { return false }
        return plugin.manifest.permissions.contains(permission)
    }

    // MARK: - State Persistence

    private struct PluginSavedState: Codable {
        var enabledPlugins: [String: Bool] = [:]
    }

    private static func loadState() -> PluginSavedState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PluginSavedState.self, from: data) else {
            return PluginSavedState()
        }
        return state
    }

    private func saveState() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(savedState) else { return }
        try? data.write(to: Self.stateURL, options: .atomic)
    }
}
