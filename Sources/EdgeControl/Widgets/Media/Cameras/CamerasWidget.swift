import AppKit
import SwiftUI

public final class CamerasWidget: DashboardWidget {
    public let widgetId = "cameras"
    public let displayName = "Cameras"
    public let description = "Live cameras from go2rtc or HLS, one at a time with tabs or all in a grid"
    public let iconName = "video"
    public let category: WidgetCategory = .media
    public let requiredServices: Set<ServiceKey> = [.cameras]
    public let supportedSizes = WidgetSizeRange(min: .size(2, 2), max: .size(20, 6))
    /// 5×3 cells is 640×360: one 16:9 camera, edge to edge.
    public let defaultSize = WidgetSize.size(5, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(
            key: CamerasSettings.serverKey, label: "go2rtc Server", type: .text, defaultValue: .string(""),
            help: "Your go2rtc address, like 192.168.1.20:1984. Frigate and Home Assistant include go2rtc."),
        // No help line: the list says itself what an empty list shows.
        ConfigSchemaEntry(
            key: CamerasSettings.camerasKey, label: "Cameras", type: .cameraList, defaultValue: .stringArray([])),
        ConfigSchemaEntry(
            key: "layout", label: "Show", type: .picker, defaultValue: .string("single"),
            options: ["single", "grid"],
            help: "Single shows one camera with tabs to switch. Grid shows them all; tap one to enlarge it."),
        ConfigSchemaEntry(
            key: "cycleSeconds", label: "Switch Every (Seconds)", type: .stepper, defaultValue: .int(0),
            minValue: 0, maxValue: 300, step: 5,
            help:
                "Single only. 0 stays on the camera you picked; a tap pauses switching for 30 seconds. The next camera connects early, so the switch lands on a playing picture."
        ),
        ConfigSchemaEntry(
            key: "fill", label: "Fill the Tile", type: .toggle, defaultValue: .bool(true),
            help: "On crops cameras to fill the widget, grid cells included. Off shows each whole picture."),
        ConfigSchemaEntry(key: "showNames", label: "Show Camera Names", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)
    /// Tabs and buttons sit on top of video, the one thing on the dashboard
    /// with no color of its own, so they take the theme's accent.
    public let defaultsToAccentColor = true

    private let service: CameraService

    public init(service: CameraService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        CamerasWidgetView(service: service, settings: CamerasSettings(config))
    }
}

/// The widget's config, read once per render.
struct CamerasSettings: Equatable {
    static let serverKey = "server"
    static let camerasKey = "cameras"

    var server: URL?
    var entries: [String]
    var grid: Bool
    var cycleSeconds: Int
    var fill: Bool
    var showNames: Bool

    init(_ config: WidgetConfig) {
        server = Go2RTC.serverURL(from: config.string(Self.serverKey))
        entries = config.stringArray(Self.camerasKey)
        grid = config.string("layout", default: "single") == "grid"
        cycleSeconds = max(0, config.int("cycleSeconds", default: 0))
        fill = config.bool("fill", default: true)
        showNames = config.bool("showNames", default: true)
    }

    /// The cameras to show, in order: the picked ones, or else every camera
    /// go2rtc has. Picked go2rtc cameras are kept even while the server's list
    /// can't be read, so a slow answer never blanks a working camera.
    func cameras(list: CameraService.ListState?) -> [CameraSource] {
        if !entries.isEmpty { return entries.compactMap(CameraSource.init(entry:)) }
        if case .loaded(let names) = list { return names.compactMap(CameraSource.init(entry:)) }
        return []
    }
}

/// Automatic switching. A camera takes seconds to start (a Ring live view
/// has to be set up through Ring's servers, and go2rtc's HLS adds a couple
/// more), so the next camera starts early and the switch waits for it to play.
enum CameraCycle {
    /// The next camera starts this long before its turn.
    static let lead: TimeInterval = 8
    /// How long past its turn the switch waits for a camera that won't play,
    /// before moving on to show what's wrong with it.
    static let patience: TimeInterval = 12

    enum Step: Equatable {
        case wait
        case startNext
        case switchToNext
    }

    static func step(sinceSwitch: TimeInterval, every seconds: Int, nextPlaying: Bool) -> Step {
        let due = TimeInterval(seconds)
        if sinceSwitch < due - lead { return .wait }
        if sinceSwitch >= due && (nextPlaying || sinceSwitch >= due + patience) { return .switchToNext }
        return .startNext
    }
}

private struct CamerasWidgetView: View {
    @ObservedObject var service: CameraService
    let settings: CamerasSettings

    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts

    /// Keeps touch zone ids apart when the same widget is placed twice.
    @State private var instance = String(UUID().uuidString.prefix(8))
    @State private var currentId: String?
    @State private var soundId: String?
    @State private var page = 0
    @State private var onScreen = true
    @State private var offScreenTask: Task<Void, Never>?
    @State private var lastTouch = Date.distantPast
    @State private var lastSwitch = Date()
    /// The next camera's stream, held open before its turn.
    @State private var upNext: LiveStreamPlayer?

    private var touchRegistry: TouchZoneRegistry { model.touchService.zoneRegistry }
    private var accent: Color { Theme.widgetPrimaryOrAccent("cameras", ts: ts) }
    private var onAccent: Color { CameraStyle.readableText(on: accent) }
    private var listState: CameraService.ListState? { settings.server.flatMap { service.lists[$0] } }
    private var cameras: [CameraSource] { settings.cameras(list: listState) }
    /// Video runs to the card's edges, so it takes the card's corners. Tabs,
    /// names and the speaker are pills whatever the theme's radius: they're
    /// controls floating on the picture, not boxes on the dashboard.
    private var tileRadius: CGFloat { Theme.radius(ts) }
    /// The theme's widget gap, between cameras as between widgets. A hairline
    /// at least, or two cameras at gap 0 read as one picture.
    private var spacing: CGFloat { max(1, CGFloat(ts.widgetGap)) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetCard()
            .background(onScreenTracker)
            .onAppear {
                if let server = settings.server { service.watch(server) }
            }
            .onDisappear {
                if let server = settings.server { service.unwatch(server) }
                offScreenTask?.cancel()
            }
            .onChange(of: settings.server) { old, new in
                if let old { service.unwatch(old) }
                if let new { service.watch(new) }
            }
            .task(id: settings) { await cycle() }
    }

    @ViewBuilder
    private var content: some View {
        let cameras = self.cameras
        if cameras.isEmpty {
            emptyState
        } else if settings.grid {
            grid(cameras)
        } else {
            single(cameras)
        }
    }

    // MARK: - One at a time

    private func single(_ cameras: [CameraSource]) -> some View {
        let current = cameras.first { $0.id == currentId } ?? cameras[0]
        return ZStack(alignment: .bottomLeading) {
            tile(current, showName: settings.showNames && cameras.count == 1, showSound: true) {
                openFullScreen(current, among: cameras)
            }
            if cameras.count > 1 {
                tabs(cameras, current: current.id)
                    .padding(8)
                    .padding(.trailing, 52)
            }
        }
    }

    private func tabs(_ cameras: [CameraSource], current: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(cameras) { camera in
                    let selected = camera.id == current
                    Text(camera.name)
                        .font(Theme.label(ts).weight(.heavy))
                        .foregroundStyle(selected ? onAccent : .white.opacity(0.8))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? accent : .black.opacity(0.45), in: Capsule())
                        .touchTappable(id: "cameras-\(instance)-tab-\(camera.id)", registry: touchRegistry) {
                            Task { @MainActor in select(camera.id) }
                        }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func select(_ id: String) {
        lastTouch = Date()
        guard id != currentId else { return }
        currentId = id
        soundId = nil
        lastSwitch = Date()
    }

    /// Automatic switching, paused for half a minute after any touch.
    private func cycle() async {
        let seconds = settings.cycleSeconds
        guard seconds > 0, !settings.grid else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            let cameras = self.cameras
            guard tilesActive, cameras.count > 1, Date().timeIntervalSince(lastTouch) >= 30 else {
                hold(nil)
                continue
            }
            let at = cameras.firstIndex { $0.id == currentId } ?? 0
            let next = cameras[(at + 1) % cameras.count]
            let nextURL = playbackURL(next)
            let step = CameraCycle.step(
                sinceSwitch: Date().timeIntervalSince(lastSwitch), every: seconds,
                nextPlaying: upNext != nil && upNext?.url == nextURL && upNext?.state == .playing)
            switch step {
            case .wait:
                hold(nil)
            case .startNext:
                hold(nextURL.map(service.player(for:)))
            case .switchToNext:
                // The stream stays held until the next pass, by which time
                // the camera's tile has it, so it plays straight on.
                currentId = next.id
                soundId = nil
                lastSwitch = Date()
            }
        }
        hold(nil)
    }

    /// Keeps a stream playing for the camera that's next, letting go of the
    /// one held before.
    private func hold(_ player: LiveStreamPlayer?) {
        guard player !== upNext else { return }
        let holder = "\(instance)-next"
        if let held = upNext { service.release(held, holder: holder) }
        upNext = player
        if let player { service.setActive(true, player, holder: holder) }
    }

