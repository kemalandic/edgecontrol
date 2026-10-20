import Foundation
import Testing

@testable import EdgeControl

/// Decks.json is shared with the App Drawer plugin's helper, and with other
/// Macs through a synced folder, so the format has to read what they wrote
/// and keep what it doesn't understand.
@Suite("App Drawer decks: the file format")
struct DeckModelTests {

    /// As the plugin's helper wrote it, with a key type and a field this
    /// version doesn't know, and a key missing its action.
    static let helperFile = """
        {
          "version": 1,
          "revision": 7,
          "decks": {
            "main": {
              "name": "Main",
              "order": "type",
              "updatedAt": 1791558461478,
              "keys": [
                { "id": "k1", "title": "Safari", "color": "#3380FF",
                  "action": { "type": "app", "bundleId": "com.apple.Safari" } },
                { "id": "k2", "icon": "symbol:sparkles",
                  "action": { "type": "shortcut", "id": "4D5D07DD-0680-420E-8011-70BBA5F51A04", "name": "Start Screen Saver" },
                  "hold": { "type": "media", "key": "next" } },
                { "id": "k3", "action": { "type": "teleport", "where": "moon", "speed": 3 } },
                { "id": "k4", "title": "No action" },
                { "id": "k5", "title": "Work",
                  "action": { "type": "folder", "keys": [
                    { "id": "k6", "action": { "type": "hotkey", "keyCode": 21, "modifiers": ["shift", "command"], "display": "⇧⌘4" } }
                  ] } }
              ]
            }
          }
        }
        """

    private func decode(_ json: String) throws -> DeckFile {
        try JSONDecoder().decode(DeckFile.self, from: Data(json.utf8))
    }

    @Test("the helper's file reads, and a key without an action is skipped, not the deck")
    func readsHelperFile() throws {
        let file = try decode(Self.helperFile)
        let deck = try #require(file.decks["main"])
        #expect(file.revision == 7)
        #expect(deck.order == .type)
        #expect(deck.updatedAt == 1_791_558_461_478)
        #expect(deck.keys.map(\.id) == ["k1", "k2", "k3", "k5"])
        #expect(deck.keys[1].action.shortcutId == "4D5D07DD-0680-420E-8011-70BBA5F51A04")
        #expect(deck.keys[1].hold?.key == "next")
        #expect(deck.keys[3].action.keys?.first?.action.keyCode == 21)
    }

    @Test("a key type and fields this version doesn't know survive a save")
    func keepsUnknownFields() throws {
        let file = try decode(Self.helperFile)
        let encoded = try JSONEncoder().encode(file)
        let again = try JSONDecoder().decode(DeckFile.self, from: encoded)
        let teleport = try #require(again.decks["main"]?.keys.first { $0.id == "k3" }?.action)
        #expect(teleport.type == "teleport")
        #expect(teleport.kind == nil)
        #expect(teleport.extra["where"] == .string("moon"))
        #expect(teleport.extra["speed"] == .number(3))
        // The shortcut's id goes back out as "id", where the helper reads it.
        let raw = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let decks = try #require(raw["decks"] as? [String: Any])
        let keys = try #require((decks["main"] as? [String: Any])?["keys"] as? [[String: Any]])
        #expect((keys[1]["action"] as? [String: Any])?["id"] as? String == "4D5D07DD-0680-420E-8011-70BBA5F51A04")
    }

    @Test("a deck that isn't an object is skipped, not the file")
    func skipsBadDeck() throws {
        let file = try decode(#"{ "revision": 1, "decks": { "main": { "keys": [] }, "broken": 42 } }"#)
        #expect(Array(file.decks.keys) == ["main"])
    }

    // MARK: - Keeping decks a sensible shape

    @Test("colors, icons and titles that aren't the right shape are dropped or cut")
    func sanitizesKeys() {
        var key = DeckKey(id: "k", title: String(repeating: "x", count: 200), color: "red", action: .link("https://a"))
        key.icon = "image:Icons/../../etc/passwd"
        let deck = Deck(keys: [key]).sanitized()
        #expect(deck.keys[0].color == nil)
        #expect(deck.keys[0].icon == nil)
        #expect(deck.keys[0].title?.count == 80)
    }

    @Test(
        "icons",
        arguments: [
            ("symbol:star.fill", true), ("symbol:", false), ("symbol:star fill", false), ("emoji:🚀", true),
            ("emoji:🚀🚀🚀🚀🚀", false), ("image:Icons/a.png", true), ("image:Icons/sub/a.png", false),
            ("image:a.png", false), ("app:com.apple.Notes", true), ("app:", false), ("other:x", false),
        ])
    func iconSpecs(icon: String, valid: Bool) {
        #expect(DeckKey.isIconSpec(icon) == valid)
    }

    @Test("holding a key can't open a folder")
    func holdIsNeverAFolder() {
        let deck = Deck(keys: [DeckKey(id: "k", action: .link("https://a"), hold: .folder())]).sanitized()
        #expect(deck.keys[0].hold == nil)
    }

    @Test("a multi-action keeps up to 20 steps, none of them folders or multi-actions")
    func sanitizesSteps() {
        let steps = [KeyAction.folder(), .multi(), .wait(1)] + Array(repeating: KeyAction.link("https://a"), count: 30)
        let deck = Deck(keys: [DeckKey(id: "k", action: .multi(steps))]).sanitized()
        let kept = deck.keys[0].action.steps ?? []
        #expect(kept.count == 20)
        #expect(kept.first?.kind == .wait)
        #expect(!kept.contains { $0.kind == .folder || $0.kind == .multi })
    }

    @Test("a deck holds at most 500 keys, and folders nest at most four deep")
    func limitsSize() {
        let many = Deck(keys: (0..<600).map { DeckKey(id: "k\($0)", action: .link("https://a")) }).sanitized()
        #expect(many.keys.count == Deck.maxKeys)

        var nested = DeckKey(id: "deepest", action: .link("https://a"))
        for level in 0..<6 { nested = DeckKey(id: "f\(level)", action: .folder([nested])) }
        let deck = Deck(keys: [nested]).sanitized()
        #expect(deck.keys.find("deepest") == nil)
        #expect(deck.keys.find("f2") != nil)
    }

    // MARK: - Order and folders

    private let keys = [
        DeckKey(id: "notes", action: .app("com.apple.Notes")),
        DeckKey(id: "link", action: .link("https://example.com")),
        DeckKey(id: "folder", title: "Zed", action: .folder()),
        DeckKey(id: "safari", action: .app("com.apple.Safari")),
    ]
    private let names = ["com.apple.Notes": "Notes", "com.apple.Safari": "Safari"]

    private func arrange(_ order: DeckOrder, ranks: [String: Int] = [:]) -> [String] {
        order.arrange(keys, title: { $0.title(appName: { names[$0] }) }, appRank: { ranks[$0] }).map(\.id)
    }

    @Test("orders")
    func orders() {
        #expect(arrange(.manual) == ["notes", "link", "folder", "safari"])
        #expect(arrange(.name) == ["link", "notes", "safari", "folder"])
        #expect(arrange(.type) == ["folder", "notes", "safari", "link"])
        // Apps by rank first, then the rest by name.
        #expect(
            arrange(.most, ranks: ["com.apple.Safari": 0, "com.apple.Notes": 3]) == [
                "safari", "notes", "link", "folder",
            ])
    }

