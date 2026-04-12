import SwiftUI

// MARK: - Grid Constants (legacy defaults)

public enum GridConstants {
    public static let columns = 20
    public static let rows = 6
    public static let cellWidth: CGFloat = 128
    public static let cellHeight: CGFloat = 120
    public static let gap: CGFloat = 8
    public static let padding: CGFloat = 16
}

// MARK: - Dynamic Grid

/// Dynamically computed grid based on available screen/window size.
/// Replaces hardcoded GridConstants for grid dimensions.
public struct DynamicGrid: Equatable, Sendable {
    public let columns: Int
    public let rows: Int
    public let cellWidth: CGFloat
    public let cellHeight: CGFloat
    public let totalWidth: CGFloat
    public let totalHeight: CGFloat

    private static let targetCellSize: CGFloat = 120
    private static let minCellSize: CGFloat = 100
    private static let maxCellSize: CGFloat = 160
    private static let minColumns = 6
    private static let maxColumns = 24
    private static let minRows = 4
    private static let maxRows = 12

    /// Minimum screen size to display a grid
    public static let minimumWidth: CGFloat = CGFloat(minColumns) * minCellSize   // 600
    public static let minimumHeight: CGFloat = CGFloat(minRows) * minCellSize     // 400

    /// Calculate grid dimensions for a given available size.
    public static func calculate(width: CGFloat, height: CGFloat) -> DynamicGrid {
        let rawCols = Int(width / targetCellSize)
        let rawRows = Int(height / targetCellSize)

        let cols = min(max(rawCols, minColumns), maxColumns)
        let rows = min(max(rawRows, minRows), maxRows)

        let cellW = width / CGFloat(cols)
        let cellH = height / CGFloat(rows)

        return DynamicGrid(
            columns: cols,
            rows: rows,
            cellWidth: cellW,
            cellHeight: cellH,
            totalWidth: width,
            totalHeight: height
        )
    }

    /// Default grid for XENEON EDGE (2560x720)
    public static let xeneonDefault = DynamicGrid.calculate(width: 2560, height: 720)
}

// MARK: - Widget Size

public struct WidgetSize: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public static func size(_ w: Int, _ h: Int) -> WidgetSize {
        WidgetSize(width: w, height: h)
    }
}

// MARK: - Widget Size Range

public struct WidgetSizeRange: Codable, Hashable, Sendable {
    public let min: WidgetSize
    public let max: WidgetSize

    public init(min: WidgetSize, max: WidgetSize) {
        self.min = min
        self.max = max
    }

    public func contains(_ size: WidgetSize) -> Bool {
        size.width >= min.width && size.width <= max.width &&
        size.height >= min.height && size.height <= max.height
    }
}

// MARK: - Widget Color (arbitrary RGB, Codable)

public struct WidgetColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(_ themeColor: ThemeColor) {
        let resolved = themeColor.color.resolve(in: EnvironmentValues())
        self.red = Double(resolved.red)
        self.green = Double(resolved.green)
        self.blue = Double(resolved.blue)
    }

    public init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(c.redComponent)
        self.green = Double(c.greenComponent)
        self.blue = Double(c.blueComponent)
    }
}

// MARK: - Widget Colors

public struct WidgetColors: Codable, Hashable, Sendable {
    public var primary: WidgetColor
    public var secondary: WidgetColor?
    public var tertiary: WidgetColor?

    public init(primary: WidgetColor, secondary: WidgetColor? = nil, tertiary: WidgetColor? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
    }

    /// Convenience init from ThemeColor — keeps widget defaultColors declarations simple.
    public init(primary: ThemeColor, secondary: ThemeColor? = nil, tertiary: ThemeColor? = nil) {
        self.primary = WidgetColor(primary)
        self.secondary = secondary.map { WidgetColor($0) }
        self.tertiary = tertiary.map { WidgetColor($0) }
    }
}

// MARK: - Widget Category

public enum WidgetCategory: String, Codable, CaseIterable, Sendable {
    case system
    case temperature
    case network
    case media
    case info
    case devtools
    case plugin

    public var displayName: String {
        switch self {
        case .system: "System"
        case .temperature: "Temperature"
        case .network: "Network"
        case .media: "Media"
        case .info: "Info"
        case .devtools: "DevTools"
        case .plugin: "Plugin"
        }
    }

