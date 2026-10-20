import AppKit
import Foundation

/// Keeps every deck in Decks.json, in a folder of the user's choosing: this
/// Mac only, or a folder iCloud Drive, Google Drive, Dropbox or OneDrive
/// already syncs. That drive's own app does the syncing, so another Mac
/// pointed at the same folder gets the same decks, with nothing to sign up
/// for. The file is checked every two seconds while a tile shows it, and a
/// change from elsewhere is merged deck by deck: each keeps whichever side
/// changed it last. Pictures chosen for keys go in Icons/ beside it.
@MainActor
public final class DeckStore: ObservableObject {
    @Published public private(set) var file = DeckFile()
    @Published public private(set) var folder: URL

    public var decks: [String: Deck] { file.decks }

    /// Where an earlier App Drawer kept its decks, to bring them in the
    /// first time; empty in tests.
    struct Legacy {
        /// The App Drawer plugin helper's own folder and its saved choice of folder.
        var helperFolder: URL?
        var helperChosenFolder: String?
        /// The plugin's storage, where App Drawer 1 kept Manual mode's apps.
        var pluginStorage: URL?

        static var installed: Legacy {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Legacy(
                helperFolder: home.appendingPathComponent("Library/Application Support/EdgeControl App Drawer"),
                helperChosenFolder: UserDefaults(suiteName: "com.phillywebteam.appdrawer-helper")?
                    .string(forKey: "decksFolder"),
                pluginStorage: AppSupport.directory
                    .appendingPathComponent("PluginData/com.phillywebteam.appdrawer/storage.json"))
        }
    }

