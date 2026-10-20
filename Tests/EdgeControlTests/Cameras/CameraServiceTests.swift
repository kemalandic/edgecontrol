import Foundation
import Testing
@testable import EdgeControl

/// Throws what URLSessionTransport throws when a host can't be reached.
private struct UnreachableTransport: CITransport {
    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        throw CIError.unreachable
    }
}

@MainActor
@Suite("Camera service")
struct CameraServiceTests {
    private let server = URL(string: "http://192.168.1.20:1984")!

    @Test("reads a server's cameras from /api/streams")
    func loads() async {
        let transport = StubTransport(replies: [("api/streams", StubTransport.fixture("go2rtc-streams"))])
        let service = CameraService(transport: transport)

        await service.refresh(server)

        #expect(service.lists[server] == .loaded(["Back_Yard", "camera9", "camera10", "front_door", "garage"]))
        #expect(transport.requestedURLs.map(\.absoluteString) == ["http://192.168.1.20:1984/api/streams"])
    }

    @Test("an unreachable server says so")
    func unreachable() async {
        let service = CameraService(transport: UnreachableTransport())
        await service.refresh(server)
        #expect(service.lists[server] == .failed("not reachable"))
    }

    @Test(
        "HTTP errors become short, actionable text",
        arguments: [
            (401, "asks for a login, which isn't supported yet"),
            (404, "no go2rtc API at this address"),
            (500, "answered with error 500"),
        ])
    func httpErrors(status: Int, message: String) async {
        let transport = StubTransport(replies: [("api/streams", .init(data: Data(), status: status))])
        let service = CameraService(transport: transport)
        await service.refresh(server)
        #expect(service.lists[server] == .failed(message))
    }

    @Test("a server that isn't go2rtc is reported, not shown as having no cameras")
    func notGo2rtc() async {
        let transport = StubTransport(replies: [("api/streams", .init(data: Data("<html></html>".utf8)))])
        let service = CameraService(transport: transport)
        await service.refresh(server)
        #expect(service.lists[server] == .failed("didn't answer like go2rtc"))
    }

    @Test("watching marks the server as loading until it answers")
    func watchStartsLoading() {
        let transport = StubTransport(replies: [("api/streams", StubTransport.fixture("go2rtc-streams"))])
        let service = CameraService(transport: transport)
        service.watch(server)
        #expect(service.lists[server] == .loading)
    }
}
