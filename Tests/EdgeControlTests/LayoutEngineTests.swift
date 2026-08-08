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

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LayoutEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        engine = LayoutEngine(store: LayoutStore(directory: directory))
        engine.currentGrid = .xeneonDefault
        engine.document.pages = [PageConfig(name: "Test", order: 0)]
        pageId = engine.document.pages[0].id
    }

    override func tearDownWithError() throws {
        engine = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        try super.tearDownWithError()
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
}
