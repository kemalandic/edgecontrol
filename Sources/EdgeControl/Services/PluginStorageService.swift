import Foundation

/// Plugin-scoped persistent key-value storage.
/// Each plugin gets its own storage.json at:
///   ~/Library/Application Support/EdgeControl/PluginData/{pluginId}/storage.json
///
/// Important: This is a @MainActor singleton. All access must be from the main actor.
@MainActor
public final class PluginStorageService {
    public static let shared = PluginStorageService()

    private static let baseDirectory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("EdgeControl/PluginData", isDirectory: true)
    }()

    /// In-memory cache: pluginId → [key: value]
    private var cache: [String: [String: Any]] = [:]
    /// Pending writes debounced per plugin
    private var pendingWrites: Set<String> = []

    private init() {}

    // MARK: - Public API

    public func get(pluginId: String, key: String) -> Any? {
        let store = loadStore(pluginId: pluginId)
        return store[key]
    }

    /// Maximum storage size per plugin (1 MB)
    private static let maxStorageBytes = 1_048_576

    public func set(pluginId: String, key: String, value: Any) {
        var store = loadStore(pluginId: pluginId)
        store[key] = value
        // Enforce size limit
        if let data = try? JSONSerialization.data(withJSONObject: store),
           data.count > Self.maxStorageBytes {
            PluginFileLogger.log(pluginId, "STORAGE REJECTED: exceeds 1MB limit")
            return
        }
        cache[pluginId] = store
        schedulePersist(pluginId: pluginId)
    }

    public func remove(pluginId: String, key: String) {
        var store = loadStore(pluginId: pluginId)
        store.removeValue(forKey: key)
        cache[pluginId] = store
        schedulePersist(pluginId: pluginId)
    }

    /// Remove all storage for a plugin (called on plugin uninstall).
    public func removeAll(pluginId: String) {
        cache.removeValue(forKey: pluginId)
        let dir = Self.baseDirectory.appendingPathComponent(pluginId, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Private

    private func storageURL(pluginId: String) -> URL {
        let dir = Self.baseDirectory.appendingPathComponent(pluginId, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("storage.json")
    }

    private func loadStore(pluginId: String) -> [String: Any] {
        if let cached = cache[pluginId] { return cached }

        let url = storageURL(pluginId: pluginId)
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            cache[pluginId] = [:]
            return [:]
        }
        cache[pluginId] = dict
        return dict
    }

    /// Debounce writes — coalesces rapid set/remove calls into a single disk write.
    private func schedulePersist(pluginId: String) {
        guard !pendingWrites.contains(pluginId) else { return }
        pendingWrites.insert(pluginId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.pendingWrites.remove(pluginId)
            guard let store = self.cache[pluginId] else { return }
            self.persistStore(pluginId: pluginId, store: store)
        }
    }

    private func persistStore(pluginId: String, store: [String: Any]) {
        let url = storageURL(pluginId: pluginId)
        guard let data = try? JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
