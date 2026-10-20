import Foundation

// MARK: - Decks
//
// A deck is what an App Drawer tile in Deck mode shows: keys that open apps,
// run Shortcuts, open links or files, copy or type text, press hotkeys or
// media keys, do several of those in a row, or open a folder of more keys.
// Every deck lives in one file, Decks.json, in the same format the App
// Drawer plugin's helper used, so decks carry over and a folder synced
// between Macs can be shared with one still running the plugin:
//
//   {
//     "version": 1,
//     "revision": 12,                 bumped on every change
//     "decks": {
//       "main": {                     a tile's Deck Name, lowercased
//         "name": "Main",
//         "order": "manual",          manual | name | type | most | recent
//         "updatedAt": 1791558461478, ms; an older save never replaces a newer one
//         "keys": [
//           { "id": "k…", "title": "Safari", "color": "#3380FF",
//             "icon": "symbol:star.fill",   or emoji:🚀, image:Icons/….png, app:<bundle id>
//             "action": { "type": "app", "bundleId": "com.apple.Safari" },
//             "hold": { "type": "media", "key": "next" } },
//           { "id": "k…", "title": "Work",
//             "action": { "type": "folder", "keys": [ … ] } }
//         ]
//       }
//     }
//   }
//
// Fields this version doesn't know are kept as they were, so a key saved by
// a newer version survives being edited here.

/// A JSON value, kept as it was read.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// Decodes what it can: an entry that isn't the right shape is skipped, so
/// one bad key doesn't cost the rest of its deck.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

extension KeyedDecodingContainer {
    fileprivate func lossyArray<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> [Value]? {
        guard let items = (try? decodeIfPresent([Lossy<Value>].self, forKey: key)) ?? nil else { return nil }
        return items.compactMap(\.value)
    }
}

/// The whole of Decks.json.
public struct DeckFile: Codable, Hashable, Sendable {
    public var version = 1
    public var revision = 0
    public var decks: [String: Deck] = [:]

    public init(revision: Int = 0, decks: [String: Deck] = [:]) {
        self.revision = revision
        self.decks = decks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decode(Int.self, forKey: .version)) ?? 1
        revision = (try? container.decode(Int.self, forKey: .revision)) ?? 0
        decks = try container.decode([String: Lossy<Deck>].self, forKey: .decks).compactMapValues(\.value)
    }
}

/// How a deck lays its keys out.
public enum DeckOrder: String, Codable, CaseIterable, Sendable {
    case manual, name, type, most, recent

    public var title: String {
        switch self {
        case .manual: "As placed"
        case .name: "A–Z"
        case .type: "By type"
        case .most: "Most used"
        case .recent: "Recent"
        }
    }
}

public struct Deck: Codable, Hashable, Sendable {
    public var name: String?
    public var order: DeckOrder
    /// Milliseconds since 1970, as the plugin wrote it.
    public var updatedAt: Double
    public var keys: [DeckKey]

    public init(name: String? = nil, order: DeckOrder = .manual, updatedAt: Double = 0, keys: [DeckKey] = []) {
        self.name = name
        self.order = order
        self.updatedAt = updatedAt
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        order = (try? container.decodeIfPresent(DeckOrder.self, forKey: .order)) ?? .manual
        updatedAt = (try? container.decodeIfPresent(Double.self, forKey: .updatedAt)) ?? 0
        keys = container.lossyArray(DeckKey.self, forKey: .keys) ?? []
    }
}

public struct DeckKey: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String?
    /// "#RRGGBB"; nil for the dimmed or full accent.
    public var color: String?
    /// symbol:<SF Symbol>, emoji:<a few characters>, image:Icons/<file>, or
    /// app:<bundle id>; nil for the action's usual look.
    public var icon: String?
    public var action: KeyAction
    /// What holding the key for half a second does instead.
    public var hold: KeyAction?

    public init(
        id: String = DeckKey.newId(), title: String? = nil, color: String? = nil, icon: String? = nil,
        action: KeyAction, hold: KeyAction? = nil
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.icon = icon
        self.action = action
        self.hold = hold
    }

    public static func newId() -> String {
        "k" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }
}

