import Foundation

/// Every way talking to a CI host can fail, in terms the UI can act on.
///
/// The previous implementation discarded response metadata entirely
/// (`try? await URLSession.shared.data(for:).0`), so an expired token, an
/// exhausted quota and a genuinely empty result were indistinguishable.
public enum CIError: Error, Equatable, Sendable {
    /// Token missing, expired, or revoked.
    case unauthorized
    /// Quota exhausted. `retryAfter` is when it is worth trying again, if known.
    case rateLimited(retryAfter: Date?)
    /// DNS, TLS, timeout, offline.
    case unreachable
    /// Any other non-success status.
    case httpStatus(Int)
    /// The body did not parse.
    case decoding(String)
}

extension CIError {
    /// Classifies a response. Returns `nil` when the request succeeded.
    ///
    /// 304 counts as success: it is the conditional-request path, and the
    /// caller reuses its cached value.
    public static func from(response: HTTPURLResponse) -> CIError? {
        let status = response.statusCode
        if (200..<300).contains(status) || status == 304 { return nil }

        func header(_ name: String) -> String? {
            response.value(forHTTPHeaderField: name)
        }

        switch status {
        case 401:
            return .unauthorized

        case 403:
            // GitHub returns 403 both for "forbidden" and for "rate limited".
            // An exhausted quota is the only reliable way to tell them apart.
            if header("x-ratelimit-remaining") == "0" {
                let reset = header("x-ratelimit-reset").flatMap(Double.init)
                return .rateLimited(retryAfter: reset.map { Date(timeIntervalSince1970: $0) })
            }
            return .unauthorized

        case 429:
            if let seconds = header("retry-after").flatMap(Double.init) {
                return .rateLimited(retryAfter: Date().addingTimeInterval(seconds))
            }
            return .rateLimited(retryAfter: nil)

        default:
            return .httpStatus(status)
        }
    }
}

/// Identity confirmed by the host. Used to label the account row and to
/// validate a token before it is stored.
public struct CIIdentity: Equatable, Sendable {
    public let login: String
    public let displayName: String?

    public init(login: String, displayName: String?) {
        self.login = login
        self.displayName = displayName
    }
}

/// A repository the account can see.
public struct CIRepository: Identifiable, Equatable, Sendable, Codable {
    public var id: String { fullName }
    /// `owner/name`.
    public let fullName: String
    /// Name without the owner, shown in the widget.
    public let shortName: String
    /// `pushed_at` on GitHub, `updated_at` on Forgejo.
    public let lastActivity: Date

    public init(fullName: String, shortName: String, lastActivity: Date) {
        self.fullName = fullName
        self.shortName = shortName
        self.lastActivity = lastActivity
    }
}

/// One CI host. Implementations hold their own account and transport, so
/// adding a host means adding a file rather than editing the orchestrator.
public protocol CIProvider: Sendable {
    func validate() async throws -> CIIdentity
    func discoverRepositories(activeSince: Date) async throws -> [CIRepository]
    func fetchRuns(repository: CIRepository, limit: Int) async throws -> [CIRun]
}
