import Foundation
import Testing
@testable import EdgeControl

/// Answers the deliveries requests from a script, the carrier list always, and
/// records every request with its headers.
final class ScriptedParcelTransport: CITransport, @unchecked Sendable {
    struct Reply {
        var body: Data
        var status = 200
        var headers: [String: String] = [:]
    }

    private let lock = NSLock()
    private var replies: [Reply]
    private var _requests: [(url: URL, headers: [String: String])] = []

    var requests: [(url: URL, headers: [String: String])] { lock.withLock { _requests } }
    var deliveryURLs: [String] {
        requests.map(\.url.absoluteString).filter { $0.contains("/deliveries/") }
    }

    init(_ replies: [Reply]) {
        self.replies = replies
    }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = lock.withLock {
            _requests.append((url, headers))
            if url.path.hasSuffix("supported_carriers.json") {
                return Reply(body: Data(#"{"ups":{"name":"UPS"},"fedex":{"name":"FedEx"}}"#.utf8))
            }
            return replies.isEmpty ? nil : replies.removeFirst()
        }
        guard let reply else { throw CIError.unreachable }
        let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        return (reply.body, response)
    }
}

@MainActor
private final class Clock {
    var now = parcelNow
}

@MainActor
@Suite("Parcel service")
struct ParcelServiceTests {
    private let clock = Clock()
    private let deliveries = ScriptedParcelTransport.Reply(body: parcelFixture("parcel-deliveries"))
    private let activeURL = "https://api.parcel.app/external/deliveries/?filter_mode=active"
    private let recentURL = "https://api.parcel.app/external/deliveries/?filter_mode=recent"

    private func makeService(
        _ replies: [ScriptedParcelTransport.Reply], key: String? = "test-key"
    ) -> (ParcelService, ScriptedParcelTransport, InMemorySecretStore) {
        let transport = ScriptedParcelTransport(replies)
        let secrets = InMemorySecretStore()
        if let key { try? secrets.write(key, for: ParcelService.keyAccount) }
        let clock = clock
        return (ParcelService(transport: transport, secrets: secrets, clock: { clock.now }), transport, secrets)
    }

    private func wait(minutes: Double) {
        clock.now = clock.now.addingTimeInterval(minutes * 60)
    }

    @Test("without a key nothing is asked, and the widget is told why")
    func needsKey() async {
        let (service, transport, _) = makeService([deliveries], key: nil)
        service.watch(.active)
        await service.tick()
        #expect(transport.requests.isEmpty)
        #expect(!service.hasKey)
        #expect(service.problem == .needsKey)
    }

    @Test("asks for the list a widget shows, with the key in the header Parcel reads")
    func asks() async throws {
        let (service, transport, _) = makeService([deliveries])
        service.watch(.active)
        await service.tick()

        #expect(transport.deliveryURLs == [activeURL])
        let request = try #require(transport.requests.first { $0.url.absoluteString == activeURL })
        #expect(request.headers["api-key"] == "test-key")
        #expect(service.lists[.active]?.deliveries.count == 6)
        #expect(service.lists[.active]?.updated == parcelNow)
        #expect(service.problem == nil)
        #expect(service.carrierName("ups") == "UPS")
        #expect(service.carrierName("amzlus") == "AMZLUS")
    }

    @Test("one list every five minutes; with both on screen, each every ten")
    func pacing() async {
        let (service, transport, _) = makeService(Array(repeating: deliveries, count: 6))
        service.watch(.active)
        await service.tick()
        wait(minutes: 4)
        await service.tick()
        #expect(transport.deliveryURLs.count == 1)
        wait(minutes: 1)
        await service.tick()
        #expect(transport.deliveryURLs == [activeURL, activeURL])

        // A second list is asked for straight away, then both every ten minutes.
        service.watch(.recent)
        await service.tick()
        #expect(transport.deliveryURLs == [activeURL, activeURL, recentURL])
        wait(minutes: 9)
        await service.tick()
        #expect(transport.deliveryURLs.count == 3)
        wait(minutes: 1)
        await service.tick()
        #expect(transport.deliveryURLs.suffix(2) == [activeURL, recentURL])
    }

