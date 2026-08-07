import XCTest
@testable import EdgeControl

private struct HeaderTransport: CITransport {
    let headers: [String: String]
    let status: Int

    init(headers: [String: String], status: Int = 200) {
        self.headers = headers
        self.status = status
    }

    func get(_ url: URL, headers _: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        return (Data("{}".utf8), response)
    }
}

final class RateLimitTrackingTransportTests: XCTestCase {
    private let url = URL(string: "https://api.github.com/user")!

    func testParsesTheQuotaHeaders() async throws {
        let reset = Date().addingTimeInterval(2400)
        let inner = HeaderTransport(headers: [
            "x-ratelimit-limit": "5000",
            "x-ratelimit-remaining": "4831",
            "x-ratelimit-reset": String(Int(reset.timeIntervalSince1970)),
        ])
        let transport = RateLimitTrackingTransport(wrapping: inner)
        _ = try await transport.get(url, headers: [:])

        let limit = try XCTUnwrap(transport.rateLimit(forHost: "api.github.com"))
        XCTAssertEqual(limit.limit, 5000)
        XCTAssertEqual(limit.remaining, 4831)
        XCTAssertEqual(limit.resetsAt?.timeIntervalSince1970 ?? 0,
                       reset.timeIntervalSince1970, accuracy: 1)
        XCTAssertFalse(limit.isLow)
    }

    /// Forgejo sends no quota headers. An absent quota is not a zero quota —
    /// showing "0/0" would be a lie.
    func testHostWithoutQuotaHeadersReportsNothing() async throws {
        let transport = RateLimitTrackingTransport(wrapping: HeaderTransport(headers: [:]))
        _ = try await transport.get(URL(string: "https://git.example.dev/api/v1/user")!, headers: [:])
        XCTAssertNil(transport.rateLimit(forHost: "git.example.dev"))
        XCTAssertTrue(transport.allRateLimits.isEmpty)
    }

    func testLowQuotaIsFlagged() {
        let plenty = CIRateLimit(limit: 5000, remaining: 4000, resetsAt: nil)
        let nearlyGone = CIRateLimit(limit: 5000, remaining: 200, resetsAt: nil)
        XCTAssertFalse(plenty.isLow)
        XCTAssertTrue(nearlyGone.isLow)
        XCTAssertEqual(nearlyGone.fractionRemaining, 0.04, accuracy: 0.001)
    }

    /// A malformed or zero limit must not divide by zero.
    func testZeroLimitDoesNotDivideByZero() {
        let odd = CIRateLimit(limit: 0, remaining: 0, resetsAt: nil)
        XCTAssertEqual(odd.fractionRemaining, 1)
        XCTAssertFalse(odd.isLow)
    }

    func testQuotaIsTrackedPerHost() async throws {
        let a = RateLimitTrackingTransport(wrapping: HeaderTransport(headers: [
            "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "10",
        ]))
        _ = try await a.get(url, headers: [:])
        XCTAssertNotNil(a.rateLimit(forHost: "api.github.com"))
        XCTAssertNil(a.rateLimit(forHost: "git.example.dev"))
    }

    func testSettingsRendersQuotaWithReset() {
        // Fixed `now`, so the assertion cannot depend on how long the test took
        // to reach this line.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let limit = CIRateLimit(
            limit: 5000, remaining: 4831, resetsAt: now.addingTimeInterval(2520)
        )
        XCTAssertEqual(
            CICDSettingsView.quotaText(limit, now: now),
            "4831/5000 · resets in 42m"
        )

        let noReset = CIRateLimit(limit: 60, remaining: 59, resetsAt: nil)
        XCTAssertEqual(CICDSettingsView.quotaText(noReset, now: now), "59/60")
    }

    /// Under a minute must read as "resetting", not "0m".
    func testQuotaResetWithinAMinute() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = CIRateLimit(limit: 60, remaining: 0, resetsAt: now.addingTimeInterval(20))
        XCTAssertEqual(CICDSettingsView.quotaText(soon, now: now), "0/60 · resetting")

        // Already past — the host will have reset by the time we ask again.
        let past = CIRateLimit(limit: 60, remaining: 0, resetsAt: now.addingTimeInterval(-90))
        XCTAssertEqual(CICDSettingsView.quotaText(past, now: now), "0/60 · resetting")
    }
}
