import Foundation
import os

/// Reads and writes layout.json from Application Support directory.
/// Handles first-launch default layout generation and migration from UserDefaults.
public final class LayoutStore: Sendable {

    private static let fileName = "layout.json"

    private static var defaultDirectoryURL: URL { AppSupport.directory }

    private let directoryURL: URL
    /// Set when the layout file on disk must not be replaced this session:
    /// it couldn't be read (it may be fine next time), couldn't be moved
    /// aside, or was written by a newer version. Saves are refused until an
    /// import replaces it deliberately.
    private let protectedFile = OSAllocatedUnfairLock(initialState: false)
    public var isProtectingFile: Bool { protectedFile.withLock { $0 } }

    private var fileURL: URL {
        directoryURL.appendingPathComponent(Self.fileName)
    }

    /// `directory` exists so tests can point the store somewhere disposable.
    /// Every caller in the app takes the default, which is Application Support.
    public init(directory: URL? = nil) {
        self.directoryURL = directory ?? Self.defaultDirectoryURL
    }

    // MARK: - Read / Write

    /// The newest layout format this version reads.
    public static let currentVersion = 1

    private var backupURL: URL { fileURL.appendingPathExtension("bak") }
    /// The layout as it was just before the last import.
    public var preImportURL: URL { directoryURL.appendingPathComponent("layout-before-import.json") }

    public func load() -> LayoutDocument {
        let url = fileURL

        if FileManager.default.fileExists(atPath: url.path) {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                // Couldn't read the file at all (permissions, a disk hiccup):
                // nothing says its contents are bad, so leave it alone, run on
                // the last good copy, and don't save over it this session.
                AppLog.persistence.error(
                    "reading layout failed: \(error.localizedDescription, privacy: .public)")
                protectedFile.withLock { $0 = true }
                return loadBackup() ?? Self.generateDefaultLayout()
            }
            if let version = LayoutValidation.declaredVersion(data), version > Self.currentVersion {
                // Written by a newer version: never rewrite or move it. Show
                // what this version can read of it, or the last good copy.
                AppLog.persistence.error("layout is from a newer version; leaving the file unchanged")
                protectedFile.withLock { $0 = true }
                if let decoded = LayoutValidation.decode(data)?.document {
                    let doc = LayoutValidation.sanitized(decoded).document
                    if !doc.pages.isEmpty { return doc }
                }
                return loadBackup() ?? Self.generateDefaultLayout()
            }
            if let (decoded, clean) = LayoutValidation.decode(data) {
                let (doc, dropped) = LayoutValidation.sanitized(decoded)
                if !doc.pages.isEmpty {
                    if clean && dropped == 0 {
                        // The last copy known to load fully, for the next time one doesn't.
                        if (try? Data(contentsOf: backupURL)) != data {
                            AppLog.attempt("keeping a copy of the layout") { try data.write(to: backupURL, options: .atomic) }
                        }
                    } else {
                        // Loaded with something skipped or replaced: keep the
                        // original bytes (or, failing that, the file itself)
                        // and leave the backup as it was.
                        AppLog.persistence.error("layout loaded with unreadable parts skipped; keeping the original")
                        let kept = AppLog.attempt("keeping the partly read layout") {
                            try data.write(to: uniqueURL("layout-partly-read"), options: .atomic)
                        }
                        if !kept { protectedFile.withLock { $0 = true } }
                    }
                    return doc
                }
            }
            // The contents can't be used. Generating defaults straight over
            // the top is how a layout "resets itself" with nothing left to
            // diagnose: move it aside, then fall back to the last copy that loaded.
            AppLog.persistence.error("layout file is unreadable or empty")
            guard quarantine(url) else {
                protectedFile.withLock { $0 = true }
                return loadBackup() ?? Self.generateDefaultLayout()
            }
            if let backup = loadBackup() {
                AppLog.persistence.info("restored the last layout that loaded")
                save(backup)
                return backup
            }
        }

