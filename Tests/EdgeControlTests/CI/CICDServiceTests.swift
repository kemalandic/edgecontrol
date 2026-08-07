import XCTest
@testable import EdgeControl

final class CICDServiceTests: XCTestCase {
    private func run(
        _ id: String,
        _ state: CIRunState,
        _ minutesAgo: Int,
        host: String = "github.com"
    ) -> CIRun {
        CIRun(
            id: id,
            accountID: UUID(),
            hostLabel: host,
            repositoryName: "repo",
            workflowName: "ci",
            title: "t",
            branch: "main",
            state: state,
            startedAt: Date().addingTimeInterval(TimeInterval(-60 * minutesAgo)),
            url: URL(string: "https://example.test/\(id)")!
        )
    }

    /// Active runs float to the top regardless of age; within each group the
    /// order is newest first.
    ///
    /// Note the deliberate ordering of the two active runs: `queued` started
    /// one minute ago and `running` five hours ago, so `queued` comes first.
    /// `running` and `queued` are peers — being active is what lifts a run to
    /// the top, not which kind of active it is.
    func testMergeSortsActiveFirstThenNewest() {
        let merged = CICDService.merge([
            [run("old-success", .success, 120), run("new-success", .success, 5)],
            [run("stale-running", .running, 300), run("fresh-queued", .queued, 1)],
        ])
        XCTAssertEqual(
            merged.map(\.id),
            ["fresh-queued", "stale-running", "new-success", "old-success"]
        )
    }

    /// Age alone must not lift a finished run above an active one.
    func testActiveBeatsRecencyAcrossGroups() {
        let merged = CICDService.merge([
            [run("just-finished", .success, 0)],
            [run("long-running", .running, 600)],
        ])
        XCTAssertEqual(merged.map(\.id), ["long-running", "just-finished"])
    }

    func testMergeCapsAtFifty() {
        let many = (0..<80).map { run("r\($0)", .success, $0) }
        XCTAssertEqual(CICDService.merge([many]).count, 50)
    }

    func testBackoffSchedule() {
        XCTAssertEqual(CICDService.backoffDelay(forConsecutiveFailures: 1), 30)
        XCTAssertEqual(CICDService.backoffDelay(forConsecutiveFailures: 2), 60)
        XCTAssertEqual(CICDService.backoffDelay(forConsecutiveFailures: 3), 120)
        XCTAssertEqual(CICDService.backoffDelay(forConsecutiveFailures: 4), 300)
        XCTAssertEqual(CICDService.backoffDelay(forConsecutiveFailures: 5), 900)
        // Capped — a long outage must not push the next attempt hours away.
        XCTAssertEqual(CICDService.backoffDelay(forConsecutiveFailures: 99), 900)
    }

    /// A repository with Actions disabled 404s on the runs endpoint. That must
    /// not fail the account — 13 of 38 repositories on one real Forgejo host do
    /// exactly this, and letting it propagate blinded the whole host.
    func testOnlyNotFoundIsTreatedAsPerRepository() {
        XCTAssertTrue(CICDService.isPerRepository(.httpStatus(404)))

        // Everything else describes the account, not one repository.
        XCTAssertFalse(CICDService.isPerRepository(.unauthorized))
        XCTAssertFalse(CICDService.isPerRepository(.rateLimited(retryAfter: nil)))
        XCTAssertFalse(CICDService.isPerRepository(.unreachable))
        XCTAssertFalse(CICDService.isPerRepository(.httpStatus(500)))
        XCTAssertFalse(CICDService.isPerRepository(.httpStatus(403)))
        XCTAssertFalse(CICDService.isPerRepository(.decoding("bad json")))
    }

    func testRunStateActivity() {
        XCTAssertTrue(CIRunState.running.isActive)
        XCTAssertTrue(CIRunState.queued.isActive)
        for state: CIRunState in [.success, .failure, .cancelled, .skipped, .unknown] {
            XCTAssertFalse(state.isActive, "\(state) must not be active")
        }
    }
}
