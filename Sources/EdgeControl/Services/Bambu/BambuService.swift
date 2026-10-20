import AppKit
import Foundation

/// Keeps a connection to each Bambu Lab printer a widget shows.
///
/// A printer is reached at the address typed into its widget, with the
/// access code from the printer's own network screen; the code lives in the
/// Keychain, not in the layout file. Status arrives over MQTT about once a
/// second for as long as a widget watches the printer. The camera streams
/// only while a widget showing it is on screen and the displays are awake.
///
/// Everything here reads: the printer is never sent a command that would move
/// or heat it, so it works in Bambu's standard LAN mode without Developer
/// Mode.
@MainActor
public final class BambuService: ObservableObject {
    public enum Connection: Equatable, Sendable {
        case connecting
        case connected
        case needsAccessCode
        case failed(String)
    }

    public struct Printer: Equatable, Sendable {
        public var connection: Connection
        public var serial: String?
        public var status: BambuStatus?

        public var model: String? { serial.flatMap(BambuStatus.model) }
    }

    typealias ReportLinkFactory =
        @MainActor (
            _ host: String, _ accessCode: String,
            _ handler: @escaping @MainActor @Sendable (BambuMQTTSession.Event) -> Void
        ) -> BambuLink
    typealias CameraLinkFactory =
        @MainActor (
            _ host: String, _ accessCode: String,
            _ handler: @escaping @MainActor @Sendable (BambuCameraSession.Event) -> Void
        ) -> BambuLink
    typealias PreviewLinkFactory =
        @MainActor (
            _ host: String, _ accessCode: String, _ paths: [String],
            _ handler: @escaping @MainActor @Sendable (BambuPreviewSession.Event) -> Void
        ) -> BambuLink

    @Published public private(set) var printers: [String: Printer] = [:]
    @Published public private(set) var frames: [String: BambuCameraFrame] = [:]
    /// The current job's plate picture, for widgets showing the model.
    @Published public private(set) var previews: [String: BambuModelPreview] = [:]
    /// What the last search of the network found, for settings to offer.
    @Published public private(set) var discovered: [BambuDiscovery.Found]?
    @Published public private(set) var discovering = false
    /// Printers found at a new address after going quiet at the old one:
    /// old address → new. Widgets showing the old address save the new one.
    @Published public private(set) var moves: [String: String] = [:]

    private let secrets: CISecretStore
    private let makeReportLink: ReportLinkFactory
    private let makeCameraLink: CameraLinkFactory
    private let makePreviewLink: PreviewLinkFactory
    private let scan: @Sendable () async -> [BambuDiscovery.Found]
    /// Serial numbers known for each address, from a widget's settings or a
    /// connection, so a printer that moves can be recognised.
    private var serials: [String: String] = [:]
    private var lastLocated: [String: Date] = [:]
    private let retryDelays: [Duration]

    private var reports: [String: BambuJSON] = [:]
    private var watchCounts: [String: Int] = [:]
    private var cameraCounts: [String: Int] = [:]
    private var links: [String: BambuLink] = [:]
    private var cameraLinks: [String: BambuLink] = [:]
    /// Bumped on every connect, so a dropped connection's late events are ignored.
    private var generations: [String: Int] = [:]
    private var cameraGenerations: [String: Int] = [:]
    private var failures: [String: Int] = [:]
    private var cameraFailures: [String: Int] = [:]
    private var retries: [String: Task<Void, Never>] = [:]
    private var cameraRetries: [String: Task<Void, Never>] = [:]
    private var previewCounts: [String: Int] = [:]
    private var previewLinks: [String: BambuLink] = [:]
    /// The job file each preview is for, fetched or being fetched.
    private var previewJobs: [String: String] = [:]
    private var previewFailures: [String: Int] = [:]
    private var previewRetries: [String: Task<Void, Never>] = [:]
    private var previewGenerations: [String: Int] = [:]
    private var screensAwake = true
    private var screenObservers: [NSObjectProtocol] = []

