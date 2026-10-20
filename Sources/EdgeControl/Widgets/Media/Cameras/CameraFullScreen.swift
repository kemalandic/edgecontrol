import SwiftUI

/// The camera open across the whole dashboard, drawn by DashboardShell above
/// every page, the page dots and the gear.
struct CameraFullScreenLayer: View {
    @ObservedObject var service: CameraService

    var body: some View {
        ZStack {
            if let fullScreen = service.fullScreen {
                CameraFullScreenView(
                    service: service, stream: service.player(for: fullScreen.camera.url), at: fullScreen
                )
                // Stepping to another camera is a new player and new controls.
                .id(fullScreen.camera.url)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: service.fullScreen)
    }
}

/// One camera, edge to edge, with controls that fade a few seconds after the
/// last touch: close, pause and play, sound, and arrows to the widget's other
/// cameras. A tap anywhere else brings the controls back or hides them.
///
/// It shows the player its tile was using, so the picture doesn't reconnect;
/// the service keeps it playing, and the tiles underneath rest until it closes.
private struct CameraFullScreenView: View {
    @ObservedObject var service: CameraService
    @ObservedObject var stream: LiveStreamPlayer
    let at: CameraFullScreen

    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    @State private var controlsShown = true
    @State private var lastTouch = Date()
    @State private var mutedBefore: Bool?
    /// Above the dashboard's touch zones, so nothing underneath takes a tap.
    private static let touchLayer = 1
    private static let controlsLinger: TimeInterval = 4

    private var registry: TouchZoneRegistry { model.touchService.zoneRegistry }
    private var accent: Color { Theme.widgetPrimaryOrAccent("cameras", ts: ts) }
    private var radius: CGFloat { Theme.radius(ts) }

    var body: some View {
        ZStack {
            Color.black
            LivePlayerView(player: stream.player, fill: false)
            if stream.state != .playing && !stream.isPaused {
                status
            }
            if controlsShown {
                controls
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .touchTappable(id: "camera-full-screen", registry: registry, layer: Self.touchLayer) {
            Task { @MainActor in toggleControls() }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsShown)
        .onAppear {
            mutedBefore = stream.isMuted
            touched()
        }
        .onDisappear {
            // The tiles get their picture back live and as loud as they left it.
            if stream.isPaused { stream.resume() }
            if let mutedBefore { stream.isMuted = mutedBefore }
        }
        .onExitCommand { service.closeFullScreen() }
        .task { await fadeControls() }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Text(at.camera.name)
                    .font(.system(size: 24 * ts.fontScale, weight: .heavy, design: ts.fontFamily.design))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if at.cameras.count > 1 {
                    Text("\(at.index + 1) of \(at.cameras.count)")
                        .font(Theme.label(ts))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                button("xmark", id: "close") { service.closeFullScreen() }
            }
            .padding(24)
            .background(LinearGradient(colors: [.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom))

            Spacer(minLength: 0)

            HStack(spacing: 14) {
                button(stream.isPaused ? "play.fill" : "pause.fill", id: "play") {
                    if stream.isPaused { stream.resume() } else { stream.pause() }
                }
                liveBadge
                Spacer()
                if stream.hasAudio {
                    let sound = stream.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                    button(sound, id: "sound", lit: !stream.isMuted) {
                        stream.isMuted.toggle()
                    }
                }
            }
            .padding(24)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            if at.cameras.count > 1 {
                HStack {
                    button("chevron.left", id: "previous") { service.stepFullScreen(by: -1) }
                    Spacer()
                    button("chevron.right", id: "next") { service.stepFullScreen(by: 1) }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    /// Big enough for a finger, on video of any brightness.
    private func button(
        _ symbol: String, id: String, lit: Bool = false, action: @escaping @MainActor () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(lit ? CameraStyle.readableText(on: accent) : .white)
            .frame(width: 60, height: 60)
            .background(lit ? accent : Color.black.opacity(0.5), in: Capsule())
            .touchTappable(id: "camera-full-screen-\(id)", registry: registry, layer: Self.touchLayer) {
                Task { @MainActor in
                    touched()
                    action()
                }
            }
    }

    private var liveBadge: some View {
        let (label, dot): (String, Color) =
            stream.isPaused
            ? ("PAUSED", .white.opacity(0.5))
            : stream.state == .playing ? ("LIVE", Theme.accentRed) : ("CONNECTING", .white.opacity(0.5))
        return HStack(spacing: 8) {
            Circle().fill(dot).frame(width: 9, height: 9)
            Text(label)
                .font(Theme.label(ts).weight(.heavy))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: 60)
        .background(.black.opacity(0.5), in: Capsule())
        .allowsHitTesting(false)
    }

    private var status: some View {
        VStack(spacing: 10) {
            if case .reconnecting(let reason) = stream.state {
                Image(systemName: "video.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.6))
                Text(reason + " Reconnecting…")
                    .font(Theme.body(ts))
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ProgressView()
                    .tint(accent)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Showing and hiding

    private func touched() {
        lastTouch = Date()
        controlsShown = true
    }

    private func toggleControls() {
        if controlsShown { controlsShown = false } else { touched() }
    }

    /// Controls stay while the picture is paused or still connecting.
    private func fadeControls() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            if controlsShown, !stream.isPaused, stream.state == .playing,
                Date().timeIntervalSince(lastTouch) > Self.controlsLinger
            {
                controlsShown = false
            }
        }
    }
}
