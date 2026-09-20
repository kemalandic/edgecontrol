import Foundation
import Testing
@testable import EdgeControl

@Suite("Layout document")
struct LayoutDocumentTests {

    private func page(_ name: String, order: Int, widgets: [WidgetPlacement] = []) -> PageConfig {
        PageConfig(name: name, order: order, widgets: widgets)
    }

    @Test("a new document starts at version 1 with no pages")
    func defaultsAreStable() {
        let doc = LayoutDocument()
        #expect(doc.version == 1)
        #expect(doc.pages.isEmpty)
        #expect(doc.grid.columns == GridConstants.columns)
        #expect(doc.grid.rows == GridConstants.rows)
    }

    /// The layout is the one piece of user data the app persists. A round trip
    /// that loses a field loses someone's dashboard.
    @Test("a document survives a round trip through JSON")
    func codableRoundTrip() throws {
        let placement = WidgetPlacement(widgetId: "cpu-gauge", col: 3, row: 1, width: 4, height: 2)
        let doc = LayoutDocument(
            version: 1,
            grid: GridDimensions(columns: 21, rows: 6),
            pages: [page("Main", order: 0, widgets: [placement]), page("Second", order: 1)]
        )

        let data = try JSONEncoder().encode(doc)
        let restored = try JSONDecoder().decode(LayoutDocument.self, from: data)

        #expect(restored.version == 1)
        #expect(restored.grid.columns == 21)
        #expect(restored.pages.count == 2)
        #expect(restored.pages[0].widgets.count == 1)

        let w = restored.pages[0].widgets[0]
        #expect(w.widgetId == "cpu-gauge")
        #expect(w.instanceId == placement.instanceId)
        #expect(w.col == 3 && w.row == 1 && w.width == 4 && w.height == 2)
    }

    /// A layout.json written before a field existed has to keep decoding, or
    /// adding one resets every dashboard in the field. The store quarantines an
    /// unreadable file rather than overwriting it, so the arrangement is
    /// recoverable either way — but it should not come to that.
    @Test(
        "a document missing top-level keys still decodes",
        arguments: [
            "version", "grid", "pages", "globalSettings",
        ])
    func missingKeysFallBackToDefaults(dropped: String) throws {
        let full = LayoutDocument(
            version: 1,
            grid: GridDimensions(columns: 21, rows: 6),
            pages: [page("Main", order: 0)]
        )
        var object =
            try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(full)) as! [String: Any]
        object.removeValue(forKey: dropped)

        let restored = try JSONDecoder().decode(
            LayoutDocument.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        // Whatever was dropped falls back; everything else survives.
        if dropped != "pages" { #expect(restored.pages.count == 1) }
        if dropped != "grid" { #expect(restored.grid.columns == 21) }
        #expect(restored.version == 1)
    }

    /// An empty object is the degenerate case of the same thing.
    @Test("an empty object decodes to a usable default document")
    func emptyObjectDecodes() throws {
        let doc = try JSONDecoder().decode(LayoutDocument.self, from: Data("{}".utf8))
        #expect(doc.version == 1)
        #expect(doc.pages.isEmpty)
        #expect(doc.grid.columns == GridConstants.columns)
    }

    @Test("widget config values survive the round trip")
    func configRoundTrips() throws {
        var values: [String: ConfigValue] = [:]
        values["showLabel"] = .bool(false)
        values["style"] = .string("analog")
        let placement = WidgetPlacement(
            widgetId: "clock", col: 0, row: 0, width: 2, height: 2,
            config: WidgetConfig(values))
        let doc = LayoutDocument(pages: [page("Main", order: 0, widgets: [placement])])

        let restored = try JSONDecoder().decode(
            LayoutDocument.self, from: JSONEncoder().encode(doc))
        let config = restored.pages[0].widgets[0].config
        #expect(config.bool("showLabel", default: true) == false)
        #expect(config.string("style", default: "") == "analog")
    }

    /// `gridRect` is what every collision and containment check runs against, so
    /// the derivation from a placement has to be exact.
    @Test("gridRect derives from the placement's own coordinates")
    func gridRectMatchesPlacement() {
        let placement = WidgetPlacement(widgetId: "storage", col: 5, row: 2, width: 3, height: 2)
        let rect = placement.gridRect
        #expect(rect.col == 5)
        #expect(rect.row == 2)
        #expect(rect.width == 3)
        #expect(rect.height == 2)
        #expect(rect.endCol == 8)
        #expect(rect.endRow == 4)
    }

    @Test("each placement gets its own instance id")
    func instanceIdsAreUnique() {
        let a = WidgetPlacement(widgetId: "clock", col: 0, row: 0, width: 2, height: 2)
        let b = WidgetPlacement(widgetId: "clock", col: 2, row: 0, width: 2, height: 2)
        #expect(a.instanceId != b.instanceId)
        #expect(a.id == a.instanceId)
    }
}
