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

        // Validate plugin ID is safe for filesystem use (no path traversal)
        let isValidId = manifest.id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
        guard isValidId, !manifest.id.isEmpty else {
            errors[bundlePath.lastPathComponent] = "Invalid plugin ID: must contain only letters, numbers, dots, hyphens, underscores"
            return
        }

        // Validate widgets have HTML files (with path traversal check)
        let bundleStd = bundlePath.standardizedFileURL.path
        for widgetDef in manifest.widgets {
            let htmlURL = bundlePath.appendingPathComponent(widgetDef.htmlFile).standardizedFileURL
            guard htmlURL.path.hasPrefix(bundleStd) else {
                errors[manifest.id] = "Invalid widget HTML path: \(widgetDef.htmlFile)"
                return
            }
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

    /// Remove a plugin bundle from disk and clean up its storage.
    public func removePlugin(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        let plugin = plugins[index]
        try? FileManager.default.removeItem(at: plugin.bundlePath)
        PluginStorageService.shared.removeAll(pluginId: id)
        plugins.remove(at: index)
        savedState.enabledPlugins.removeValue(forKey: id)
        saveState()
    }

    /// Install a plugin from a local URL — supports both .ecplugin directories and .zip files.
    /// For zip files, extraction runs in the background to avoid blocking the main thread.
    /// Important: `sourceURL` must be a trusted local file path (e.g., from NSOpenPanel).
    public func installPlugin(from sourceURL: URL, completion: (@Sendable (Bool) -> Void)? = nil) {
        if sourceURL.pathExtension == "zip" {
            installFromZip(sourceURL, completion: completion ?? { _ in })
        } else {
            let result = installFromDirectory(sourceURL)
            completion?(result)
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

    private func installFromZip(_ zipURL: URL, completion: @escaping @Sendable (Bool) -> Void) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            errors["install"] = "Install failed: \(error.localizedDescription)"
            completion(false)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, tempDir.path]
        process.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                guard let self else { return }
                defer { try? FileManager.default.removeItem(at: tempDir) }

                guard proc.terminationStatus == 0 else {
                    self.errors["install"] = "Failed to extract zip file"
                    completion(false)
                    return
                }

                guard let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else {
                    self.errors["install"] = "Failed to read extracted contents"
                    completion(false)
                    return
                }

                if let pluginDir = contents.first(where: { $0.pathExtension == "ecplugin" }) {
                    completion(self.installFromDirectory(pluginDir))
                } else {
                    let directManifest = tempDir.appendingPathComponent("manifest.json")
                    if FileManager.default.fileExists(atPath: directManifest.path) {
                        let name = zipURL.deletingPathExtension().lastPathComponent
                        let wrapperParent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                        let wrappedDir = wrapperParent.appendingPathComponent("\(name).ecplugin")
                        do {
                            try FileManager.default.createDirectory(at: wrapperParent, withIntermediateDirectories: true)
                            try FileManager.default.copyItem(at: tempDir, to: wrappedDir)
                            let result = self.installFromDirectory(wrappedDir)
                            try? FileManager.default.removeItem(at: wrapperParent)
                            completion(result)
                        } catch {
                            self.errors["install"] = "Install failed: \(error.localizedDescription)"
                            completion(false)
                        }
                    } else {
                        self.errors["install"] = "No .ecplugin bundle found in zip"
                        completion(false)
                    }
                }
            }
        }
        do {
            try process.run()
        } catch {
            errors["install"] = "Install failed: \(error.localizedDescription)"
            completion(false)
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
