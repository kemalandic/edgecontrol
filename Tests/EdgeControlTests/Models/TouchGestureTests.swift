import CoreGraphics
import Testing
@testable import EdgeControl

@Suite("Touch gestures")
struct TouchGestureTests {
    private let start = CGPoint(x: 400, y: 300)

    @Test("a finger that lifts where it went down is a tap")
    func tap() {
        var g = TouchGesture()
        _ = g.began(at: start, time: 0)
        #expect(g.moved(to: CGPoint(x: 403, y: 302), time: 0.05).isEmpty)
        #expect(g.ended(at: CGPoint(x: 403, y: 302), time: 0.12) == [.tap(start)])
        #expect(g.isIdle)
    }

    @Test("a finger that rests presses where it went down, then drags and releases")
    func press() {
        var g = TouchGesture()
        _ = g.began(at: start, time: 0)
        #expect(g.holdElapsed(time: 0.29).isEmpty)
        #expect(g.holdElapsed(time: 0.3) == [.pressBegan(start)])
        #expect(g.moved(to: CGPoint(x: 500, y: 300), time: 0.5) == [.pressMoved(CGPoint(x: 500, y: 300))])
        #expect(g.ended(at: CGPoint(x: 500, y: 300), time: 0.7) == [.pressEnded(CGPoint(x: 500, y: 300))])
    }

    @Test("a rest the timer didn't get to is still a press")
    func lateTimer() {
        var g = TouchGesture()
        _ = g.began(at: start, time: 0)
        #expect(
            g.moved(to: CGPoint(x: 440, y: 300), time: 0.4) == [
                .pressBegan(start), .pressMoved(CGPoint(x: 440, y: 300)),
            ])

        var held = TouchGesture()
        _ = held.began(at: start, time: 0)
        #expect(held.ended(at: start, time: 0.8) == [.pressBegan(start), .pressEnded(start)])
    }

    @Test("a quick sideways move pages, measured from where the finger went down")
    func paging() {
        var g = TouchGesture()
        _ = g.began(at: start, time: 0)
        #expect(g.moved(to: CGPoint(x: 380, y: 302), time: 0.05) == [.paging(dx: -20)])
        #expect(g.moved(to: CGPoint(x: 250, y: 310), time: 0.15) == [.paging(dx: -150)])
        #expect(g.holdElapsed(time: 0.4).isEmpty)
        #expect(g.ended(at: CGPoint(x: 240, y: 310), time: 0.2) == [.pageEnded(dx: -160)])
    }

    @Test("a quick move up or down scrolls, in steps from the last point")
    func scrolling() {
        var g = TouchGesture()
        _ = g.began(at: start, time: 0)
        #expect(
            g.moved(to: CGPoint(x: 402, y: 280), time: 0.05)
                == [.scrollBegan(start), .scrolled(dx: 2, dy: -20, at: CGPoint(x: 402, y: 280))])
        #expect(
            g.moved(to: CGPoint(x: 402, y: 250), time: 0.1) == [.scrolled(dx: 0, dy: -30, at: CGPoint(x: 402, y: 250))])
        #expect(g.ended(at: CGPoint(x: 402, y: 250), time: 0.2) == [.scrollEnded(CGPoint(x: 402, y: 250))])
    }

    @Test("small jitter while resting doesn't stop a press")
    func jitter() {
        var g = TouchGesture()
        _ = g.began(at: start, time: 0)
        #expect(g.moved(to: CGPoint(x: 404, y: 305), time: 0.1).isEmpty)
        #expect(g.holdElapsed(time: 0.31) == [.pressBegan(start)])
    }

    @Test("the panel's own range maps corner to corner, with no calibration")
    func mapping() {
        let mapping = PanelMapping()
        let size = CGSize(width: 2560, height: 720)
        #expect(mapping.point(x: 0, y: 0, in: size) == .zero)
        #expect(mapping.point(x: 16_383, y: 9_599, in: size) == CGPoint(x: 2560, y: 720))
        #expect(mapping.point(x: 99_999, y: -5, in: size) == CGPoint(x: 2560, y: 0))
        let middle = mapping.point(x: 8_192, y: 4_800, in: size)
        #expect(abs(middle.x - 1280) < 1 && abs(middle.y - 360) < 1)
    }
}
