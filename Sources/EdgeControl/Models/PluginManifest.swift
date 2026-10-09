import Foundation

// MARK: - Plugin Manifest (parsed from manifest.json in .ecplugin bundle)

public struct PluginManifest: Codable, Identifiable, Sendable {
    public let id: String  // e.g. "com.example.mywidget"
    public let name: String
    public let version: String
    public let author: String
    public let description: String?
    public let homepage: String?
    public let minAppVersion: String?
    public let permissions: [PluginPermission]
    public let widgets: [PluginWidgetDef]
    public let icon: String?  // SF Symbol for plugin list (e.g. "bolt.fill")
    public let allowedDomains: [String]?  // Whitelisted domains for network-access permission
    public let desktopWidget: PluginDesktopWidgetConfig?  // macOS desktop widget support
    public let menuItems: [PluginMenuItem]?  // Added to EdgeControl's menu bar menu

    public init(
        id: String, name: String, version: String, author: String,
        description: String? = nil, homepage: String? = nil,
        minAppVersion: String? = nil, permissions: [PluginPermission] = [],
        widgets: [PluginWidgetDef] = [],
        icon: String? = nil,
        allowedDomains: [String]? = nil,
        desktopWidget: PluginDesktopWidgetConfig? = nil,
        menuItems: [PluginMenuItem]? = nil
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
        self.icon = icon
        self.allowedDomains = allowedDomains
        self.desktopWidget = desktopWidget
        self.menuItems = menuItems
    }
}

// MARK: - Menu Items

/// An item a plugin adds to EdgeControl's menu bar menu, for a plugin whose
/// settings or companion app live outside the dashboard. It opens one of the
/// plugin's own apps or a web page, nothing else, and only when chosen.
public struct PluginMenuItem: Codable, Hashable, Sendable {
    public let title: String
    /// The bundle identifier of an app to open. It must come from the
    /// plugin's own developer: its first two parts match the plugin id's
    /// ("com.example.helper" for "com.example.mywidget").
    public let openApp: String?
    /// An http or https page to open.
    public let openURL: String?

    public init(title: String, openApp: String? = nil, openURL: String? = nil) {
        self.title = title
        self.openApp = openApp
        self.openURL = openURL
    }

    public enum Target: Codable, Hashable, Sendable {
        case app(bundleId: String)
        case url(URL)
    }

    /// What choosing the item opens, or nil when the item asks for
    /// something a plugin may not open.
    public func target(forPlugin pluginId: String) -> Target? {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= 60 else { return nil }
        return Self.target(openApp: openApp, openURL: openURL, forPlugin: pluginId)
    }

    /// What `openApp` or `openURL` opens for a plugin, or nil when it's
    /// something a plugin may not open. A settings button follows the same
    /// rule as a menu item.
    public static func target(openApp: String?, openURL: String?, forPlugin pluginId: String) -> Target? {
        if let openApp {
            let vendor = pluginId.split(separator: ".").prefix(2)
            let app = openApp.split(separator: ".", omittingEmptySubsequences: false)
            guard vendor.count == 2, app.count > 2, openApp.count <= 200, Array(app.prefix(2)) == Array(vendor),
                app.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } })
            else { return nil }
            return .app(bundleId: openApp)
        }
        if let openURL, let url = URL(string: openURL), let scheme = url.scheme?.lowercased(),
            scheme == "https" || scheme == "http", url.host != nil
        {
            return .url(url)
        }
        return nil
    }
}

// MARK: - Plugin Permission

public enum PluginPermission: String, Codable, CaseIterable, Sendable {
    // Data permissions (v1)
    case systemMetrics = "system-metrics"  // CPU, memory, storage, uptime
    case temperature  // CPU/GPU/SSD temps
    case network  // Network speed, WiFi info
    case processes  // Process list
    case media  // Now playing info
    case bluetooth  // BT devices
    case audio  // Audio devices, volume
    case weather  // Weather data
    case diskIO = "disk-io"  // Disk read/write speeds

    // Action/access permissions (v2)
    case notifications  // Send macOS notifications
    case openURL = "open-url"  // Open URLs in default browser
    case clipboard  // Write to system clipboard
    case storage  // Persistent key-value storage
    case networkAccess = "network-access"  // External network requests (restricted to allowedDomains)

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
        case .notifications: "Notifications"
        case .openURL: "Open URLs"
        case .clipboard: "Clipboard"
        case .storage: "Persistent Storage"
        case .networkAccess: "Network Access"
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
        case .notifications: "bell.badge"
        case .openURL: "safari"
        case .clipboard: "doc.on.clipboard"
        case .storage: "externaldrive"
        case .networkAccess: "globe"
        }
    }
}

