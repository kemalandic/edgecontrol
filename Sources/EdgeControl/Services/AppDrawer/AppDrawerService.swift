import AppKit
import Combine
import Foundation

/// What App Drawer tiles show and do: the apps on this Mac, the Dock,
/// what's running and in front, usage history, Shortcuts and decks, and
/// running keys. It runs while an App Drawer is anywhere on the dashboard.
@MainActor
public final class AppDrawerService: ObservableObject {
    @Published public private(set) var apps: [String: DrawerApp] = [:]
    /// Installed apps by name.
    @Published public private(set) var installed: [String] = []
    @Published private(set) var dock = AppCatalog.Dock()
    @Published public private(set) var running: [String] = []
    @Published public private(set) var frontmost: String?
    @Published public private(set) var mostUsed: [String] = []
    @Published public private(set) var recentlyUsed: [String] = []
    @Published public private(set) var shortcuts: [DrawerShortcut] = []
    /// Whether keyboard keys can work; see KeyRunner.
    @Published public private(set) var canPostEvents = false
    /// Apps opening from a tap, which bounce until they're in front.
    @Published public private(set) var launching: Set<String> = []
    /// Keys that just ran, for a moment, and keys that failed, with why.
    @Published public private(set) var fired: Set<String> = []
    @Published public private(set) var failures: [String: String] = [:]
    /// The last failure's message and when, for the tile to show.
    @Published public private(set) var lastFailure: (key: String, message: String, at: Date)?

    public let decks: DeckStore
    let runner = KeyRunner()
    private var usage: UsageLedger
    private let usageURL: URL
    private var observers: [NSObjectProtocol] = []
    private var tasks: [Task<Void, Never>] = []
    private var started = false

    public init(decks: DeckStore? = nil) {
        self.decks = decks ?? DeckStore()
        usageURL = AppSupport.directory.appendingPathComponent("App Drawer/usage.json")
        usage = UsageLedger()
        runner.shortcuts = { [weak self] in self?.shortcuts ?? [] }
    }

    // MARK: - Lifecycle

