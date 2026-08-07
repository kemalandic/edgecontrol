import XCTest
@testable import EdgeControl

/// Records every request it sees and replies from a scripted list.
private final class ScriptedTransport: CITransport, @unchecked Sendable {
    struct Step {
        let status: Int
        let body: String
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var _seenHeaders: [[String: String]] = []

    var seenHeaders: [[String: String]] { lock.withLock { _seenHeaders } }
    var requestCount: Int { lock.withLock { _seenHeaders.count } }

    init(steps: [Step]) { self.steps = steps }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let step: Step = lock.withLock {
            _seenHeaders.append(headers)
            return steps.isEmpty ? Step(status: 200, body: "", headers: [:]) : steps.removeFirst()
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: step.status,
            httpVersion: "HTTP/1.1",
            headerFields: step.headers
        )!
        return (Data(step.body.utf8), response)
    }
}

final class ConditionalGETTransportTests: XCTestCase {
    private let url = URL(string: "https://example.test/api/runs")!

    func testFirstRequestSendsNoValidatorAndStoresTheETag() async throws {
        let inner = ScriptedTransport(steps: [
            .init(status: 200, body: "first", headers: ["ETag": "\"v1\""])
        ])
        let transport = ConditionalGETTransport(wrapping: inner)

        let (data, response) = try await transport.get(url, headers: [:])

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "first")
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNil(inner.seenHeaders[0]["If-None-Match"])
        XCTAssertEqual(transport.cachedEntryCount, 1)
    }

    /// The whole point: a 304 must look like a normal success to the caller,
    /// carrying the body the host did not resend.
    func testNotModifiedReplaysTheCachedBodyAsSuccess() async throws {
        let inner = ScriptedTransport(steps: [
            .init(status: 200, body: "cached-payload", headers: ["ETag": "\"v1\""]),
            .init(status: 304, body: "", headers: [:]),
        ])
        let transport = ConditionalGETTransport(wrapping: inner)

        _ = try await transport.get(url, headers: [:])
        let (data, response) = try await transport.get(url, headers: [:])

        XCTAssertEqual(inner.seenHeaders[1]["If-None-Match"], "\"v1\"")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "cached-payload")
        XCTAssertEqual(response.statusCode, 200, "callers must not have to handle 304")
        XCTAssertNil(CIError.from(response: response))
    }

    func testChangedContentReplacesTheCachedEntry() async throws {
        let inner = ScriptedTransport(steps: [
            .init(status: 200, body: "old", headers: ["ETag": "\"v1\""]),
            .init(status: 200, body: "new", headers: ["ETag": "\"v2\""]),
            .init(status: 304, body: "", headers: [:]),
        ])
        let transport = ConditionalGETTransport(wrapping: inner)

        _ = try await transport.get(url, headers: [:])
        _ = try await transport.get(url, headers: [:])
        let (data, _) = try await transport.get(url, headers: [:])

        XCTAssertEqual(inner.seenHeaders[2]["If-None-Match"], "\"v2\"")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "new")
    }

    /// A host that sends no ETag must keep working, just without caching.
    func testHostWithoutETagIsPassedThroughUnchanged() async throws {
        let inner = ScriptedTransport(steps: [
            .init(status: 200, body: "a", headers: [:]),
            .init(status: 200, body: "b", headers: [:]),
        ])
        let transport = ConditionalGETTransport(wrapping: inner)

        _ = try await transport.get(url, headers: [:])
        let (data, _) = try await transport.get(url, headers: [:])

        XCTAssertEqual(String(decoding: data, as: UTF8.self), "b")
        XCTAssertEqual(transport.cachedEntryCount, 0)
        XCTAssertNil(inner.seenHeaders[1]["If-None-Match"])
    }

    /// Errors must not be cached, or a transient 500 would be replayed forever.
    func testErrorResponsesAreNotCached() async throws {
        let inner = ScriptedTransport(steps: [
            .init(status: 500, body: "boom", headers: ["ETag": "\"v1\""])
        ])
        let transport = ConditionalGETTransport(wrapping: inner)

        let (_, response) = try await transport.get(url, headers: [:])
        XCTAssertEqual(response.statusCode, 500)
        XCTAssertEqual(transport.cachedEntryCount, 0)
    }

    func testCallerSuppliedHeadersSurvive() async throws {
        let inner = ScriptedTransport(steps: [
            .init(status: 200, body: "x", headers: ["ETag": "\"v1\""])
        ])
        let transport = ConditionalGETTransport(wrapping: inner)

        _ = try await transport.get(url, headers: ["Authorization": "token abc"])
        XCTAssertEqual(inner.seenHeaders[0]["Authorization"], "token abc")
    }
}
