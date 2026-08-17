import Foundation

// MARK: - Layout Document (Root)

public struct LayoutDocument: Codable, Sendable {
    public var version: Int
    public var grid: GridDimensions
    public var pages: [PageConfig]
    public var globalSettings: GlobalSettings

    public init(
        version: Int = 1,
        grid: GridDimensions = GridDimensions(),
        pages: [PageConfig] = [],
        globalSettings: GlobalSettings = GlobalSettings()
    ) {
        self.version = version
        self.grid = grid
        self.pages = pages
        self.globalSettings = globalSettings
    }
}

// MARK: - Grid Dimensions

public struct GridDimensions: Codable, Sendable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int = GridConstants.columns, rows: Int = GridConstants.rows) {
        self.columns = columns
        self.rows = rows
    }
}

// MARK: - Page Config

public struct PageConfig: Codable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var order: Int
    public var widgets: [WidgetPlacement]

    public init(
        id: String = UUID().uuidString,
        name: String,
        order: Int,
        widgets: [WidgetPlacement] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.widgets = widgets
    }
}

// MARK: - Widget Placement

public struct WidgetPlacement: Codable, Identifiable, Hashable, Sendable {
    public let instanceId: String
    public let widgetId: String
    public var col: Int
    public var row: Int
    public var width: Int
    public var height: Int
    public var config: WidgetConfig

    public var id: String { instanceId }

    public init(
        instanceId: String = UUID().uuidString,
        widgetId: String,
        col: Int,
        row: Int,
        width: Int,
        height: Int,
        config: WidgetConfig = WidgetConfig()
    ) {
        self.instanceId = instanceId
        self.widgetId = widgetId
        self.col = col
        self.row = row
        self.width = width
        self.height = height
        self.config = config
    }

    /// Grid rect occupied by this widget (col..<col+width, row..<row+height)
    public var gridRect: GridRect {
        GridRect(col: col, row: row, width: width, height: height)
    }
}

// MARK: - Grid Rect

public struct GridRect: Hashable, Sendable {
    public let col: Int
    public let row: Int
    public let width: Int
    public let height: Int

    public var endCol: Int { col + width }
    public var endRow: Int { row + height }

    public func intersects(_ other: GridRect) -> Bool {
        col < other.endCol && endCol > other.col &&
        row < other.endRow && endRow > other.row
    }

    public func fitsInGrid(columns: Int, rows: Int) -> Bool {
        col >= 0 && row >= 0 && endCol <= columns && endRow <= rows
    }
}

// MARK: - Global Settings

public struct GlobalSettings: Codable, Sendable {
    public var selectedDisplayName: String?
    public var kioskMode: Bool
    public var launchAtLogin: Bool
    public var debugMode: Bool
    /// When true, the kiosk window NEVER falls back to NSScreen.main if
    /// the configured selectedDisplayName isn't currently enumerated
    /// (e.g. the secondary display is asleep, unplugged, or still
    /// re-handshaking after wake). Instead the window stays parked
    /// off-screen until the target reappears. Default false preserves
    /// the existing fallback-to-non-main-then-main chain in
    /// WindowPlacement.configure.
    public var strictMonitorAffinity: Bool
    /// Hide from the Dock and Cmd-Tab, leaving the menu-bar item as the only
    /// affordance. Suits a kiosk whose window lives on a secondary display.
    /// Default false keeps EdgeControl a normal app.
    public var hideFromDock: Bool
    /// Units the dashboard displays in. Defaults to whatever the user's region
    /// already uses rather than to metric, so a fresh install abroad is right
    /// without anyone going looking for the setting.
    public var units: UnitSystem
    public var theme: ThemeSettings
    /// Drops the kiosk window one notch below the menu-bar level, so system
    /// panels that present there — clipboard managers like Paste, most
    /// hotkey-summoned pickers — appear above the dashboard instead of being
    /// invisibly buried behind it. The trade: the kiosk display's menu bar
    /// can also draw over the dashboard's top edge.
    public var allowSystemPanels: Bool

    public init(
        selectedDisplayName: String? = nil,
        kioskMode: Bool = true,
        launchAtLogin: Bool = false,
        debugMode: Bool = false,
        strictMonitorAffinity: Bool = false,
        hideFromDock: Bool = false,
        units: UnitSystem = .localeDefault,
        theme: ThemeSettings = ThemeSettings(),
        allowSystemPanels: Bool = false
    ) {
        self.selectedDisplayName = selectedDisplayName
        self.kioskMode = kioskMode
        self.launchAtLogin = launchAtLogin
        self.debugMode = debugMode
        self.strictMonitorAffinity = strictMonitorAffinity
        self.hideFromDock = hideFromDock
        self.units = units
        self.theme = theme
        self.allowSystemPanels = allowSystemPanels
    }

    enum CodingKeys: String, CodingKey {
        case selectedDisplayName, kioskMode, launchAtLogin, debugMode
        case strictMonitorAffinity, hideFromDock, units, theme
        case allowSystemPanels
    }

    // Custom Decodable so existing layout.json files (which don't carry
    // strictMonitorAffinity) keep decoding. Synthesized Decodable would
    // throw on a missing key even with a struct-field default. Other
    // fields keep their normal decoding behavior.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedDisplayName = try c.decodeIfPresent(String.self, forKey: .selectedDisplayName)
        kioskMode = try c.decodeIfPresent(Bool.self, forKey: .kioskMode) ?? true
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        debugMode = try c.decodeIfPresent(Bool.self, forKey: .debugMode) ?? false
        strictMonitorAffinity = try c.decodeIfPresent(Bool.self, forKey: .strictMonitorAffinity) ?? false
        hideFromDock = try c.decodeIfPresent(Bool.self, forKey: .hideFromDock) ?? false
        units = try c.decodeIfPresent(UnitSystem.self, forKey: .units) ?? .localeDefault
        theme = try c.decodeIfPresent(ThemeSettings.self, forKey: .theme) ?? ThemeSettings()
        allowSystemPanels = try c.decodeIfPresent(Bool.self, forKey: .allowSystemPanels) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(selectedDisplayName, forKey: .selectedDisplayName)
        try c.encode(kioskMode, forKey: .kioskMode)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(debugMode, forKey: .debugMode)
        try c.encode(strictMonitorAffinity, forKey: .strictMonitorAffinity)
        try c.encode(hideFromDock, forKey: .hideFromDock)
        try c.encode(units, forKey: .units)
        try c.encode(theme, forKey: .theme)
        try c.encode(allowSystemPanels, forKey: .allowSystemPanels)
    }
}
