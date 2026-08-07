import Foundation

public enum CIProviderKind: String, Codable, Sendable, CaseIterable {
    case github, forgejo

    public var displayName: String {
        switch self {
        case .github:  return "GitHub"
        case .forgejo: return "Forgejo / Gitea"
        }
    }
}

/// A configured CI host.
///
/// Never carries the token — that lives in the Keychain, keyed by `id`, so the
/// account list can be persisted to UserDefaults without leaking credentials.
public struct CIAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var kind: CIProviderKind
    /// Shown in the widget when more than one account exists, e.g. "github.com".
    public var host: String
    public var apiBaseURL: URL
    public var username: String

    public init(
        id: UUID,
        kind: CIProviderKind,
        host: String,
        apiBaseURL: URL,
        username: String
    ) {
        self.id = id
        self.kind = kind
        self.host = host
        self.apiBaseURL = apiBaseURL
        self.username = username
    }

    /// Derives the API base from a web URL, so users paste what they see in the
    /// browser rather than an API path.
    public static func apiBaseURL(forKind kind: CIProviderKind, webURL: URL) -> URL {
        switch kind {
        case .github:
            return webURL.host == "github.com"
                ? URL(string: "https://api.github.com")!
                : webURL.appendingPathComponent("api/v3")
        case .forgejo:
            return webURL.appendingPathComponent("api/v1")
        }
    }
}
