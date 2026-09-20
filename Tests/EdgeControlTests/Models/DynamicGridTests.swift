import CoreGraphics
import Testing
@testable import EdgeControl

@Suite("DynamicGrid")
struct DynamicGridTests {

    /// One row of the resolution matrix. A struct rather than a tuple so a
    /// failure names the display instead of printing four bare numbers.
    struct Case: CustomStringConvertible, Sendable {
        let display: String
        let width: CGFloat
        let height: CGFloat
        let columns: Int
        let rows: Int
        let cellWidth: CGFloat
        let cellHeight: CGFloat

        var description: String { display }
    }

    static let cases: [Case] = [
        Case(
            display: "XENEON EDGE 2560x720", width: 2560, height: 720,
            columns: 21, rows: 6, cellWidth: 2560.0 / 21.0, cellHeight: 120),
        Case(
            display: "1920x1080", width: 1920, height: 1080,
            columns: 16, rows: 9, cellWidth: 120, cellHeight: 120),
        Case(
            display: "4K 3840x2160, clamped on both axes", width: 3840, height: 2160,
            columns: 24, rows: 12, cellWidth: 160, cellHeight: 180),
        Case(
            display: "iPad Sidecar 1366x1024", width: 1366, height: 1024,
            columns: 11, rows: 8, cellWidth: 1366.0 / 11.0, cellHeight: 128),
        Case(
            display: "exact minimum 600x400", width: 600, height: 400,
            columns: 6, rows: 4, cellWidth: 100, cellHeight: 100),
        Case(
            display: "below minimum 320x240", width: 320, height: 240,
            columns: 6, rows: 4, cellWidth: 320.0 / 6.0, cellHeight: 60),
    ]

    @Test("grid dimensions match the display", arguments: Self.cases)
    func gridMatchesDisplay(c: Case) {
        let grid = DynamicGrid.calculate(width: c.width, height: c.height)
        #expect(grid.columns == c.columns)
        #expect(grid.rows == c.rows)
        #expect(abs(grid.cellWidth - c.cellWidth) < 0.001)
        #expect(abs(grid.cellHeight - c.cellHeight) < 0.001)
    }

    /// Cells must tile the surface exactly. A rounding change here would leave a
    /// gap or an overhang at the right or bottom edge of every dashboard.
    @Test("cells tile the full surface", arguments: Self.cases)
    func cellsTileTheSurface(c: Case) {
        let grid = DynamicGrid.calculate(width: c.width, height: c.height)
        #expect(abs(grid.cellWidth * CGFloat(grid.columns) - c.width) < 0.001)
        #expect(abs(grid.cellHeight * CGFloat(grid.rows) - c.height) < 0.001)
        #expect(grid.totalWidth == c.width)
        #expect(grid.totalHeight == c.height)
    }

    /// The clamps are the contract every widget's size range is written against.
    @Test("counts stay inside the supported range", arguments: Self.cases)
    func countsStayClamped(c: Case) {
        let grid = DynamicGrid.calculate(width: c.width, height: c.height)
        #expect(grid.columns >= 6 && grid.columns <= 24)
        #expect(grid.rows >= 4 && grid.rows <= 12)
    }

    @Test("the advertised minimum display size is 600x400")
    func minimumsAreStable() {
        #expect(DynamicGrid.minimumWidth == 600)
        #expect(DynamicGrid.minimumHeight == 400)
    }

    /// The default the app falls back to before a GeometryReader has reported.
    @Test("the XENEON default matches a live 2560x720 calculation")
    func xeneonDefaultMatches() {
        let live = DynamicGrid.calculate(width: 2560, height: 720)
        #expect(DynamicGrid.xeneonDefault == live)
    }
}