// MARK: - Plugin Widget Definition

public struct PluginWidgetDef: Codable, Identifiable, Sendable {
    public let id: String  // widget ID within plugin
    public let name: String
    public let description: String?
    public let icon: String?  // SF Symbol name
    public let htmlFile: String  // relative path to HTML file
    public let supportedSizes: PluginSizeRange
    public let defaultSize: [Int]  // [width, height]
    public let configSchema: [PluginConfigField]?
    public let refreshInterval: Double?  // seconds, nil = default (2s)

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
    public let type: String  // "string", "number", "boolean", "color", "select", "button"
    public let defaultValue: PluginConfigValue
    public let options: [String]?  // for "select" type
    /// For "button": what it opens, by the same rule as a menu item.
    public let openApp: String?
    public let openURL: String?
    /// Shows the field only while another field has one of some values.
    public let showWhen: ConfigCondition?

    enum CodingKeys: String, CodingKey {
        case key, label, type
        case defaultValue = "default"
        case options, openApp, openURL, showWhen
    }
}

extension PluginConfigField {
    /// A button holds no value, so it needs no default. Every other field
    /// still needs one, and a null default is still refused.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(String.self, forKey: .type)
        defaultValue =
            type == "button"
            ? try container.decodeIfPresent(PluginConfigValue.self, forKey: .defaultValue) ?? .string("")
            : try container.decode(PluginConfigValue.self, forKey: .defaultValue)
        options = try container.decodeIfPresent([String].self, forKey: .options)
        openApp = try container.decodeIfPresent(String.self, forKey: .openApp)
        openURL = try container.decodeIfPresent(String.self, forKey: .openURL)
        showWhen = try container.decodeIfPresent(ConfigCondition.self, forKey: .showWhen)
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
        throw DecodingError.typeMismatch(
            PluginConfigValue.self,
            .init(codingPath: decoder.codingPath, debugDescription: "Unsupported plugin config value"))
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

/// Resolving a widget's HTML file against the bundle it must stay inside.
///
/// This lived as three hand-copied string comparisons — in PluginManager, in the
/// WebView widget and in the desktop-widget snapshot path — and only one of them
/// was ever correct. One place, three callers.
public enum PluginBundle {
    /// The URL of `htmlFile` inside `bundlePath`, or nil when it resolves
    /// outside it.
    ///
    /// The prefix has to carry the separator: without it a sibling directory
    /// whose name merely starts with the same characters passes, because
    /// ".../demo.ecplugin-evil/x.html" does have the prefix ".../demo.ecplugin".
    ///
    /// Symlinks are resolved on both sides. Plugins are installed by extracting
    /// an archive with `ditto`, which preserves links, so a link planted inside
    /// the bundle would satisfy a purely textual check while pointing anywhere
    /// on disk. Resolving both sides also keeps /var and /private/var from
    /// looking like different roots.
    public static func containedHTMLURL(bundlePath: URL, htmlFile: String) -> URL? {
        let candidate = bundlePath.appendingPathComponent(htmlFile)
            .standardizedFileURL.resolvingSymlinksInPath()
        let root = bundlePath.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard candidate.path.hasPrefix(prefix) else { return nil }
        return candidate
    }
}

public struct LoadedPlugin: Identifiable, Sendable {
    public let manifest: PluginManifest
    public let bundlePath: URL
    public var isEnabled: Bool

    public var id: String { manifest.id }
}

// MARK: - Desktop Widget Config

public struct PluginDesktopWidgetConfig: Codable, Sendable {
    public let enabled: Bool
    public let sizes: [String]?  // ["small", "medium", "large"] — nil = all
    public let refreshInterval: Double?  // seconds between snapshots, default 300 (5 min)

    public var effectiveRefreshInterval: Double {
        max(60, refreshInterval ?? 300)  // minimum 1 minute
    }

    /// Convert size strings to WidgetKit family names
    public var supportedFamilies: Set<String> {
        let all: Set<String> = ["small", "medium", "large"]
        guard let sizes else { return all }
        return all.intersection(sizes.map { $0.lowercased() })
    }
}

// MARK: - Safe Array Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
