import Foundation

/// Shared data model between main app and widget extension.
/// Main app encodes to JSON, widget extension decodes.
public struct WidgetData: Codable, Sendable {
    public let timestamp: Date

    // CPU & Memory
    public let cpuUsage: Double
    public let memoryUsage: Double
    public let memoryUsedGB: Double
    public let memoryTotalGB: Double

    // Temperature (Celsius)
    public let cpuTemp: Double?
    public let gpuTemp: Double?
    public let ssdTemp: Double?

    // Disk I/O (bytes/sec)
    public let diskReadRate: Double
    public let diskWriteRate: Double

    // Network (bytes/sec)
    public let networkUpRate: Double
    public let networkDownRate: Double

    // WiFi
    public let wifiSSID: String?
    public let wifiSignalStrength: Int?
    public let wifiChannel: Int?
    public let wifiBand: String?

    // CI/CD
    public let cicdRuns: [WidgetCICDRun]

    public init(
        timestamp: Date = Date(),
        cpuUsage: Double = 0,
        memoryUsage: Double = 0,
        memoryUsedGB: Double = 0,
        memoryTotalGB: Double = 0,
        cpuTemp: Double? = nil,
        gpuTemp: Double? = nil,
        ssdTemp: Double? = nil,
        diskReadRate: Double = 0,
        diskWriteRate: Double = 0,
        networkUpRate: Double = 0,
        networkDownRate: Double = 0,
        wifiSSID: String? = nil,
        wifiSignalStrength: Int? = nil,
        wifiChannel: Int? = nil,
        wifiBand: String? = nil,
        cicdRuns: [WidgetCICDRun] = []
    ) {
        self.timestamp = timestamp
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB
        self.cpuTemp = cpuTemp
        self.gpuTemp = gpuTemp
        self.ssdTemp = ssdTemp
        self.diskReadRate = diskReadRate
        self.diskWriteRate = diskWriteRate
        self.networkUpRate = networkUpRate
        self.networkDownRate = networkDownRate
        self.wifiSSID = wifiSSID
        self.wifiSignalStrength = wifiSignalStrength
        self.wifiChannel = wifiChannel
        self.wifiBand = wifiBand
        self.cicdRuns = cicdRuns
    }

    /// Reads WidgetData from the shared App Group container.
    public static func read() -> WidgetData? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.pakslab.edgecontrol"
        )?.appendingPathComponent("EdgeControlWidgets.json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.widgetDecoder.decode(WidgetData.self, from: data)
    }

    /// Writes WidgetData to the shared App Group container.
    public func write() {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.pakslab.edgecontrol"
        )?.appendingPathComponent("EdgeControlWidgets.json") else { return }
        guard let data = try? JSONEncoder.widgetEncoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Whether data is stale (older than 10 minutes).
    public var isStale: Bool {
        Date().timeIntervalSince(timestamp) > 600
    }

    /// Minutes since last update.
    public var minutesAgo: Int {
        Int(Date().timeIntervalSince(timestamp) / 60)
    }
}

public struct WidgetCICDRun: Codable, Identifiable, Sendable {
    public let id: Int
    public let repoName: String
    public let title: String
    public let status: String
    public let conclusion: String?
    public let url: String
    public let updatedAt: Date

    public init(id: Int, repoName: String, title: String, status: String, conclusion: String?, url: String, updatedAt: Date) {
        self.id = id
        self.repoName = repoName
        self.title = title
        self.status = status
        self.conclusion = conclusion
        self.url = url
        self.updatedAt = updatedAt
    }
}

// MARK: - Plugin Desktop Widget Metadata

/// Metadata about available plugin desktop widgets, written by main app, read by widget extension.
/// Stored at App Group container: PluginWidgets/plugins.json
public struct PluginWidgetManifest: Codable, Sendable {
    public let plugins: [PluginWidgetInfo]
    public let updatedAt: Date

    public init(plugins: [PluginWidgetInfo], updatedAt: Date = Date()) {
        self.plugins = plugins
        self.updatedAt = updatedAt
    }

    /// App Group container directory for plugin widget data
    public static var containerDirectory: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.pakslab.edgecontrol"
        )?.appendingPathComponent("PluginWidgets", isDirectory: true)
    }

    public static func read() -> PluginWidgetManifest? {
        guard let url = containerDirectory?.appendingPathComponent("plugins.json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.widgetDecoder.decode(PluginWidgetManifest.self, from: data)
    }

    public func write() {
        guard let dir = Self.containerDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("plugins.json")
        guard let data = try? JSONEncoder.widgetEncoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Get snapshot image path for a plugin at a given size
    public static func snapshotURL(pluginId: String, size: String) -> URL? {
        containerDirectory?.appendingPathComponent("\(pluginId)_\(size).png")
    }
}

public struct PluginWidgetInfo: Codable, Sendable, Identifiable, Hashable {
    public let id: String           // plugin ID
    public let name: String         // display name
    public let icon: String?        // SF Symbol
    public let sizes: [String]      // ["small", "medium", "large"]

    public init(id: String, name: String, icon: String?, sizes: [String]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.sizes = sizes
    }
}

extension JSONEncoder {
    static let widgetEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let widgetDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