    public var iconName: String {
        switch self {
        case .system: "cpu"
        case .temperature: "thermometer.medium"
        case .network: "network"
        case .media: "play.circle"
        case .info: "info.circle"
        case .devtools: "hammer"
        case .plugin: "puzzlepiece.extension"
        }
    }
}

// MARK: - Widget Config

public struct WidgetConfig: Codable, Hashable, Sendable {
    private var storage: [String: ConfigValue]

    public init(_ values: [String: ConfigValue] = [:]) {
        self.storage = values
    }

    public subscript(key: String) -> ConfigValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    public func bool(_ key: String, default defaultValue: Bool = false) -> Bool {
        if case .bool(let v) = storage[key] { return v }
        return defaultValue
    }

    public func int(_ key: String, default defaultValue: Int = 0) -> Int {
        if case .int(let v) = storage[key] { return v }
        return defaultValue
    }

    public func double(_ key: String, default defaultValue: Double = 0) -> Double {
        if case .double(let v) = storage[key] { return v }
        return defaultValue
    }

    public func string(_ key: String, default defaultValue: String = "") -> String {
        if case .string(let v) = storage[key] { return v }
        return defaultValue
    }

    public func stringArray(_ key: String, default defaultValue: [String] = []) -> [String] {
        if case .stringArray(let v) = storage[key] { return v }
        return defaultValue
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var keys: Dictionary<String, ConfigValue>.Keys { storage.keys }
}

// MARK: - Config Value

public enum ConfigValue: Codable, Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case stringArray([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode([String].self) { self = .stringArray(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(ConfigValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported config value type"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .stringArray(let v): try container.encode(v)
        }
    }
}

// MARK: - Config Schema (for plugin & settings UI)

public struct ConfigSchemaEntry: Codable, Hashable, Sendable {
    public let key: String
    public let label: String
    public let type: ConfigFieldType
    public let defaultValue: ConfigValue
    public let options: [String]?
    public let minValue: Double?
    public let maxValue: Double?
    public let step: Double?

    public init(
        key: String,
        label: String,
        type: ConfigFieldType,
        defaultValue: ConfigValue,
        options: [String]? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        step: Double? = nil
    ) {
        self.key = key
        self.label = label
        self.type = type
        self.defaultValue = defaultValue
        self.options = options
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
    }
}

public enum ConfigFieldType: String, Codable, Hashable, Sendable {
    case toggle
    case stepper
    case slider
    case text
    case picker
    case colorPicker
}

// MARK: - Service Key

/// Identifies a system service that widgets can depend on.
/// Used for lazy service activation — services only run when a widget needs them.
public enum ServiceKey: String, CaseIterable, Hashable, Sendable {
    case metrics        // SystemMetricsService
    case smc            // SMCService (temperatures)
    case network        // NetworkMonitorService
    case wifi           // WiFiService
    case bluetooth      // BluetoothService
    case nowPlaying     // NowPlayingService
    case audio          // AudioService
    case weather        // WeatherService
    case diskIO         // DiskIOService
    case process        // ProcessMonitorService
    case github         // GitHubService
}

// MARK: - Dashboard Widget Protocol

public protocol DashboardWidget: Identifiable where ID == String {
    var widgetId: String { get }
    var displayName: String { get }
    var description: String { get }
    var iconName: String { get }
    var category: WidgetCategory { get }
    var supportedSizes: WidgetSizeRange { get }
    var defaultSize: WidgetSize { get }
    var isConfigurable: Bool { get }
    var configSchema: [ConfigSchemaEntry] { get }
    var defaultColors: WidgetColors { get }
    /// Services this widget requires. Empty = self-contained (no external data).
    var requiredServices: Set<ServiceKey> { get }

    @MainActor @ViewBuilder
    func body(size: WidgetSize, config: WidgetConfig) -> any View

    @MainActor @ViewBuilder
    func settingsBody(config: Binding<WidgetConfig>) -> any View
}

extension DashboardWidget {
    public var id: String { widgetId }
    public var isConfigurable: Bool { !configSchema.isEmpty }

    public var defaultColors: WidgetColors {
        WidgetColors(primary: .cyan)
    }

    public var requiredServices: Set<ServiceKey> { [] }

    public func settingsBody(config: Binding<WidgetConfig>) -> any View {
        EmptyView()
    }

    public func defaultConfig() -> WidgetConfig {
        var config = WidgetConfig()
        for entry in configSchema {
            config[entry.key] = entry.defaultValue
        }
        return config
    }
}
