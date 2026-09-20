import Testing
@testable import EdgeControl

@Suite("Grid placement geometry")
struct GridGeometryTests {

    // MARK: intersects

    /// Widgets sitting flush against each other must not read as overlapping —
    /// the most load-bearing case here, since a packed dashboard is nothing but
    /// touching edges.
    @Test("rectangles sharing an edge do not intersect")
    func touchingEdgesDoNotIntersect() {
        let left = GridRect(col: 0, row: 0, width: 2, height: 2)
        let right = GridRect(col: 2, row: 0, width: 2, height: 2)
        let below = GridRect(col: 0, row: 2, width: 2, height: 2)
        #expect(!left.intersects(right))
        #expect(!right.intersects(left))
        #expect(!left.intersects(below))
        #expect(!below.intersects(left))
    }

    @Test("overlapping by a single cell counts as an intersection")
    func singleCellOverlapIntersects() {
        let a = GridRect(col: 0, row: 0, width: 2, height: 2)
        let b = GridRect(col: 1, row: 1, width: 2, height: 2)
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }

    @Test("a rectangle fully inside another intersects it")
    func containmentIntersects() {
        let outer = GridRect(col: 0, row: 0, width: 4, height: 4)
        let inner = GridRect(col: 1, row: 1, width: 1, height: 1)
        #expect(outer.intersects(inner))
        #expect(inner.intersects(outer))
    }

    @Test("a rectangle intersects itself")
    func selfIntersects() {
        let r = GridRect(col: 3, row: 1, width: 2, height: 2)
        #expect(r.intersects(r))
    }

    @Test("rectangles separated on one axis do not intersect")
    func separatedDoNotIntersect() {
        let a = GridRect(col: 0, row: 0, width: 2, height: 6)
        let b = GridRect(col: 5, row: 0, width: 2, height: 6)
        #expect(!a.intersects(b))
    }

    // MARK: endCol / endRow

    @Test("end coordinates are exclusive")
    func endCoordinatesAreExclusive() {
        let r = GridRect(col: 3, row: 2, width: 4, height: 1)
        #expect(r.endCol == 7)
        #expect(r.endRow == 3)
    }

    // MARK: fitsInGrid

    /// 21x6 is the XENEON EDGE grid, so these are the real boundaries.
    @Test("a placement flush against the right and bottom edges fits")
    func flushAgainstEdgeFits() {
        let r = GridRect(col: 19, row: 4, width: 2, height: 2)
        #expect(r.fitsInGrid(columns: 21, rows: 6))
    }

    @Test("a placement one cell past the edge does not fit")
    func oneCellPastEdgeDoesNotFit() {
        #expect(!GridRect(col: 20, row: 0, width: 2, height: 1).fitsInGrid(columns: 21, rows: 6))
        #expect(!GridRect(col: 0, row: 5, width: 1, height: 2).fitsInGrid(columns: 21, rows: 6))
    }

    @Test("negative origins do not fit")
    func negativeOriginsDoNotFit() {
        #expect(!GridRect(col: -1, row: 0, width: 1, height: 1).fitsInGrid(columns: 21, rows: 6))
        #expect(!GridRect(col: 0, row: -1, width: 1, height: 1).fitsInGrid(columns: 21, rows: 6))
    }

    @Test("a placement filling the whole grid fits")
    func fullGridFits() {
        #expect(GridRect(col: 0, row: 0, width: 21, height: 6).fitsInGrid(columns: 21, rows: 6))
    }

    // MARK: WidgetSizeRange

    @Test("a size range includes its own bounds")
    func rangeIncludesItsBounds() {
        let range = WidgetSizeRange(min: .size(1, 1), max: .size(8, 4))
        #expect(range.contains(.size(1, 1)))
        #expect(range.contains(.size(8, 4)))
        #expect(range.contains(.size(4, 3)))
    }

    @Test("a size outside either dimension is rejected")
    func outsideEitherDimensionRejected() {
        let range = WidgetSizeRange(min: .size(3, 2), max: .size(6, 4))
        #expect(!range.contains(.size(2, 3)))  // too narrow
        #expect(!range.contains(.size(7, 3)))  // too wide
        #expect(!range.contains(.size(4, 1)))  // too short
        #expect(!range.contains(.size(4, 5)))  // too tall
    }
}
