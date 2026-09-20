import AppKit
import Carbon.HIToolbox
import Testing

@testable import EdgeControl

/// Capture writes into a note the person is not looking at, from a window
/// that closes straight after. Nothing about it is visible while it happens,
/// so what has to be certain is that the line lands and nothing already there
/// is disturbed.
@Suite("Quick capture")
@MainActor
struct QuickCaptureTests {

    private let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
    private let colour = NSColor.white

    private func append(_ line: String, to existing: NSAttributedString?) -> NSAttributedString? {
        QuickCapture.appending(line, to: existing, baseFont: font, textColor: colour)
    }

    @Test("The first capture makes the note, with a heading to name it")
    func firstCaptureSeedsTheNote() throws {
        let note = try #require(append("buy stamps", to: nil))
        #expect(note.string == "Inbox\nbuy stamps")

        // The heading is what the index reads as the note's title, so the
        // widget picker has something recognisable to point at.
        #expect(NoteIndex.title(fromPlainText: note.string) == "Inbox")
        let headingFont = note.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect((headingFont?.pointSize ?? 0) > font.pointSize)
    }

    @Test("Later captures are added under what is already there")
    func laterCapturesAppend() throws {
        let first = try #require(append("one", to: nil))
        let second = try #require(append("two", to: first))
        let third = try #require(append("three", to: second))

        #expect(third.string == "Inbox\none\ntwo\nthree")
    }

    @Test("Nothing typed captures nothing")
    func emptyCapturesAreRefused() {
        #expect(append("", to: nil) == nil)
        #expect(append("   ", to: nil) == nil)
        #expect(append("\n\t ", to: nil) == nil)
    }

    @Test("Surrounding space is not part of the line")
    func linesAreTrimmed() throws {
        let note = try #require(append("  padded  ", to: nil))
        #expect(note.string.hasSuffix("padded"))
        #expect(!note.string.hasSuffix(" "))
    }

    /// The inbox is a note like any other — someone will open it and edit it,
    /// and the next capture must not flatten what they did.
    @Test("An edited note keeps its formatting when something is captured into it")
    func existingFormattingSurvives() throws {
        let edited = NoteMarkdown.attributed(
            fromMarkdown: "# Inbox\n- [x] done already\n**bold line**",
            baseFont: font, textColor: colour)

        let note = try #require(append("new thought", to: edited))

        #expect(note.string.hasPrefix(edited.string))
        #expect(note.string.hasSuffix("new thought"))
        // The checkbox and the emphasis are still what they were.
        #expect(NoteMarkdown.markdown(from: note, baseFont: font).contains("- [x] done already"))
        #expect(NoteMarkdown.markdown(from: note, baseFont: font).contains("**bold line**"))
    }

    @Test("A captured line is a line, not a list item")
    func capturesArePlain() throws {
        // Plenty of what lands here is a thought rather than a task, and
        // turning one into a to-do in the note is a single keystroke.
        let note = try #require(append("think about the grid", to: nil))
        let lines = note.string.components(separatedBy: "\n")
        #expect(StickyNoteMarkup.marker(of: lines.last ?? "") == nil)
    }

    @Test("A captured line survives being written to a note and read back")
    func roundTripsThroughRTF() throws {
        let note = try #require(append("remember the milk", to: nil))
        let data = try #require(
            note.rtf(
                from: NSRange(location: 0, length: note.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))
        let restored = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        #expect(restored.string == note.string)
    }

    @Test("The inbox has a fixed identity, so its file and its picker entry are stable")
    func inboxIdentity() {
        #expect(QuickCapture.inboxNoteId == "inbox")
        #expect(NoteMedia.isSafeFilename(QuickCapture.inboxNoteId + ".rtf"))
    }

    @Test("The key is one nothing else on the machine is likely to want")
    func theChosenKey() {
        // Cmd+Shift+N would be taken from Finder's New Folder everywhere.
        #expect(QuickCaptureService.modifiers & UInt32(cmdKey) == 0)
        #expect(QuickCaptureService.modifiers & UInt32(controlKey) != 0)
        #expect(QuickCaptureService.modifiers & UInt32(optionKey) != 0)
    }
}