    /// Hidden under a camera open full screen, the tiles rest.
    private var tilesActive: Bool { onScreen && service.screensAwake && service.fullScreen == nil }

    // MARK: - Grid

    private func grid(_ cameras: [CameraSource]) -> some View {
        GeometryReader { geo in
            let layout = CameraGrid.arrange(count: cameras.count, in: geo.size, spacing: spacing)
            let pages = (cameras.count + layout.perPage - 1) / layout.perPage
            let page = min(self.page, pages - 1)
            let visible = Array(cameras.dropFirst(page * layout.perPage).prefix(layout.perPage))
            let frames = CameraGrid.frames(
                count: visible.count, arrangement: layout, in: geo.size, spacing: spacing, fill: settings.fill)

            ZStack {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, camera in
                    let frame = frames[index]
                    // Sound is for full screen, where there's room for the button.
                    tile(camera, showName: settings.showNames, showSound: false) {
                        openFullScreen(camera, among: cameras)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if pages > 1 { pager(pages: pages, current: page) }
            }
        }
    }

    private func pager(pages: Int, current: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<pages, id: \.self) { index in
                Circle()
                    .fill(index == current ? accent : Theme.text3(ts))
                    .frame(width: 6, height: 6)
                    .padding(4)
                    .touchTappable(id: "cameras-\(instance)-page-\(index)", registry: touchRegistry) {
                        Task { @MainActor in
                            lastTouch = Date()
                            page = index
                        }
                    }
            }
        }
        .offset(y: 4)
    }

    // MARK: - A camera

    @ViewBuilder
    private func tile(
        _ camera: CameraSource, showName: Bool, showSound: Bool, onTap: @escaping @MainActor @Sendable () -> Void
    ) -> some View {
        if let url = playbackURL(camera) {
            CameraTile(
                service: service, stream: service.player(for: url), holder: "\(instance)-\(camera.id)",
                name: camera.name,
                active: tilesActive,
                muted: soundId != camera.id, fill: settings.fill,
                showName: showName, showSound: showSound, radius: tileRadius, accent: accent, onAccent: onAccent,
                registry: touchRegistry, soundZoneId: "cameras-\(instance)-sound-\(camera.id)",
                tapZoneId: "cameras-\(instance)-camera-\(camera.id)", onTap: onTap
            ) {
                lastTouch = Date()
                soundId = soundId == camera.id ? nil : camera.id
            }
            // A new player whenever the address changes, e.g. a new server.
            .id(url)
        } else {
            unplayable(camera)
        }
    }

    /// Opens a camera across the whole dashboard, with the widget's other
    /// cameras a swipe of the arrows away.
    private func openFullScreen(_ camera: CameraSource, among cameras: [CameraSource]) {
        lastTouch = Date()
        let playable = cameras.compactMap { source in
            playbackURL(source).map { CameraFullScreen.Camera(name: source.name, url: $0) }
        }
        guard let url = playbackURL(camera), let index = playable.firstIndex(where: { $0.url == url }) else { return }
        service.showFullScreen(playable, at: index)
    }

    private func playbackURL(_ camera: CameraSource) -> URL? {
        switch camera.feed {
        case .go2rtc(let stream):
            return settings.server.map { Go2RTC.hlsURL(server: $0, stream: stream) }
        case .hls(let url):
            return url
        }
    }

