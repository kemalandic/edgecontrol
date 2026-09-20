import AppKit
import SwiftUI

/// The colours a sticky note can be given.
///
/// Two callers need the same answers — the view that draws a note and the
/// converter that turns a pre-RTF note into rich text — and a second hand-kept
/// copy of a colour list is how the two quietly stop matching.
enum StickyNotePalette {

    /// The card tint. Falls back to the widget's themed colour so a note that
    /// was never given one follows the dashboard's accent.
    static func tint(_ name: String, ts: ThemeSettings) -> Color {
        switch name {
        case "orange": .orange
        case "pink": .pink
        case "red": .red
        case "green": .green
        case "mint": .mint
        case "blue": .blue
        case "purple": .purple
        case "gray": .gray
        default: Theme.widgetPrimary("sticky-note", ts: ts, default: .yellow)
        }
    }

    /// "soft white" is a touch darker than pure white — easier on the eyes
    /// against the tinted card.
    static func text(_ name: String) -> NSColor {
        switch name {
        case "white": .white
        case "gray": .systemGray
        case "black": .black
        case "yellow": .systemYellow
        case "orange": .systemOrange
        case "pink": .systemPink
        case "red": .systemRed
        case "green": .systemGreen
        case "mint": .systemMint
        case "blue": .systemBlue
        case "purple": .systemPurple
        default: NSColor(white: 0.85, alpha: 1)
        }
    }
}
