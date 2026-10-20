import Foundation

/// A camera the Cameras widget can show, parsed from one entry of the widget's
/// `cameras` setting.
///
/// Entries are plain strings so they fit `ConfigValue.stringArray`:
/// - a go2rtc stream name, e.g. `front_door`, played through the widget's
///   go2rtc server;
/// - `Name | https://host/live.m3u8`, an HLS stream played directly.
///
/// RTSP cameras are not entries of their own: they belong in go2rtc, which
/// turns them into streams the widget can play and keeps their passwords out
/// of EdgeControl's layout file.
public struct CameraSource: Identifiable, Hashable, Sendable {
    public enum Feed: Hashable, Sendable {
        /// A stream defined in go2rtc.
        case go2rtc(stream: String)
        /// An HLS playlist, played without go2rtc.
        case hls(URL)
    }

    /// The config entry itself: unique within a widget and stable across launches.
    public let id: String
    public let name: String
    public let feed: Feed

    static let separator = " | "

    /// Parses a config entry; nil for one that can't be played.
    public init?(entry: String) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.contains("://") {
            let parts = trimmed.components(separatedBy: Self.separator)
            let urlText = parts.count > 1 ? parts.dropFirst().joined(separator: Self.separator) : trimmed
            guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)),
                Self.problem(withURL: url.absoluteString) == nil
            else { return nil }
            let given = parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : ""
            self.id = trimmed
            self.name = given.isEmpty ? (url.host ?? "Camera") : given
            self.feed = .hls(url)
        } else {
            self.id = trimmed
            self.name = Self.displayName(forStream: trimmed)
            self.feed = .go2rtc(stream: trimmed)
        }
    }

    /// The entry for a direct stream with a name of the user's choosing.
    public static func entry(name: String, url: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: separator, with: " ")
        let url = url.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? url : name + separator + url
    }

    /// go2rtc names are config keys like `plant_wall`; people read "Plant wall".
    public static func displayName(forStream stream: String) -> String {
        let spaced = stream.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        guard let first = spaced.first else { return stream }
        return first.uppercased() + spaced.dropFirst()
    }

    /// Why a URL can't be added as a camera, or nil if it can.
    public static func problem(withURL text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host != nil else {
            return "Enter a full address, like https://camera.local/live.m3u8."
        }
        switch scheme {
        case "http", "https":
            return nil
        case "rtsp", "rtsps", "rtmp", "rtmps", "srt", "onvif":
            return "Add \(scheme.uppercased()) cameras to go2rtc, then pick them from its list."
        default:
            return "Only HLS streams (http:// or https://) can be added directly."
        }
    }

    /// Scheme and host only, for showing where a camera lives without echoing
    /// a token that might be in its path or query.
    public var location: String {
        switch feed {
        case .go2rtc(let stream):
            return "go2rtc · \(stream)"
        case .hls(let url):
            return "HLS · \(url.host ?? url.absoluteString)"
        }
    }
}
