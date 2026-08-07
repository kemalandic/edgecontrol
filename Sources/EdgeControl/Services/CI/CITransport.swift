import Foundation

/// Injection point for HTTP.
///
/// Providers take a transport rather than calling `URLSession` directly, so
/// every provider can be tested against recorded fixtures without network
/// access.
public protocol CITransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: CITransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CIError.decoding("non-HTTP response")
            }
            return (data, http)
        } catch let error as CIError {
            throw error
        } catch {
            // Transport-level failures (DNS, TLS, timeout, offline) all read the
            // same way to the user: the host could not be reached.
            throw CIError.unreachable
        }
    }
}
