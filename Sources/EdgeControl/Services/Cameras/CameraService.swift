import AppKit
import Foundation

/// Reads the camera list from each go2rtc server a Cameras widget points at.
///
/// Widgets register the servers they show with `watch(_:)`. Each server is
/// read as soon as it's watched, and again every minute while the service
/// runs, so a camera added to go2rtc shows up without touching the dashboard.
/// Video never passes through here: each camera tile streams on its own, but
/// they all stop while the displays sleep.
@MainActor
public final class CameraService: ObservableObject {
    public enum ListState: Equatable, Sendable {
        case loading
        case loaded([String])
        case failed(String)
    }

    @Published public private(set) var lists: [URL: ListState] = [:]
    /// False while the displays sleep: nobody is watching, so nothing streams.
    @Published public private(set) var screensAwake = true
    /// The camera open across the whole dashboard, if one is.
    @Published public private(set) var fullScreen: CameraFullScreen?

    private let transport: CITransport
    private let pollInterval: Duration
    private var watchCounts: [URL: Int] = [:]
    private var inFlight: Set<URL> = []
    private var pollTask: Task<Void, Never>?

    public init(
        transport: CITransport = URLSessionTransport(session: CameraService.session),
        pollInterval: Duration = .seconds(60)
    ) {
        self.transport = transport
        self.pollInterval = pollInterval
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

    private var screenObservers: [NSObjectProtocol] = []

    private func setScreensAwake(_ awake: Bool) {
        screensAwake = awake
        if let url = fullScreen?.camera.url {
            holders[url, default: [:]][Self.fullScreenHolder] = awake
            update(url)
        }
    }

    /// Cameras are on the LAN: a server that hasn't answered in ten seconds
    /// isn't going to, and the shared session would wait a full minute.
    nonisolated public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public func watch(_ server: URL) {
        watchCounts[server, default: 0] += 1
        guard watchCounts[server] == 1 else { return }
        if lists[server] == nil { lists[server] = .loading }
        Task { await refresh(server) }
    }

    public func unwatch(_ server: URL) {
        guard let count = watchCounts[server] else { return }
        if count <= 1 {
            watchCounts[server] = nil
        } else {
            watchCounts[server] = count - 1
        }
    }

    /// Reads one server's list now. Settings use this to show the cameras on a
    /// server that was only just typed in.
    public func refresh(_ server: URL) async {
        guard !inFlight.contains(server) else { return }
        inFlight.insert(server)
        defer { inFlight.remove(server) }
        if lists[server] == nil { lists[server] = .loading }

        do {
            let (data, response) = try await transport.get(
                Go2RTC.streamsURL(server: server), headers: ["Accept": "application/json"])
            guard (200..<300).contains(response.statusCode) else {
                throw CIError.httpStatus(response.statusCode)
            }
            lists[server] = .loaded(try Go2RTC.streamNames(from: data))
        } catch let error as CIError {
            lists[server] = .failed(Self.message(for: error))
        } catch {
            lists[server] = .failed(Self.message(for: .unreachable))
        }
    }

    // MARK: - Players

    /// One player per stream, shared by every view showing that camera: the
    /// same camera on two widgets streams once, and a camera opens full
    /// screen without connecting again.
    private var players: [URL: LiveStreamPlayer] = [:]
    /// Who is showing each stream, and whether they want it playing. A view
    /// on a page off to the side shows it but doesn't.
    private var holders: [URL: [String: Bool]] = [:]

    func player(for url: URL) -> LiveStreamPlayer {
        if let player = players[url] { return player }
        let player = LiveStreamPlayer(url: url)
        players[url] = player
        return player
    }

    /// The stream plays while anyone showing it wants it to.
    func setActive(_ active: Bool, _ player: LiveStreamPlayer, holder: String) {
        if players[player.url] == nil { players[player.url] = player }
        holders[player.url, default: [:]][holder] = active
        update(player.url)
    }

    /// A view stopped showing the stream; with nobody left, the player goes.
    func release(_ player: LiveStreamPlayer, holder: String) {
        holders[player.url]?[holder] = nil
        update(player.url)
    }

    private func update(_ url: URL) {
        guard let player = players[url] else { return }
        let wanted = holders[url]?.values.contains(true) ?? false
        if wanted { player.start() } else { player.stop() }
        if holders[url]?.isEmpty ?? true {
            holders[url] = nil
            players[url] = nil
        }
    }

    // MARK: - Full screen

    private static let fullScreenHolder = "full-screen"
    /// Bumped with every claim, so a late release can't undo a newer one.
    private var claims = 0
    /// How long a closed camera keeps playing for the tiles to take it back.
    var handBack: Duration = .seconds(1)

    public func showFullScreen(_ cameras: [CameraFullScreen.Camera], at index: Int) {
        guard cameras.indices.contains(index) else { return }
        let opened = CameraFullScreen(cameras: cameras, index: index)
        // Claimed before the tiles underneath let go, so it never stops.
        claim(opened.camera.url)
        fullScreen = opened
    }

    /// The next or previous camera, round the list.
    public func stepFullScreen(by step: Int) {
        guard let next = fullScreen?.moved(by: step) else { return }
        claim(next.camera.url)
        fullScreen = next
    }

    /// The camera plays on for a moment, until its tile has it again.
    public func closeFullScreen() {
        guard let url = fullScreen?.camera.url else { return }
        fullScreen = nil
        claims += 1
        let claim = claims
        let delay = handBack
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.claims == claim else { return }
            self.holders[url]?[Self.fullScreenHolder] = nil
            self.update(url)
        }
    }

    /// The full-screen camera plays while it's open and the displays are on;
    /// any other camera it held goes back to its tiles.
    private func claim(_ url: URL) {
        claims += 1
        for other in holders.keys where other != url && holders[other]?[Self.fullScreenHolder] != nil {
            holders[other]?[Self.fullScreenHolder] = nil
            update(other)
        }
        _ = player(for: url)
        holders[url, default: [:]][Self.fullScreenHolder] = screensAwake
        update(url)
    }

    public func start() {
        guard pollTask == nil else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                for server in self.watchCounts.keys {
                    await self.refresh(server)
                }
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Short enough for a tile, specific enough to act on.
    static func message(for error: CIError) -> String {
        switch error {
        case .unreachable: return "not reachable"
        case .unauthorized, .httpStatus(401), .httpStatus(403): return "asks for a login, which isn't supported yet"
        case .httpStatus(404): return "no go2rtc API at this address"
        case .httpStatus(let code): return "answered with error \(code)"
        case .rateLimited: return "busy, try again shortly"
        case .decoding: return "didn't answer like go2rtc"
        }
    }
}

/// A camera across the whole dashboard, and the cameras its widget shows,
/// which the arrows step through.
public struct CameraFullScreen: Equatable, Sendable {
    public struct Camera: Equatable, Sendable {
        public let name: String
        public let url: URL

        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    public let cameras: [Camera]
    public private(set) var index: Int

    public var camera: Camera { cameras[index] }

    func moved(by step: Int) -> CameraFullScreen {
        var moved = self
        let count = cameras.count
        moved.index = ((index + step) % count + count) % count
        return moved
    }
}
