import CoreGraphics
import Foundation
import Testing
@testable import EdgeControl

@Suite("Camera grid")
struct CameraGridTests {

    @Test("one camera fills the widget's width at 16:9")
    func single() {
        let a = CameraGrid.arrange(count: 1, in: CGSize(width: 624, height: 344), spacing: 6)
        #expect(a.columns == 1 && a.rows == 1 && a.perPage == 1)
        #expect(a.cellSize == CGSize(width: 611, height: 343))
    }

    @Test("four cameras in a wide widget sit in a row, not stretched into slivers")
    func wideRow() {
        let a = CameraGrid.arrange(count: 4, in: CGSize(width: 1264, height: 344), spacing: 6)
        #expect(a.columns == 4 && a.rows == 1)
        #expect(abs(a.cellSize.width / a.cellSize.height - 16 / 9) < 0.02, "cells must keep the camera's shape")
    }

    @Test("four cameras in a squarer widget make a 2×2")
    func twoByTwo() {
        let a = CameraGrid.arrange(count: 4, in: CGSize(width: 368, height: 224), spacing: 6)
        #expect(a.columns == 2 && a.rows == 2)
    }

    @Test("without fill, cells keep 16:9 and the grid is centered")
    func centered() {
        let size = CGSize(width: 1264, height: 344)
        let a = CameraGrid.arrange(count: 4, in: size, spacing: 6)
        let frames = CameraGrid.frames(count: 4, arrangement: a, in: size, spacing: 6, fill: false)
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0.size == a.cellSize })
        let union = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
        #expect(abs(union.midX - size.width / 2) <= 1 && abs(union.midY - size.height / 2) <= 1)
    }

    @Test("with fill, cells reach the widget's edges and a short last row widens")
    func filled() {
        let size = CGSize(width: 484, height: 352)
        let a = CameraGrid.arrange(count: 3, in: size, spacing: 6)
        #expect(a.columns == 2 && a.rows == 2)
        let frames = CameraGrid.frames(count: 3, arrangement: a, in: size, spacing: 6, fill: true)
        #expect(frames[0] == CGRect(x: 0, y: 0, width: 239, height: 173))
        #expect(frames[1] == CGRect(x: 245, y: 0, width: 239, height: 173))
        #expect(frames[2] == CGRect(x: 0, y: 179, width: 484, height: 173), "the lone camera should take the row")
        #expect(frames.allSatisfy { CGRect(origin: .zero, size: size).contains($0) })
    }

    @Test("with fill, a partly empty last page still fills the widget")
    func filledLastPage() {
        let size = CGSize(width: 240, height: 224)
        let a = CameraGrid.arrange(count: 2, in: size, spacing: 6)
        let frames = CameraGrid.frames(count: 1, arrangement: a, in: size, spacing: 6, fill: true)
        #expect(frames == [CGRect(x: 0, y: 0, width: 240, height: 224)])
    }

    @Test("cameras that would be too small to see go on further pages")
    func pages() {
        let a = CameraGrid.arrange(count: 9, in: CGSize(width: 240, height: 224), spacing: 6)
        #expect(a.perPage < 9)
        #expect(a.cellSize.width >= CameraGrid.minimumCell.width)
    }

    @Test("a widget smaller than the minimum still shows one camera")
    func tiny() {
        let a = CameraGrid.arrange(count: 3, in: CGSize(width: 100, height: 60), spacing: 6)
        #expect(a.perPage == 1)
    }
}

@Suite("Live playback")
struct LiveEdgeTests {

    @Test("playback a little behind live is left alone")
    func closeEnough() {
        #expect(LiveEdge.seekTarget(current: 10, liveEdge: 12) == nil)
    }

    @Test("playback that drifted jumps to just behind the newest video")
    func catchUp() {
        let target = LiveEdge.seekTarget(current: 10, liveEdge: 20)
        #expect(target.map { abs($0 - 19.2) < 1e-9 } == true)
    }

    @Test("no seeking on times AVPlayer hasn't worked out yet")
    func unknownTimes() {
        #expect(LiveEdge.seekTarget(current: .nan, liveEdge: 20) == nil)
        #expect(LiveEdge.seekTarget(current: 5, liveEdge: .infinity) == nil)
    }

    @Test("reconnects back off to thirty seconds")
    func backoff() {
        #expect((1...7).map(LiveEdge.retryDelay(afterFailures:)) == [1, 2, 4, 8, 16, 30, 30])
    }
}

@Suite("Cameras: on screen or not")
struct CameraOnScreenTests {
    /// A 2560×720 dashboard's bounds as a widget at `x` sees them, which is
    /// how `GeometryProxy.bounds(of:)` gives them.
    private func dashboard(seenFrom x: CGFloat) -> CGRect {
        CGRect(x: -x, y: -120, width: 2560, height: 720)
    }

    private let tile = CGSize(width: 640, height: 360)

    @Test("a widget anywhere on the dashboard is on screen, the right half included")
    func onTheDashboard() {
        #expect(CameraGrid.isOnScreen(size: tile, dashboard: dashboard(seenFrom: 0)))
        #expect(CameraGrid.isOnScreen(size: tile, dashboard: dashboard(seenFrom: 1536)))
        #expect(CameraGrid.isOnScreen(size: tile, dashboard: dashboard(seenFrom: 1920)))
    }

    @Test("one on the next page, or mostly past the edge mid-swipe, isn't")
    func offTheDashboard() {
        #expect(!CameraGrid.isOnScreen(size: tile, dashboard: dashboard(seenFrom: 2560 + 100)))
        #expect(!CameraGrid.isOnScreen(size: tile, dashboard: dashboard(seenFrom: 2560 - 200)))
        #expect(!CameraGrid.isOnScreen(size: tile, dashboard: dashboard(seenFrom: -500)))
    }

    @Test("outside a dashboard, as in the catalog's preview, it's on screen")
    func noDashboard() {
        #expect(CameraGrid.isOnScreen(size: tile, dashboard: nil))
    }
}
