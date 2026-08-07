import XCTest
@testable import EdgeControl

final class GitHubProviderTests: XCTestCase {
    private let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeProvider(_ transport: CITransport) -> GitHubProvider {
        GitHubProvider(
            accountID: accountID,
            hostLabel: "github.com",
            apiBaseURL: URL(string: "https://api.github.com")!,
            token: "test-token",
            transport: transport
        )
    }

    private func fetchAll() async throws -> [CIRun] {
        let transport = StubTransport(replies: [
            ("actions/runs", StubTransport.fixture("github-runs"))
        ])
        let repo = CIRepository(
            fullName: "acme/platform", shortName: "platform", lastActivity: Date()
        )
        return try await makeProvider(transport).fetchRuns(repository: repo, limit: 10)
    }

    func testMapsEveryStatusAndConclusionPair() async throws {
        let runs = try await fetchAll()
        XCTAssertEqual(runs.map(\.state), [
            .success, .failure, .failure, .cancelled, .skipped, .running, .queued,
        ])
    }

    func testMapsFieldsFromGitHubNames() async throws {
        let run = try await fetchAll()[0]
        XCTAssertEqual(run.workflowName, "Release Individual Service")
        XCTAssertEqual(run.title, "fix(api): reject zero-amount events")
        XCTAssertEqual(run.branch, "api/v1.0.46")
        XCTAssertEqual(run.repositoryName, "platform")
        XCTAssertEqual(run.hostLabel, "github.com")
        XCTAssertEqual(
            run.startedAt,
            ISO8601DateFormatter().date(from: "2026-07-23T04:00:57Z")
        )
        XCTAssertEqual(
            run.url,
            URL(string: "https://github.com/acme/platform/actions/runs/29978452950")
        )
    }

    /// Two hosts can return the same numeric run ID. Identity must include the
    /// account and repository or SwiftUI's ForEach will collapse rows.
    func testIDIsQualifiedByAccountAndRepository() async throws {
        let run = try await fetchAll()[0]
        XCTAssertEqual(run.id, "\(accountID.uuidString)/acme/platform/29978452950")
    }

    func testUnauthorizedResponseThrowsTypedError() async throws {
        let transport = StubTransport(replies: [
            ("actions/runs", StubTransport.Reply(data: Data(), status: 401))
        ])
        let repo = CIRepository(fullName: "a/b", shortName: "b", lastActivity: Date())
        do {
            _ = try await makeProvider(transport).fetchRuns(repository: repo, limit: 10)
            XCTFail("expected CIError.unauthorized")
        } catch let error as CIError {
            XCTAssertEqual(error, .unauthorized)
        }
    }
}
