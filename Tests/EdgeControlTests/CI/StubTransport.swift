import Foundation
@testable import EdgeControl

/// Returns canned responses keyed by URL substring, and records every request
/// so tests can assert on query construction.
final class StubTransport: CITransport, @unchecked Sendable {
    struct Reply {
        let data: Data
        let status: Int
        let headers: [String: String]

        init(data: Data, status: Int = 200, headers: [String: String] = [:]) {
            self.data = data
            self.status = status
            self.headers = headers
        }
    }

    private let replies: [(match: String, reply: Reply)]
    private let lock = NSLock()
    private var _requestedURLs: [URL] = []

    var requestedURLs: [URL] {
        lock.withLock { _requestedURLs }
    }

    init(replies: [(match: String, reply: Reply)]) {
        self.replies = replies
    }

    /// Loads a recorded response from the test bundle.
    static func fixture(_ name: String, status: Int = 200) -> Reply {
        let url = Bundle(for: StubTransport.self).url(forResource: name, withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else {
            fatalError("fixture \(name).json not found in the test bundle — check project.yml resources")
        }
        return Reply(data: data, status: status)
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        // Swift 6 forbids bare lock()/unlock() across an await boundary; the
        // scoped form is the async-safe equivalent.
        lock.withLock { _requestedURLs.append(url) }

        guard let match = replies.first(where: { url.absoluteString.contains($0.match) }) else {
            fatalError("StubTransport has no reply for \(url.absoluteString)")
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: match.reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: match.reply.headers
        )!
        return (match.reply.data, response)
    }
}
