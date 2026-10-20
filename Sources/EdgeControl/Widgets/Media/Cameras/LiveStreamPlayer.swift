import AVFoundation
import AppKit
import SwiftUI

/// Decisions about a live stream, kept apart from AVPlayer so they can be tested.
enum LiveEdge {
    /// How far behind the newest video playback may fall before it jumps forward.
    static let maxLag: Double = 2.5
    /// Where a jump lands, behind the newest video, so the next segment has
    /// time to arrive before playback reaches it.
    static let landing: Double = 0.8
    /// With no new frame for this long, the stream is rebuilt.
    static let stallTimeout: TimeInterval = 10
    /// Never-started streams are rebuilt after this long.
    static let startTimeout: TimeInterval = 20

    /// Where to seek to catch up, or nil to leave playback alone.
    static func seekTarget(current: Double, liveEdge: Double) -> Double? {
        guard current.isFinite, liveEdge.isFinite, liveEdge - current > maxLag else { return nil }
        return max(0, liveEdge - landing)
    }

    /// Seconds before reconnecting after the nth consecutive failure: 1, 2, 4, … 30.
    static func retryDelay(afterFailures failures: Int) -> TimeInterval {
        min(30, pow(2, Double(max(0, failures - 1))))
    }
}

/// Plays a camera's HLS stream as close to live as AVPlayer allows.
///
/// AVPlayer is built for video on demand. Left alone it buffers several
/// seconds, drifts further behind with every network hiccup, and stops for
/// good when a live stream restarts. For a camera that is the wrong trade, so
/// this player starts as soon as the stream is ready, jumps back to the live
/// edge when it lags, and rebuilds the stream when it stalls or fails.
/// Against go2rtc's HLS (half-second segments) it runs about two seconds
/// behind the camera.
@MainActor
final class LiveStreamPlayer: ObservableObject {
    enum State: Equatable {
        case connecting
        case playing
        case reconnecting(String)
    }

    @Published private(set) var state: State = .connecting
    @Published private(set) var hasAudio = false
    /// Held on purpose, as opposed to stalled: nothing reconnects or catches up.
    @Published private(set) var isPaused = false
    @Published var isMuted = true {
        didSet { player.isMuted = isMuted }
    }

    let player = AVPlayer()
    let url: URL
    private var tick: Task<Void, Never>?
    private var loadedAt = Date()
    private var lastProgress: (time: Double, at: Date)?
    private var failures = 0
    private var retryAt: Date?

    init(url: URL) {
        self.url = url
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
    }

    var isRunning: Bool { tick != nil }

    /// Holds the picture. Downloading stops too, so a paused camera costs nothing.
    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        player.pause()
    }

    /// Plays again from live: a camera an hour behind is no use to anyone, and
    /// the live-edge check jumps forward on the next tick.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        lastProgress = nil
    }

    func start() {
        guard tick == nil else { return }
        load()
        tick = Task { [weak self] in
            while !Task.isCancelled {
                self?.step()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Stops downloading as well as playing: a camera on another page costs nothing.
    func stop() {
        tick?.cancel()
        tick = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .connecting
        hasAudio = false
        isPaused = false
        retryAt = nil
    }

    private func load() {
        let item = AVPlayerItem(url: url)
        // Keep the buffer short: a camera is only worth watching live.
        item.preferredForwardBufferDuration = 1
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        player.replaceCurrentItem(with: item)
        loadedAt = Date()
        lastProgress = nil
    }

    private func step() {
        guard !isPaused else { return }
        let now = Date()
        if let retryAt {
            guard now >= retryAt else { return }
            self.retryAt = nil
            load()
            return
        }
        guard let item = player.currentItem else { return }

        switch item.status {
        case .failed:
            fail(Self.reason(for: item))
        case .unknown:
            if now.timeIntervalSince(loadedAt) > LiveEdge.startTimeout { fail("The camera didn't start.") }
        case .readyToPlay:
            if player.timeControlStatus == .paused { player.play() }
            let current = player.currentTime().seconds
            if let edge = item.seekableTimeRanges.last?.timeRangeValue.end.seconds,
                let target = LiveEdge.seekTarget(current: current, liveEdge: edge)
            {
                player.seek(
                    to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
                    toleranceAfter: .zero)
            }
            if let last = lastProgress, current == last.time {
                if now.timeIntervalSince(last.at) > LiveEdge.stallTimeout { fail("The stream stalled.") }
            } else if current.isFinite {
                lastProgress = (current, now)
                if player.timeControlStatus == .playing, state != .playing {
                    state = .playing
                    failures = 0
                }
            }
            hasAudio = item.tracks.contains { $0.assetTrack?.mediaType == .audio }
        @unknown default:
            break
        }
    }

    /// AVFoundation's errors are codes; go2rtc's HTTP status says what happened.
    private static func reason(for item: AVPlayerItem) -> String {
        switch item.errorLog()?.events.last?.errorStatusCode ?? 0 {
        case 404: return "go2rtc doesn't have this camera."
        case 500...599: return "go2rtc couldn't reach the camera."
        default: return "The camera isn't answering."
        }
    }

    private func fail(_ reason: String) {
        failures += 1
        state = .reconnecting(reason)
        player.replaceCurrentItem(with: nil)
        retryAt = Date().addingTimeInterval(LiveEdge.retryDelay(afterFailures: failures))
    }
}

/// Draws an AVPlayer with no controls. Clicks pass through to the SwiftUI
/// views around it, which own every tap on the widget.
struct LivePlayerView: NSViewRepresentable {
    let player: AVPlayer
    let fill: Bool

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }

    static func dismantleNSView(_ view: PlayerLayerView, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
