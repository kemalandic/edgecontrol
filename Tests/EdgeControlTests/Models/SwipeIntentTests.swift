import CoreGraphics
import Testing
@testable import EdgeControl

@Suite("Swipe or hold")
struct SwipeIntentTests {
    private func intent(_ samples: [(distance: CGFloat, elapsed: Double)]) -> SwipeIntent {
        var intent = SwipeIntent()
        for sample in samples { intent.track(distanceFromStart: sample.distance, elapsed: sample.elapsed) }
        return intent
    }

    @Test("a finger that moves straight away is a swipe, however long it then takes")
    func swipe() {
        #expect(!intent([(2, 0.02), (10, 0.08), (60, 0.2), (240, 0.6)]).isHold)
    }

    @Test("a finger that rests before moving is holding, and stays holding as it drags")
    func hold() {
        #expect(intent([(1, 0.1), (3, 0.31), (80, 0.5)]).isHold)
    }

    @Test("a rest with no samples in between still counts: the first move after it is a drag")
    func restWithoutSamples() {
        #expect(intent([(40, 0.45)]).isHold)
    }

    @Test("jitter within the still radius doesn't make a swipe")
    func jitter() {
        #expect(intent([(4, 0.05), (7, 0.15), (5, 0.32)]).isHold)
    }
}
