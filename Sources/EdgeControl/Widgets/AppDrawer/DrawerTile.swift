import AppKit
import SwiftUI

/// One tile in an App Drawer: an app, or a deck's key.
struct DrawerTile: Identifiable {
    enum Look: Sendable {
        /// An app's own icon.
        case app(String)
        /// A file's or folder's icon, as Finder shows it.
        case file(String)
        /// A picture chosen for the key, which fills it.
        case picture(URL)
        case symbol(String)
        case emoji(String)
    }

    let id: String
    var label: String
    var look: Look
    /// The key's own colour, if it has one.
    var color: Color?
    var running = false
    var front = false
    var launching = false
    var missing = false
    var failed = false
    var fired = false
    /// The first app after the Dock's divider.
    var divider = false
    /// A neutral key (Back) rather than an accented one.
    var neutral = false
    var action: TileAction
    /// The key, when holding it does something.
    var holdKey: DeckKey?

    var isGlyph: Bool {
        switch look {
        case .symbol, .emoji: true
        case .app, .file, .picture: false
        }
    }
}

/// What tapping a tile does.
enum TileAction: Sendable {
    case openApp(String)
    case runKey(DeckKey)
    case openFolder(String)
    case back
}

/// Where tiles' images come from, cached by the service.
@MainActor
struct DrawerImages {
    var app: @MainActor (String) -> NSImage?
    var file: @MainActor (String) -> NSImage?
    var picture: @MainActor (URL) -> NSImage?

    func icon(_ look: DrawerTile.Look) -> NSImage? {
        switch look {
        case .app(let bundleId): app(bundleId)
        case .file(let path): file(path)
        case .picture(let url): picture(url)
        case .symbol, .emoji: nil
        }
    }
}

extension Color {
    /// A key's "#RRGGBB".
    init?(deckHex text: String) {
        guard DeckKey.isHexColor(text), let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
        self.init(
            .sRGB, red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

/// How keys without a colour of their own look, from the tile's settings.
struct KeyPalette {
    var accent: Color
    var fullAccent: Bool
    var whiteIcons: Bool

    static let neutral = Color.white.opacity(0.10)

    /// The macOS app icon's outline: Apple's continuous-corner rectangle
    /// with a corner radius of 26.15% of its side, which matches the
    /// system's own icons to within a pixel.
    static func iconShape(_ side: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: side * 0.2615, style: .continuous)
    }

    /// macOS draws an app's icon in the middle 824 of its 1024 points and
    /// leaves the rest for its shadow, so an app's image is drawn larger
    /// than its box to make the icon itself the size of a key beside it.
    static let appIconScale: CGFloat = 1024 / 824

    func fill(_ tile: DrawerTile) -> Color {
        if let color = tile.color { return color }
        if tile.neutral { return Self.neutral }
        return fullAccent ? accent : accent.opacity(0.22)
    }

    func ink(_ tile: DrawerTile) -> Color {
        if let color = tile.color { return Self.ink(on: color) }
        if tile.neutral { return .white }
        if whiteIcons { return .white }
        return fullAccent ? Self.ink(on: accent) : accent
    }

    /// A key's label in the Keys style: the ink on a key of its own colour
    /// or the full accent, and the usual text color on a dimmed or plain one.
    func label(_ tile: DrawerTile) -> Color {
        if let color = tile.color { return Self.ink(on: color) }
        if fullAccent && tile.isGlyph && !tile.neutral { return ink(tile) }
        return Color.white.opacity(0.92)
    }

    /// Near-black or white, whichever reads on `color`.
    static func ink(on color: Color) -> Color {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return .white }
        let light = Ink.isLight(
            red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
        return light ? Color(.sRGB, red: Ink.dark.red, green: Ink.dark.green, blue: Ink.dark.blue) : .white
    }
}

/// A tile's icon in the Plain, Cards and Dividers styles: an app's icon, or
/// a key in the shape of one.
struct DrawerIcon: View {
    let tile: DrawerTile
    let side: CGFloat
    let palette: KeyPalette
    let images: DrawerImages

    var body: some View {
        switch tile.look {
        case .app, .file:
            let big = side * KeyPalette.appIconScale
            Group {
                if let image = images.icon(tile.look) {
                    Image(nsImage: image).resizable().interpolation(.high)
                } else {
                    KeyPalette.iconShape(side / KeyPalette.appIconScale).fill(KeyPalette.neutral)
                }
            }
            .frame(width: big, height: big)
            .frame(width: side, height: side)
        case .picture:
            Group {
                if let image = images.icon(tile.look) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: side, height: side)
            .clipShape(KeyPalette.iconShape(side))
        case .symbol, .emoji:
            ZStack {
                KeyPalette.iconShape(side).fill(palette.fill(tile))
                KeyGlyph(look: tile.look, size: side * 0.5, color: palette.ink(tile))
            }
            .frame(width: side, height: side)
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 2, y: 2)
        }
    }
}

/// A symbol in the key's ink, or an emoji in its own colours.
struct KeyGlyph: View {
    let look: DrawerTile.Look
    let size: CGFloat
    let color: Color

