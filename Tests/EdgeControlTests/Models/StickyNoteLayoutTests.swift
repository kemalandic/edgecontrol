import AppKit
import Testing
@testable import EdgeControl

/// A note's indent level is never stored. It is written into the paragraph
/// geometry and read back out of it, so the two halves have to agree exactly —
/// and when they do not, nested lists quietly flatten on the next save.
@Suite("Sticky note layout")
struct StickyNoteLayoutTests {

    private let layout = StickyNoteLayout(font: .systemFont(ofSize: 18))

    // MARK: the round trip

    /// The invariant the whole indent feature rests on.
    @Test("a level written into a style reads back as itself", arguments: 0...6)
    func levelRoundTripsForLists(level: Int) {
        let style = layout.paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: level)
        #expect(layout.indentLevel(of: style, isList: true) == level)
    }

    @Test("the round trip holds for plain lines too", arguments: 0...6)
    func levelRoundTripsForPlainLines(level: Int) {
        let style = layout.paragraphStyle(isHeading: false, isList: false, markerInset: 0, level: level)
        #expect(layout.indentLevel(of: style, isList: false) == level)
    }

    /// A marker inset shifts the first line only, so it must not leak into the
    /// level — a long number and a bullet at the same depth are the same depth.
    @Test("the marker inset does not change the level that reads back")
    func markerInsetDoesNotShiftLevel() {
        for inset in [CGFloat(0), 4, 17.5, 40] {
            let style = layout.paragraphStyle(isHeading: false, isList: true, markerInset: inset, level: 3)
            #expect(layout.indentLevel(of: style, isList: true) == 3, "inset \(inset)")
        }
    }

    @Test(
        "the round trip survives any note font",
        arguments: [
            "Helvetica", "Menlo", "Marker Felt", "Noteworthy",
        ])
    func roundTripAcrossFonts(fontName: String) throws {
        let font = try #require(NSFont(name: fontName, size: 15) ?? NSFont(name: fontName, size: 15))
        let other = StickyNoteLayout(font: font)
        for level in 0...other.maxIndentLevel {
            let style = other.paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: level)
            #expect(other.indentLevel(of: style, isList: true) == level, "\(fontName) level \(level)")
        }
    }

    // MARK: bounds

    @Test("no style means the outermost level")
    func noStyleIsLevelZero() {
        #expect(layout.indentLevel(of: nil, isList: true) == 0)
    }

    /// Geometry from a note written with a different font, or hand-edited, must
    /// not produce a level the editor cannot represent.
    @Test("a level read from foreign geometry is clamped")
    func foreignGeometryIsClamped() {
        let tooDeep = NSMutableParagraphStyle()
        tooDeep.firstLineHeadIndent = layout.indentStep * 99
        #expect(layout.indentLevel(of: tooDeep, isList: false) == layout.maxIndentLevel)

        let negative = NSMutableParagraphStyle()
        negative.firstLineHeadIndent = -500
        #expect(layout.indentLevel(of: negative, isList: false) == 0)
    }

    // MARK: geometry

    @Test("list text starts far enough in for a two-digit marker")
    func listColumnFitsTwoDigits() {
        let twoDigits = ("88." as NSString).size(withAttributes: [.font: layout.font]).width
        #expect(layout.listTextIndent >= twoDigits)
    }

    @Test("each level shifts the text column by exactly one step")
    func levelsShiftByOneStep() {
        let one = layout.paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: 1)
        let two = layout.paragraphStyle(isHeading: false, isList: true, markerInset: 0, level: 2)
        #expect(two.headIndent - one.headIndent == layout.indentStep)
    }

    @Test("a list line hangs its wrapped text under the text column, not the marker")
    func wrappedListTextHangs() {
        let style = layout.paragraphStyle(isHeading: false, isList: true, markerInset: 20, level: 0)
        #expect(style.headIndent == layout.listTextIndent)
        #expect(style.firstLineHeadIndent == 20)
    }

    @Test("headings get more space above them than below")
    func headingsBreathe() {
        let heading = layout.paragraphStyle(isHeading: true, isList: false, markerInset: 0, level: 0)
        #expect(heading.paragraphSpacingBefore > heading.paragraphSpacing)
    }

    // MARK: markers and fonts

    @Test("markers right-align, so a wider marker sits further left")
    func widerMarkersSitFurtherLeft() {
        let single = layout.markerInset(for: "1.\tone")
        let double = layout.markerInset(for: "88.\teighty-eight")
        #expect(double < single, "a two-digit marker should start further left to end on the same edge")
    }

    @Test("a line with no marker has no inset")
    func noMarkerNoInset() {
        #expect(layout.markerInset(for: "just text") == 0)
    }

    @Test("headings get bigger toward level one", arguments: [1, 2, 3])
    func headingSizes(level: Int) {
        #expect(layout.headingFont(level).pointSize > layout.font.pointSize)
        if level > 1 {
            #expect(layout.headingFont(level).pointSize < layout.headingFont(level - 1).pointSize)
        }
    }

    /// Two handwriting fonts set their letters tight enough to blur on the
    /// panel; everything else is left alone.
    @Test("tracking is added only for the fonts that need it")
    func kernOnlyWhereNeeded() throws {
        #expect(StickyNoteLayout(font: .systemFont(ofSize: 18)).kern == 0)
        if let felt = NSFont(name: "Marker Felt", size: 18) {
            #expect(StickyNoteLayout(font: felt).kern > 0)
        }
    }
}
