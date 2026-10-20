import CoreGraphics
import Foundation
import Testing

@testable import EdgeControl

@Suite("App Drawer: apps, usage, layout and keys")
struct AppDrawerCatalogTests {

    // MARK: - Shortcuts and the Dock

    @Test("Shortcuts are read from `shortcuts list --show-identifiers`")
    func parsesShortcuts() {
        let output = """
            Start Screen Saver (4D5D07DD-0680-420E-8011-70BBA5F51A04)
            Morning (Work) (11111111-2222-3333-4444-555555555555)
            Not a shortcut line
            Short id (1234)
            """
        let list = AppCatalog.parseShortcuts(output)
        #expect(list.map(\.name) == ["Start Screen Saver", "Morning (Work)"])
        #expect(list.first?.id == "4D5D07DD-0680-420E-8011-70BBA5F51A04")
    }

    @Test("the Dock's tiles give their bundle ids, from the tile or its app")
    func readsDockTiles() {
        let items: [[String: Any]] = [
            ["tile-data": ["bundle-identifier": "com.apple.Safari"]],
            ["tile-data": ["file-data": ["_CFURLString": "file:///System/Applications/Notes.app/"]]],
            ["tile-data": [:] as [String: Any]],
            ["spacer": true],
        ]
        #expect(AppCatalog.dockBundleIds(items) == ["com.apple.Safari", "com.apple.Notes"])
    }

    // MARK: - Usage

    @Test("time in front fades by half every 14 days")
    func usageDecays() {
        var usage = AppUsage()
        usage.add(seconds: 100, at: 1000)
        #expect(usage.decayedScore(at: 1000) == 100)
        #expect(abs(usage.decayedScore(at: 1000 + AppUsage.halfLife) - 50) < 0.001)
    }

    @Test("the ledger counts time in front, and not EdgeControl's")
    func ledgerCountsFront() {
        var ledger = UsageLedger()
        ledger.open("com.apple.Notes", at: 0)
        ledger.open("ai.pakslab.edgecontrol", at: 60)
        ledger.open("com.apple.Safari", at: 120)
        ledger.close(at: 150)
        #expect(ledger.entries["com.apple.Notes"]?.score == 60)
        #expect(ledger.entries["com.apple.Safari"]?.score == 30)
        #expect(ledger.entries["com.apple.Safari"]?.activations == 1)
        #expect(ledger.entries["ai.pakslab.edgecontrol"] == nil)
    }

    @Test("most used and recent come from time in front and Spotlight's history")
    func rankings() {
        let url = URL(fileURLWithPath: "/Applications/X.app")
        let apps = [
            "a": DrawerApp(
                bundleId: "a", name: "A", url: url, spotlightLastUsed: Date(timeIntervalSince1970: 500),
                spotlightUseCount: 10),
            "b": DrawerApp(bundleId: "b", name: "B", url: url, spotlightLastUsed: nil, spotlightUseCount: 0),
            "c": DrawerApp(bundleId: "c", name: "C", url: url, spotlightLastUsed: nil, spotlightUseCount: 0),
        ]
        var ledger = UsageLedger()
        ledger.open("b", at: 1000)
        ledger.close(at: 2000)
        let ranked = ledger.rankings(apps, at: 2000)
        // a: ten uses count as ten minutes; b: 1,000 seconds in front.
        #expect(ranked.most == ["b", "a"])
        #expect(ranked.recent == ["b", "a"])
    }

    // MARK: - Layout

    private func fit(_ count: Int, _ width: CGFloat, _ height: CGFloat, keys: Bool = false) -> DrawerLayout {
        DrawerLayout.fit(
            count: count, width: width, height: height, gap: 6, keys: keys, showNames: true, showRunning: true,
            fixedIcon: nil)
    }

    @Test("a wide, short tile puts its apps in one row")
    func oneRow() {
        let layout = fit(10, 1000, 110)
        #expect(layout.rows == 1)
        #expect(layout.columns == 10)
        #expect(layout.icon > 40)
    }

    @Test("a taller tile uses rows to make icons bigger")
    func rows() {
        let layout = fit(16, 800, 260)
        #expect(layout.rows == 2)
        #expect(layout.columns == 8)
    }

    @Test("more apps than fit make a page of them")
    func pages() {
        let layout = fit(200, 400, 100)
        #expect(layout.perPage < 200)
        #expect(layout.perPage >= 1)
    }

    @Test("keys are square, with the icon half the key")
    func keys() {
        let layout = fit(6, 600, 200, keys: true)
        #expect(layout.key > 0)
        #expect(layout.icon == (layout.key * 0.5).rounded())
    }

    // MARK: - Settings and colors

    @Test("App Drawer 1's Manual mode is Deck mode")
    func manualIsDeck() {
        #expect(DrawerSettings(WidgetConfig(["mode": .string("Manual")])).mode == .deck)
        #expect(DrawerSettings(WidgetConfig(["mode": .string("Nonsense")])).mode == .dock)
        #expect(DrawerSettings(WidgetConfig(["deck": .string("  ")])).deckName == "Main")
    }

    @Test(
        "ink is near-black on light colors and white on dark or see-through ones",
        arguments: [
            (0.96, 0.77, 0.09, 1.0, true), (1.0, 1.0, 1.0, 1.0, true), (0.2, 0.5, 1.0, 1.0, false),
            (1.0, 1.0, 1.0, 0.1, false),
        ])
    func ink(red: Double, green: Double, blue: Double, alpha: Double, light: Bool) {
        #expect(Ink.isLight(red: red, green: green, blue: blue, alpha: alpha) == light)
    }

    // MARK: - Keyboard keys

    @MainActor
    @Test("typing goes a few characters to an event, with returns and tabs as keys")
    func typingPlan() {
        let plan = KeyRunner.typingPlan("Hi\tthere\nThis line is longer than twenty characters")
        #expect(plan[0] == .characters(Array("Hi".utf16)))
        #expect(plan[1] == .key(48))
        #expect(plan[2] == .characters(Array("there".utf16)))
        #expect(plan[3] == .key(36))
        let rest = plan.dropFirst(4).compactMap { step -> [UniChar]? in
            if case .characters(let units) = step { return units }
            return nil
        }
        #expect(rest.allSatisfy { $0.count <= 20 })
        #expect(String(decoding: rest.flatMap { $0 }, as: UTF16.self) == "This line is longer than twenty characters")
    }

    @MainActor
    @Test("arrow keys carry the flags a real keyboard sends")
    func hotkeyFlags() {
        let up = KeyRunner.flags(keyCode: 126, modifiers: ["control"])
        #expect(up.contains(.maskControl))
        #expect(up.contains(.maskSecondaryFn))
        let copy = KeyRunner.flags(keyCode: 8, modifiers: ["command"])
        #expect(copy == .maskCommand)
    }

    @Test("search finds every word, or the letters with the spaces taken out")
    func search() {
        #expect(DrawerPicker.matches("Visual Studio Code", query: "studio vis"))
        #expect(DrawerPicker.matches("Visual Studio Code", query: "visualstudio"))
        #expect(!DrawerPicker.matches("Visual Studio Code", query: "xcode"))
        #expect(DrawerPicker.matches("Anything", query: "  "))
    }
}
