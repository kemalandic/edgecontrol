import CoreGraphics
import Foundation

/// An App Drawer tile's settings, read from its config.
struct DrawerSettings: Equatable {
    enum Mode: String, CaseIterable {
        case dock = "Dock"
        case recent = "Recently used"
        case most = "Most used"
        case deck = "Deck"
    }

    enum Style: String, CaseIterable {
        case plain = "Plain"
        case cards = "Cards"
        case dividers = "Dividers"
        case keys = "Keys"
    }

    enum IconSize: String, CaseIterable {
        case auto = "Auto"
        case small = "Small"
        case medium = "Medium"
        case large = "Large"

        var points: CGFloat? {
            switch self {
            case .auto: nil
            case .small: 32
            case .medium: 48
            case .large: 64
            }
        }
    }

    var mode: Mode
    var style: Style
    var iconSize: IconSize
    var showNames: Bool
    var showRunning: Bool
    var deckName: String
    var title: String
    /// Keys without their own colour in the full accent, rather than dimmed.
    var fullAccent: Bool
    /// Their symbols white, rather than the theme colour.
    var whiteIcons: Bool

    init(_ config: WidgetConfig) {
        // "Manual" was Deck mode's name in the App Drawer plugin's first version.
        let mode = config.string("mode", default: Mode.dock.rawValue)
        self.mode = mode == "Manual" ? .deck : Mode(rawValue: mode) ?? .dock
        style = Style(rawValue: config.string("style", default: Style.plain.rawValue)) ?? .plain
        iconSize = IconSize(rawValue: config.string("iconSize", default: IconSize.auto.rawValue)) ?? .auto
        showNames = config.bool("showNames", default: true)
        showRunning = config.bool("showRunning", default: true)
        let deck = config.string("deck", default: "Main").trimmingCharacters(in: .whitespaces)
        deckName = deck.isEmpty ? "Main" : deck
        title = config.string("title").trimmingCharacters(in: .whitespaces)
        fullAccent = config.string("keyColor") == "Accent"
        whiteIcons = config.string("iconColor") == "White"
    }

    var deckId: String { deckName.lowercased() }
}

/// How many tiles fit in a row and a column, and how big their icons are:
/// the arrangement with the biggest icons that still fits every tile, or a
/// page of them.
struct DrawerLayout: Equatable {
    var columns: Int
    var rows: Int
    /// An icon's side, in points.
    var icon: CGFloat
    /// A key's side in the Keys style; 0 otherwise.
    var key: CGFloat

    var perPage: Int { columns * rows }

    static func fit(
        count: Int, width: CGFloat, height: CGFloat, gap: CGFloat, keys: Bool, showNames: Bool, showRunning: Bool,
        fixedIcon: CGFloat?
    ) -> DrawerLayout {
        let nameHeight: CGFloat = showNames && !keys ? 18 : 0
        let dotHeight: CGFloat = showRunning && !keys ? 7 : 0
        // The smallest workable cell: the icon (or 28 points) with its name
        // and dot; a key needs room for its label inside it.
        let minIcon = fixedIcon ?? 28
        let minWidth = keys ? max(56, (fixedIcon ?? 0) * 1.6) : max(minIcon + 10, showNames ? 60 : 40)
        let minHeight = keys ? minWidth : minIcon + nameHeight + dotHeight + 10
        let maxColumns = max(1, Int((width + gap) / (minWidth + gap)))
        let maxRows = max(1, Int((height + gap) / (minHeight + gap)))
        let n = max(1, min(count, maxColumns * maxRows))

        var best: (columns: Int, rows: Int, size: CGFloat, score: CGFloat)?
        for rows in 1...maxRows {
            let columns = min(maxColumns, Int((Double(n) / Double(rows)).rounded(.up)))
            guard columns * rows >= n else { continue }
            let cellWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let size =
                keys
                ? min(cellWidth, cellHeight)
                : min(cellWidth - 12, cellHeight - nameHeight - dotHeight - 12)
            // Empty cells cost a little, so a full grid wins a near tie.
            let score = size - CGFloat(columns * rows - n) * 0.3
            if best == nil || score > best!.score { best = (columns, rows, size, score) }
        }
        let chosen = best ?? (1, 1, min(width, height) - nameHeight - dotHeight - 12, 0)
        if keys {
            let key = max(48, min(fixedIcon.map { $0 * 1.8 } ?? 150, chosen.size)).rounded()
            return DrawerLayout(columns: chosen.columns, rows: chosen.rows, icon: (key * 0.5).rounded(), key: key)
        }
        let icon = max(20, min(fixedIcon ?? 96, chosen.size)).rounded()
        return DrawerLayout(columns: chosen.columns, rows: chosen.rows, icon: icon, key: 0)
    }
}

/// The colour of a symbol or label that reads on a colour: near-black on a
/// light one, white on a dark one, by its relative luminance.
enum Ink {
    static let dark = (red: 18.0 / 255, green: 18.0 / 255, blue: 22.0 / 255)

    static func isLight(red: Double, green: Double, blue: Double, alpha: Double = 1) -> Bool {
        // A colour mostly see-through shows what's under it: dark, here.
        guard alpha >= 0.5 else { return false }
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue) > 0.4
    }
}
