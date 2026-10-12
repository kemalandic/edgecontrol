import Foundation
import Testing

@testable import EdgeControl

/// Recovering the user's layout when a file can't be read, and checking an
/// imported one before it replaces the current layout. Runs in a scratch
/// directory, never the real layout.
@Suite("Layout recovery and import")
struct LayoutRecoveryTests {
    let directory: URL
    var layoutURL: URL { directory.appendingPathComponent("layout.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LayoutRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func write(_ json: String) throws { try Data(json.utf8).write(to: layoutURL) }
    private func files(_ prefix: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasPrefix(prefix) }
    }
    private func failure(_ result: Result<LayoutDocument, LayoutStore.ImportError>) -> LayoutStore.ImportError? {
        if case .failure(let error) = result { error } else { nil }
    }

    static let good = """
        {"version":1,"pages":[{"id":"mine","name":"Mine","order":0,"widgets":[
          {"instanceId":"x","widgetId":"weather","col":0,"row":0,"width":6,"height":6,"config":{"storage":{}}}]}]}
        """

    @Test("one unreadable widget, page or setting doesn't reset the whole layout")
    func lenientDecoding() throws {
        let mixed = """
            {"version":1,"pages":[
              {"id":"p1","name":"Home","order":0,"widgets":[
                {"instanceId":"a","widgetId":"cpu-gauge","col":0,"row":0,"width":4,"height":3,"config":7},
                {"instanceId":"b","widgetId":"broken","col":"zero"}]},
              "not a page"],
             "globalSettings":{"debugMode":"yes","strictMonitorAffinity":true,
               "theme":{"fontFamily":"comic-sans-2030","fontScale":1.2}}}
            """
        let doc = try JSONDecoder().decode(LayoutDocument.self, from: Data(mixed.utf8))
        #expect(doc.pages.map(\.id) == ["p1"])
        #expect(doc.pages.first?.widgets.map(\.instanceId) == ["a"])
        #expect(doc.pages.first?.widgets.first?.config.isEmpty == true)
        #expect(doc.globalSettings.strictMonitorAffinity && !doc.globalSettings.debugMode)
        #expect(doc.globalSettings.theme.fontScale == 1.2)
        #expect(doc.globalSettings.theme.fontFamily == ThemeSettings().fontFamily)
        #expect(LayoutValidation.decode(Data(mixed.utf8))?.clean == false)
    }

    @Test("an unreadable layout is replaced by the last copy that loaded, not the defaults")
    func restoresLastGoodCopy() throws {
        let store = LayoutStore(directory: directory)
        try write(Self.good)
        #expect(store.load().pages.map(\.id) == ["mine"])
        #expect(files("layout.json.bak").count == 1)

        try write("{ not json")
        #expect(store.load().pages.map(\.id) == ["mine"])
        try write("[1, 2")
        #expect(store.load().pages.map(\.id) == ["mine"])
        #expect(files("layout-unreadable-").count == 2)
    }

    @Test("a layout from a newer version is used but never saved over")
    func protectsNewerVersion() throws {
        let store = LayoutStore(directory: directory)
        try write(#"{"version":9,"pages":[{"id":"future","name":"F","order":0,"widgets":[]}]}"#)
        let before = try Data(contentsOf: layoutURL)
        let doc = store.load()
        #expect(doc.pages.map(\.id) == ["future"])
        #expect(store.isProtectingFile)
        #expect(!store.save(doc))
        #expect(try Data(contentsOf: layoutURL) == before)
    }

    @Test("imports that aren't complete, valid layouts are refused")
    func refusesBadImports() throws {
        let store = LayoutStore(directory: directory)
        try write(Self.good)
        _ = store.load()
        let before = try Data(contentsOf: layoutURL)
        for bad in ["{}", "hello", #"{"version":1,"pages":[]}"#, #"{"version":1,"pages":[{}]}"#,
                    #"{"version":1,"pages":[{"id":"d","name":"D","order":0,"widgets":"damaged"}]}"#,
                    #"{"version":1,"pages":[{"id":"d","name":"D","order":0,"widgets":[{"instanceId":"i","widgetId":"w","col":0,"row":0,"width":-2,"height":2,"config":{"storage":{}}}]}]}"#]
        {
            #expect(failure(store.importData(Data(bad.utf8))) == .notALayout, "\(bad)")
        }
        #expect(failure(store.importData(Data(#"{"version":99,"pages":[{"id":"n","name":"N","order":0,"widgets":[]}]}"#.utf8)))
                == .newerVersion(99))
        #expect(try Data(contentsOf: layoutURL) == before)
    }

    @Test("a valid import keeps the layout on screen as layout-before-import.json")
    func importKeepsPrevious() throws {
        let store = LayoutStore(directory: directory)
        try write(Self.good)
        _ = store.load()
        let live = LayoutDocument(pages: [PageConfig(id: "live", name: "On screen", order: 0)])
        let result = store.importData(
            Data(#"{"version":1,"pages":[{"id":"new","name":"New","order":0,"widgets":[]}]}"#.utf8), current: live)
        #expect(failure(result) == nil)
        #expect(store.load().pages.map(\.id) == ["new"])
        let kept = try JSONDecoder().decode(LayoutDocument.self, from: Data(contentsOf: store.preImportURL))
        #expect(kept.pages.map(\.id) == ["live"])
    }
}
