import Foundation
import Testing
@testable import EdgeControl

/// The plugin system runs third-party HTML and JS described by this manifest.
/// It is the only place in the app where data someone else authored crosses
/// into typed Swift, so these tests ask "does it fail safely", not "does it
/// work". See D6 in the test-infrastructure design.
@Suite("Plugin manifest — untrusted input")
struct PluginManifestTests {

    private func decode(_ json: String) throws -> PluginManifest {
        try JSONDecoder().decode(PluginManifest.self, from: Data(json.utf8))
    }

    private let wellFormed = """
    {
      "id": "com.example.demo",
      "name": "Demo",
      "version": "1.0.0",
      "author": "Someone",
      "permissions": ["system-metrics"],
      "widgets": [{
        "id": "demo",
        "name": "Demo Widget",
        "htmlFile": "index.html",
        "supportedSizes": { "min": [2, 2], "max": [6, 4] },
        "defaultSize": [4, 3]
      }]
    }
    """

    // MARK: the happy path, so the adversarial cases mean something

    @Test("a well-formed manifest decodes")
    func wellFormedDecodes() throws {
        let m = try decode(wellFormed)
        #expect(m.id == "com.example.demo")
        #expect(m.widgets.count == 1)
        #expect(m.widgets[0].widgetSize == .size(4, 3))
        #expect(m.widgets[0].sizeRange.min == .size(2, 2))
        #expect(m.widgets[0].sizeRange.max == .size(6, 4))
    }

    // MARK: malformed structure

    @Test("empty input is rejected")
    func emptyInputRejected() {
        #expect(throws: (any Error).self) { try decode("") }
    }

    @Test("truncated JSON is rejected")
    func truncatedRejected() {
        #expect(throws: (any Error).self) { try decode(#"{"id": "com.example.demo""#) }
    }

    @Test("a JSON array where an object is expected is rejected")
    func arrayInsteadOfObjectRejected() {
        #expect(throws: (any Error).self) { try decode("[]") }
    }