    static let folderKey = "appDrawer.decksFolder"
    let defaultFolder: URL
    private let defaults: UserDefaults
    private let legacy: Legacy
    private var loaded = false
    /// The file's modification date as last written or read here, and each
    /// deck's updatedAt then, to tell another Mac's changes from ours.
    private var lastStamp: Date?
    private var syncedUpdatedAt: [String: Double] = [:]
    private var saveTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        defaultFolder: URL = AppSupport.directory.appendingPathComponent("App Drawer", isDirectory: true),
        legacy: Legacy = AppSupport.isRunningTests ? Legacy() : .installed
    ) {
        self.defaults = defaults
        self.defaultFolder = defaultFolder
        self.legacy = legacy
        folder =
            defaults.string(forKey: Self.folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? defaultFolder
    }

    public var fileURL: URL { folder.appendingPathComponent("Decks.json") }

    // MARK: - Reading and writing

    /// Reads Decks.json the first time decks are needed. With none yet,
    /// decks come from the App Drawer plugin's helper if it was used, or
    /// from App Drawer 1's Manual mode.
    public func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let disk = Self.read(fileURL) {
            file = disk
            noteSynced()
            return
        }
        if adoptHelperDecks() { return }
        file = DeckFile(revision: 1, decks: migratedManualSets())
        save()
    }

    static func read(_ url: URL) -> DeckFile? {
        guard let data = try? Data(contentsOf: url), var decoded = try? JSONDecoder().decode(DeckFile.self, from: data)
        else { return nil }
        decoded.decks = decoded.decks.mapValues { $0.sanitized() }
        return decoded
    }

    private func noteSynced() {
        lastStamp = Self.stamp(fileURL)
        syncedUpdatedAt = file.decks.mapValues(\.updatedAt)
    }

    private static func stamp(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    func save() {
        saveTask?.cancel()
        saveTask = nil
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: fileURL, options: .atomic)
        noteSynced()
    }

    /// Edits arrive a keystroke at a time from the editor; the file, and a
    /// cloud drive's upload, only need the last of them.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    // MARK: - Watching for other Macs' changes

    public func startWatching() {
        loadIfNeeded()
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.checkFile()
            }
        }
    }

    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        if saveTask != nil { save() }
    }

    /// Another Mac, through the synced folder, or a text editor changed the
    /// file. Each deck keeps whichever side changed it last; a deck that's
    /// gone from the file and hasn't changed here since was deleted there.
    func checkFile() {
        // While an edit of ours is waiting to be written, ours is the newer copy.
        guard saveTask == nil, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let stamp = Self.stamp(fileURL)
        guard stamp != lastStamp else { return }
        lastStamp = stamp
        guard let disk = Self.read(fileURL) else { return }
        var merged = disk.decks
        var keptOurs = false
        for (id, deck) in file.decks {
            if let theirs = merged[id] {
                if deck.updatedAt > theirs.updatedAt {
                    merged[id] = deck
                    keptOurs = true
                }
            } else if deck.updatedAt > (syncedUpdatedAt[id] ?? 0) {
                merged[id] = deck
                keptOurs = true
            }
        }
        file.decks = merged
        file.revision = max(file.revision, disk.revision) + 1
        if keptOurs { save() } else { noteSynced() }
    }

    // MARK: - Changing decks

    public func deck(_ id: String) -> Deck {
        file.decks[id.lowercased()] ?? Deck(name: id)
    }

    /// Changes a deck, making it if it isn't there, and saves soon after.
    public func edit(_ id: String, _ change: (inout Deck) -> Void) {
        loadIfNeeded()
        let key = id.lowercased()
        guard !key.isEmpty else { return }
        var deck = file.decks[key] ?? Deck(name: id)
        change(&deck)
        deck.updatedAt = (Date().timeIntervalSince1970 * 1000).rounded()
        file.decks[key] = deck.sanitized()
        file.revision += 1
        scheduleSave()
    }

    public func remove(_ id: String) {
        file.decks[id.lowercased()] = nil
        file.revision += 1
        save()
    }

    /// Lowercased deck ids, sorted by name.
    public var deckIds: [String] {
        file.decks.keys.sorted {
            (file.decks[$0]?.name ?? $0).localizedCaseInsensitiveCompare(file.decks[$1]?.name ?? $1)
                == .orderedAscending
        }
    }

    // MARK: - Bringing in earlier decks

    /// The App Drawer plugin's helper kept decks in its own folder, or in a
    /// cloud folder it was pointed at. A cloud folder is simply adopted, so
    /// syncing carries on; a local one is copied here, with its pictures.
    private func adoptHelperDecks() -> Bool {
        if let chosen = legacy.helperChosenFolder {
            let url = URL(fileURLWithPath: chosen, isDirectory: true)
            if let disk = Self.read(url.appendingPathComponent("Decks.json")) {
                folder = url
                defaults.set(url.path, forKey: Self.folderKey)
                file = disk
                noteSynced()
                AppLog.appDrawer.info("Using the decks in \(url.path, privacy: .public), as the plugin's helper did")
                return true
            }
        }
        guard let helperFolder = legacy.helperFolder,
            let disk = Self.read(helperFolder.appendingPathComponent("Decks.json"))
        else { return false }
        file = disk
        Self.copyPictures(from: helperFolder, to: folder)
        save()
        AppLog.appDrawer.info("Brought in \(disk.decks.count) deck(s) from the plugin's helper")
        return true
    }

    /// App Drawer 1 kept each set of picked apps in the plugin's storage as
    /// "apps:<name>"; each becomes a deck of app keys.
    private func migratedManualSets() -> [String: Deck] {
        guard let url = legacy.pluginStorage, let data = try? Data(contentsOf: url),
            let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        let now = (Date().timeIntervalSince1970 * 1000).rounded()
        var result: [String: Deck] = [:]
        for (key, value) in store where key.hasPrefix("apps:") {
            let name = String(key.dropFirst("apps:".count))
            guard let ids = value as? [String], !ids.isEmpty else { continue }
            let order = (store["order:" + name] as? String).flatMap(DeckOrder.init(rawValue:)) ?? .manual
            result[name.lowercased()] = Deck(
                name: name.prefix(1).uppercased() + name.dropFirst(), order: order, updatedAt: now,
                keys: ids.map { DeckKey(action: .app($0)) })
        }
        return result
    }

    private static func copyPictures(from source: URL, to target: URL) {
        let fm = FileManager.default
        let icons = source.appendingPathComponent("Icons")
        guard let files = try? fm.contentsOfDirectory(atPath: icons.path) else { return }
        let destination = target.appendingPathComponent("Icons")
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in files where !fm.fileExists(atPath: destination.appendingPathComponent(name).path) {
            try? fm.copyItem(at: icons.appendingPathComponent(name), to: destination.appendingPathComponent(name))
        }
    }

    // MARK: - Pictures

    /// A picture's file, for an image:Icons/… icon.
    public func pictureURL(_ icon: String) -> URL? {
        guard icon.hasPrefix("image:"), DeckKey.isIconSpec(icon) else { return nil }
        return folder.appendingPathComponent(String(icon.dropFirst("image:".count)))
    }

    /// Copies a picture into Icons/, cropped square and 256 pixels a side,
    /// and returns the icon that names it.
    public func importPicture(_ source: URL) -> String? {
        guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0 else { return nil }
        let side = 256
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let crop = min(image.size.width, image.size.height)
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: NSRect(
                x: (image.size.width - crop) / 2, y: (image.size.height - crop) / 2, width: crop, height: crop),
            operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let icons = folder.appendingPathComponent("Icons")
        try? FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
        let name = String(UUID().uuidString.lowercased().prefix(12)) + ".png"
        guard (try? png.write(to: icons.appendingPathComponent(name))) != nil else { return nil }
        return "image:Icons/" + name
    }

    // MARK: - Where decks are saved

    public struct Location: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let folder: URL
    }

    static let subfolder = "EdgeControl Decks"

    /// This Mac, and the cloud drives this Mac has. Only folder names are
    /// read to offer them; nothing inside a drive is touched until one is
    /// chosen, since macOS may ask first.
    public func locations() -> [Location] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var list = [Location(id: "local", name: "This Mac only", folder: defaultFolder)]
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) {
            list.append(
                Location(id: "icloud", name: "iCloud Drive", folder: icloud.appendingPathComponent(Self.subfolder)))
        }
        let storage = home.appendingPathComponent("Library/CloudStorage")
        for entry in ((try? fm.contentsOfDirectory(atPath: storage.path)) ?? []).sorted() {
            // Drives that were disconnected leave a folder named "… (date)".
            guard !entry.hasSuffix(")") else { continue }
            let base = storage.appendingPathComponent(entry)
            if entry.hasPrefix("GoogleDrive-") {
                let account = entry.dropFirst("GoogleDrive-".count)
                list.append(
                    Location(
                        id: entry, name: "Google Drive (\(account))",
                        folder: base.appendingPathComponent("My Drive").appendingPathComponent(Self.subfolder)))
            } else if entry.hasPrefix("Dropbox") {
                list.append(Location(id: entry, name: "Dropbox", folder: base.appendingPathComponent(Self.subfolder)))
            } else if entry.hasPrefix("OneDrive") {
                list.append(Location(id: entry, name: "OneDrive", folder: base.appendingPathComponent(Self.subfolder)))
            }
        }
        let dropbox = home.appendingPathComponent("Dropbox")
        if fm.fileExists(atPath: dropbox.path), !list.contains(where: { $0.name == "Dropbox" }) {
            list.append(
                Location(id: "dropbox", name: "Dropbox", folder: dropbox.appendingPathComponent(Self.subfolder)))
        }
        return list
    }

    public var currentLocation: Location {
        locations().first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
            ?? Location(id: "custom", name: folder.lastPathComponent, folder: folder)
    }

    public func folderHasDecks(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("Decks.json").path)
    }

    public enum MoveError: LocalizedError {
        case unwritable(String)
        public var errorDescription: String? {
            switch self {
            case .unwritable(let reason): "Couldn't use that folder: \(reason)"
            }
        }
    }

    /// Moves Decks.json to another folder. If decks are already there (from
    /// another Mac), `adopt` uses them, merged with this Mac's by each deck's
    /// last change; otherwise this Mac's decks are written there. Pictures
    /// chosen for keys go too.
    public func move(to target: URL, adopt: Bool) throws {
        loadIfNeeded()
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            throw MoveError.unwritable(error.localizedDescription)
        }
        Self.copyPictures(from: folder, to: target)
        let mine = file.decks
        folder = target
        defaults.set(
            target.standardizedFileURL == defaultFolder.standardizedFileURL ? nil : target.path, forKey: Self.folderKey)
        if adopt, let theirs = Self.read(fileURL) {
            var merged = theirs.decks
            for (id, deck) in mine where deck.updatedAt > (merged[id]?.updatedAt ?? -1) { merged[id] = deck }
            file.decks = merged
        }
        file.revision += 1
        save()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw MoveError.unwritable("the file wasn't written")
        }
    }
}
