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
    public var theme: ThemeSettings

    public init(
        selectedDisplayName: String? = nil,
        kioskMode: Bool = true,
        launchAtLogin: Bool = false,
        debugMode: Bool = false,
        theme: ThemeSettings = ThemeSettings()
    ) {
        self.selectedDisplayName = selectedDisplayName
        self.kioskMode = kioskMode
        self.launchAtLogin = launchAtLogin
        self.debugMode = debugMode
        self.theme = theme
    }
}
