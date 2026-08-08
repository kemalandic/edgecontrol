import Foundation

/// Reads and writes layout.json from Application Support directory.
/// Handles first-launch default layout generation and migration from UserDefaults.
public final class LayoutStore: Sendable {

    private static let fileName = "layout.json"

    private static var defaultDirectoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("EdgeControl", isDirectory: true)
    }

    private let directoryURL: URL

    private var fileURL: URL {
        directoryURL.appendingPathComponent(Self.fileName)
    }

    /// `directory` exists so tests can point the store somewhere disposable.
    /// Every caller in the app takes the default, which is Application Support.
    public init(directory: URL? = nil) {
        self.directoryURL = directory ?? Self.defaultDirectoryURL
    }

    // MARK: - Read / Write

    public func load() -> LayoutDocument {
        let url = fileURL

        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(LayoutDocument.self, from: data)
            } catch {
                // There is a file and we cannot read it. Generating defaults
                // straight over the top is how a layout "resets itself" with
                // nothing left to diagnose — and the read can fail for reasons
                // that have nothing to do with the contents. Move it aside first.
                AppLog.persistence.error(
                    "loading layout failed: \(error.localizedDescription, privacy: .public)"
                )
                quarantine(url)
            }
        }

        // Genuinely nothing usable on disk — first launch, or the file we just
        // moved aside.
        let doc = Self.generateDefaultLayout()
        save(doc)
        migrateFromUserDefaults(into: doc)
        return doc
    }

    /// Keeps one generation. A second failure must not bury the first copy: that
    /// one is closest to the last good state and is the user's real arrangement.
    private func quarantine(_ url: URL) {
        let backup = url.appendingPathExtension("corrupt")
        let fm = FileManager.default
        guard !fm.fileExists(atPath: backup.path) else { return }
        _ = AppLog.attempt("moving unreadable layout to \(backup.lastPathComponent)") {
            try fm.moveItem(at: url, to: backup)
        }
    }

    public func save(_ document: LayoutDocument) {
        let url = fileURL
        let dir = directoryURL
        AppLog.attempt("creating layout directory") {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            AppLog.persistence.error(
                "encoding layout failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        // A failure here loses the user's dashboard arrangement. It used to be
        // discarded silently, which made "my layout reset itself" impossible to
        // diagnose.
        AppLog.attempt("writing layout to \(url.lastPathComponent)") {
            try data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Export / Import

    public func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let doc = load()
        return try? encoder.encode(doc)
    }

    public func importData(_ data: Data) -> LayoutDocument? {
        guard let doc = try? JSONDecoder().decode(LayoutDocument.self, from: data) else { return nil }
        save(doc)
        return doc
    }

    // MARK: - Default Layout Generation

    /// Generates a layout matching the current 7 hardcoded pages as closely as possible.
    private static func generateDefaultLayout() -> LayoutDocument {
        var pages: [PageConfig] = []

        // Page 1: System Monitor + Weather (original page1)
        pages.append(PageConfig(name: "System Monitor", order: 0, widgets: [
            WidgetPlacement(widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3),
            WidgetPlacement(widgetId: "memory-gauge", col: 4, row: 0, width: 4, height: 3),
            WidgetPlacement(widgetId: "cpu-history", col: 0, row: 3, width: 4, height: 3),
            WidgetPlacement(widgetId: "memory-history", col: 4, row: 3, width: 4, height: 3),
            WidgetPlacement(widgetId: "weather", col: 8, row: 0, width: 6, height: 6),
            WidgetPlacement(widgetId: "storage-bars", col: 14, row: 0, width: 6, height: 3),
            WidgetPlacement(widgetId: "process-list", col: 14, row: 3, width: 6, height: 3),
        ]))

        // Page 2: Network + Processes
        pages.append(PageConfig(name: "Network", order: 1, widgets: [
            WidgetPlacement(widgetId: "network-stats", col: 0, row: 0, width: 8, height: 4),
            WidgetPlacement(widgetId: "process-list", col: 8, row: 0, width: 8, height: 6),
            WidgetPlacement(widgetId: "disk-io", col: 0, row: 4, width: 8, height: 2),
        ]))

        // Page 3: Temperatures
        pages.append(PageConfig(name: "Temperatures", order: 2, widgets: [
            WidgetPlacement(widgetId: "cpu-temp", col: 0, row: 0, width: 5, height: 4),
            WidgetPlacement(widgetId: "gpu-temp", col: 5, row: 0, width: 5, height: 4),
            WidgetPlacement(widgetId: "temp-history", col: 10, row: 0, width: 10, height: 4),
            WidgetPlacement(widgetId: "cpu-gauge", col: 0, row: 4, width: 5, height: 2),
            WidgetPlacement(widgetId: "memory-gauge", col: 5, row: 4, width: 5, height: 2),
        ]))

        // Page 4: Disk I/O + Storage
        pages.append(PageConfig(name: "Storage", order: 3, widgets: [
            WidgetPlacement(widgetId: "disk-io", col: 0, row: 0, width: 8, height: 4),
            WidgetPlacement(widgetId: "storage-bars", col: 8, row: 0, width: 8, height: 4),
            WidgetPlacement(widgetId: "network-stats", col: 0, row: 4, width: 10, height: 2),
        ]))

        // Page 5: Now Playing
        pages.append(PageConfig(name: "Now Playing", order: 4, widgets: [
            WidgetPlacement(widgetId: "now-playing", col: 2, row: 0, width: 12, height: 6),
            WidgetPlacement(widgetId: "audio-devices", col: 14, row: 0, width: 6, height: 3),
        ]))

        // Page 6: Connectivity
        pages.append(PageConfig(name: "Connectivity", order: 5, widgets: [
            WidgetPlacement(widgetId: "wifi-info", col: 0, row: 0, width: 6, height: 4),
            WidgetPlacement(widgetId: "bluetooth", col: 6, row: 0, width: 6, height: 4),
            WidgetPlacement(widgetId: "audio-devices", col: 12, row: 0, width: 6, height: 4),
            WidgetPlacement(widgetId: "network-stats", col: 0, row: 4, width: 10, height: 2),
        ]))

        // Page 7: Time & Info
        pages.append(PageConfig(name: "Time & Info", order: 6, widgets: [
            WidgetPlacement(widgetId: "world-clocks", col: 0, row: 0, width: 8, height: 4),
            WidgetPlacement(widgetId: "day-progress", col: 8, row: 0, width: 6, height: 3),
            WidgetPlacement(widgetId: "moon-phase", col: 14, row: 0, width: 4, height: 4),
            WidgetPlacement(widgetId: "weather", col: 8, row: 3, width: 6, height: 3),
        ]))

        return LayoutDocument(
            version: 1,
            grid: GridDimensions(),
            pages: pages,
            globalSettings: GlobalSettings()
        )
    }

    // MARK: - Migration from UserDefaults

    private func migrateFromUserDefaults(into document: LayoutDocument) {
        let key = "EdgeControlSettings"
        guard let data = UserDefaults.standard.data(forKey: key) else { return }

        struct LegacySettings: Codable {
            var selectedDisplayName: String?
            var kioskMode: Bool?
            var debugMode: Bool?
        }

        guard let legacy = try? JSONDecoder().decode(LegacySettings.self, from: data) else { return }

        var doc = document
        doc.globalSettings.selectedDisplayName = legacy.selectedDisplayName
        if let kiosk = legacy.kioskMode { doc.globalSettings.kioskMode = kiosk }
        if let debug = legacy.debugMode { doc.globalSettings.debugMode = debug }

        // Save migrated settings and remove old key
        save(doc)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
