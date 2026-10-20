import Foundation
import Testing
@testable import EdgeControl

@MainActor
@Suite("Camera full screen")
struct CameraFullScreenTests {
    private let beans = URL(string: "http://127.0.0.1:9/api/stream.m3u8?src=beans")!
    private let plants = URL(string: "http://127.0.0.1:9/api/stream.m3u8?src=plant_wall")!
    private var cameras: [CameraFullScreen.Camera] {
        [.init(name: "Beans", url: beans), .init(name: "Plant wall", url: plants)]
    }

    private func service() -> CameraService {
        let service = CameraService(transport: StubTransport(replies: []))
        service.handBack = .milliseconds(20)
        return service
    }

    @Test("two views of one camera share a player, which plays while either wants it")
    func sharedPlayer() {
        let service = service()
        let player = service.player(for: beans)
        #expect(service.player(for: beans) === player)

        service.setActive(true, player, holder: "page-1")
        service.setActive(false, player, holder: "page-2")
        #expect(player.isRunning)

        service.setActive(false, player, holder: "page-1")
        #expect(!player.isRunning)

        service.release(player, holder: "page-1")
        service.release(player, holder: "page-2")
        #expect(service.player(for: beans) !== player)
    }

    @Test("opening a camera keeps its stream playing while the tiles underneath let go")
    func openKeepsPlaying() {
        let service = service()
        let player = service.player(for: beans)
        service.setActive(true, player, holder: "tile")

        service.showFullScreen(cameras, at: 0)
        service.setActive(false, player, holder: "tile")

        #expect(service.fullScreen?.camera.name == "Beans")
        #expect(player.isRunning)
    }

    @Test("the arrows go round the cameras, and the one left behind goes back to its tiles")
    func stepping() {
        let service = service()
        service.showFullScreen(cameras, at: 0)
        let first = service.player(for: beans)

        service.stepFullScreen(by: 1)
        #expect(service.fullScreen?.camera.name == "Plant wall")
        #expect(service.player(for: plants).isRunning)
        #expect(service.player(for: beans) !== first)  // nobody held it, so it went

        service.stepFullScreen(by: 1)
        #expect(service.fullScreen?.camera.name == "Beans")
        service.stepFullScreen(by: -1)
        #expect(service.fullScreen?.camera.name == "Plant wall")
    }

    @Test("closing hands the stream back to its tile without a gap")
    func handBack() async throws {
        let service = service()
        let player = service.player(for: beans)
        service.setActive(true, player, holder: "tile")
        service.showFullScreen(cameras, at: 0)
        service.setActive(false, player, holder: "tile")

        service.closeFullScreen()
        #expect(service.fullScreen == nil)
        #expect(player.isRunning)  // still playing while the tile wakes up
        service.setActive(true, player, holder: "tile")
        try await Task.sleep(for: .milliseconds(60))
        #expect(player.isRunning)

        // With no tile wanting it, it stops once the hand-back time is up.
        service.showFullScreen(cameras, at: 0)
        service.setActive(false, player, holder: "tile")
        service.closeFullScreen()
        try await Task.sleep(for: .milliseconds(60))
        #expect(!player.isRunning)
    }

    @Test("reopening straight after closing isn't undone by the closing")
    func reopen() async throws {
        let service = service()
        service.showFullScreen(cameras, at: 0)
        service.closeFullScreen()
        service.showFullScreen(cameras, at: 0)
        try await Task.sleep(for: .milliseconds(60))
        #expect(service.player(for: beans).isRunning)
    }

    @Test("pausing holds the stream; stopping forgets the pause")
    func pause() {
        let player = LiveStreamPlayer(url: beans)
        player.pause()
        #expect(!player.isPaused)  // nothing to pause yet

        player.start()
        player.pause()
        #expect(player.isPaused)
        player.resume()
        #expect(!player.isPaused)

        player.pause()
        player.stop()
        #expect(!player.isPaused)
        #expect(!player.isRunning)
    }

    @Test("mute is published, so the controls follow it")
    func mute() {
        let player = LiveStreamPlayer(url: beans)
        #expect(player.isMuted && player.player.isMuted)
        player.isMuted = false
        #expect(!player.player.isMuted)
    }
}
