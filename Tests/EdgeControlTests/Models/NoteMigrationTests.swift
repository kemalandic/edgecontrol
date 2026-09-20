import Foundation
import Testing

@testable import EdgeControl

@Suite("Note migration")
struct NoteMigrationTests {

    private func stickyConfig(
        rtf: String = "", note: String = "", extras: [String: ConfigValue] = [:]
    )
        -> WidgetConfig
    {
        var config = WidgetConfig(extras)
        if !rtf.isEmpty { config[NoteMigration.bodyKey] = .string(rtf) }
        if !note.isEmpty { config[NoteMigration.plainKey] = .string(note) }
        return config
    }

    @Test("A note in the layout becomes a note in the store")
    func bodyMovesOut() throws {
        let config = stickyConfig(
            rtf: "cnRmLWJvZHk=", note: "shopping",
            extras: ["color": .string("mint"), "fontSize": .double(20)])

        let plan = try #require(NoteMigration.plan(config: config, id: "note-1"))

        #expect(plan.noteId == "note-1")
        #expect(plan.rtfBase64 == "cnRmLWJvZHk=")
        #expect(plan.plainText == "shopping")
        // What is left points at the note and no longer contains it.
        #expect(plan.config.string(NoteMigration.idKey) == "note-1")
        #expect(plan.config[NoteMigration.bodyKey] == nil)
        #expect(plan.config[NoteMigration.plainKey] == nil)
        // Everything about how the note looks is untouched.
        #expect(plan.config.string("color") == "mint")
        #expect(plan.config.double("fontSize") == 20)
    }

    @Test("A widget that already points at a note is left alone")
    func alreadyMigrated() {
        var config = stickyConfig(rtf: "cnRm")
        config[NoteMigration.idKey] = .string("existing")
        #expect(NoteMigration.plan(config: config, id: "new") == nil)
        #expect(!NoteMigration.needsMigration(config))
    }

    @Test("A note nobody ever typed in still becomes a note")
    func emptyWidgetStillGetsANote() throws {
        // Otherwise there are two kinds of sticky note widget forever: ones
        // with a note behind them and ones without.
        let plan = try #require(NoteMigration.plan(config: WidgetConfig(), id: "note-1"))
        #expect(plan.rtfBase64.isEmpty)
        #expect(plan.plainText.isEmpty)
        #expect(plan.config.string(NoteMigration.idKey) == "note-1")
    }

    @Test("A note written before rich text arrives as plain text")
    func legacyPlainOnlyNote() throws {
        let plan = try #require(NoteMigration.plan(config: stickyConfig(note: "- milk\n- eggs"), id: "n"))
        #expect(plan.rtfBase64.isEmpty)
        #expect(plan.plainText == "- milk\n- eggs")
    }

    // MARK: - Walking a layout

    private func document(_ widgets: [WidgetPlacement]) -> LayoutDocument {
        LayoutDocument(pages: [PageConfig(name: "Main", order: 0, widgets: widgets)])
    }

    @Test("Only sticky notes are touched, and each gets its own note")
    func walkingALayout() {
        let doc = document([
            WidgetPlacement(
                instanceId: "a", widgetId: "sticky-note", col: 0, row: 0, width: 2, height: 2,
                config: stickyConfig(rtf: "b25l")),
            WidgetPlacement(instanceId: "w", widgetId: "weather", col: 2, row: 0, width: 4, height: 4),
            WidgetPlacement(
                instanceId: "b", widgetId: "sticky-note", col: 6, row: 0, width: 2, height: 2,
                config: stickyConfig(rtf: "dHdv")),
        ])

        var counter = 0
        let (migrated, plans) = NoteMigration.plans(for: doc) {
            counter += 1
            return "note-\(counter)"
        }

        #expect(plans.map(\.noteId) == ["note-1", "note-2"])
        #expect(plans.map(\.rtfBase64) == ["b25l", "dHdv"])

        let widgets = migrated.pages[0].widgets
        #expect(widgets[0].config.string(NoteMigration.idKey) == "note-1")
        #expect(widgets[2].config.string(NoteMigration.idKey) == "note-2")
        // The weather widget was not given a note id on the way past.
        #expect(widgets[1].config.isEmpty)
    }

    @Test("Running the migration again finds nothing to do")
    func idempotent() {
        let doc = document([
            WidgetPlacement(
                instanceId: "a", widgetId: "sticky-note", col: 0, row: 0, width: 2, height: 2,
                config: stickyConfig(rtf: "b25l"))
        ])

        let (once, firstPlans) = NoteMigration.plans(for: doc) { "note-1" }
        #expect(firstPlans.count == 1)

        let (twice, secondPlans) = NoteMigration.plans(for: once) { "note-2" }
        #expect(secondPlans.isEmpty)
        // The second pass must not hand the widget a different note.
        #expect(twice.pages[0].widgets[0].config == once.pages[0].widgets[0].config)
        #expect(twice.pages[0].widgets[0].config.string(NoteMigration.idKey) == "note-1")
    }

    @Test("Notes on every page move, not just the visible one")
    func everyPage() {
        let doc = LayoutDocument(pages: [
            PageConfig(
                name: "One", order: 0,
                widgets: [
                    WidgetPlacement(widgetId: "sticky-note", col: 0, row: 0, width: 2, height: 2)
                ]),
            PageConfig(
                name: "Two", order: 1,
                widgets: [
                    WidgetPlacement(widgetId: "sticky-note", col: 0, row: 0, width: 2, height: 2)
                ]),
        ])

        var counter = 0
        let (_, plans) = NoteMigration.plans(for: doc) {
            counter += 1
            return "note-\(counter)"
        }
        #expect(plans.count == 2)
    }
}