    /// A go2rtc camera with no server to play it through.
    private func unplayable(_ camera: CameraSource) -> some View {
        VStack(spacing: 4) {
            Text(camera.name.uppercased())
                .font(Theme.label(ts))
                .foregroundStyle(Theme.text2(ts))
            Text("Set a go2rtc server in this widget's settings")
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black, in: RoundedRectangle(cornerRadius: tileRadius, style: .continuous))
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyState: some View {
        let host = settings.server?.host ?? ""
        switch (settings.server, listState) {
        case (nil, _):
            message("video.badge.plus", "ADD CAMERAS", "Set a go2rtc server in this widget's settings")
        case (_, .failed(let reason)):
            message("video.slash", "GO2RTC UNAVAILABLE", "\(host) \(reason)")
        case (_, .loaded):
            message("video", "NO CAMERAS", "Add streams to go2rtc on \(host)")
        default:
            message("video", "CONNECTING", host)
        }
    }

    private func message(_ symbol: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 30 * ts.fontScale))
                .foregroundStyle(Theme.text3(ts))
            Text(title)
                .font(Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
            Text(detail)
                .font(Theme.caption(ts))
                .foregroundStyle(Theme.text3(ts))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(Theme.compactPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - On screen

    /// Pages next to the visible one stay rendered so swipes are smooth. A
    /// camera there would keep streaming for nobody, so cameras play only
    /// while at least half the widget is on the dashboard, and stop a few
    /// seconds after it leaves (a swipe that springs back shouldn't restart
    /// every stream).
    private var onScreenTracker: some View {
        GeometryReader { geo in
            // The frame only says when to look again; whether it's on screen
            // is worked out in the widget's own coordinates.
            let frame = geo.frame(in: .named(TouchCoordinate.name))
            let dashboard = geo.bounds(of: .named(TouchCoordinate.name))
            let size = geo.size
            Color.clear
                .onAppear { updateOnScreen(size: size, dashboard: dashboard) }
                .onChange(of: frame) { _, _ in updateOnScreen(size: size, dashboard: dashboard) }
        }
    }

    private func updateOnScreen(size: CGSize, dashboard: CGRect?) {
        let visible = CameraGrid.isOnScreen(size: size, dashboard: dashboard)
        offScreenTask?.cancel()
        if visible {
            if !onScreen { onScreen = true }
        } else if onScreen {
            offScreenTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if !Task.isCancelled { onScreen = false }
            }
        }
    }
}

/// One camera: the picture, a status line until it plays, and its name and
/// sound button.
private struct CameraTile: View {
    @ObservedObject var service: CameraService
    @ObservedObject var stream: LiveStreamPlayer
    let holder: String
    let name: String
    let active: Bool
    let muted: Bool
    let fill: Bool
    let showName: Bool
    let showSound: Bool
    let radius: CGFloat
    let accent: Color
    let onAccent: Color
    let registry: TouchZoneRegistry
    let soundZoneId: String
    let tapZoneId: String
    let onTap: @MainActor @Sendable () -> Void
    let onSound: @MainActor @Sendable () -> Void

    @Environment(\.themeSettings) private var ts

    init(
        service: CameraService, stream: LiveStreamPlayer, holder: String, name: String, active: Bool, muted: Bool,
        fill: Bool, showName: Bool, showSound: Bool, radius: CGFloat, accent: Color, onAccent: Color,
        registry: TouchZoneRegistry, soundZoneId: String, tapZoneId: String,
        onTap: @escaping @MainActor @Sendable () -> Void, onSound: @escaping @MainActor @Sendable () -> Void
    ) {
        self.tapZoneId = tapZoneId
        self.onTap = onTap
        self.service = service
        self.stream = stream
        self.holder = holder
        self.name = name
        self.active = active
        self.muted = muted
        self.fill = fill
        self.showName = showName
        self.showSound = showSound
        self.radius = radius
        self.accent = accent
        self.onAccent = onAccent
        self.registry = registry
        self.soundZoneId = soundZoneId
        self.onSound = onSound
    }

    var body: some View {
        ZStack {
            LivePlayerView(player: stream.player, fill: fill)
            if stream.state != .playing {
                status
            }
        }
        // Under the name and the speaker, so a click on the speaker mutes
        // rather than opening the camera.
        .touchTappable(id: tapZoneId, registry: registry) {
            Task { @MainActor in onTap() }
        }
        .overlay(alignment: .bottomLeading) {
            if showName {
                Text(name)
                    .font(Theme.caption(ts).weight(.heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(8)
                    // A tap on the name is a tap on the camera.
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showSound && stream.hasAudio {
                soundButton
                    .touchTappable(id: soundZoneId, registry: registry) {
                        Task { @MainActor in onSound() }
                    }
                    .padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(Rectangle())
        .onAppear {
            stream.isMuted = muted
            service.setActive(active, stream, holder: holder)
        }
        .onDisappear { service.release(stream, holder: holder) }
        .onChange(of: active) { _, isActive in service.setActive(isActive, stream, holder: holder) }
        .onChange(of: muted) { _, isMuted in stream.isMuted = isMuted }
    }

    private var status: some View {
        VStack(spacing: 8) {
            if case .reconnecting(let reason) = stream.state {
                Image(systemName: "video.slash")
                    .foregroundStyle(Theme.text3(ts))
                Text(reason + " Reconnecting…")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var soundButton: some View {
        Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 16 * ts.fontScale, weight: .semibold))
            .foregroundStyle(muted ? .white.opacity(0.85) : onAccent)
            .frame(width: 36, height: 36)
            .background(muted ? Color.black.opacity(0.45) : accent, in: Capsule())
    }
}

enum CameraStyle {
    /// Dark text on light accents like yellow, white on the rest: buttons and
    /// the selected tab sit on video, so they need their contrast from the
    /// accent itself.
    static func readableText(on color: Color) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}
