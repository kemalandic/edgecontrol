import XCTest
@testable import EdgeControl

final class ForgejoProviderTests: XCTestCase {
    private let accountID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    private func fetchAll() async throws -> [CIRun] {
        let transport = StubTransport(replies: [
            ("actions/runs", StubTransport.fixture("forgejo-runs"))
        ])
        let provider = ForgejoProvider(
            accountID: accountID,
            hostLabel: "git.example.dev",
            apiBaseURL: URL(string: "https://git.example.dev/api/v1")!,
            token: "test-token",
            transport: transport
        )
        let repo = CIRepository(
            fullName: "acme/feed", shortName: "feed", lastActivity: Date()
        )
        return try await provider.fetchRuns(repository: repo, limit: 10)
    }

    func testMapsAllEightStatusValues() async throws {
        let runs = try await fetchAll()
        XCTAssertEqual(runs.map(\.state), [
            .success, .failure, .cancelled, .running,
            .queued,   // waiting
            .queued,   // blocked
            .skipped, .unknown,
        ])
    }

    func testMapsFieldsFromForgejoNames() async throws {
        let run = try await fetchAll()[0]
        XCTAssertEqual(run.workflowName, "ci.yml")
        XCTAssertEqual(run.title, "chore(backoffice): remove deprecated admin")
        XCTAssertEqual(run.branch, "main")
        XCTAssertEqual(run.hostLabel, "git.example.dev")
    }

    /// Forgejo sends a zero date for runs that have not started. Sorting on
    /// that would bury queued runs at the bottom of the list forever.
    func testZeroStartedFallsBackToCreated() async throws {
        let waiting = try await fetchAll()[4]
        XCTAssertEqual(waiting.state, .queued)
        XCTAssertEqual(
            waiting.startedAt,
            ISO8601DateFormatter().date(from: "2026-08-05T19:00:00Z")
        )
    }

    /// `id` is internal; `index_in_repo` is the number in the URL. Run identity
    /// must use the same value the html_url points at.
    func testIDUsesRepoIndexNotInternalID() async throws {
        let run = try await fetchAll()[0]
        XCTAssertEqual(run.id, "\(accountID.uuidString)/acme/feed/221")
    }
}