/// What a key does. One shape for every kind, with the fields each kind
/// uses, as in the file; `type` says which.
public struct KeyAction: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case app, shortcut, url, file, text, hotkey, media, multi, wait, folder
    }

    public var type: String
    public var bundleId: String?
    /// A Shortcut's identifier ("id" in the file).
    public var shortcutId: String?
    /// A Shortcut's name, or a preset hotkey's ("Area Screenshot").
    public var name: String?
    public var url: String?
    public var path: String?
    public var text: String?
    /// For text: "type" types it into the app in front; otherwise it's copied.
    public var mode: String?
    public var keyCode: Int?
    /// control, option, shift, command.
    public var modifiers: [String]?
    /// How a hotkey reads: "⇧⌘4".
    public var display: String?
    /// A media key: playPause, next, previous, volumeUp, volumeDown, mute.
    public var key: String?
    public var seconds: Double?
    /// A folder's keys.
    public var keys: [DeckKey]?
    /// A multi-action's steps.
    public var steps: [KeyAction]?
    /// Fields this version doesn't know.
    public var extra: [String: JSONValue] = [:]

    public var kind: Kind? { Kind(rawValue: type) }

    public init(_ kind: Kind) {
        type = kind.rawValue
    }

    public static func app(_ bundleId: String) -> KeyAction {
        var action = KeyAction(.app)
        action.bundleId = bundleId
        return action
    }

    public static func shortcut(id: String, name: String) -> KeyAction {
        var action = KeyAction(.shortcut)
        action.shortcutId = id
        action.name = name
        return action
    }

    public static func link(_ url: String) -> KeyAction {
        var action = KeyAction(.url)
        action.url = url
        return action
    }

    public static func file(_ path: String) -> KeyAction {
        var action = KeyAction(.file)
        action.path = path
        return action
    }

    public static func text(_ text: String, typed: Bool = false) -> KeyAction {
        var action = KeyAction(.text)
        action.text = text
        action.mode = typed ? "type" : nil
        return action
    }

    public static func hotkey(_ preset: HotkeyPreset) -> KeyAction {
        var action = KeyAction(.hotkey)
        action.keyCode = preset.keyCode
        action.modifiers = preset.modifiers
        action.name = preset.name
        action.display = preset.display
        return action
    }

    public static func media(_ key: MediaKey) -> KeyAction {
        var action = KeyAction(.media)
        action.key = key.rawValue
        return action
    }

    public static func folder(_ keys: [DeckKey] = []) -> KeyAction {
        var action = KeyAction(.folder)
        action.keys = keys
        return action
    }

    public static func multi(_ steps: [KeyAction] = []) -> KeyAction {
        var action = KeyAction(.multi)
        action.steps = steps
        return action
    }

    public static func wait(_ seconds: Double = 0.5) -> KeyAction {
        var action = KeyAction(.wait)
        action.seconds = seconds
        return action
    }

    public var typesText: Bool { kind == .text && mode == "type" }
}

extension KeyAction: Codable {
    private struct Field: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ name: String) { stringValue = name }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private static let known: Set<String> = [
        "type", "bundleId", "id", "name", "url", "path", "text", "mode", "keyCode", "modifiers", "display", "key",
        "seconds", "keys", "steps",
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Field.self)
        func string(_ name: String) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: Field(name))) ?? nil
        }
        type = try container.decode(String.self, forKey: Field("type"))
        bundleId = string("bundleId")
        shortcutId = string("id")
        name = string("name")
        url = string("url")
        path = string("path")
        text = string("text")
        mode = string("mode")
        display = string("display")
        key = string("key")
        if let code = (try? container.decodeIfPresent(Double.self, forKey: Field("keyCode"))) ?? nil {
            keyCode = Int(exactly: code)
        }
        modifiers = (try? container.decodeIfPresent([String].self, forKey: Field("modifiers"))) ?? nil
        seconds = (try? container.decodeIfPresent(Double.self, forKey: Field("seconds"))) ?? nil
        keys = container.lossyArray(DeckKey.self, forKey: Field("keys"))
        steps = container.lossyArray(KeyAction.self, forKey: Field("steps"))
        for field in container.allKeys where !Self.known.contains(field.stringValue) {
            extra[field.stringValue] = try? container.decode(JSONValue.self, forKey: field)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Field.self)
        for (name, value) in extra { try container.encode(value, forKey: Field(name)) }
        try container.encode(type, forKey: Field("type"))
        try container.encodeIfPresent(bundleId, forKey: Field("bundleId"))
        try container.encodeIfPresent(shortcutId, forKey: Field("id"))
        try container.encodeIfPresent(name, forKey: Field("name"))
        try container.encodeIfPresent(url, forKey: Field("url"))
        try container.encodeIfPresent(path, forKey: Field("path"))
        try container.encodeIfPresent(text, forKey: Field("text"))
        try container.encodeIfPresent(mode, forKey: Field("mode"))
        try container.encodeIfPresent(keyCode, forKey: Field("keyCode"))
        try container.encodeIfPresent(modifiers, forKey: Field("modifiers"))
        try container.encodeIfPresent(display, forKey: Field("display"))
        try container.encodeIfPresent(key, forKey: Field("key"))
        try container.encodeIfPresent(seconds, forKey: Field("seconds"))
        try container.encodeIfPresent(keys, forKey: Field("keys"))
        try container.encodeIfPresent(steps, forKey: Field("steps"))
    }
}

