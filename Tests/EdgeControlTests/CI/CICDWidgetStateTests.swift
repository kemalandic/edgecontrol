import XCTest
@testable import EdgeControl

final class CICDWidgetStateTests: XCTestCase {
    private func account(_ host: String) -> CIAccount {
        CIAccount(
            id: UUID(),
            kind: .github,
            host: host,
            apiBaseURL: URL(string: "https://api.github.com")!,
            username: "u"
        )
    }

    private func sampleRun() -> CIRun {
        CIRun(
            id: "a/b/1",
            accountID: UUID(),
            hostLabel: "github.com",
            repositoryName: "b",
            workflowName: "ci",
            title: "t",
            branch: "main",
            state: .success,
            startedAt: Date(),
            url: URL(string: "https://example.test/1")!
        )
    }

    func testNoAccountsIsDistinctFromNoRuns() {
        XCTAssertEqual(
            CICDWidgetState.resolve(runs: [], accounts: [], states: [:]),
            .noAccounts
        )
    }

    func testConfiguredAccountWithNoRunsIsEmptyNotAnError() {
        let a = account("github.com")
        XCTAssertEqual(
            CICDWidgetState.resolve(
                runs: [], accounts: [a], states: [a.id: .ok(lastSync: Date())]
            ),
            .empty
        )
    }

    func testFailingAccountWithNoRunsSurfacesTheError() {
        let a = account("git.example.dev")
        let state = CICDWidgetState.resolve(
            runs: [], accounts: [a], states: [a.id: .failed(.unauthorized, at: Date())]
        )
        XCTAssertEqual(state, .accountError("git.example.dev", .unauthorized))
    }

    /// Partial failure: one host is down, the other works. Runs must still
    /// render, with a count of failing accounts for the header badge.
    func testPartialFailureStillShowsRuns() {
        let good = account("github.com")
        let bad = account("git.example.dev")
        let state = CICDWidgetState.resolve(
            runs: [sampleRun()],
            accounts: [good, bad],
            states: [
                good.id: .ok(lastSync: Date()),
                bad.id: .failed(.unreachable, at: Date()),
            ]
        )
        guard case .runs(let runs, let failingCount) = state else {
            return XCTFail("expected .runs")
        }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(failingCount, 1)
    }

    /// The widget and the desktop widget must describe the same situation the
    /// same way, so both read from this one resolver.
    func testStatusNoteMatchesWidgetState() {
        let a = account("git.example.dev")
        XCTAssertEqual(
            WidgetDataBridge.statusNote(runs: [], accounts: [], states: [:]),
            "No accounts configured"
        )
        XCTAssertEqual(
            WidgetDataBridge.statusNote(
                runs: [], accounts: [a], states: [a.id: .failed(.unauthorized, at: Date())]
            ),
            "git.example.dev — authentication failed"
        )
        XCTAssertEqual(
            WidgetDataBridge.statusNote(
                runs: [], accounts: [a], states: [a.id: .ok(lastSync: Date())]
            ),
            "No recent runs"
        )
        XCTAssertNil(
            WidgetDataBridge.statusNote(
                runs: [sampleRun()], accounts: [a], states: [a.id: .ok(lastSync: Date())]
            )
        )
    }
}
