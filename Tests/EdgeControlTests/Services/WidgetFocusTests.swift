import Foundation
import Testing

@testable import EdgeControl

/// Focus puts one widget over the whole panel. What can go wrong is not the
/// drawing — it is being left in it: focused on a widget that has been
/// removed, or focused and editing at the same time, with both wanting the
/// same screen and the same Esc.
@Suite("Widget focus")
@MainActor
struct WidgetFocusTests {

    private func engine(with widgets: [WidgetPlacement]) -> LayoutEngine {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WidgetFocusTests-\(UUID().uuidString)", isDirectory: true)
        let engine = LayoutEngine(store: LayoutStore(directory: directory))
        engine.document = LayoutDocument(pages: [PageConfig(name: "Main", order: 0, widgets: widgets)])
        return engine
    }

    private var note: WidgetPlacement {
        WidgetPlacement(
            instanceId: "note-1", widgetId: "sticky-note", col: 0, row: 0, width: 3, height: 2)
    }

    @Test("Focusing names the widget, and clearing lets it go")
    func focusAndClear() {
        let engine = engine(with: [note])
        let pageId = engine.document.pages[0].id

        #expect(engine.focusedWidget == nil)
        engine.focus(pageId: pageId, instanceId: "note-1")
        #expect(engine.isFocused(pageId: pageId, instanceId: "note-1"))
        #expect(!engine.isFocused(pageId: pageId, instanceId: "other"))

        engine.clearFocus()
        #expect(engine.focusedWidget == nil)
    }

    @Test("The focused widget can be found, so the shell has something to draw")
    func placementLookup() {
        let engine = engine(with: [note])
        let pageId = engine.document.pages[0].id

        #expect(engine.placement(pageId: pageId, instanceId: "note-1")?.widgetId == "sticky-note")
        #expect(engine.placement(pageId: pageId, instanceId: "missing") == nil)
        #expect(engine.placement(pageId: "no-such-page", instanceId: "note-1") == nil)
    }

    /// Otherwise the panel shows an overlay with nothing in it and no way out.
    @Test("Removing the focused widget ends the focus")
    func removalClearsFocus() {
        let engine = engine(with: [note])
        let pageId = engine.document.pages[0].id
        engine.focus(pageId: pageId, instanceId: "note-1")

        engine.removeWidget(pageId: pageId, instanceId: "note-1")

        #expect(engine.focusedWidget == nil)
    }

    @Test("Removing a different widget leaves the focus alone")
    func unrelatedRemoval() {
        let other = WidgetPlacement(
            instanceId: "clock-1", widgetId: "clock", col: 4, row: 0, width: 2, height: 2)
        let engine = engine(with: [note, other])
        let pageId = engine.document.pages[0].id
        engine.focus(pageId: pageId, instanceId: "note-1")

        engine.removeWidget(pageId: pageId, instanceId: "clock-1")

        #expect(engine.isFocused(pageId: pageId, instanceId: "note-1"))
    }

    /// They want the same screen and the same key. Editing wins, because a
    /// layout being rearranged is the thing that needs every widget visible.
    @Test("Editing the layout takes the screen back")
    func editingClearsFocus() {
        let engine = engine(with: [note])
        let pageId = engine.document.pages[0].id
        engine.focus(pageId: pageId, instanceId: "note-1")

        engine.isEditing = true

        #expect(engine.focusedWidget == nil)
    }

    @Test("A widget cannot be focused while the layout is being edited")
    func noFocusWhileEditing() {
        let engine = engine(with: [note])
        let pageId = engine.document.pages[0].id
        engine.isEditing = true

        engine.focus(pageId: pageId, instanceId: "note-1")

        #expect(engine.focusedWidget == nil)
    }
}