    var body: some View {
        switch look {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
        case .emoji(let text):
            Text(text).font(.system(size: size * 1.2))
        case .app, .file, .picture:
            EmptyView()
        }
    }
}

/// A tile in the Keys style: a square key with its label inside, like a
/// Stream Deck, in the key's colour edge to edge.
struct DrawerKey: View {
    let tile: DrawerTile
    let side: CGFloat
    let palette: KeyPalette
    let labelFont: Font
    let images: DrawerImages

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.18, style: .continuous)
        let ink = tile.isGlyph || tile.color != nil ? palette.ink(tile) : Color.white.opacity(0.92)
        ZStack(alignment: .bottom) {
            if isPicture, let image = images.icon(tile.look) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: side, height: side).clipped()
            } else {
                shape.fill(tile.isGlyph || tile.color != nil ? palette.fill(tile) : Color.white.opacity(0.12))
            }
            VStack(spacing: side * 0.05) {
                Group {
                    switch tile.look {
                    case .app, .file:
                        if let image = images.icon(tile.look) {
                            Image(nsImage: image).resizable().interpolation(.high)
                        }
                    case .symbol, .emoji:
                        KeyGlyph(look: tile.look, size: side * 0.3, color: ink)
                    case .picture:
                        Color.clear
                    }
                }
                .frame(width: side * 0.5, height: side * 0.5)
                Text(tile.label)
                    .font(labelFont)
                    .foregroundStyle(isPicture ? .white : palette.label(tile))
                    .shadow(color: isPicture ? .black.opacity(0.8) : .clear, radius: 2, y: 1)
                    .lineLimit(1)
                    .padding(.horizontal, side * 0.06)
            }
            .padding(.top, side * 0.09)
            .padding(.bottom, side * 0.08)
            .frame(width: side, height: side, alignment: isPicture ? .bottom : .center)
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(tile.isGlyph || tile.color != nil ? 0 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 3)
    }

    private var isPicture: Bool {
        if case .picture = tile.look { return true }
        return false
    }
}

// MARK: - A deck's keys as tiles

@MainActor
extension DrawerTile {
    /// A key as the tile, the picker and the deck editor all show it: its
    /// own icon if that can be shown (a misspelt symbol or a missing picture
    /// falls back), or its action's.
    static func look(_ key: DeckKey, service: AppDrawerService, decks: DeckStore) -> Look {
        if let icon = key.icon, let colon = icon.firstIndex(of: ":") {
            let value = String(icon[icon.index(after: colon)...])
            switch icon[..<colon] {
            case "symbol" where NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil:
                return .symbol(value)
            case "emoji":
                return .emoji(value)
            case "image":
                if let url = decks.pictureURL(icon), FileManager.default.fileExists(atPath: url.path) {
                    return .picture(url)
                }
            case "app" where service.appIcon(value) != nil:
                return .app(value)
            default:
                break
            }
        }
        switch key.action.kind {
        case .app: return .app(key.action.bundleId ?? "")
        case .file where service.fileIcon(key.action.path ?? "") != nil: return .file(key.action.path ?? "")
        default: return .symbol(key.action.symbol)
        }
    }

    static func key(_ key: DeckKey, service: AppDrawerService, decks: DeckStore) -> DrawerTile {
        let action = key.action
        let bundleId = action.kind == .app ? action.bundleId : nil
        return DrawerTile(
            id: key.id, label: key.title(appName: service.appName), look: look(key, service: service, decks: decks),
            color: key.color.flatMap(Color.init(deckHex:)),
            running: bundleId.map(service.running.contains) ?? false,
            front: bundleId != nil && service.frontmost == bundleId,
            launching: bundleId.map(service.launching.contains) ?? false,
            missing: bundleId.map { service.apps[$0] == nil && !service.apps.isEmpty } ?? false,
            failed: service.failures[key.id] != nil, fired: service.fired.contains(key.id),
            action: action.kind == .folder ? .openFolder(key.id) : .runKey(key),
            holdKey: key.hold == nil ? nil : key)
    }
}
