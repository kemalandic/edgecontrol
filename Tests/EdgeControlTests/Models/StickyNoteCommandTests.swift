import Foundation
import Testing

@testable import EdgeControl

/// The slash menu is a second way into things that can already be typed, so
/// the risk is not that a command fails loudly — it is that it writes a marker
/// the editor's own parser does not recognise, and the line then looks like a
/// list while behaving like prose.
@Suite("Sticky note commands")
struct StickyNoteCommandTests {

    @Test("Every command a person can pick says what it is")
    func allCommandsArePresentable() {
        for command in StickyNoteCommand.allCases {
            #expect(!command.title.isEmpty)
            #expect(!command.symbolName.isEmpty)
        }
        // Nothing is listed twice under a different name.
        #expect(Set(StickyNoteCommand.allCases.map(\.title)).count == StickyNoteCommand.allCases.count)
    }

    @Test("A marker a command writes is one the editor reads back")
    func markersRoundTripThroughTheParser() {
        for command in StickyNoteCommand.allCases {
            guard let marker = command.marker else { continue }
            let line = marker + "something"
            #expect(
                StickyNoteMarkup.marker(of: line) != nil,
                "\(command.rawValue) writes a marker the parser does not recognise")
            #expect(StickyNoteMarkup.markerLength(of: line) == (marker as NSString).length)
            #expect(StickyNoteMarkup.hasContentAfterMarker(line))
        }
    }

    @Test("The list commands are the three kinds of list item, and nothing else")
    func markersMatchTheListKinds() {
        #expect(StickyNoteMarkup.marker(of: StickyNoteCommand.todo.marker! + "x") == .checkbox)
        #expect(StickyNoteMarkup.marker(of: StickyNoteCommand.bullet.marker! + "x") == .bullet)
        #expect(StickyNoteMarkup.marker(of: StickyNoteCommand.numbered.marker! + "x") == .ordered(1))

        let withoutMarkers = StickyNoteCommand.allCases.filter { $0.marker == nil }
        #expect(Set(withoutMarkers) == [.heading1, .heading2, .heading3, .code, .divider, .date, .body])
    }

    /// A numbered list starting anywhere but 1 is the thing the editor
    /// deliberately refuses to create from typing; the menu must not be a way
    /// around that.
    @Test("The numbered command starts a list at one")
    func numberedStartsAtOne() {
        #expect(StickyNoteCommand.numbered.marker == "1.\t")
        #expect(StickyNoteMarkup.startsOrderedList("1.", continuingExistingItem: false))
    }

    @Test("Heading commands carry the level, others carry none")
    func headingLevels() {
        #expect(StickyNoteCommand.heading1.headingLevel == 1)
        #expect(StickyNoteCommand.heading2.headingLevel == 2)
        #expect(StickyNoteCommand.heading3.headingLevel == 3)
        for command in StickyNoteCommand.allCases where !command.rawValue.hasPrefix("heading") {
            #expect(command.headingLevel == nil)
        }
    }

    @Test("A command is either a marker or a heading, never both")
    func markersAndHeadingsAreExclusive() {
        for command in StickyNoteCommand.allCases {
            #expect(!(command.marker != nil && command.headingLevel != nil))
        }
    }

    @Test("The date is written the way the reader's system writes dates")
    func dateFollowsTheLocale() {
        let date = Date(timeIntervalSince1970: 1_758_326_400)  // 2025-09-20 UTC
        let british = StickyNoteCommand.todaysDate(date, locale: Locale(identifier: "en_GB"))
        let american = StickyNoteCommand.todaysDate(date, locale: Locale(identifier: "en_US"))

        #expect(!british.isEmpty)
        #expect(!american.isEmpty)
        // Not ISO, not a timestamp — a date a person reads.
        #expect(british.contains("2025"))
        #expect(american.contains("2025"))
    }
}