    @Test("a second widget on the same list doesn't ask twice, and the last one gone stops the asking")
    func watchers() async {
        let (service, transport, _) = makeService(Array(repeating: deliveries, count: 3))
        service.watch(.active)
        service.watch(.active)
        await service.tick()
        service.unwatch(.active)
        wait(minutes: 5)
        await service.tick()
        #expect(transport.deliveryURLs.count == 2)
        service.unwatch(.active)
        wait(minutes: 5)
        await service.tick()
        #expect(transport.deliveryURLs.count == 2)
    }

    @Test("a refused key says so, in Parcel's words")
    func refused() async {
        let refusal = Data(#"{"success":false,"error_message":"Invalid API key"}"#.utf8)
        let (service, _, _) = makeService([.init(body: refusal, status: 401)])
        service.watch(.active)
        await service.tick()
        #expect(service.problem == .keyRefused("Invalid API key"))
    }

    @Test("told to slow down, it waits as long as Parcel asks")
    func rateLimited() async {
        let (service, transport, _) = makeService([
            .init(body: Data(), status: 429, headers: ["Retry-After": "1200"]), deliveries,
        ])
        service.watch(.active)
        await service.tick()
        #expect(service.problem == .rateLimited(until: parcelNow.addingTimeInterval(1200)))
        wait(minutes: 15)
        await service.tick()
        #expect(transport.deliveryURLs.count == 1)
        wait(minutes: 5)
        await service.tick()
        #expect(transport.deliveryURLs.count == 2)
        #expect(service.problem == nil)
    }

    @Test(
        "Retry-After is kept between a minute and a day",
        arguments: [("5", 60.0), ("900", 900), ("999999", 86_400)] as [(String, TimeInterval)])
    func retryAfter(header: String, seconds: TimeInterval) throws {
        let response = try #require(
            HTTPURLResponse(
                url: ParcelService.base, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": header]))
        #expect(ParcelService.retryAfter(response) == seconds)
    }

    @Test("a list that can't be refreshed is kept, with the problem beside it")
    func keepsList() async {
        let (service, _, _) = makeService([deliveries])
        service.watch(.active)
        await service.tick()
        wait(minutes: 5)
        await service.tick()
        #expect(service.lists[.active]?.deliveries.count == 6)
        #expect(service.lists[.active]?.updated == parcelNow)
        #expect(service.problem == .unreachable)
    }

    @Test("a body that isn't Parcel's is a failure, not an empty list")
    func strangeBody() async {
        let (service, _, _) = makeService([.init(body: Data("<html>Bad gateway</html>".utf8))])
        service.watch(.active)
        await service.tick()
        #expect(service.problem == .failed("Unexpected reply"))
        #expect(service.lists[.active] == nil)
    }

    @Test("a new key is trimmed and starts afresh; removing it clears the lists")
    func key() async throws {
        let (service, _, secrets) = makeService([deliveries], key: nil)
        try service.setKey("  new-key \n")
        #expect(secrets.read(ParcelService.keyAccount) == "new-key")
        #expect(service.hasKey)
        #expect(service.problem == nil)

        service.watch(.active)
        await service.tick()
        #expect(service.lists[.active] != nil)
        service.removeKey()
        #expect(secrets.read(ParcelService.keyAccount) == nil)
        #expect(service.lists.isEmpty)
        #expect(service.problem == .needsKey)
    }

    @Test("deliveries come out with what needs doing soonest first")
    func order() async {
        let (service, _, _) = makeService([deliveries])
        service.watch(.active)
        await service.tick()
        #expect(
            service.deliveries(.active)?.map(\.status) == [
                .outForDelivery, .awaitingPickup, .inTransit, .infoReceived, .unknown, .delivered,
            ])
    }

    @Test("among deliveries in the same state, the one due first comes first, and one without a date last")
    func orderByDate() {
        let soon = ParcelDelivery(
            carrier: "ups", description: "B", status: .inTransit, trackingNumber: "1",
            expected: .init(start: newYorkDate(2026, 10, 9), hasTime: false))
        let later = ParcelDelivery(
            carrier: "ups", description: "A", status: .inTransit, trackingNumber: "2",
            expected: .init(start: newYorkDate(2026, 10, 12), hasTime: false))
        let undated = ParcelDelivery(carrier: "ups", description: "C", status: .inTransit, trackingNumber: "3")
        #expect([undated, later, soon].sorted(by: ParcelService.precedes).map(\.trackingNumber) == ["1", "2", "3"])
    }
}
