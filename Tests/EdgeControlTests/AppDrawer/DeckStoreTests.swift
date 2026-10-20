import Foundation
import Testing

@testable import EdgeControl

/// Decks.json in a folder another Mac may be writing to as well.
@MainActor
@Suite("App Drawer decks: the store")
struct DeckStoreTests {

    private func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeckStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func defaults() -> UserDefaults {
        let name = "DeckStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func store(_ folder: URL, legacy: DeckStore.Legacy = .init()) -> DeckStore {
        DeckStore(defaults: defaults(), defaultFolder: folder, legacy: legacy)
    }

    private func write(_ file: DeckFile, to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(file).write(to: folder.appendingPathComponent("Decks.json"))
    }

    @Test("an edit is saved to Decks.json")
    func editSaves() throws {
        let folder = scratch()
        let decks = store(folder)
        decks.loadIfNeeded()
        decks.edit("Main") { $0.keys.append(DeckKey(id: "k1", action: .app("com.apple.Notes"))) }
        decks.stopWatching()  // writes what's waiting
        let saved = try #require(DeckStore.read(folder.appendingPathComponent("Decks.json")))
        #expect(saved.decks["main"]?.keys.map(\.id) == ["k1"])
        #expect(saved.decks["main"]?.name == "Main")
        #expect((saved.decks["main"]?.updatedAt ?? 0) > 0)
    }

    @Test("the plugin helper's decks come in the first time, with their pictures")
    func importsHelperDecks() throws {
        let helper = scratch()
        try write(
            DeckFile(revision: 3, decks: ["main": Deck(name: "Main", keys: [DeckKey(id: "k", action: .wait())])]),
            to: helper)
        try FileManager.default.createDirectory(
            at: helper.appendingPathComponent("Icons"), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: helper.appendingPathComponent("Icons/a.png"))

        let folder = scratch()
        let decks = store(folder, legacy: .init(helperFolder: helper))
        decks.loadIfNeeded()
        #expect(decks.decks["main"]?.keys.map(\.id) == ["k"])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icons/a.png").path))
        #expect(decks.folder == folder)
    }

    @Test("a cloud folder the helper was pointed at is used as it is, so syncing carries on")
    func adoptsHelperCloudFolder() throws {
        let cloud = scratch()
        try write(DeckFile(revision: 1, decks: ["work": Deck(name: "Work")]), to: cloud)
        let decks = store(scratch(), legacy: .init(helperChosenFolder: cloud.path))
        decks.loadIfNeeded()
        #expect(decks.folder.standardizedFileURL == cloud.standardizedFileURL)
        #expect(decks.decks["work"] != nil)
    }

    @Test("App Drawer 1's picked apps become decks when there's nothing newer")
    func migratesManualSets() throws {
        let storage = scratch().appendingPathComponent("storage.json")
        let store = ["apps:main": ["com.apple.Notes", "com.apple.Safari"], "order:main": "name"] as [String: Any]
        try JSONSerialization.data(withJSONObject: store).write(to: storage)
        let decks = self.store(scratch(), legacy: .init(pluginStorage: storage))
        decks.loadIfNeeded()
        let deck = try #require(decks.decks["main"])
        #expect(deck.name == "Main")
        #expect(deck.order == .name)
        #expect(deck.keys.compactMap(\.action.bundleId) == ["com.apple.Notes", "com.apple.Safari"])
    }

    @Test("another Mac's change is merged deck by deck, newest wins")
    func mergesOtherMacs() throws {
        let folder = scratch()
        let decks = store(folder)
        decks.loadIfNeeded()
        decks.edit("mine") { $0.keys = [DeckKey(id: "a", action: .wait())] }
        decks.edit("shared") { $0.keys = [DeckKey(id: "old", action: .wait())] }
        decks.stopWatching()

        // The other Mac changes "shared" later, and adds "theirs".
        var disk = try #require(DeckStore.read(decks.fileURL))
        disk.decks["shared"]?.keys = [DeckKey(id: "new", action: .wait())]
        disk.decks["shared"]?.updatedAt += 1000
        disk.decks["theirs"] = Deck(name: "Theirs", updatedAt: 1)
        disk.decks["mine"] = nil
        // A newer modification date than the one this store last saw.
        try JSONEncoder().encode(disk).write(to: decks.fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: decks.fileURL.path)

        decks.checkFile()
        #expect(decks.decks["shared"]?.keys.map(\.id) == ["new"])
        #expect(decks.decks["theirs"] != nil)
        // Deleted there, and not changed here since: gone here too.
        #expect(decks.decks["mine"] == nil)
    }

    @Test("moving to a folder with decks of its own can use both, newest winning")
    func movesAndAdopts() throws {
        let decks = store(scratch())
        decks.loadIfNeeded()
        decks.edit("main") { $0.keys = [DeckKey(id: "here", action: .wait())] }
        let cloud = scratch()
        try write(
            DeckFile(revision: 1, decks: ["main": Deck(updatedAt: 1, keys: []), "other": Deck(updatedAt: 1)]), to: cloud
        )

        #expect(decks.folderHasDecks(cloud))
        try decks.move(to: cloud, adopt: true)
        #expect(decks.decks["main"]?.keys.map(\.id) == ["here"])
        #expect(decks.decks["other"] != nil)
        #expect(DeckStore.read(cloud.appendingPathComponent("Decks.json"))?.decks["main"]?.keys.first?.id == "here")
    }

    @Test("pictures are kept inside the decks folder")
    func pictureURLs() {
        let folder = scratch()
        let decks = store(folder)
        #expect(decks.pictureURL("image:Icons/a.png") == folder.appendingPathComponent("Icons/a.png"))
        #expect(decks.pictureURL("image:Icons/../../secret") == nil)
        #expect(decks.pictureURL("symbol:star") == nil)
    }
}