// MARK: - Keeping decks a sensible shape
//
// Decks come from a file another Mac can write, and from the tile, so they
// are checked before anything acts on them: strings are capped, a deck holds
// at most 500 keys, folders nest at most four deep, a multi-action has at
// most 20 steps and none of them are folders or multi-actions, and a key
// can't open a folder by being held.

extension Deck {
    public static let maxKeys = 500

    public func sanitized() -> Deck {
        var budget = Self.maxKeys
        var clean = self
        clean.name = name.map { String($0.prefix(80)) }
        clean.keys = Self.sanitized(keys, depth: 0, budget: &budget)
        return clean
    }

    static func sanitized(_ keys: [DeckKey], depth: Int, budget: inout Int) -> [DeckKey] {
        guard depth <= 4 else { return [] }
        var out: [DeckKey] = []
        for key in keys {
            guard budget > 0, !key.id.isEmpty, key.id.count <= 64, !key.action.type.isEmpty,
                key.action.type.count <= 32
            else { continue }
            budget -= 1
            var clean = key
            clean.title = key.title.map { String($0.prefix(80)) }
            clean.color = key.color.flatMap { DeckKey.isHexColor($0) ? $0 : nil }
            clean.icon = key.icon.flatMap { DeckKey.isIconSpec($0) ? $0 : nil }
            clean.action = key.action.capped()
            if key.action.kind == .folder {
                clean.action.keys = sanitized(key.action.keys ?? [], depth: depth + 1, budget: &budget)
            }
            clean.hold = key.hold.flatMap {
                $0.kind == .folder || $0.type.isEmpty || $0.type.count > 32 ? nil : $0.capped()
            }
            out.append(clean)
        }
        return out
    }
}

extension DeckKey {
    public static func isHexColor(_ text: String) -> Bool {
        text.count == 7 && text.hasPrefix("#") && text.dropFirst().allSatisfy(\.isHexDigit)
    }

    /// symbol:<SF Symbol name>, emoji:<a few characters>, app:<bundle id>,
    /// or image:Icons/<file>, which must stay inside the decks folder's Icons/.
    public static func isIconSpec(_ text: String) -> Bool {
        guard text.count <= 200, let colon = text.firstIndex(of: ":") else { return false }
        let value = text[text.index(after: colon)...]
        switch text[..<colon] {
        case "symbol": return !value.isEmpty && value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." }
        case "emoji": return !value.isEmpty && value.count <= 4
        case "app": return !value.isEmpty
        case "image": return value.hasPrefix("Icons/") && !value.contains("..") && !value.dropFirst(6).contains("/")
        default: return false
        }
    }
}

extension KeyAction {
    /// Strings capped at 4,000 characters, and a multi-action's steps
    /// checked. A folder's keys are checked by `Deck.sanitized`.
    func capped() -> KeyAction {
        func cap(_ text: String?) -> String? { text.map { String($0.prefix(4000)) } }
        var clean = self
        clean.bundleId = cap(bundleId)
        clean.shortcutId = cap(shortcutId)
        clean.name = cap(name)
        clean.url = cap(url)
        clean.path = cap(path)
        clean.text = cap(text)
        clean.display = cap(display).map { String($0.prefix(40)) }
        clean.modifiers = modifiers?.filter { HotkeyPreset.modifierNames.contains($0) }
        if kind == .multi {
            clean.steps = (steps ?? [])
                .filter { $0.kind != .folder && $0.kind != .multi && !$0.type.isEmpty && $0.type.count <= 32 }
                .prefix(20)
                .map { $0.capped() }
        } else {
            clean.steps = nil
        }
        if kind != .folder { clean.keys = nil }
        return clean
    }
}

// MARK: - Keyboard keys

/// A media key, as the keyboard's own (NX_KEYTYPE_*).
public enum MediaKey: String, CaseIterable, Sendable {
    case playPause, previous, next, volumeUp, volumeDown, mute

    public var title: String {
        switch self {
        case .playPause: "Play/Pause"
        case .previous: "Previous track"
        case .next: "Next track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .mute: "Mute"
        }
    }

