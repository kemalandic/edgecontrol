import CoreGraphics
import Testing
@testable import EdgeControl

@MainActor
@Suite("Touch zone layers")
struct TouchZoneLayerTests {
    @Test("the smallest zone under a finger wins, as before")
    func smallestWins() {
        let registry = TouchZoneRegistry()
        var hit = ""
        registry.register(id: "card", frame: CGRect(x: 0, y: 0, width: 400, height: 300)) {
            MainActor.assumeIsolated { hit = "card" }
        }
        registry.register(id: "button", frame: CGRect(x: 10, y: 10, width: 40, height: 40)) {
            MainActor.assumeIsolated { hit = "button" }
        }
        #expect(registry.handleTap(at: CGPoint(x: 20, y: 20)))
        #expect(hit == "button")
    }

    @Test("while something is drawn over the dashboard, nothing beneath it can be hit")
    func overlayBlocks() {
        let registry = TouchZoneRegistry()
        var hits: [String] = []
        registry.register(id: "widget-button", frame: CGRect(x: 10, y: 10, width: 40, height: 40)) {
            MainActor.assumeIsolated { hits.append("widget") }
        }
        registry.register(id: "overlay", frame: CGRect(x: 0, y: 0, width: 2560, height: 720), layer: 1) {
            MainActor.assumeIsolated { hits.append("overlay") }
        }
        registry.register(id: "close", frame: CGRect(x: 2480, y: 20, width: 60, height: 60), layer: 1) {
            MainActor.assumeIsolated { hits.append("close") }
        }

        #expect(registry.topLayer == 1)
        _ = registry.handleTap(at: CGPoint(x: 20, y: 20))
        _ = registry.handleTap(at: CGPoint(x: 2500, y: 40))
        #expect(hits == ["overlay", "close"])

        registry.unregister(id: "overlay")
        registry.unregister(id: "close")
        #expect(registry.topLayer == 0)
        _ = registry.handleTap(at: CGPoint(x: 20, y: 20))
        #expect(hits.last == "widget")
    }
}
