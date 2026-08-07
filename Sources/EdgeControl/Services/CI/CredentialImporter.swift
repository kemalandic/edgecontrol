import Foundation

public struct DiscoveredCredential: Equatable, Sendable {
    public let kind: CIProviderKind
    public let host: String
    public let webURL: URL
    public let username: String
    public let token: String
    /// Which CLI it came from, shown in the import sheet.
    public let source: String

    public init(
        kind: CIProviderKind,
        host: String,
        webURL: URL,
        username: String,
        token: String,
        source: String
    ) {
        self.kind = kind
        self.host = host
        self.webURL = webURL
        self.username = username
        self.token = token
        self.source = source
    }
}

/// Reads existing logins out of `gh` and `tea`.
///
/// Both use documented command interfaces rather than parsing a configuration
/// file: `tea login helper get` speaks the git-credential protocol, so `tea`'s
/// YAML config is never touched — parsing it would mean hand-rolling a YAML
/// parser under this project's no-dependency rule.
///
/// Every failure is silent by design: a missing or logged-out CLI simply
/// contributes nothing.
public struct CredentialImporter {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func discover() -> [DiscoveredCredential] {
        gitHubCredentials() + forgejoCredentials()
    }

    // MARK: - gh

    private func gitHubCredentials() -> [DiscoveredCredential] {
        guard let token = try? runner.run("gh", ["auth", "token"], stdin: nil),
              !token.isEmpty else { return [] }
        return [DiscoveredCredential(
            kind: .github,
            host: "github.com",
            webURL: URL(string: "https://github.com")!,
            username: "",           // resolved by validate() before saving
            token: token,
            source: "gh"
        )]
    }

    // MARK: - tea

    private struct TeaLogin: Decodable {
        let url: String
        let user: String
    }

    private func forgejoCredentials() -> [DiscoveredCredential] {
        guard let json = try? runner.run("tea", ["login", "list", "--output", "json"], stdin: nil),
              let logins = try? JSONDecoder().decode([TeaLogin].self, from: Data(json.utf8))
        else { return [] }

        return logins.compactMap { login -> DiscoveredCredential? in
            guard let webURL = URL(string: login.url), let host = webURL.host else { return nil }
            // tea speaks the git-credential protocol; the trailing blank line
            // terminates the request.
            let request = "protocol=https\nhost=\(host)\n\n"
            guard let response = try? runner.run("tea", ["login", "helper", "get"], stdin: request),
                  let token = Self.credentialField("password", in: response),
                  !token.isEmpty
            else { return nil }

            return DiscoveredCredential(
                kind: .forgejo,
                host: host,
                webURL: webURL,
                username: Self.credentialField("username", in: response) ?? login.user,
                token: token,
                source: "tea"
            )
        }
    }

    static func credentialField(_ name: String, in output: String) -> String? {
        output
            .split(separator: "\n")
            .first { $0.hasPrefix(name + "=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }
}