    public func start() {
        guard !started else { return }
        started = true
        let legacyUsage =
            AppSupport.isRunningTests
            ? nil
            : FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/EdgeControl App Drawer/usage.json")
        usage = UsageLedger.load(from: usageURL, legacy: legacyUsage)
        decks.startWatching()
        dock = AppCatalog.readDock()
        refreshRunning()
        usage.open(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, at: Self.now)
        runner.noteFront(NSWorkspace.shared.frontmostApplication)
        canPostEvents = runner.canPostEvents
        scanApps()
        refreshShortcuts()
        observe()

        // The Dock and Accessibility every few seconds; apps, Shortcuts and
        // the usage file now and then.
        tasks.append(
            Task { [weak self] in
                var ticks = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self else { return }
                    ticks += 1
                    let dock = AppCatalog.readDock()
                    if dock != self.dock { self.dock = dock }
                    let access = self.runner.canPostEvents
                    if access != self.canPostEvents { self.canPostEvents = access }
                    if ticks % 12 == 0 {
                        self.refreshShortcuts()
                        self.usage.save(to: self.usageURL)
                        self.rank()
                    }
                    if ticks % 120 == 0 { self.scanApps() }
                }
            })
    }

    public func stop() {
        guard started else { return }
        started = false
        usage.close(at: Self.now)
        usage.save(to: usageURL)
        tasks.forEach { $0.cancel() }
        tasks = []
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
        decks.stopWatching()
    }

    private static var now: Double { Date().timeIntervalSince1970 }

    private func observe() {
        let center = NSWorkspace.shared.notificationCenter
        // Notifications aren't Sendable: only the app's process id crosses
        // over to the main actor.
        observers.append(
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                    .processIdentifier
                Task { @MainActor [weak self] in self?.activated(pid) }
            })
        func on(_ names: [Notification.Name], _ handle: @escaping @MainActor @Sendable (AppDrawerService) -> Void) {
            for name in names {
                observers.append(
                    center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            if let self { handle(self) }
                        }
                    })
            }
        }
        on([NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]) {
            $0.refreshRunning()
        }
        // Time in front pauses while the Mac sleeps or the session is locked.
        on([
            NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]) {
            $0.usage.close(at: Self.now)
            $0.usage.save(to: $0.usageURL)
        }
        on([
            NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]) {
            $0.usage.open(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, at: Self.now)
        }
    }

    private func activated(_ pid: pid_t?) {
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        usage.open(app?.bundleIdentifier, at: Self.now)
        runner.noteFront(app)
        refreshRunning()
        rank()
    }

    // MARK: - Apps

    private func scanApps() {
        Task {
            let scanned = await Task.detached(priority: .utility) { AppCatalog.scanInstalled() }.value
            self.apps = self.withRunningApps(scanned)
            self.installed = scanned.values
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map(\.bundleId)
            self.rank()
        }
    }

    /// Running apps that aren't in the usual folders (a downloaded app still
    /// in Downloads, say) can be shown too.
    private func withRunningApps(_ known: [String: DrawerApp]) -> [String: DrawerApp] {
        var all = known
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, all[id] == nil, let url = app.bundleURL else { continue }
            all[id] = DrawerApp(
                bundleId: id, name: app.localizedName ?? id, url: url, spotlightLastUsed: nil, spotlightUseCount: 0)
        }
        return all
    }

    private func refreshRunning() {
        let regular = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        let ids = regular.compactMap(\.bundleIdentifier)
        if ids != running { running = ids }
        frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if ids.contains(where: { apps[$0] == nil }) { apps = withRunningApps(apps) }
    }

    private func rank() {
        let ranked = usage.rankings(apps, at: Self.now)
        if ranked.most != mostUsed { mostUsed = ranked.most }
        if ranked.recent != recentlyUsed { recentlyUsed = ranked.recent }
    }

    private func refreshShortcuts() {
        Task {
            let list = await Task.detached(priority: .utility) { AppCatalog.listShortcuts() }.value
            if list != self.shortcuts { self.shortcuts = list }
        }
    }

    /// The Dock as a Dock tile shows it: kept apps, then running apps that
    /// aren't kept and the Dock's recent apps, after a divider.
    public var dockLayout: (kept: [String], others: [String]) {
        let kept = dock.apps.filter { apps[$0] != nil }
        var others: [String] = []
        for id in running + dock.recents where !kept.contains(id) && !others.contains(id) && apps[id] != nil {
            others.append(id)
        }
        return (kept, others)
    }

    public func appName(_ bundleId: String) -> String? { apps[bundleId]?.name }

    private var iconCache: [String: NSImage] = [:]

    /// An app's icon, a file's, or a picture chosen for a key, kept once
    /// loaded: tiles redraw often.
    func appIcon(_ bundleId: String) -> NSImage? {
        cached("app:" + bundleId) {
            guard let url = apps[bundleId]?.url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            else { return nil }
            // Safari in /Applications is a link to the system's copy, and a
            // link's icon carries an alias arrow.
            return NSWorkspace.shared.icon(forFile: url.resolvingSymlinksInPath().path)
        }
    }

    func fileIcon(_ path: String) -> NSImage? {
        cached("file:" + path) {
            let expanded = (path as NSString).expandingTildeInPath
            return FileManager.default.fileExists(atPath: expanded) ? NSWorkspace.shared.icon(forFile: expanded) : nil
        }
    }

    func picture(_ url: URL) -> NSImage? {
        cached("picture:" + url.path) { NSImage(contentsOf: url) }
    }

    private func cached(_ key: String, _ load: () -> NSImage?) -> NSImage? {
        if let image = iconCache[key] { return image }
        guard let image = load() else { return nil }
        if iconCache.count > 400 { iconCache.removeAll() }
        iconCache[key] = image
        return image
    }

    var images: DrawerImages {
        DrawerImages(
            app: { [weak self] in self?.appIcon($0) }, file: { [weak self] in self?.fileIcon($0) },
            picture: { [weak self] in self?.picture($0) })
    }

    /// Lower is used more, or more lately: for a deck's Most used and Recent orders.
    public func rank(of bundleId: String, recent: Bool) -> Int? {
        (recent ? recentlyUsed : mostUsed).firstIndex(of: bundleId)
    }

    // MARK: - Running keys

    /// Opens an app from a tile: it bounces until the app has opened.
    public func open(_ bundleId: String) {
        let tapped = ContinuousClock.now
        launching.insert(bundleId)
        Task {
            if let failure = await runner.launch(bundleId) {
                self.flag("app:" + bundleId, failure)
            }
            await self.stopBouncing(bundleId, tapped: tapped)
        }
    }

    /// Runs a key, or what holding it does.
    public func run(_ key: DeckKey, held: Bool = false) {
        guard let action = held ? key.hold : key.action, action.kind != .folder else { return }
        let tapped = ContinuousClock.now
        if action.kind == .app, let id = action.bundleId { launching.insert(id) }
        fired.insert(key.id)
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            self.fired.remove(key.id)
        }
        Task {
            if let failure = await runner.run(action) { self.flag(key.id, failure) }
            if action.kind == .app, let id = action.bundleId { await self.stopBouncing(id, tapped: tapped) }
        }
    }

    /// Once the app is open, after one bounce at least so a tap on an app
    /// that's already open still shows. An app that's slow to start keeps
    /// bouncing till it has, as in the Dock, for up to 8 seconds.
    private func stopBouncing(_ bundleId: String, tapped: ContinuousClock.Instant) async {
        try? await Task.sleep(until: tapped + .milliseconds(760), clock: .continuous)
        while tapped.duration(to: .now) < .seconds(8),
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).contains(where: {
                !$0.isFinishedLaunching
            })
        {
            try? await Task.sleep(for: .milliseconds(200))
        }
        launching.remove(bundleId)
    }

    private func flag(_ id: String, _ message: String) {
        AppLog.appDrawer.notice("A key didn't run: \(message, privacy: .public)")
        failures[id] = message
        lastFailure = (id, message, Date())
        Task {
            try? await Task.sleep(for: .seconds(4))
            if self.failures[id] == message { self.failures[id] = nil }
        }
    }

    /// Asks macOS for Accessibility, which adds EdgeControl to the list,
    /// and opens that list.
    public func openAccessibilitySettings() {
        _ = CGRequestPostEventAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension AppDrawerService: ServiceLifecycle {}
