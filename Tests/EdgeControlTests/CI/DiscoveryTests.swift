import XCTest
@testable import EdgeControl

final class DiscoveryTests: XCTestCase {
    private let accountID = UUID()
    private let cutoff = ISO8601DateFormatter().date(from: "2026-07-30T00:00:00Z")!

    // MARK: - GitHub

    private func gitHub(_ transport: CITransport) -> GitHubProvider {
        GitHubProvider(
            accountID: accountID,
            hostLabel: "github.com",
            apiBaseURL: URL(string: "https://api.github.com")!,
            token: "t",
            transport: transport
        )
    }

    func testGitHubValidateReturnsLogin() async throws {
        let transport = StubTransport(replies: [
            ("/user", StubTransport.fixture("github-user"))
        ])
        let identity = try await gitHub(transport).validate()
        XCTAssertEqual(identity.login, "octo")
        XCTAssertEqual(identity.displayName, "Octo Example")
    }

    func testGitHubDiscoveryFiltersByWindowAndIncludesOrgs() async throws {
        // Order matters: the more specific paths must be matched before "/user".
        let transport = StubTransport(replies: [
            ("/user/orgs", StubTransport.fixture("github-orgs")),
            ("/user/repos", StubTransport.fixture("github-repos")),
            ("/orgs/acme/repos", StubTransport.fixture("github-repos")),
        ])
        let repos = try await gitHub(transport).discoverRepositories(activeSince: cutoff)
        // "archive" is outside the window; "retired" is archived; "dashboard"
        // appears in both the user and org responses and must be de-duplicated.
        XCTAssertEqual(repos.map(\.fullName), ["octo/dashboard"])
        XCTAssertEqual(repos.first?.shortName, "dashboard")
    }

    /// Archiving leaves pushed_at untouched, so an archived repository stays
    /// inside the activity window and used to be discovered — filling the
    /// widget with runs that can never change again.
    func testGitHubDiscoverySkipsArchivedRepositories() async throws {
        let transport = StubTransport(replies: [
            ("/user/orgs", StubTransport.fixture("github-orgs")),
            ("/user/repos", StubTransport.fixture("github-repos")),
            ("/orgs/acme/repos", StubTransport.fixture("github-repos")),
        ])
        let repos = try await gitHub(transport).discoverRepositories(activeSince: cutoff)

        XCTAssertFalse(
            repos.contains { $0.fullName == "octo/retired" },
            "octo/retired is archived with a recent push and must not be discovered"
        )
    }

    // MARK: - Forgejo

    private func forgejo(_ transport: CITransport) -> ForgejoProvider {
        ForgejoProvider(
            accountID: accountID,
            hostLabel: "git.example.dev",
            apiBaseURL: URL(string: "https://git.example.dev/api/v1")!,
            token: "t",
            transport: transport
        )
    }

    func testForgejoValidateReturnsLogin() async throws {
        let transport = StubTransport(replies: [
            ("/user", StubTransport.fixture("forgejo-user"))
        ])
        let identity = try await forgejo(transport).validate()
        XCTAssertEqual(identity.login, "someone")
    }

    /// Forgejo returns org repositories from /user/repos, so no fan-out is
    /// needed. Exactly one request should be issued.
    func testForgejoDiscoveryUsesSingleCall() async throws {
        let transport = StubTransport(replies: [
            ("/user/repos", StubTransport.fixture("forgejo-repos"))
        ])
        let repos = try await forgejo(transport).discoverRepositories(activeSince: cutoff)
        XCTAssertEqual(repos.map(\.fullName), ["acme/feed"])
        XCTAssertEqual(transport.requestedURLs.count, 1)
        XCTAssertTrue(
            transport.requestedURLs[0].absoluteString.contains("order_by=recentupdate")
        )
    }

    /// Same reasoning as the GitHub case: archiving does not move updated_at.
    func testForgejoDiscoverySkipsArchivedRepositories() async throws {
        let transport = StubTransport(replies: [
            ("/user/repos", StubTransport.fixture("forgejo-repos"))
        ])
        let repos = try await forgejo(transport).discoverRepositories(activeSince: cutoff)

        XCTAssertFalse(
            repos.contains { $0.fullName == "acme/retired" },
            "acme/retired is archived with a recent update and must not be discovered"
        )
    }
}