    @Test("each required field is genuinely required",
          arguments: ["id", "name", "version", "author", "widgets"])
    func requiredFieldsAreRequired(field: String) throws {
        var object = try JSONSerialization.jsonObject(with: Data(wellFormed.utf8)) as! [String: Any]
        object.removeValue(forKey: field)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(PluginManifest.self, from: data)
        }
    }

    @Test("a string where a list is expected is rejected")
    func wrongTypeRejected() {
        let json = wellFormed.replacingOccurrences(of: "\"widgets\": [", with: "\"widgets\": \"")
        #expect(throws: (any Error).self) { try decode(json) }
    }

    // MARK: sizes — the array indexing that a hostile manifest would aim at

    /// `widgetSize` and `sizeRange` read fixed positions out of arrays the
    /// plugin author supplies. Short or empty arrays must fall back, never trap.
    @Test("short and empty size arrays fall back instead of trapping",
          arguments: ["[]", "[7]"])
    func shortSizeArraysFallBack(defaultSize: String) throws {
        let json = wellFormed.replacingOccurrences(of: "\"defaultSize\": [4, 3]",
                                                   with: "\"defaultSize\": \(defaultSize)")
        let widget = try decode(json).widgets[0]
        let size = widget.widgetSize
        if defaultSize == "[]" {
            #expect(size == .size(4, 3))   // both defaults
        } else {
            #expect(size == .size(7, 3))   // width given, height defaulted
        }
    }

    @Test("empty min and max arrays fall back to the built-in range")
    func emptySizeRangeFallsBack() throws {
        let json = wellFormed.replacingOccurrences(
            of: "\"supportedSizes\": { \"min\": [2, 2], \"max\": [6, 4] }",
            with: "\"supportedSizes\": { \"min\": [], \"max\": [] }")
        let range = try decode(json).widgets[0].sizeRange
        #expect(range.min == .size(2, 2))
        #expect(range.max == .size(10, 6))
    }

    /// Documents today's behaviour rather than endorsing it: nothing rejects a
    /// negative or absurd size, so a manifest can ask for one. If the loader
    /// ever grows validation, this test is where the change gets noticed.
    @Test("negative and absurd sizes are currently accepted, not validated")
    func extremeSizesAreNotValidated() throws {
        let json = wellFormed.replacingOccurrences(of: "\"defaultSize\": [4, 3]",
                                                   with: "\"defaultSize\": [-5, 99999]")
        #expect(try decode(json).widgets[0].widgetSize == .size(-5, 99999))
    }

    // MARK: permissions

    /// An unknown permission string fails the whole manifest. Worth knowing:
    /// a plugin built against a newer app cannot be partially loaded here.
    @Test("an unrecognised permission rejects the entire manifest")
    func unknownPermissionRejectsManifest() {
        let json = wellFormed.replacingOccurrences(of: "\"system-metrics\"",
                                                   with: "\"launch-missiles\"")
        #expect(throws: (any Error).self) { try decode(json) }
    }

    @Test("an empty permission list is allowed")
    func emptyPermissionsAllowed() throws {
        let json = wellFormed.replacingOccurrences(of: "[\"system-metrics\"]", with: "[]")
        #expect(try decode(json).permissions.isEmpty)
    }

    // MARK: config values

    @Test("config defaults accept the three supported scalar types")
    func configScalarsAccepted() throws {
        for (literal, check) in [("true", "bool"), ("42", "number"), ("\"hi\"", "string")] {
            let json = wellFormed.replacingOccurrences(
                of: "\"defaultSize\": [4, 3]",
                with: """
                "defaultSize": [4, 3],
                "configSchema": [{"key": "k", "label": "L", "type": "\(check)", "default": \(literal)}]
                """)
            let field = try decode(json).widgets[0].configSchema?.first
            #expect(field != nil, "\(literal) did not decode")
        }
    }

    @Test("a null config default is rejected rather than silently dropped")
    func nullConfigDefaultRejected() {
        let json = wellFormed.replacingOccurrences(
            of: "\"defaultSize\": [4, 3]",
            with: """
            "defaultSize": [4, 3],
            "configSchema": [{"key": "k", "label": "L", "type": "string", "default": null}]
            """)
        #expect(throws: (any Error).self) { try decode(json) }
    }

    @Test("a nested object as a config default is rejected")
    func objectConfigDefaultRejected() {
        let json = wellFormed.replacingOccurrences(
            of: "\"defaultSize\": [4, 3]",
            with: """
            "defaultSize": [4, 3],
            "configSchema": [{"key": "k", "label": "L", "type": "string", "default": {"nested": 1}}]
            """)
        #expect(throws: (any Error).self) { try decode(json) }
    }

    // MARK: hostile-but-valid content

    /// Valid JSON is not the same as safe content. These decode; the test
    /// records that the manifest layer passes them through untouched, which is
    /// where any future sanitising would have to happen.
    @Test("oversized and unicode identifiers decode unchanged")
    func hostileStringsPassThrough() throws {
        let long = String(repeating: "a", count: 10_000)
        let json = wellFormed.replacingOccurrences(of: "\"Demo\"", with: "\"\(long)\"")
        #expect(try decode(json).name.count == 10_000)

        let rtl = wellFormed.replacingOccurrences(of: "\"Demo\"", with: "\"\\u202Egnp.exe\"")
        #expect(try decode(rtl).name.contains("\u{202E}"))
    }

    @Test("a traversal path in htmlFile decodes — nothing here rejects it")
    func traversalPathPassesThroughManifest() throws {
        let json = wellFormed.replacingOccurrences(of: "\"index.html\"",
                                                   with: "\"../../../../etc/passwd\"")
        #expect(try decode(json).widgets[0].htmlFile == "../../../../etc/passwd")
    }
}
