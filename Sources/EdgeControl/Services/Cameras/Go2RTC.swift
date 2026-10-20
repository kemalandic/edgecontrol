import Foundation

/// The parts of go2rtc's HTTP API the Cameras widget uses.
///
/// go2rtc (https://github.com/AlexxIT/go2rtc) turns RTSP, ONVIF, HomeKit and
/// most other camera protocols into streams a player can use. Frigate and
/// Home Assistant both ship it, so many camera setups already have one.
public enum Go2RTC {
    public static let defaultPort = 1984

    /// Accepts what people type: `192.168.1.20`, `nvr.local:1984`,
    /// `http://nvr:1984/`, a `ws://` address copied from go2rtc's own player,
    /// or an https reverse proxy with a path. A bare host gets `http://` and
    /// go2rtc's default port.
    public static func serverURL(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("ws://") || lower.hasPrefix("wss://") {
            text = "http" + text.dropFirst(2)
        } else if !lower.contains("://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else { return nil }

        // An address copied from go2rtc's own player points into its API.
        if let api = components.path.range(of: "/api/") {
            components.path = String(components.path[..<api.lowerBound])
        } else if components.path.hasSuffix("/api") {
            components.path.removeLast(4)
        }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        if components.port == nil, scheme == "http", components.path.isEmpty {
            components.port = defaultPort
        }
        components.scheme = scheme
        components.host = host.lowercased()
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// GET: every stream go2rtc knows, keyed by name.
    public static func streamsURL(server: URL) -> URL {
        server.appending(path: "api/streams")
    }

    /// An HLS playlist for one named stream. go2rtc's HLS endpoint only serves
    /// streams that already exist, which is why cameras go into go2rtc first.
    public static func hlsURL(server: URL, stream: String) -> URL {
        server.appending(path: "api/stream.m3u8").appending(queryItems: [URLQueryItem(name: "src", value: stream)])
    }

    /// Stream names from `GET /api/streams`, in a stable order.
    ///
    /// The response is a JSON object, so its order carries no meaning. Streams
    /// go2rtc created on the fly from a source URL are named after that URL,
    /// which can include a password, so they are left out.
    public static func streamNames(from data: Data) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let streams = object as? [String: Any]
        else { throw CIError.decoding("go2rtc's stream list isn't a JSON object") }
        return streams.keys
            .filter { !$0.contains("://") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