    public var symbol: String {
        switch self {
        case .playPause: "playpause.fill"
        case .previous: "backward.end.fill"
        case .next: "forward.end.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        }
    }

    /// NX_KEYTYPE_SOUND_UP and so on.
    var systemCode: Int {
        switch self {
        case .volumeUp: 0
        case .volumeDown: 1
        case .mute: 7
        case .playPause: 16
        case .next: 17
        case .previous: 18
        }
    }
}

/// A keyboard shortcut worth a key of its own.
public struct HotkeyPreset: Hashable, Sendable {
    public let name: String
    public let keyCode: Int
    public let modifiers: [String]
    public let display: String

    public static let modifierNames: Set<String> = ["control", "option", "shift", "command"]
    static let modifierSymbols: [(name: String, symbol: String)] = [
        ("control", "⌃"), ("option", "⌥"), ("shift", "⇧"), ("command", "⌘"),
    ]

    /// How a shortcut reads, modifiers in the system's order: "⇧⌘4".
    public static func display(keyCode: Int, modifiers: [String]) -> String {
        modifierSymbols.filter { modifiers.contains($0.name) }.map(\.symbol).joined()
            + (keyNames[keyCode] ?? "Key \(keyCode)")
    }

    public static let groups: [(name: String, presets: [HotkeyPreset])] = [
        (
            "Editing",
            [
                .init("Copy", 8, ["command"]), .init("Paste", 9, ["command"]), .init("Cut", 7, ["command"]),
                .init("Undo", 6, ["command"]), .init("Redo", 6, ["shift", "command"]),
                .init("Select All", 0, ["command"]), .init("Find", 3, ["command"]), .init("Save", 1, ["command"]),
            ]
        ),
        (
            "Windows and apps",
            [
                .init("New Tab", 17, ["command"]), .init("Close Window", 13, ["command"]),
                .init("Minimize", 46, ["command"]), .init("Full Screen", 3, ["control", "command"]),
                .init("Hide App", 4, ["command"]), .init("Quit App", 12, ["command"]),
                .init("Force Quit…", 53, ["option", "command"]),
            ]
        ),
        (
            "Screenshots",
            [
                .init("Area Screenshot", 21, ["shift", "command"]), .init("Full Screenshot", 20, ["shift", "command"]),
                .init("Screenshot Tools", 23, ["shift", "command"]),
            ]
        ),
        (
            "System",
            [
                .init("Spotlight", 49, ["command"]), .init("Mission Control", 126, ["control"]),
                .init("App Windows", 125, ["control"]), .init("Space Left", 123, ["control"]),
                .init("Space Right", 124, ["control"]), .init("Emoji & Symbols", 49, ["control", "command"]),
                .init("Lock Screen", 12, ["control", "command"]),
            ]
        ),
    ]

    init(_ name: String, _ keyCode: Int, _ modifiers: [String]) {
        self.name = name
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = Self.display(keyCode: keyCode, modifiers: modifiers)
    }

    /// How a key reads in a shortcut, by key code (US layout).
    public static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥",
        49: "Space", 50: "`", 51: "⌫", 53: "⎋", 115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟", 123: "←",
        124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

// MARK: - What keys are called

extension KeyAction {
    /// What "By type" sorts kinds of key in.
    var typeRank: Int {
        switch kind {
        case .folder: 0
        case .app: 1
        case .shortcut: 2
        case .url: 3
        case .file: 4
        case .text: 5
        case .hotkey: 6
        case .media: 7
        case .multi: 8
        default: 9
        }
    }

    /// The SF Symbol for an action without an icon of its own.
    public var symbol: String {
        switch kind {
        case .shortcut: "square.2.layers.3d"
        case .url: "globe"
        case .file: "doc"
        case .folder: "folder.fill"
        case .text: typesText ? "keyboard" : "doc.on.clipboard"
        case .hotkey: "command"
        case .media: MediaKey(rawValue: key ?? "")?.symbol ?? "playpause.fill"
        case .multi: "square.stack.3d.down.right.fill"
        case .wait: "hourglass"
        case .app: "app"
        case nil: "questionmark"
        }
    }