        // Genuinely nothing usable on disk — first launch, or the file we just
        // moved aside with no earlier copy.
        let doc = Self.generateDefaultLayout()
        save(doc)
        migrateFromUserDefaults(into: doc)
        return doc
    }

    private func loadBackup() -> LayoutDocument? {
        guard let data = try? Data(contentsOf: backupURL),
              (LayoutValidation.declaredVersion(data) ?? 1) <= Self.currentVersion,
              let doc = LayoutValidation.decode(data)?.document else { return nil }
        let sanitized = LayoutValidation.sanitized(doc).document
        return sanitized.pages.isEmpty ? nil : sanitized
    }

    /// A name no earlier copy has: date, time and a random suffix.
    private func uniqueURL(_ prefix: String) -> URL {
        let stamp = ISO8601DateFormatter.string(
            from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime])
            .replacingOccurrences(of: ":", with: "")
        let suffix = UUID().uuidString.prefix(6)
        return directoryURL.appendingPathComponent("\(prefix)-\(stamp)-\(suffix).json")
    }

    /// Each unreadable file is kept under its own name, so a second failure
    /// can't bury the first. False when it couldn't be moved (then it must
    /// not be overwritten either).
    private func quarantine(_ url: URL) -> Bool {
        let destination = uniqueURL("layout-unreadable")
        return AppLog.attempt("moving unreadable layout to \(destination.lastPathComponent)") {
            try FileManager.default.moveItem(at: url, to: destination)
        }
    }

    /// Writes the layout; false (and logged) when it couldn't be saved.
    @discardableResult
    public func save(_ document: LayoutDocument) -> Bool {
        guard !isProtectingFile else {
            AppLog.persistence.error("not saving: the layout file on disk is being protected this session")
            return false
        }
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
            return false
        }
        // A failure here loses the user's dashboard arrangement. It used to be
        // discarded silently, which made "my layout reset itself" impossible to
        // diagnose.
        return AppLog.attempt("writing layout to \(url.lastPathComponent)") {
            try data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Export / Import

    public func exportData(_ document: LayoutDocument? = nil) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Callers with a live document pass it in; store writes pause during
        // edit sessions, so the disk copy can lag far behind the screen.
        let doc = document ?? load()
        return try? encoder.encode(doc)
    }

    public enum ImportError: Error, Equatable {
        /// Not JSON, no pages, or parts that can't be read or laid out.
        case notALayout
        /// Written by a newer EdgeControl.
        case newerVersion(Int)
        /// The current layout couldn't be kept as a backup first.
        case backupFailed
        case saveFailed

        public var message: String {
            switch self {
            case .notALayout: "That file isn't a complete EdgeControl layout. Your dashboard is unchanged."
            case .newerVersion: "That layout is from a newer version of EdgeControl. Your dashboard is unchanged."
            case .backupFailed: "Your current layout couldn't be backed up, so nothing was imported."
            case .saveFailed: "The layout couldn't be saved. Your dashboard is unchanged."
            }
        }
    }

    /// Checks an imported layout before it replaces the current one, and
    /// keeps `current` (the layout on screen, including unsaved changes; the
    /// file on disk if nil) as layout-before-import.json.
    public func importData(_ data: Data, current: LayoutDocument? = nil) -> Result<LayoutDocument, ImportError> {
        // The lenient decoder reads almost anything (even {}) as a layout, so
        // an import must decode completely, with pages, and lay out cleanly.
        guard let (decoded, clean) = LayoutValidation.decode(data), clean,
              !decoded.pages.isEmpty,
              LayoutValidation.sanitized(decoded).dropped == 0
        else { return .failure(.notALayout) }
        guard decoded.version <= Self.currentVersion else { return .failure(.newerVersion(decoded.version)) }

        let fm = FileManager.default
        let previous: Data?
        if let current {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let encoded = try? encoder.encode(current) else { return .failure(.backupFailed) }
            previous = encoded
        } else if fm.fileExists(atPath: fileURL.path) {
            guard let onDisk = try? Data(contentsOf: fileURL) else { return .failure(.backupFailed) }
            previous = onDisk
        } else {
            previous = nil
        }
        if let previous {
            guard AppLog.attempt("keeping the layout from before the import", {
                try previous.write(to: preImportURL, options: .atomic)
            }) else { return .failure(.backupFailed) }
        }
        // A deliberate replacement. A protected file (unreadable at launch,
        // or from a newer version) is moved aside first; renaming works even
        // when it can't be read. If that fails, nothing is imported.
        let wasProtected = protectedFile.withLock { $0 }
        if wasProtected, fm.fileExists(atPath: fileURL.path) {
            guard AppLog.attempt("keeping the protected layout file", {
                try fm.moveItem(at: fileURL, to: uniqueURL("layout-replaced-by-import"))
            }) else { return .failure(.backupFailed) }
        }
        protectedFile.withLock { $0 = false }
        guard save(decoded) else {
            protectedFile.withLock { $0 = wasProtected }
            return .failure(.saveFailed)
        }
        return .success(decoded)
    }

    // MARK: - Default Layout Generation

    /// Generates a layout matching the current 7 hardcoded pages as closely as possible.
    private static func generateDefaultLayout() -> LayoutDocument {
        var pages: [PageConfig] = []

        // Page 1: System Monitor + Weather (original page1)
        pages.append(
            PageConfig(
                name: "System Monitor", order: 0,
                widgets: [
                    WidgetPlacement(widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3),
                    WidgetPlacement(widgetId: "memory-gauge", col: 4, row: 0, width: 4, height: 3),
                    WidgetPlacement(widgetId: "cpu-history", col: 0, row: 3, width: 4, height: 3),
                    WidgetPlacement(widgetId: "memory-history", col: 4, row: 3, width: 4, height: 3),
                    WidgetPlacement(widgetId: "weather", col: 8, row: 0, width: 6, height: 6),
                    WidgetPlacement(widgetId: "storage-bars", col: 14, row: 0, width: 6, height: 3),
                    WidgetPlacement(widgetId: "process-list", col: 14, row: 3, width: 6, height: 3),
                ]))

        // Page 2: Network + Processes
        pages.append(
            PageConfig(
                name: "Network", order: 1,
                widgets: [
                    WidgetPlacement(widgetId: "network-stats", col: 0, row: 0, width: 8, height: 4),
                    WidgetPlacement(widgetId: "process-list", col: 8, row: 0, width: 8, height: 6),
                    WidgetPlacement(widgetId: "disk-io", col: 0, row: 4, width: 8, height: 2),
                ]))

        // Page 3: Temperatures
        pages.append(
            PageConfig(
                name: "Temperatures", order: 2,
                widgets: [
                    WidgetPlacement(widgetId: "cpu-temp", col: 0, row: 0, width: 5, height: 4),
                    WidgetPlacement(widgetId: "gpu-temp", col: 5, row: 0, width: 5, height: 4),
                    WidgetPlacement(widgetId: "temp-history", col: 10, row: 0, width: 10, height: 4),
                    WidgetPlacement(widgetId: "cpu-gauge", col: 0, row: 4, width: 5, height: 2),
                    WidgetPlacement(widgetId: "memory-gauge", col: 5, row: 4, width: 5, height: 2),
                ]))

        // Page 4: Disk I/O + Storage
        pages.append(
            PageConfig(
                name: "Storage", order: 3,
                widgets: [
                    WidgetPlacement(widgetId: "disk-io", col: 0, row: 0, width: 8, height: 4),
                    WidgetPlacement(widgetId: "storage-bars", col: 8, row: 0, width: 8, height: 4),
                    WidgetPlacement(widgetId: "network-stats", col: 0, row: 4, width: 10, height: 2),
                ]))

        // Page 5: Now Playing
        pages.append(
            PageConfig(
                name: "Now Playing", order: 4,
                widgets: [
                    WidgetPlacement(widgetId: "now-playing", col: 2, row: 0, width: 12, height: 6),
                    WidgetPlacement(widgetId: "audio-devices", col: 14, row: 0, width: 6, height: 3),
                ]))

        // Page 6: Connectivity
        pages.append(
            PageConfig(
                name: "Connectivity", order: 5,
                widgets: [
                    WidgetPlacement(widgetId: "wifi-info", col: 0, row: 0, width: 6, height: 4),
                    WidgetPlacement(widgetId: "bluetooth", col: 6, row: 0, width: 6, height: 4),
                    WidgetPlacement(widgetId: "audio-devices", col: 12, row: 0, width: 6, height: 4),
                    WidgetPlacement(widgetId: "network-stats", col: 0, row: 4, width: 10, height: 2),
                ]))

        // Page 7: Time & Info
        pages.append(
            PageConfig(
                name: "Time & Info", order: 6,
                widgets: [
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
