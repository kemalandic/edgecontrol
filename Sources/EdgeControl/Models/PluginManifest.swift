import Foundation

// MARK: - Plugin Manifest (parsed from manifest.json in .ecplugin bundle)

public struct PluginManifest: Codable, Identifiable, Sendable {
    public let id: String                    // e.g. "com.example.mywidget"
    public let name: String
    public let version: String
    public let author: String
    public let description: String?
    public let homepage: String?
    public let minAppVersion: String?
    public let permissions: [PluginPermission]
    public let widgets: [PluginWidgetDef]

    public init(
        id: String, name: String, version: String, author: String,
        description: String? = nil, homepage: String? = nil,
        minAppVersion: String? = nil, permissions: [PluginPermission] = [],
        widgets: [PluginWidgetDef] = []
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.homepage = homepage
        self.minAppVersion = minAppVersion
        self.permissions = permissions
        self.widgets = widgets
    }
}

// MARK: - Plugin Permission

public enum PluginPermission: String, Codable, CaseIterable, Sendable {
    case systemMetrics = "system-metrics"  // CPU, memory, storage, uptime
    case temperature                        // CPU/GPU/SSD temps
    case network                            // Network speed, WiFi info
    case processes                           // Process list
    case media                              // Now playing info
    case bluetooth                          // BT devices
    case audio                              // Audio devices, volume
    case weather                            // Weather data
    case diskIO = "disk-io"                // Disk read/write speeds

    public var displayName: String {
        switch self {
        case .systemMetrics: "System Metrics"
        case .temperature: "Temperature Sensors"
        case .network: "Network Info"
        case .processes: "Process List"
        case .media: "Media Playback"
        case .bluetooth: "Bluetooth Devices"
        case .audio: "Audio Devices"
        case .weather: "Weather Data"
        case .diskIO: "Disk I/O"
        }
    }

    public var iconName: String {
        switch self {
        case .systemMetrics: "cpu"
        case .temperature: "thermometer.medium"
        case .network: "network"
        case .processes: "list.bullet.rectangle"
        case .media: "play.circle"
        case .bluetooth: "wave.3.right"
        case .audio: "speaker.wave.2"
        case .weather: "cloud.sun"
        case .diskIO: "internaldrive"
        }
    }
}

// MARK: - Plugin Widget Definition

public struct PluginWidgetDef: Codable, Identifiable, Sendable {
    public let id: String                    // widget ID within plugin
    public let name: String
    public let description: String?
    public let icon: String?                 // SF Symbol name
    public let htmlFile: String              // relative path to HTML file
    public let supportedSizes: PluginSizeRange
    public let defaultSize: [Int]            // [width, height]
    public let configSchema: [PluginConfigField]?
    public let refreshInterval: Double?      // seconds, nil = default (2s)

    public var widgetSize: WidgetSize {
        WidgetSize(width: defaultSize[safe: 0] ?? 4, height: defaultSize[safe: 1] ?? 3)
    }

    public var sizeRange: WidgetSizeRange {
        WidgetSizeRange(
            min: WidgetSize(width: supportedSizes.min[safe: 0] ?? 2, height: supportedSizes.min[safe: 1] ?? 2),
            max: WidgetSize(width: supportedSizes.max[safe: 0] ?? 10, height: supportedSizes.max[safe: 1] ?? 6)
        )
    }
}

public struct PluginSizeRange: Codable, Sendable {
    public let min: [Int]  // [width, height]
    public let max: [Int]  // [width, height]
}

// MARK: - Plugin Config Field

public struct PluginConfigField: Codable, Sendable {
    public let key: String
    public let label: String
    public let type: String      // "string", "number", "boolean", "color", "select"
    public let defaultValue: PluginConfigValue
    public let options: [String]? // for "select" type

    enum CodingKeys: String, CodingKey {
        case key, label, type
        case defaultValue = "default"
        case options
    }
}

public enum PluginConfigValue: Codable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Double.self) { self = .number(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        throw DecodingError.typeMismatch(PluginConfigValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported plugin config value"))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
}

// MARK: - Loaded Plugin State

public struct LoadedPlugin: Identifiable, Sendable {
    public let manifest: PluginManifest
    public let bundlePath: URL
    public var isEnabled: Bool

    public var id: String { manifest.id }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
