import Foundation

/// Adds HTTP conditional requests to any transport.
///
/// Remembers the `ETag` a host returned for each URL and sends it back as
/// `If-None-Match`. When the host answers `304 Not Modified` the cached body is
/// returned as if it were a fresh `200`, so callers need no special handling.
///
/// This is a decorator rather than a change to `CIProvider`: providers keep
/// asking for a URL and getting a body, and their tests keep working against a
/// plain stub.
///
/// On GitHub a `304` does not count against the rate limit, which matters when
/// several accounts poll dozens of repositories every 30 seconds.
public final class ConditionalGETTransport: CITransport, @unchecked Sendable {
    private struct Entry {
        let etag: String
        let data: Data
    }

    private let wrapped: CITransport
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    /// Bounds memory: one entry per repository per account, plus discovery.
    private let capacity: Int

    public init(wrapping transport: CITransport, capacity: Int = 500) {
        self.wrapped = transport
        self.capacity = capacity
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let key = url.absoluteString
        let cached = lock.withLock { cache[key] }

        var headers = headers
        if let cached {
            headers["If-None-Match"] = cached.etag
        }

        let (data, response) = try await wrapped.get(url, headers: headers)

        if response.statusCode == 304, let cached {
            // Present the cached body as a fresh success. Rebuilding the
            // response keeps `CIError.from` and the decoders on one path.
            let synthesized = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["ETag": cached.etag]
            )!
            return (cached.data, synthesized)
        }

        if (200..<300).contains(response.statusCode),
           let etag = response.value(forHTTPHeaderField: "ETag") {
            store(key: key, entry: Entry(etag: etag, data: data))
        }

        return (data, response)
    }

    private func store(key: String, entry: Entry) {
        lock.withLock {
            if cache[key] == nil, cache.count >= capacity {
                // Crude but bounded: drop an arbitrary entry rather than grow
                // without limit. Losing one ETag costs a single full response.
                if let victim = cache.keys.first { cache.removeValue(forKey: victim) }
            }
            cache[key] = entry
        }
    }

    /// Number of cached validators. Exposed for tests.
    public var cachedEntryCount: Int {
        lock.withLock { cache.count }
    }
}
