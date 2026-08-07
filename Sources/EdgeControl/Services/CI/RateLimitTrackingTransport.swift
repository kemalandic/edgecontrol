import Foundation

/// What a host says is left of the caller's request quota.
public struct CIRateLimit: Equatable, Sendable {
    public let limit: Int
    public let remaining: Int
    public let resetsAt: Date?

    public init(limit: Int, remaining: Int, resetsAt: Date?) {
        self.limit = limit
        self.remaining = remaining
        self.resetsAt = resetsAt
    }

    /// Fraction still available, for a gauge or a colour threshold.
    public var fractionRemaining: Double {
        limit > 0 ? Double(remaining) / Double(limit) : 1
    }

    /// Worth drawing attention to before requests actually start failing.
    public var isLow: Bool { fractionRemaining < 0.15 }
}

extension CIRateLimit {
    /// Reads the `x-ratelimit-*` family. Returns nil for hosts that do not
    /// report a quota — Forgejo does not, and an absent quota is not zero.
    public static func from(response: HTTPURLResponse) -> CIRateLimit? {
        func intValue(_ name: String) -> Int? {
            response.value(forHTTPHeaderField: name).flatMap(Int.init)
        }
        guard let limit = intValue("x-ratelimit-limit"),
              let remaining = intValue("x-ratelimit-remaining") else { return nil }
        let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset")
            .flatMap(Double.init)
            .map { Date(timeIntervalSince1970: $0) }
        return CIRateLimit(limit: limit, remaining: remaining, resetsAt: reset)
    }
}

/// Records the most recent quota each host reported.
///
/// A decorator for the same reason `ConditionalGETTransport` is one: providers
/// keep asking for a URL and getting a body, and their tests keep working
/// against a plain stub. Without this the quota was only ever visible at the
/// moment it hit zero, which is too late to act on.
public final class RateLimitTrackingTransport: CITransport, @unchecked Sendable {
    private let wrapped: CITransport
    private let lock = NSLock()
    private var byHost: [String: CIRateLimit] = [:]

    public init(wrapping transport: CITransport) {
        self.wrapped = transport
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await wrapped.get(url, headers: headers)
        if let host = url.host, let limit = CIRateLimit.from(response: response) {
            lock.withLock { byHost[host] = limit }
        }
        return (data, response)
    }

    /// Latest quota for a host, or nil if it never reported one.
    ///
    /// The key is the *API* host, so `api.github.com` rather than `github.com`.
    public func rateLimit(forHost host: String) -> CIRateLimit? {
        lock.withLock { byHost[host] }
    }

    public var allRateLimits: [String: CIRateLimit] {
        lock.withLock { byHost }
    }
}