    @Test("dragging a key puts it just before or after the one it's dropped on")
    func dragging() {
        let ids = ["a", "b", "c", "d"]
        #expect(DeckEditorModel.reordered(ids, moving: "a", to: "c", after: false) == ["b", "a", "c", "d"])
        #expect(DeckEditorModel.reordered(ids, moving: "a", to: "c", after: true) == ["b", "c", "a", "d"])
        #expect(DeckEditorModel.reordered(ids, moving: "d", to: "a", after: false) == ["d", "a", "b", "c"])
        #expect(DeckEditorModel.reordered(ids, moving: "b", to: "d", after: true) == ["a", "c", "d", "b"])
    }

    @Test("a drop that wouldn't move anything, or of something that isn't a key here, does nothing")
    func draggingNowhere() {
        let ids = ["a", "b", "c"]
        #expect(DeckEditorModel.reordered(ids, moving: "b", to: "b", after: true) == nil)
        #expect(DeckEditorModel.reordered(ids, moving: "b", to: "c", after: false) == nil)
        #expect(DeckEditorModel.reordered(ids, moving: "b", to: "a", after: true) == nil)
        #expect(DeckEditorModel.reordered(ids, moving: "some text", to: "a", after: false) == nil)
    }

    @Test("a level inside folders can be read and changed, and keys found and removed at any depth")
    func levels() {
        var keys = [DeckKey(id: "a", action: .folder([DeckKey(id: "b", action: .folder())]))]
        keys.editLevel(["a", "b"]) { $0.append(DeckKey(id: "c", action: .link("https://c"))) }
        #expect(keys.level(["a", "b"]).map(\.id) == ["c"])
        #expect(keys.level(["missing"]).isEmpty)
        #expect(keys.update("c") { $0.title = "C" })
        #expect(keys.find("c")?.title == "C")
        #expect(keys.totalCount == 3)
        keys.remove("c")
        #expect(keys.find("c") == nil)
    }

    // MARK: - Names

    @Test("what keys are called when they have no title")
    func defaultTitles() {
        let name: (String) -> String? = { _ in nil }
        #expect(KeyAction.link("https://www.example.com/x").defaultTitle(appName: name) == "example.com")
        #expect(KeyAction.file("/Users/me/Report.pdf").defaultTitle(appName: name) == "Report.pdf")
        #expect(KeyAction.media(.next).defaultTitle(appName: name) == "Next track")
        #expect(
            KeyAction.text("Thanks, talk soon! See you", typed: true).defaultTitle(appName: name)
                == "Thanks, talk soon! See y")
        #expect(KeyAction(.hotkey).defaultTitle(appName: name) == "Hotkey")
    }

    @Test("which keys need Accessibility")
    func eventAccess() {
        #expect(KeyAction(.hotkey).needsEventAccess)
        #expect(KeyAction.media(.mute).needsEventAccess)
        #expect(KeyAction.text("x", typed: true).needsEventAccess)
        #expect(!KeyAction.text("x").needsEventAccess)
        #expect(KeyAction.multi([.wait(), .media(.next)]).needsEventAccess)
        #expect(!KeyAction.multi([.wait(), .link("https://a")]).needsEventAccess)
    }

    @Test("how hotkeys read: modifiers in the system's order, then the key")
    func hotkeyDisplay() {
        #expect(HotkeyPreset.display(keyCode: 21, modifiers: ["command", "shift"]) == "⇧⌘4")
        #expect(HotkeyPreset.display(keyCode: 126, modifiers: ["control"]) == "⌃↑")
        #expect(HotkeyPreset.display(keyCode: 49, modifiers: ["control", "command"]) == "⌃⌘Space")
        #expect(HotkeyPreset.display(keyCode: 200, modifiers: []) == "Key 200")
    }
}
