import XCTest
@testable import EdgeControl

final class CICDServiceTests: XCTestCase {
    private func run(
        _ id: String,
        _ state: CIRunState,
        _ minutesAgo: Int,
        host: String = "github.com",
        workflow: String = "ci"
    ) -> CIRun {
        CIRun(
            id: id,
            accountID: UUID(),
            hostLabel: host,
            repositoryName: "repo",
            workflowName: workflow,
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

    /// The collapse has to come before the cap. A repository busy enough to fill
    /// the cap with repeat runs of one workflow would otherwise push every other
    /// repository out of the data, and the widget would show a single row.
    func testCollapsingHappensBeforeTheCap() {
        let account = UUID().uuidString
        let busy = (0..<80).map {
            run("\(account)/acme/busy/\($0)", .success, $0, workflow: "ci")
        }
        // Older than every one of them, so a cap applied first would drop it.
        let quiet = [run("\(account)/acme/quiet/1", .success, 500, workflow: "deploy")]

        let merged = CICDService.merge([busy, quiet])

        XCTAssertEqual(merged.count, 2, "expected one row per workflow")
        XCTAssertTrue(
            merged.contains { $0.id.contains("/quiet/") },
            "the quiet repository was pushed out by the busy one"
        )
    }

    /// Two repositories with the same short name in different orgs are distinct
    /// workflows, not one.
    func testSameWorkflowNameInTwoReposStaysSeparate() {
        let account = UUID().uuidString
        let merged = CICDService.merge([[
            run("\(account)/acme/app/1", .success, 10, workflow: "ci"),
            run("\(account)/other/app/1", .success, 20, workflow: "ci"),
        ]])
        XCTAssertEqual(merged.count, 2)
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