    public convenience init() {
        self.init(
            secrets: KeychainSecretStore(service: "ai.pakslab.edgecontrol.bambu"),
            retryDelays: [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)],
            makeReportLink: { BambuMQTTSession(host: $0, accessCode: $1, handler: $2) },
            makeCameraLink: { BambuCameraSession(host: $0, accessCode: $1, handler: $2) },
            makePreviewLink: { BambuPreviewSession(host: $0, accessCode: $1, paths: $2, handler: $3) },
            scan: { await BambuDiscovery.scan() })
    }

    init(
        secrets: CISecretStore, retryDelays: [Duration], makeReportLink: @escaping ReportLinkFactory,
        makeCameraLink: @escaping CameraLinkFactory, makePreviewLink: @escaping PreviewLinkFactory,
        scan: @escaping @Sendable () async -> [BambuDiscovery.Found]
    ) {
        self.scan = scan
        self.secrets = secrets
        self.retryDelays = retryDelays
        self.makeReportLink = makeReportLink
        self.makeCameraLink = makeCameraLink
        self.makePreviewLink = makePreviewLink
        let center = NSWorkspace.shared.notificationCenter
        for (name, awake) in [
            (NSWorkspace.screensDidSleepNotification, false), (NSWorkspace.screensDidWakeNotification, true),
        ] {
            screenObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setScreensAwake(awake) }
                })
        }
    }

    // MARK: - Lifecycle

    public func start() {
        for host in watchCounts.keys where links[host] == nil { connect(host) }
        for host in cameraCounts.keys where cameraLinks[host] == nil { connectCamera(host) }
    }

    public func stop() {
        for host in Array(links.keys) { disconnect(host) }
        for host in Array(cameraLinks.keys) { disconnectCamera(host) }
    }

    // MARK: - Watching

    /// `serial`, when a widget knows it, lets a printer be followed if its
    /// address changes.
    public func watch(_ host: String, serial: String? = nil) {
        guard !host.isEmpty else { return }
        if let serial, !serial.isEmpty { serials[host] = serial }
        watchCounts[host, default: 0] += 1
        if watchCounts[host] == 1 { connect(host) }
    }

    public func unwatch(_ host: String) {
        guard let count = watchCounts[host] else { return }
        if count > 1 {
            watchCounts[host] = count - 1
        } else {
            watchCounts[host] = nil
            moves[host] = nil
            disconnect(host)
        }
    }

    public func watchCamera(_ host: String) {
        guard !host.isEmpty else { return }
        cameraCounts[host, default: 0] += 1
        if cameraCounts[host] == 1 { connectCamera(host) }
    }

    public func unwatchCamera(_ host: String) {
        guard let count = cameraCounts[host] else { return }
        if count > 1 {
            cameraCounts[host] = count - 1
        } else {
            cameraCounts[host] = nil
            disconnectCamera(host)
            frames[host] = nil
        }
    }

    // MARK: - Access codes

    public func hasAccessCode(for host: String) -> Bool {
        secrets.read(host) != nil
    }

    /// Saves the code and connects with it straight away, so settings can
    /// show whether it was right.
    public func setAccessCode(_ code: String, for host: String) throws {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !code.isEmpty else { return }
        try secrets.write(code, for: host)
        reconnect(host)
    }

    /// Tries again now rather than after the retry delay.
    public func reconnect(_ host: String) {
        failures[host] = 0
        cameraFailures[host] = 0
        if watchCounts[host] != nil {
            disconnect(host)
            connect(host)
        }
        if cameraCounts[host] != nil {
            disconnectCamera(host)
            connectCamera(host)
        }
    }

    // MARK: - Status

    private func connect(_ host: String) {
        retries[host]?.cancel()
        retries[host] = nil
        guard let code = secrets.read(host) else {
            update(host) { $0.connection = .needsAccessCode }
            return
        }
        update(host) { $0.connection = .connecting }
        let generation = generations[host, default: 0] + 1
        generations[host] = generation
        links[host] = makeReportLink(host, code) { [weak self] event in
            guard let self, self.generations[host] == generation else { return }
            self.handle(event, from: host)
        }
    }

    private func disconnect(_ host: String) {
        retries[host]?.cancel()
        retries[host] = nil
        generations[host, default: 0] += 1
        links.removeValue(forKey: host)?.cancel()
    }

    private func handle(_ event: BambuMQTTSession.Event, from host: String) {
        switch event {
        case .connected(let serial):
            failures[host] = 0
            serials[host] = serial
            update(host) {
                $0.serial = serial
                $0.connection = .connected
            }
        case .report(let print, let complete):
            let merged = complete ? print : (reports[host]?.merging(print) ?? print)
            reports[host] = merged
            let status = BambuStatus(merged)
            if printers[host]?.status != status { update(host) { $0.status = status } }
            fetchPreviewIfNeeded(host)
        case .failed(let problem):
            links[host] = nil
            update(host) { $0.connection = .failed(problem) }
            // A wrong code stays wrong until somebody types a new one.
            guard problem != "Wrong access code", watchCounts[host] != nil else { return }
            let attempt = failures[host, default: 0]
            failures[host] = attempt + 1
            if attempt + 1 >= 2 { locate(host) }
            let delay = retryDelays[min(attempt, retryDelays.count - 1)]
            retries[host] = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, self.watchCounts[host] != nil else { return }
                self.connect(host)
            }
        }
    }

    private func update(_ host: String, _ change: (inout Printer) -> Void) {
        var printer = printers[host] ?? Printer(connection: .connecting)
        change(&printer)
        if printers[host] != printer { printers[host] = printer }
    }

    // MARK: - Camera

    private func connectCamera(_ host: String) {
        cameraRetries[host]?.cancel()
        cameraRetries[host] = nil
        guard screensAwake, let code = secrets.read(host) else { return }
        let generation = cameraGenerations[host, default: 0] + 1
        cameraGenerations[host] = generation
        cameraLinks[host] = makeCameraLink(host, code) { [weak self] event in
            guard let self, self.cameraGenerations[host] == generation else { return }
            switch event {
            case .frame(let frame):
                self.cameraFailures[host] = 0
                self.frames[host] = frame
            case .failed:
                self.cameraLinks[host] = nil
                self.retryCamera(host)
            }
        }
    }

    private func disconnectCamera(_ host: String) {
        cameraRetries[host]?.cancel()
        cameraRetries[host] = nil
        cameraGenerations[host, default: 0] += 1
        cameraLinks.removeValue(forKey: host)?.cancel()
    }

    /// Printers without this camera (X1, H2) refuse it every time, so the
    /// wait grows to a minute and stays there.
    private func retryCamera(_ host: String) {
        guard cameraCounts[host] != nil else { return }
        let attempt = cameraFailures[host, default: 0]
        cameraFailures[host] = attempt + 1
        let delay = retryDelays[min(attempt, retryDelays.count - 1)]
        cameraRetries[host] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.cameraCounts[host] != nil else { return }
            self.connectCamera(host)
        }
    }

    // MARK: - Finding printers

    /// Searches this Mac's networks for Bambu printers, for settings to list.
    public func discover() {
        guard !discovering else { return }
        discovering = true
        let scan = scan
        Task {
            let found = await scan()
            discovered = found
            discovering = false
            remember(found)
        }
    }

    private func remember(_ found: [BambuDiscovery.Found]) {
        for printer in found where serials[printer.host] == nil { serials[printer.host] = printer.serial }
    }

    /// A printer that answered before and has gone quiet may only have been
    /// given a new address by the router. Looks for its serial number, at
    /// most every five minutes, and moves its access code along if found.
    private func locate(_ host: String) {
        guard let serial = serials[host] ?? printers[host]?.serial,
            Date().timeIntervalSince(lastLocated[serial] ?? .distantPast) > 300
        else { return }
        lastLocated[serial] = Date()
        let scan = scan
        Task {
            let found = await scan()
            remember(found)
            guard watchCounts[host] != nil, let match = found.first(where: { $0.serial == serial }),
                match.host != host
            else { return }
            if let code = secrets.read(host), secrets.read(match.host) == nil {
                try? secrets.write(code, for: match.host)
            }
            moves[host] = match.host
        }
    }

    // MARK: - Model picture

    public func watchPreview(_ host: String) {
        guard !host.isEmpty else { return }
        previewCounts[host, default: 0] += 1
        if previewCounts[host] == 1 { fetchPreviewIfNeeded(host) }
    }

    public func unwatchPreview(_ host: String) {
        guard let count = previewCounts[host] else { return }
        if count > 1 {
            previewCounts[host] = count - 1
            return
        }
        previewCounts[host] = nil
        // A picture already fetched stays, so coming back to it is instant;
        // one half-fetched is dropped and fetched again when wanted.
        previewRetries.removeValue(forKey: host)?.cancel()
        previewGenerations[host, default: 0] += 1
        if let link = previewLinks.removeValue(forKey: host) {
            link.cancel()
            if previews[host] == nil { previewJobs[host] = nil }
        }
    }

    /// One fetch per job: a new job file replaces the picture. Only .3mf
    /// files carry pictures; a plain .gcode job has none.
    private func fetchPreviewIfNeeded(_ host: String) {
        guard previewCounts[host] != nil, let file = printers[host]?.status?.jobFile else { return }
        if previewJobs[host] != file {
            previewRetries.removeValue(forKey: host)?.cancel()
            previewLinks.removeValue(forKey: host)?.cancel()
            previews[host] = nil
            previewFailures[host] = 0
            previewJobs[host] = file
        } else if previews[host] != nil || previewLinks[host] != nil || previewRetries[host] != nil {
            return
        }
        guard file.lowercased().hasSuffix(".3mf"), previewFailures[host, default: 0] < 3,
            let code = secrets.read(host)
        else { return }
        let generation = previewGenerations[host, default: 0] + 1
        previewGenerations[host] = generation
        previewLinks[host] = makePreviewLink(host, code, BambuPreviewSession.paths(forJobFile: file)) {
            [weak self] event in
            guard let self, self.previewGenerations[host] == generation else { return }
            self.previewLinks[host] = nil
            switch event {
            case .preview(let preview):
                self.previews[host] = preview
            case .failed:
                // A job sent some other way may have no file to read; three
                // tries is enough to tell.
                let attempt = self.previewFailures[host, default: 0]
                self.previewFailures[host] = attempt + 1
                let delay = self.retryDelays[min(attempt + 1, self.retryDelays.count - 1)]
                self.previewRetries[host] = Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled, let self else { return }
                    self.previewRetries[host] = nil
                    self.fetchPreviewIfNeeded(host)
                }
            }
        }
    }

    private func setScreensAwake(_ awake: Bool) {
        screensAwake = awake
        if awake {
            for host in cameraCounts.keys where cameraLinks[host] == nil { connectCamera(host) }
        } else {
            for host in Array(cameraLinks.keys) { disconnectCamera(host) }
        }
    }
}