    /// A key's name when it has no title of its own. Apps are named by the
    /// caller, which knows what's installed.
    public func defaultTitle(appName: (String) -> String?) -> String {
        switch kind {
        case .app: return bundleId.flatMap(appName) ?? bundleId ?? "App"
        case .shortcut: return name ?? "Shortcut"
        case .url:
            let link = url ?? ""
            if let host = URL(string: link)?.host { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
            return link.isEmpty ? "Link" : link
        case .file: return ((path ?? "") as NSString).lastPathComponent
        case .folder: return "Folder"
        case .text: return String((text ?? "Text").prefix(24))
        case .hotkey: return name ?? display ?? "Hotkey"
        case .media: return MediaKey(rawValue: key ?? "")?.title ?? "Media key"
        case .multi: return "Multi-action"
        case .wait: return "Wait"
        case nil: return type
        }
    }

    /// What kind of key it is, in a list: "Link · https://…".
    public var subtitle: String {
        switch kind {
        case .app: return "App"
        case .shortcut: return "Shortcut"
        case .url: return "Link · " + (url ?? "")
        case .file: return "File · " + (path ?? "")
        case .text: return typesText ? "Types text" : "Copies text"
        case .hotkey: return "Hotkey" + (display.map { " · " + $0 } ?? "")
        case .media: return "Media key"
        case .multi:
            let count = steps?.count ?? 0
            return "Multi-action · \(count) step\(count == 1 ? "" : "s")"
        case .folder:
            let count = keys?.count ?? 0
            return "Folder · \(count) key\(count == 1 ? "" : "s")"
        case .wait: return "Wait"
        case nil: return type
        }
    }

    /// Whether running it posts keyboard events, which needs Accessibility.
    public var needsEventAccess: Bool {
        switch kind {
        case .hotkey, .media: return true
        case .text: return typesText
        case .multi: return (steps ?? []).contains(where: \.needsEventAccess)
        default: return false
        }
    }
}

extension DeckKey {
    public func title(appName: (String) -> String?) -> String {
        if let title, !title.isEmpty { return title }
        return action.defaultTitle(appName: appName)
    }
}

// MARK: - Order

extension DeckOrder {
    /// The keys in this order. Most used and Recent put apps first, by how
    /// much or how lately each was used (`appRank`, lower first); other
    /// keys follow by name.
    public func arrange(
        _ keys: [DeckKey], title: (DeckKey) -> String, appRank: (String) -> Int?
    ) -> [DeckKey] {
        func byName(_ a: DeckKey, _ b: DeckKey) -> Bool {
            title(a).localizedCaseInsensitiveCompare(title(b)) == .orderedAscending
        }
        switch self {
        case .manual:
            return keys
        case .name:
            return keys.sorted(by: byName)
        case .type:
            return keys.sorted { a, b in
                a.action.typeRank != b.action.typeRank ? a.action.typeRank < b.action.typeRank : byName(a, b)
            }
        case .most, .recent:
            func rank(_ key: DeckKey) -> Int {
                key.action.kind == .app ? key.action.bundleId.flatMap(appRank) ?? .max : .max
            }
            return keys.sorted { a, b in rank(a) != rank(b) ? rank(a) < rank(b) : byName(a, b) }
        }
    }
}

// MARK: - Finding and changing keys

extension [DeckKey] {
    /// The keys inside the folder at `path` (folder key ids from the top).
    public func level(_ path: [String]) -> [DeckKey] {
        var keys = self
        for id in path {
            guard let folder = keys.first(where: { $0.id == id }), folder.action.kind == .folder else { return [] }
            keys = folder.action.keys ?? []
        }
        return keys
    }

    /// Changes the keys of the folder at `path`.
    public mutating func editLevel(_ path: [String], _ change: (inout [DeckKey]) -> Void) {
        guard let first = path.first else { return change(&self) }
        guard let index = firstIndex(where: { $0.id == first && $0.action.kind == .folder }) else { return }
        var inner = self[index].action.keys ?? []
        inner.editLevel([String](path.dropFirst()), change)
        self[index].action.keys = inner
    }

    /// The key with this id, at any depth.
    public func find(_ id: String) -> DeckKey? {
        for key in self {
            if key.id == id { return key }
            if let found = key.action.keys?.find(id) { return found }
        }
        return nil
    }

    /// Changes the key with this id, at any depth. False if there's none.
    @discardableResult
    public mutating func update(_ id: String, _ change: (inout DeckKey) -> Void) -> Bool {
        for index in indices {
            if self[index].id == id {
                change(&self[index])
                return true
            }
            if var inner = self[index].action.keys, inner.update(id, change) {
                self[index].action.keys = inner
                return true
            }
        }
        return false
    }

    /// Removes the key with this id, at any depth.
    public mutating func remove(_ id: String) {
        removeAll { $0.id == id }
        for index in indices where self[index].action.keys != nil {
            self[index].action.keys?.remove(id)
        }
    }

    /// Every key at every depth.
    public var totalCount: Int {
        reduce(0) { $0 + 1 + ($1.action.keys?.totalCount ?? 0) }
    }
}
