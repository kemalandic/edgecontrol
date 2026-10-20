import Foundation
import Testing

@testable import EdgeControl

@Suite("Cameras: switching every few seconds")
struct CameraCycleTests {

    @Test("the next camera starts a few seconds before its turn")
    func startsEarly() {
        #expect(CameraCycle.step(sinceSwitch: 10, every: 30, nextPlaying: false) == .wait)
        #expect(CameraCycle.step(sinceSwitch: 23, every: 30, nextPlaying: false) == .startNext)
    }

    @Test("a camera that plays already is switched to on time, not before")
    func switchesOnTime() {
        #expect(CameraCycle.step(sinceSwitch: 29, every: 30, nextPlaying: true) == .startNext)
        #expect(CameraCycle.step(sinceSwitch: 30, every: 30, nextPlaying: true) == .switchToNext)
    }

    @Test("the switch waits for a slow camera, then moves on to show what's wrong")
    func waitsForSlowCamera() {
        #expect(CameraCycle.step(sinceSwitch: 35, every: 30, nextPlaying: false) == .startNext)
        #expect(
            CameraCycle.step(sinceSwitch: 30 + CameraCycle.patience, every: 30, nextPlaying: false) == .switchToNext)
    }

    @Test("switching quicker than a camera starts keeps the next one going all the time")
    func shortIntervals() {
        #expect(CameraCycle.step(sinceSwitch: 0, every: 5, nextPlaying: false) == .startNext)
    }
}
