import AppKit
import CoreServices
import Foundation

/// An app App Drawer can show.
public struct DrawerApp: Hashable, Sendable {
    public let bundleId: String
    public let name: String
    public let url: URL
    /// From Spotlight, for history from before EdgeControl watched.
    let spotlightLastUsed: Date?
    let spotlightUseCount: Int
}

/// The apps on this Mac and how they're used: what's installed, what's in
/// the Dock, what's running and in front, and which are used most and most
/// recently. History starts from Spotlight's last-used dates and use counts,
/// then adds the time each app spends in front, which fades with a 14-day
/// half-life and stays on this Mac.
enum AppCatalog {
    static let appFolders: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        ].map { URL(fileURLWithPath: $0, isDirectory: true) } + [home.appendingPathComponent("Applications")]
    }()

    /// Apps you'd launch: menu bar extras and background agents are left out.
    static func app(at url: URL) -> DrawerApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        if (info["LSUIElement"] as? Bool) == true || (info["LSUIElement"] as? String) == "1" { return nil }
        if (info["LSBackgroundOnly"] as? Bool) == true { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        var lastUsed: Date?
        var useCount = 0
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
            lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            useCount = (MDItemCopyAttribute(item, "kMDItemUseCount" as CFString) as? NSNumber)?.intValue ?? 0
        }
        return DrawerApp(bundleId: id, name: name, url: url, spotlightLastUsed: lastUsed, spotlightUseCount: useCount)
    }

    /// Every app in the usual folders, and one level down for apps that
    /// install into a folder of their own. Slow enough to keep off the main
    /// thread.
    static func scanInstalled() -> [String: DrawerApp] {
        let fm = FileManager.default
        var apps: [String: DrawerApp] = [:]
        func consider(_ url: URL) {
            guard let app = app(at: url), apps[app.bundleId] == nil else { return }
            apps[app.bundleId] = app
        }
        for folder in appFolders {
            for url in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [] {
                if url.pathExtension == "app" {
                    consider(url)
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    for inner in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                    where inner.pathExtension == "app" {
                        consider(inner)
                    }
                }
            }
        }
        consider(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        return apps
    }

    // MARK: - Dock

    struct Dock: Equatable, Sendable {
        /// Finder and the kept apps, in Dock order.
        var apps: [String] = []
        /// The "Show suggested and recent apps" section, if it's on.
        var recents: [String] = []
    }

    static func readDock() -> Dock {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        let showRecents =
            (CFPreferencesCopyAppValue("show-recents" as CFString, "com.apple.dock" as CFString) as? Bool) ?? true
        return Dock(
            apps: ["com.apple.finder"] + dockBundleIds(dockValue("persistent-apps")),
            recents: showRecents ? dockBundleIds(dockValue("recent-apps")) : [])
    }

    private static func dockValue(_ key: String) -> [[String: Any]] {
        CFPreferencesCopyAppValue(key as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
    }

    /// The bundle ids of the Dock's tiles: from the tile's own id, or the
    /// app its file URL points at.
    static func dockBundleIds(_ items: [[String: Any]]) -> [String] {
        items.compactMap { item in
            guard let tile = item["tile-data"] as? [String: Any] else { return nil }
            if let id = tile["bundle-identifier"] as? String { return id }
            if let file = tile["file-data"] as? [String: Any], let text = file["_CFURLString"] as? String,
                let url = URL(string: text)
            {
                return Bundle(url: url)?.bundleIdentifier
            }
            return nil
        }
    }

    // MARK: - Shortcuts

    /// `shortcuts list --show-identifiers` prints "Name (UUID)" a line.
    static func parseShortcuts(_ output: String) -> [DrawerShortcut] {
        output.split(separator: "\n").compactMap { line in
            guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else { return nil }
            let name = line[..<open].trimmingCharacters(in: .whitespaces)
            let id = line[line.index(after: open)..<line.index(before: line.endIndex)]
            guard !name.isEmpty, id.count == 36 else { return nil }
            return DrawerShortcut(id: String(id), name: name)
        }
    }

    static func listShortcuts() -> [DrawerShortcut] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list", "--show-identifiers"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return parseShortcuts(String(decoding: data, as: UTF8.self))
    }
}

public struct DrawerShortcut: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
}

// MARK: - Usage

/// How much and how lately each app has been used.
struct AppUsage: Codable, Equatable, Sendable {
    /// Seconds since 1970.
    var lastUsed: Double = 0
    /// Seconds in front, fading with a 14-day half-life.
    var score: Double = 0
    /// When `score` was last brought up to date.
    var updated: Double = 0
    var activations: Int = 0

    static let halfLife: Double = 14 * 24 * 3600

    func decayedScore(at now: Double) -> Double {
        guard updated > 0 else { return score }
        return score * pow(0.5, (now - updated) / Self.halfLife)
    }

    /// Adds time in front, after fading what was there.
    mutating func add(seconds: Double, at now: Double) {
        score = decayedScore(at: now) + max(0, seconds)
        updated = now
    }
}

/// Usage for every app, saved in AppSupport/App Drawer/usage.json; the
/// first time, it starts from the plugin helper's history if there is one.
struct UsageLedger {
    var entries: [String: AppUsage] = [:]
    private var front: (id: String, since: Double)?

    /// EdgeControl itself isn't an app anyone means to launch from it.
    static let untracked: Set<String> = ["ai.pakslab.edgecontrol"]

    mutating func close(at now: Double) {
        guard let current = front else { return }
        front = nil
        guard !Self.untracked.contains(current.id) else { return }
        entries[current.id, default: AppUsage()].add(seconds: now - current.since, at: now)
    }

    mutating func open(_ id: String?, at now: Double) {
        close(at: now)
        guard let id else { return }
        front = (id, now)
        guard !Self.untracked.contains(id) else { return }
        entries[id, default: AppUsage()].lastUsed = now
        entries[id, default: AppUsage()].activations += 1
    }

    static func load(from url: URL, legacy: URL?) -> UsageLedger {
        for candidate in [url, legacy].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: candidate),
                let entries = try? JSONDecoder().decode([String: AppUsage].self, from: data)
            {
                return UsageLedger(entries: entries)
            }
        }
        return UsageLedger()
    }

    func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The apps most used, then the most recent: Spotlight's counts (a use
    /// counts as a minute) plus time in front, and the later of Spotlight's
    /// date and the last time in front.
    func rankings(_ apps: [String: DrawerApp], at now: Double) -> (most: [String], recent: [String]) {
        var score: [String: Double] = [:]
        var last: [String: Double] = [:]
        for (id, app) in apps where !Self.untracked.contains(id) {
            let usage = entries[id]
            score[id] = (usage?.decayedScore(at: now) ?? 0) + Double(min(app.spotlightUseCount, 500)) * 60
            last[id] = max(usage?.lastUsed ?? 0, app.spotlightLastUsed?.timeIntervalSince1970 ?? 0)
        }
        let most = score.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
        let recent = last.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map(\.key)
        return (Array(most.prefix(60)), Array(recent.prefix(60)))
    }
}
