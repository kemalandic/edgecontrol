import Foundation
import Testing
@testable import EdgeControl

/// `PluginManager.loadPlugin` refuses a widget whose `htmlFile` escapes the
/// plugin bundle. These tests exercise that guard against a real directory tree
/// rather than trusting the code to read correctly.
@MainActor
@Suite("Plugin bundle path containment")
struct PluginPathContainmentTests {

    /// Builds a plugin bundle on disk and returns its path plus the temporary
    /// root, so a caller can plant sibling directories next to it.
    private func makeBundle(
        root: URL,
        directoryName: String,
        pluginId: String,
        htmlFile: String,
        createHTMLInsideBundle: Bool = true
    ) throws -> URL {
        let bundle = root.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

        let manifest = """
        {
          "id": "\(pluginId)",
          "name": "Demo",
          "version": "1.0.0",
          "author": "Someone",
          "permissions": [],
          "widgets": [{
            "id": "demo",
            "name": "Demo Widget",
            "htmlFile": "\(htmlFile)",
            "supportedSizes": { "min": [2, 2], "max": [6, 4] },
            "defaultSize": [4, 3]
          }]
        }
        """
        try Data(manifest.utf8).write(to: bundle.appendingPathComponent("manifest.json"))

        if createHTMLInsideBundle {
            try Data("<html></html>".utf8).write(to: bundle.appendingPathComponent("index.html"))
        }
        return bundle
    }

    private func withTemporaryRoot(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginPathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    @Test("a plugin whose html sits inside its bundle loads")
    func wellFormedBundleLoads() throws {
        try withTemporaryRoot { root in
            let bundle = try makeBundle(root: root, directoryName: "demo.ecplugin",
                                        pluginId: "com.example.demo", htmlFile: "index.html")
            let manager = PluginManager()
            manager.loadPlugin(at: bundle)
            #expect(manager.errors.isEmpty, "unexpected errors: \(manager.errors)")
            #expect(manager.plugins.count == 1)
        }
    }

    @Test("an html path climbing out of the bundle is refused")
    func plainTraversalRefused() throws {
        try withTemporaryRoot { root in
            let bundle = try makeBundle(root: root, directoryName: "demo.ecplugin",
                                        pluginId: "com.example.demo",
                                        htmlFile: "../../../../etc/passwd")
            let manager = PluginManager()
            manager.loadPlugin(at: bundle)
            #expect(manager.plugins.isEmpty)
            #expect(manager.errors["com.example.demo"]?.contains("Invalid widget HTML path") == true,
                    "errors: \(manager.errors)")
        }
    }

    /// The containment check compares with `hasPrefix` against the bundle path
    /// and no trailing separator. A sibling directory whose name merely *starts*
    /// with the bundle's name therefore satisfies the prefix while living
    /// outside the bundle.
    @Test("a sibling directory sharing the bundle's name prefix is refused")
    func siblingPrefixIsRefused() throws {
        try withTemporaryRoot { root in
            // The victim bundle.
            let bundle = try makeBundle(
                root: root, directoryName: "demo.ecplugin", pluginId: "com.example.demo",
                htmlFile: "../demo.ecplugin-evil/steal.html")

            // A sibling that is NOT inside the bundle, but whose path begins with
            // the bundle's path as a string.
            let sibling = root.appendingPathComponent("demo.ecplugin-evil", isDirectory: true)
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            try Data("<html>outside the bundle</html>".utf8)
                .write(to: sibling.appendingPathComponent("steal.html"))

            let manager = PluginManager()
            manager.loadPlugin(at: bundle)

            #expect(manager.plugins.isEmpty,
                    "a plugin pointing outside its bundle was loaded")
            #expect(manager.errors["com.example.demo"]?.contains("Invalid widget HTML path") == true,
                    "errors: \(manager.errors)")
        }
    }

    @Test("a plugin id containing path separators is refused")
    func unsafePluginIdRefused() throws {
        try withTemporaryRoot { root in
            let bundle = try makeBundle(root: root, directoryName: "demo.ecplugin",
                                        pluginId: "../../escape", htmlFile: "index.html")
            let manager = PluginManager()
            manager.loadPlugin(at: bundle)
            #expect(manager.plugins.isEmpty)
            #expect(manager.errors.values.contains { $0.contains("Invalid plugin ID") },
                    "errors: \(manager.errors)")
        }
    }
}
