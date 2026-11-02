import CoreGraphics
import Testing

@testable import EdgeControl

@Suite("Windows behind the dashboard")
struct WindowRescueTests {
    // Two 2560×1440 displays side by side, and a 2560×720 dashboard above the
    // right one, as AppKit measures them.
    private let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let right = CGRect(x: 2560, y: 0, width: 2560, height: 1440)
    private let dashboard = CGRect(x: 2560, y: 1440, width: 2560, height: 720)

    @Test("a window behind the dashboard goes to the middle of the target, whole")
    func centred() {
        let window = CGRect(x: 3000, y: 1500, width: 800, height: 600)
        #expect(
            WindowRescueService.destination(of: window, dashboard: dashboard, target: main)
                == CGRect(x: 880, y: 420, width: 800, height: 600))
    }

    @Test("one bigger than the target is shrunk to fit it")
    func shrunk() {
        let window = CGRect(x: 2600, y: 1000, width: 3000, height: 1600)
        #expect(
            WindowRescueService.destination(of: window, dashboard: dashboard, target: main)
                == CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    @Test("a window mostly on another display stays put")
    func notBehind() {
        let overlapping = CGRect(x: 2600, y: 1000, width: 800, height: 600)
        #expect(WindowRescueService.destination(of: overlapping, dashboard: dashboard, target: main) == nil)
        let elsewhere = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(WindowRescueService.destination(of: elsewhere, dashboard: dashboard, target: main) == nil)
    }

    @Test("windows go to the display under the pointer")
    func pointerScreen() {
        #expect(
            WindowRescueService.targetScreen(
                pointer: CGPoint(x: 3000, y: 700), screens: [main, right, dashboard], dashboard: dashboard) == right)
    }

    @Test("with the pointer on the dashboard, they go to the menu bar's display")
    func pointerOnDashboard() {
        #expect(
            WindowRescueService.targetScreen(
                pointer: CGPoint(x: 3000, y: 1800), screens: [main, right, dashboard], dashboard: dashboard) == main)
        // Unless the dashboard is on the menu bar's display.
        #expect(
            WindowRescueService.targetScreen(
                pointer: CGPoint(x: 100, y: 100), screens: [main, right], dashboard: main) == right)
    }

    @Test("with only the dashboard's display, there's nowhere to go")
    func nowhere() {
        #expect(
            WindowRescueService.targetScreen(pointer: .zero, screens: [dashboard], dashboard: dashboard) == nil)
    }
}
