import XCTest
@testable import EdgeControl

final class CIErrorMappingTests: XCTestCase {
    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.test/api")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    func testSuccessMapsToNil() {
        XCTAssertNil(CIError.from(response: response(200)))
        XCTAssertNil(CIError.from(response: response(304)))
    }

    func testUnauthorizedStatuses() {
        XCTAssertEqual(CIError.from(response: response(401)), .unauthorized)
    }

    /// A 403 is ambiguous on GitHub: it means "forbidden" normally, but
    /// "rate limited" when the remaining quota is zero. The header decides.
    func testForbiddenWithoutRateLimitHeaderIsUnauthorized() {
        XCTAssertEqual(CIError.from(response: response(403)), .unauthorized)
    }

    func testForbiddenWithExhaustedQuotaIsRateLimited() {
        let r = response(403, headers: [
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "1785999999",
        ])
        XCTAssertEqual(
            CIError.from(response: r),
            .rateLimited(retryAfter: Date(timeIntervalSince1970: 1_785_999_999))
        )
    }

    func testTooManyRequestsUsesRetryAfterSeconds() throws {
        let r = response(429, headers: ["retry-after": "120"])
        guard case .rateLimited(let date) = CIError.from(response: r) else {
            return XCTFail("expected rateLimited")
        }
        let delta = try XCTUnwrap(date).timeIntervalSinceNow
        XCTAssertEqual(delta, 120, accuracy: 2)
    }

    func testTooManyRequestsWithoutHeader() {
        XCTAssertEqual(CIError.from(response: response(429)), .rateLimited(retryAfter: nil))
    }

    func testServerErrorCarriesStatus() {
        XCTAssertEqual(CIError.from(response: response(503)), .httpStatus(503))
    }

    func testUnexpectedClientErrorCarriesStatus() {
        XCTAssertEqual(CIError.from(response: response(404)), .httpStatus(404))
    }
}
