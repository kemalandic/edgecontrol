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
    /// Bumped whenever the shared payload changes shape. The widget refuses
    /// snapshots it does not recognise rather than rendering wrong data.
    public static let currentSchemaVersion = 2
    public let schemaVersion: Int
    /// Set when there are no runs for a reason worth showing, e.g.
    /// "No accounts configured". Nil when runs are present.
    public let cicdStatusNote: String?
    /// Units the app is displaying in, so the desktop widget agrees with the
    /// dashboard. Optional on purpose and deliberately does NOT bump
    /// schemaVersion: the gate above is strict equality, so bumping would make
    /// the widget reject every snapshot written before the upgrade. An added
    /// optional cannot make an older payload render wrongly — it reads as nil
    /// and falls back to Celsius, which is what those payloads meant.
    public let unitSystem: UnitSystem?

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
        cicdRuns: [WidgetCICDRun] = [],
        cicdStatusNote: String? = nil,
        unitSystem: UnitSystem? = nil
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
        self.cicdStatusNote = cicdStatusNote
        self.unitSystem = unitSystem
        // Derived, never passed in.
        self.schemaVersion = Self.currentSchemaVersion
    }

    /// Reads WidgetData from the shared App Group container.
    public static func read() -> WidgetData? {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.pakslab.edgecontrol"
        )?.appendingPathComponent("EdgeControlWidgets.json") else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decode(from: data)
    }

    /// Returns nil for a snapshot written by a different schema version, so
    /// the widget can say "open the app to refresh" instead of rendering
    /// stale or wrong data.
    public static func decode(from data: Data) -> WidgetData? {
        guard let decoded = try? JSONDecoder.widgetDecoder.decode(WidgetData.self, from: data),
              decoded.schemaVersion == currentSchemaVersion else { return nil }
        return decoded
    }

    /// Writes WidgetData to the shared App Group container.
    public func write() {
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.ai.pakslab.edgecontrol"
        )?.appendingPathComponent("EdgeControlWidgets.json") else { return }
        let data: Data
        do {
            data = try JSONEncoder.widgetEncoder.encode(self)
        } catch {
            AppLog.persistence.error(
                "encoding widget snapshot failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        // A failure here freezes the desktop widget on stale data.
        AppLog.attempt("writing widget snapshot") {
            try data.write(to: url, options: .atomic)
        }
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
    /// Globally unique: "<accountID>/<repo>/<runID>".
    public let id: String
    /// Rendered under the repository name when several accounts are configured.
    public let hostLabel: String
    public let repoName: String
    public let title: String
    /// Normalised across hosts — replaces the old GitHub-shaped
    /// `status` + `conclusion` pair.
    public let state: CIRunState
    public let url: String
    public let updatedAt: Date

    public init(
        id: String,
        hostLabel: String,
        repoName: String,
        title: String,
        state: CIRunState,
        url: String,
        updatedAt: Date
    ) {
        self.id = id
        self.hostLabel = hostLabel
        self.repoName = repoName
        self.title = title
        self.state = state
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

    /// Serial: two writes in quick succession must land in the order they were
    /// issued. A concurrent queue would let the older manifest win at random.
    private static let writeQueue = DispatchQueue(
        label: "ai.pakslab.edgecontrol.plugin-manifest",
        qos: .utility
    )

    public func write() {
        guard let dir = Self.containerDirectory else { return }
        let data: Data
        do {
            data = try JSONEncoder.widgetEncoder.encode(self)
        } catch {
            AppLog.persistence.error(
                "encoding plugin manifest failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }
        // App-group container writes have been observed hanging the calling
        // thread on __open inside Foundation's atomic-write path (sandbox /
        // container-manager state we don't control). Move the whole dance —
        // directory creation, freshness check, atomic write — off the caller's
        // thread. Worst case the manifest is a tick stale, which is fine for
        // desktop widgets that already poll.
        Self.writeQueue.async {
            AppLog.attempt("creating plugin manifest directory") {
                try FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true
                )
            }
            let url = dir.appendingPathComponent("plugins.json")
            // Unchanged manifests are common — the renderer rewrites on every
            // pass. Skipping the write avoids waking WidgetKit for nothing.
            if let existing = try? Data(contentsOf: url), existing == data { return }
            AppLog.attempt("writing plugin manifest") {
                try data.write(to: url, options: .atomic)
            }
        }
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
