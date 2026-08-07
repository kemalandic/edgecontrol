import XCTest
@testable import EdgeControl

final class WidgetDataSchemaTests: XCTestCase {
    private func sampleRun() -> WidgetCICDRun {
        WidgetCICDRun(
            id: "acct/repo/1",
            hostLabel: "git.example.dev",
            repoName: "repo",
            title: "t",
            state: .running,
            url: "https://example.test/1",
            updatedAt: Date()
        )
    }

    /// A snapshot written by an older build must not decode into misleading
    /// values — it must be rejected so the widget can say "open the app".
    func testSnapshotFromOlderSchemaIsRejected() {
        let legacy = """
        {"timestamp":"2026-08-01T00:00:00Z","cpuUsage":10,"cicdRuns":[]}
        """
        XCTAssertNil(
            WidgetData.decode(from: Data(legacy.utf8)),
            "a snapshot without schemaVersion must not decode"
        )
    }

    func testCurrentSchemaRoundTrips() throws {
        let data = WidgetData(timestamp: Date(), cicdRuns: [sampleRun()])
        let encoded = try JSONEncoder.widgetEncoder.encode(data)
        let decoded = try XCTUnwrap(WidgetData.decode(from: encoded))

        XCTAssertEqual(decoded.schemaVersion, WidgetData.currentSchemaVersion)
        XCTAssertEqual(decoded.cicdRuns.first?.state, .running)
        XCTAssertEqual(decoded.cicdRuns.first?.hostLabel, "git.example.dev")
        XCTAssertEqual(decoded.cicdRuns.first?.id, "acct/repo/1")
    }

    func testStatusNoteSurvivesRoundTrip() throws {
        let data = WidgetData(
            timestamp: Date(), cicdRuns: [], cicdStatusNote: "No accounts configured"
        )
        let encoded = try JSONEncoder.widgetEncoder.encode(data)
        let decoded = try XCTUnwrap(WidgetData.decode(from: encoded))
        XCTAssertEqual(decoded.cicdStatusNote, "No accounts configured")
    }

    /// schemaVersion is derived, never supplied by a caller.
    func testSchemaVersionIsAlwaysCurrent() {
        XCTAssertEqual(
            WidgetData(timestamp: Date()).schemaVersion,
            WidgetData.currentSchemaVersion
        )
    }
}
