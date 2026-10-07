import Foundation
import Network
import Testing
@testable import EdgeControl

/// Answers each POST with the next scripted reply, and records where it went.
final class ScriptedPrinterTransport: PrinterTransport, @unchecked Sendable {
    enum Reply: Sendable {
        case data(Data, status: Int = 200)
        case unreachable
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var _posts: [(url: URL, body: Data)] = []

    var postedURLs: [String] { lock.withLock { _posts.map(\.url.absoluteString) } }
    var bodies: [Data] { lock.withLock { _posts.map(\.body) } }

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        let reply = lock.withLock {
            _posts.append((url, body))
            return replies.isEmpty ? .unreachable : replies.removeFirst()
        }
        switch reply {
        case .data(let data, let status):
            return (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
        case .unreachable:
            throw URLError(.timedOut)
        }
    }
}

@MainActor
@Suite("Printer service")
struct PrinterServiceTests {
    private let id = "HP Smart Tank 6000 series [115A08]"
    private let endpoint = PrinterEndpoint(host: "192.168.1.150", port: 631, resourcePath: "ipp/print", secure: false)

    @Test("asks the printer at its IPP address and reads its status")
    func fetches() async throws {
        let transport = ScriptedPrinterTransport([.data(ippFixture("ipp-hp-smart-tank"))])
        let service = PrinterService(transport: transport)

        let outcome = await service.fetch(endpoint, name: id)

        guard case .success(let status, let used) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(status.name == "HP Smart Tank 6000 series")
        #expect(used == endpoint)
        #expect(transport.postedURLs == ["http://192.168.1.150:631/ipp/print"])
        let body = try #require(transport.bodies.first)
        #expect(body.range(of: Data("ipp://192.168.1.150:631/ipp/print".utf8)) != nil)
    }

    @Test("a printer that answers 426 is asked again over TLS, and remembered as secure")
    func upgradesToTLS() async {
        let transport = ScriptedPrinterTransport([.data(Data(), status: 426), .data(ippFixture("ipp-hp-smart-tank"))])
        let service = PrinterService(transport: transport)

        let outcome = await service.fetch(endpoint, name: id)

        guard case .success(_, let used) = outcome else {
            Issue.record("expected success, got \(outcome)")
            return
        }
        #expect(used.secure)
        #expect(
            transport.postedURLs == ["http://192.168.1.150:631/ipp/print", "https://192.168.1.150:631/ipp/print"])
        #expect(transport.bodies[1].range(of: Data("ipps://192.168.1.150:631/ipp/print".utf8)) != nil)
    }

    @Test(
        "failures become short status text",
        arguments: [
            (ScriptedPrinterTransport.Reply.unreachable, "Not responding"),
            (.data(Data(), status: 500), "Error 500"),
            (.data(Data("<html>".utf8)), "Unexpected reply"),
            (.data(ippReply(status: 0x0400, [])), "Refused the request"),
        ])
    func failures(reply: ScriptedPrinterTransport.Reply, text: String) async {
        let service = PrinterService(transport: ScriptedPrinterTransport([reply]))
        #expect(await service.fetch(endpoint, name: id) == .failure(text))
    }

    @Test("a printer that stops answering keeps its last status, with the problem alongside")
    func keepsLastStatus() async throws {
        let transport = ScriptedPrinterTransport([.data(ippFixture("ipp-hp-smart-tank")), .unreachable])
        let service = PrinterService(transport: transport)
        service.add(id: id, endpoint: endpoint)

        await service.refresh(id)
        #expect(service.printers.first?.status?.state == .idle)
        #expect(service.printers.first?.problem == nil)

        await service.refresh(id)
        let printer = try #require(service.printers.first)
        #expect(printer.status?.supplies.count == 4)
        #expect(printer.problem == "Not responding")
    }

    @Test("before it answers, a printer is named from its Bonjour name")
    func nameBeforeStatus() {
        let service = PrinterService(transport: ScriptedPrinterTransport([]))
        service.add(id: id, endpoint: endpoint)
        #expect(service.printers.first?.name == "HP Smart Tank 6000 series")
    }

    @Test("IPv6 addresses are bracketed, and TLS changes both schemes")
    func endpointURLs() {
        let v6 = PrinterEndpoint(host: "fe80::1", port: 631, resourcePath: "ipp/print", secure: true)
        #expect(v6.url?.absoluteString == "https://[fe80::1]:631/ipp/print")
        #expect(v6.printerURI == "ipps://[fe80::1]:631/ipp/print")
        #expect(endpoint.printerURI == "ipp://192.168.1.150:631/ipp/print")
    }

    @Test(
        "resolved addresses lose the interface Network.framework appends",
        arguments: [
            ("192.168.1.20%en7", "192.168.1.20"), ("192.168.1.20", "192.168.1.20"),
            ("fe80::1%en0", "fe80::1"),
        ])
    func resolvedAddress(raw: String, address: String) {
        #expect(PrinterService.address(NWEndpoint.Host(raw)) == address)
        #expect(PrinterService.address(.name("HP115A08.local", nil)) == "HP115A08.local")
    }

    @Test("an address no URL can hold is a failure, not a crash")
    func badAddress() async {
        let transport = ScriptedPrinterTransport([])
        let service = PrinterService(transport: transport)
        let scoped = PrinterEndpoint(host: "192.168.1.20%en7", port: 631, resourcePath: "ipp/print", secure: false)
        #expect(await service.fetch(scoped, name: id) == .failure("Bad address"))
        #expect(transport.postedURLs.isEmpty)
    }
}
