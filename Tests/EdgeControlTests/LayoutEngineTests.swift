import XCTest
@testable import EdgeControl

/// Placement is the one piece of layout logic a user can corrupt by dragging:
/// every mutation here either holds the no-overlap, inside-the-grid invariant or
/// refuses and leaves the widget where it was.
@MainActor
final class LayoutEngineTests: XCTestCase {
    private var directory: URL!
    private var engine: LayoutEngine!
    private var pageId: String!

    // XCTest's throwing set-up hooks are nonisolated, so on a @MainActor
    // test case they cannot touch the main-actor state they exist to build.
    // The async hooks inherit the class's isolation, so use those instead.
    override func setUp() async throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LayoutEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        engine = LayoutEngine(store: LayoutStore(directory: directory))
        engine.currentGrid = .xeneonDefault
        engine.document.pages = [PageConfig(name: "Test", order: 0)]
        pageId = engine.document.pages[0].id
    }

    override func tearDown() async throws {
        engine = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private var widgets: [WidgetPlacement] { engine.document.pages[0].widgets }

    private func widget(_ instanceId: String) throws -> WidgetPlacement {
        try XCTUnwrap(widgets.first { $0.instanceId == instanceId })
    }

    // MARK: - Placement

    func testAWidgetOverlappingAnExistingOneIsRefused() {
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        XCTAssertNil(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 2, row: 1, width: 4, height: 3)
        )
        XCTAssertEqual(widgets.count, 1)
    }

    func testAWidgetHangingOffTheGridEdgeIsRefused() {
        let lastColumn = engine.currentGrid.columns - 1

        XCTAssertNil(
            engine.placeWidget(pageId: pageId, widgetId: "clock", col: lastColumn, row: 0, width: 3, height: 2)
        )
        XCTAssertTrue(widgets.isEmpty)
    }

    func testTouchingWidgetsAreAllowed() {
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 4, row: 0, width: 4, height: 3),
            "sharing an edge is not an overlap"
        )
    }

    // MARK: - Displacing overlaps on drop

    /// A drop keeps the widget exactly where the user put it and moves what it
    /// covers. If the dropped widget shifted even a cell, the gesture would not
    /// mean what it looked like.
    func testTheDroppedWidgetDoesNotMove() throws {
        let settled = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        engine.isEditing = true
        let dropped = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 2, row: 1, width: 4, height: 3)
        )

        engine.resolveOverlaps(pageId: pageId, keeping: dropped)

        let kept = try widget(dropped)
        XCTAssertEqual(kept.col, 2)
        XCTAssertEqual(kept.row, 1)
        XCTAssertNotEqual(try widget(settled).gridRect, GridRect(col: 0, row: 0, width: 4, height: 3),
                          "the covered widget should have been displaced")
    }

    /// After a drop the page is clean again: nothing overlaps anything.
    func testDisplacedWidgetsLandOnFreeCells() throws {
        for col in stride(from: 0, to: 12, by: 4) {
            XCTAssertNotNil(
                engine.placeWidget(pageId: pageId, widgetId: "clock", col: col, row: 0, width: 4, height: 3)
            )
        }
        engine.isEditing = true
        let dropped = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 1, row: 0, width: 6, height: 3)
        )

        engine.resolveOverlaps(pageId: pageId, keeping: dropped)

        XCTAssertFalse(engine.hasOverlaps, "the page still holds overlaps after resolving")
        XCTAssertEqual(widgets.count, 4, "no widget was dropped from the page")
    }

    /// Nearest by Manhattan distance, so a displaced widget lands beside where
    /// it was rather than wherever the scan happened to reach first.
    func testDisplacementPrefersTheNearestFreeSpot() throws {
        let settled = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 8, row: 0, width: 2, height: 2)
        )
        engine.isEditing = true
        let dropped = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 8, row: 0, width: 2, height: 2)
        )

        engine.resolveOverlaps(pageId: pageId, keeping: dropped)

        let moved = try widget(settled)
        let distance = abs(moved.col - 8) + abs(moved.row - 0)
        XCTAssertLessThanOrEqual(distance, 2, "moved to (\(moved.col), \(moved.row)), further than it had to")
    }

    /// A relocated widget only takes genuinely free cells — displacement does
    /// not cascade, or one drop could rearrange the whole page.
    func testARelocatedWidgetDoesNotBumpAThird() throws {
        let a = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 0, row: 0, width: 3, height: 2)
        )
        let b = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "clock", col: 3, row: 0, width: 3, height: 2)
        )
        let bRect = try widget(b).gridRect

        engine.isEditing = true
        let dropped = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 3, height: 2)
        )

        engine.resolveOverlaps(pageId: pageId, keeping: dropped)

        XCTAssertEqual(try widget(b).gridRect, bRect, "an untouched widget was moved")
        XCTAssertNotEqual(try widget(a).gridRect, bRect)
        XCTAssertFalse(engine.hasOverlaps)
    }

    /// With the page full and no minimum to shrink to, the displaced widget
    /// stays where it is — overlapped, which is the staged state the session is
    /// allowed to hold and refuses to save.
    func testNothingFitsAnywhereLeavesTheOverlapStaged() throws {
        let columns = engine.currentGrid.columns
        let rows = engine.currentGrid.rows
        let filler = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge",
                               col: 0, row: 0, width: columns, height: rows)
        )
        engine.isEditing = true
        let dropped = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 2, height: 2)
        )

        engine.resolveOverlaps(pageId: pageId, keeping: dropped)

        XCTAssertEqual(try widget(filler).gridRect,
                       GridRect(col: 0, row: 0, width: columns, height: rows))
        XCTAssertTrue(engine.hasOverlaps, "nowhere to go, so the overlap stays staged")
    }

    /// When nothing fits at full size, a widget that declares a minimum shrinks
    /// rather than staying on top of the drop. The page is filled except for a
    /// 2x2 gap, so the displaced 4x2 widget has to give up width to land.
    func testAWidgetShrinksWhenItCannotFitAtFullSize() throws {
        let big = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 0, row: 0, width: 4, height: 2)
        )
        // Everything else, leaving only (19,4)-(20,5) free on the 21x6 grid.
        XCTAssertNotNil(engine.placeWidget(pageId: pageId, widgetId: "clock", col: 4, row: 0, width: 17, height: 2))
        XCTAssertNotNil(engine.placeWidget(pageId: pageId, widgetId: "clock", col: 0, row: 2, width: 21, height: 2))
        XCTAssertNotNil(engine.placeWidget(pageId: pageId, widgetId: "clock", col: 0, row: 4, width: 19, height: 2))

        engine.isEditing = true
        let dropped = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 2)
        )

        engine.resolveOverlaps(pageId: pageId, keeping: dropped) { _ in .size(1, 1) }

        let shrunk = try widget(big)
        XCTAssertLessThan(shrunk.width, 4, "no full-size spot existed, so it had to shrink")
        XCTAssertFalse(engine.hasOverlaps)
        XCTAssertEqual(try widget(dropped).gridRect, GridRect(col: 0, row: 0, width: 4, height: 2),
                       "the dropped widget still must not move")
    }

    // MARK: - Edit sessions and persistence

    /// The guarantee the whole staging design rests on: an overlapping layout
    /// never reaches disk. Three gates enforce it — the debounced save refuses
    /// while editing, the exit path refuses to leave edit mode, and this one,
    /// the flush on quit. Only the comments said so before this test.
    func testQuittingMidEditDoesNotPersistOverlaps() throws {
        let store = LayoutStore(directory: directory)
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        engine.flushSave()
        XCTAssertEqual(store.load().pages.first?.widgets.count, 1, "the clean layout should be on disk")

        engine.isEditing = true
        // Overlapping is legal mid-session; that is the staging state.
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 1, row: 1, width: 4, height: 3)
        )
        XCTAssertTrue(engine.hasOverlaps)

        engine.flushSave()

        XCTAssertEqual(
            store.load().pages.first?.widgets.count, 1,
            "quitting mid-edit persisted an overlapping layout"
        )
    }

    /// Esc abandons the session: the layout returns to what it was when editing
    /// began, which is by construction overlap-free.
    func testCancellingAnEditSessionRestoresTheBaseline() {
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        engine.isEditing = true
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 1, row: 1, width: 4, height: 3)
        )
        XCTAssertTrue(engine.hasOverlaps)

        engine.cancelEditing()

        XCTAssertFalse(engine.isEditing)
        XCTAssertFalse(engine.hasOverlaps, "the session was abandoned but overlaps survived")
        XCTAssertEqual(widgets.count, 1)
    }

    /// Undo steps back one gesture at a time within the session.
    func testUndoAndRedoStepThroughTheSession() {
        engine.isEditing = true
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 2, height: 2)
        )
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "clock", col: 4, row: 0, width: 2, height: 2)
        )
        XCTAssertEqual(widgets.count, 2)

        engine.undoLayout()
        XCTAssertEqual(widgets.count, 1)
        engine.undoLayout()
        XCTAssertEqual(widgets.count, 0)

        engine.redoLayout()
        XCTAssertEqual(widgets.count, 1)
    }

    /// The history only exists while a session is open, so undo outside one is
    /// a no-op rather than a way to walk backwards through earlier work.
    func testUndoDoesNothingOutsideAnEditSession() {
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 2, height: 2)
        )
        engine.undoLayout()
        XCTAssertEqual(widgets.count, 1)
    }

    // MARK: - Move and resize

    func testMovingOntoAnotherWidgetLeavesTheOriginalWhereItWas() throws {
        let moving = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        _ = engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 4, row: 0, width: 4, height: 3)

        XCTAssertFalse(engine.moveWidget(pageId: pageId, instanceId: moving, toCol: 4, toRow: 0))

        let after = try widget(moving)
        XCTAssertEqual(after.col, 0)
        XCTAssertEqual(after.row, 0)
    }

    func testResizingIntoANeighbourLeavesTheSizeAlone() throws {
        let growing = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        _ = engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 4, row: 0, width: 4, height: 3)

        XCTAssertFalse(engine.resizeWidget(pageId: pageId, instanceId: growing, newWidth: 6, newHeight: 3))

        XCTAssertEqual(try widget(growing).width, 4)
    }

    func testAWidgetCanMoveIntoTheSpaceItJustLeft() throws {
        let only = try XCTUnwrap(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )

        XCTAssertTrue(
            engine.moveWidget(pageId: pageId, instanceId: only, toCol: 2, toRow: 0),
            "a widget must not collide with itself"
        )
        XCTAssertEqual(try widget(only).col, 2)
    }

    // MARK: - Pages

    func testRemovingTheCurrentPageClampsTheIndex() {
        engine.addPage(name: "Second")
        engine.currentPageIndex = 1

        engine.removePage(id: engine.document.pages[1].id)

        XCTAssertEqual(engine.pageCount, 1)
        XCTAssertEqual(engine.currentPageIndex, 0, "the index must not point past the last page")
        XCTAssertNotNil(engine.currentPage)
    }

    func testMovingAPageRenumbersTheRest() {
        engine.addPage(name: "B")
        engine.addPage(name: "C")

        engine.movePage(id: engine.document.pages[2].id, toOrder: 0)

        XCTAssertEqual(engine.sortedPages.map(\.name), ["C", "Test", "B"])
        XCTAssertEqual(
            engine.sortedPages.map(\.order), [0, 1, 2],
            "orders have to stay contiguous or sortedPages stops matching the array"
        )
    }

    // MARK: - Edit session (staged overlaps)

    func testEditingAllowsOverlapAsAStagingState() throws {
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        engine.isEditing = true

        // Place, move and resize onto occupied cells all succeed mid-edit.
        let staged = engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 2, row: 1, width: 4, height: 3)
        XCTAssertNotNil(staged)
        XCTAssertTrue(engine.moveWidget(pageId: pageId, instanceId: try XCTUnwrap(staged), toCol: 0, toRow: 0))
        XCTAssertTrue(engine.resizeWidget(pageId: pageId, instanceId: try XCTUnwrap(staged), newWidth: 5, newHeight: 3))

        XCTAssertTrue(engine.hasOverlaps)
        XCTAssertEqual(engine.overlappingInstanceIds(pageId: pageId).count, 2)

        // Off-grid stays refused even while editing.
        XCTAssertFalse(engine.moveWidget(pageId: pageId, instanceId: try XCTUnwrap(staged), toCol: 50, toRow: 0))
    }

    func testEndingEditRestoresStrictPlacement() {
        engine.isEditing = true
        engine.isEditing = false
        XCTAssertNotNil(
            engine.placeWidget(pageId: pageId, widgetId: "cpu-gauge", col: 0, row: 0, width: 4, height: 3)
        )
        XCTAssertNil(
            engine.placeWidget(pageId: pageId, widgetId: "memory-gauge", col: 2, row: 1, width: 4, height: 3)
        )
        XCTAssertFalse(engine.hasOverlaps)
    }

    // MARK: - Page reordering

    func testMovingPagesKeepsTheVisiblePageVisible() {
        engine.document.pages = [
            PageConfig(name: "A", order: 0),
            PageConfig(name: "B", order: 1),
            PageConfig(name: "C", order: 2),
        ]
        engine.currentPageIndex = 1  // viewing B

        // Move A to the end; B shifts to index 0 and must stay on screen.
        engine.movePage(id: engine.document.pages[0].id, toOrder: 2)

        XCTAssertEqual(engine.sortedPages.map(\.name), ["B", "C", "A"])
        XCTAssertEqual(engine.sortedPages[engine.currentPageIndex].name, "B")
    }
}
