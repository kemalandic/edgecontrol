import CoreGraphics
import Foundation
import Testing
@testable import EdgeControl

/// Stands in for a network connection: records what it was opened with and
/// lets the test speak for the printer.
private final class FakeLink: BambuLink, @unchecked Sendable {
    let host: String
    let accessCode: String
    private(set) var cancelled = false

    init(host: String, accessCode: String) {
        self.host = host
        self.accessCode = accessCode
    }

    func cancel() { cancelled = true }
}

/// What a search of the network finds, set by the test.
private final class FakeScan: @unchecked Sendable {
    private let lock = NSLock()
    private var _result: [BambuDiscovery.Found] = []
    private var _count = 0

    var result: [BambuDiscovery.Found] {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }
    var count: Int { lock.withLock { _count } }

    func run() -> [BambuDiscovery.Found] {
        lock.withLock {
            _count += 1
            return _result
        }
    }
}

@MainActor
private final class FakeNetwork {
    let scan = FakeScan()
    var reports: [(link: FakeLink, send: @MainActor @Sendable (BambuMQTTSession.Event) -> Void)] = []
    var cameras: [(link: FakeLink, send: @MainActor @Sendable (BambuCameraSession.Event) -> Void)] = []
    var previews: [(link: FakeLink, paths: [String], send: @MainActor @Sendable (BambuPreviewSession.Event) -> Void)] =
        []

    func service(secrets: CISecretStore) -> BambuService {
        BambuService(
            secrets: secrets, retryDelays: [.milliseconds(1)],
            makeReportLink: { host, code, handler in
                let link = FakeLink(host: host, accessCode: code)
                self.reports.append((link, handler))
                return link
            },
            makeCameraLink: { host, code, handler in
                let link = FakeLink(host: host, accessCode: code)
                self.cameras.append((link, handler))
                return link
            },
            makePreviewLink: { host, code, paths, handler in
                let link = FakeLink(host: host, accessCode: code)
                self.previews.append((link, paths, handler))
                return link
            },
            scan: { [scan] in scan.run() })
    }
}

@MainActor
@Suite("Bambu service")
struct BambuServiceTests {
    private let host = "192.168.1.50"

    private func secrets(code: String? = "12345678") throws -> InMemorySecretStore {
        let store = InMemorySecretStore()
        if let code { try store.write(code, for: host) }
        return store
    }

    @Test("watching a printer connects with its saved access code")
    func connects() throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())

        service.watch(host)

        #expect(network.reports.map(\.link.host) == [host])
        #expect(network.reports.first?.link.accessCode == "12345678")
        #expect(service.printers[host]?.connection == .connecting)

        network.reports[0].send(.connected(serial: "01P00A000000000"))
        #expect(service.printers[host]?.connection == .connected)
        #expect(service.printers[host]?.model == "P1S")
    }

    @Test("without an access code nothing connects, and the widget says what's missing")
    func needsCode() throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets(code: nil))

        service.watch(host)

        #expect(network.reports.isEmpty)
        #expect(service.printers[host]?.connection == .needsAccessCode)

        try service.setAccessCode(" 87654321 ", for: host)
        #expect(network.reports.map(\.link.accessCode) == ["87654321"])
    }

    @Test("a full report, then a delta laid over it")
    func reports() throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())
        service.watch(host)

        network.reports[0].send(.report(try bambuFixture("bambu-p1s-pushall"), complete: true))
        network.reports[0].send(.report(try bambuJSON(#"{"mc_percent":8,"layer_num":2}"#), complete: false))

        let status = try #require(service.printers[host]?.status)
        #expect(status.progress == 8)
        #expect(status.layer == 2)
        #expect(status.filaments.count == 4)
    }

    @Test("a lost printer keeps its last status and is tried again")
    func retries() async throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())
        service.watch(host)
        network.reports[0].send(.report(try bambuFixture("bambu-p1s-pushall"), complete: true))

        network.reports[0].send(.failed("Not reachable"))

        #expect(service.printers[host]?.connection == .failed("Not reachable"))
        #expect(service.printers[host]?.status?.progress == 7)
        try await Task.sleep(for: .milliseconds(50))
        #expect(network.reports.count == 2)
    }

    @Test("a wrong access code isn't retried until a new one is entered")
    func wrongCode() async throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())
        service.watch(host)

        network.reports[0].send(.failed("Wrong access code"))
        try await Task.sleep(for: .milliseconds(50))

        #expect(network.reports.count == 1)
        #expect(service.printers[host]?.connection == .failed("Wrong access code"))
    }

    @Test("two widgets share one connection, which closes when the last one goes")
    func sharing() throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())

        service.watch(host)
        service.watch(host)
        #expect(network.reports.count == 1)

        service.unwatch(host)
        #expect(network.reports[0].link.cancelled == false)
        service.unwatch(host)
        #expect(network.reports[0].link.cancelled)
    }

    @Test("events from a dropped connection are ignored")
    func staleEvents() throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())
        service.watch(host)
        let old = network.reports[0]

        service.reconnect(host)
        old.send(.connected(serial: "01P00A000000000"))

        #expect(old.link.cancelled)
        #expect(service.printers[host]?.connection == .connecting)
    }

    @Test("the camera streams only while watched, and drops its picture when unwatched")
    func camera() throws {
        let network = FakeNetwork()
        let service = network.service(secrets: try secrets())

        service.watchCamera(host)
        #expect(network.cameras.count == 1)

        let image = try #require(
            CGContext(
                data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage())
        network.cameras[0].send(.frame(BambuCameraFrame(image: image)))
        #expect(service.frames[host] != nil)

        service.unwatchCamera(host)
        #expect(network.cameras[0].link.cancelled)
        #expect(service.frames[host] == nil)
    }
}

@Suite("Bambu camera framing")
struct BambuFrameReaderTests {
    private func frame(_ jpeg: [UInt8]) -> Data {
        var header = [UInt8](repeating: 0, count: 16)
        let length = UInt32(jpeg.count)
        for index in 0..<4 { header[index] = UInt8(length >> (8 * UInt32(index)) & 0xFF) }
        header[8] = 1
        return Data(header + jpeg)
    }

    @Test("the login packet is 80 bytes: header, then user and code padded to 32")
    func auth() {
        let packet = [UInt8](BambuFrameReader.authPacket(accessCode: "12345678"))
        #expect(packet.count == 80)
        #expect(Array(packet.prefix(8)) == [0x40, 0, 0, 0, 0, 0x30, 0, 0])
        #expect(Array(packet[16..<20]) == Array("bblp".utf8))
        #expect(packet[20..<48].allSatisfy { $0 == 0 })
        #expect(Array(packet[48..<56]) == Array("12345678".utf8))
    }

    @Test("pictures split across reads come out whole")
    func frames() throws {
        let jpeg: [UInt8] = [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]
        let stream = frame(jpeg) + frame(jpeg)
        var reader = BambuFrameReader()
        reader.append(stream.prefix(10))
        #expect(try reader.next() == nil)
        reader.append(stream.dropFirst(10))
        #expect(try reader.next() == Data(jpeg))
        #expect(try reader.next() == Data(jpeg))
        #expect(try reader.next() == nil)
    }

    @Test("a stream that has lost its place is an error")
    func lostPlace() {
        var reader = BambuFrameReader()
        reader.append(frame([1, 2, 3, 4]))
        #expect(throws: BambuFrameReader.DecodingError.malformed) { try reader.next() }

        var huge = BambuFrameReader()
        huge.append(Data([0xFF, 0xFF, 0xFF, 0x7F] + [UInt8](repeating: 0, count: 12)))
        #expect(throws: BambuFrameReader.DecodingError.malformed) { try huge.next() }
    }
}

@MainActor
@Suite("Bambu model picture fetching")
struct BambuPreviewFetchTests {
    private let host = "192.168.1.50"

    private func service(_ network: FakeNetwork) throws -> BambuService {
        let store = InMemorySecretStore()
        try store.write("12345678", for: host)
        return network.service(secrets: store)
    }

    private func job(_ file: String, percent: Int = 10) throws -> BambuMQTTSession.Event {
        .report(
            try bambuJSON(#"{"gcode_state":"RUNNING","gcode_file":"\#(file)","mc_percent":\#(percent)}"#),
            complete: true)
    }

    @Test("a job's picture is fetched once, from where printers keep job files")
    func once() throws {
        let network = FakeNetwork()
        let service = try service(network)
        service.watch(host)
        service.watchPreview(host)

        network.reports[0].send(try job("Shelf_plate_2.3mf"))
        network.reports[0].send(try job("Shelf_plate_2.3mf", percent: 11))

        #expect(network.previews.count == 1)
        #expect(network.previews[0].paths == ["/cache/Shelf_plate_2.3mf", "/Shelf_plate_2.3mf"])
        network.previews[0].send(.preview(try #require(BambuModelPreview(png: testPNG(gray: 0.5)))))
        #expect(service.previews[host] != nil)
    }

    @Test("a new job replaces the picture")
    func newJob() throws {
        let network = FakeNetwork()
        let service = try service(network)
        service.watch(host)
        service.watchPreview(host)
        network.reports[0].send(try job("Shelf_plate_2.3mf"))
        network.previews[0].send(.preview(try #require(BambuModelPreview(png: testPNG(gray: 0.5)))))

        network.reports[0].send(try job("Lid.3mf"))

        #expect(service.previews[host] == nil)
        #expect(network.previews.count == 2)
        #expect(network.previews[1].paths.first == "/cache/Lid.3mf")
    }

    @Test("plain G-code jobs have no picture to fetch")
    func gcode() throws {
        let network = FakeNetwork()
        let service = try service(network)
        service.watch(host)
        service.watchPreview(host)
        network.reports[0].send(try job("calibration.gcode"))
        #expect(network.previews.isEmpty)
    }

    @Test("nothing is fetched until a widget shows the model")
    func onlyWhenShown() throws {
        let network = FakeNetwork()
        let service = try service(network)
        service.watch(host)
        network.reports[0].send(try job("Shelf_plate_2.3mf"))
        #expect(network.previews.isEmpty)

        service.watchPreview(host)
        #expect(network.previews.count == 1)
    }

    @Test("a failed fetch is tried three times in all, then left")
    func retries() async throws {
        let network = FakeNetwork()
        let service = try service(network)
        service.watch(host)
        service.watchPreview(host)
        network.reports[0].send(try job("Shelf_plate_2.3mf"))

        for attempt in 0..<3 {
            #expect(network.previews.count == attempt + 1)
            network.previews[attempt].send(.failed("Job file not found"))
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(network.previews.count == 3)
    }
}

@MainActor
@Suite("Bambu printer discovery")
struct BambuDiscoveryTests {
    private let serial = "01P00A000000001"

    @Test("a /24 network is every address but its own, its network and its broadcast")
    func homeNetwork() {
        let hosts = BambuDiscovery.hosts(address: 0xC0A8_010A, mask: 0xFFFF_FF00)  // 192.168.1.10/24
        #expect(hosts.count == 253)
        #expect(hosts.first == "192.168.1.1")
        #expect(hosts.last == "192.168.1.254")
        #expect(!hosts.contains("192.168.1.10"))
    }

    @Test("a big network is narrowed to the 256 addresses around this Mac; link-local is skipped")
    func narrowing() {
        let hosts = BambuDiscovery.hosts(address: 0x0A00_0507, mask: 0xFFFF_0000)  // 10.0.5.7/16
        #expect(hosts.count == 253)
        #expect(hosts.allSatisfy { $0.hasPrefix("10.0.5.") })
        #expect(BambuDiscovery.hosts(address: 0x0A00_0001, mask: 0xFFFF_FFFC) == ["10.0.0.2"])
        #expect(BambuDiscovery.hosts(address: 0xA9FE_0102, mask: 0xFFFF_0000).isEmpty)
    }

    @Test("only Bambu's authority and a serial-shaped name count as a printer")
    func certificate() {
        #expect(BambuDiscovery.isSerial("01P00A000000001"))
        #expect(!BambuDiscovery.isSerial("printer.local"))
        #expect(!BambuDiscovery.isSerial("01p00a000000001"))
        #expect(BambuDiscovery.isBambuIssuer(Data("O=BBL Technologies Co., Ltd, CN=BBL CA".utf8)))
        #expect(!BambuDiscovery.isBambuIssuer(Data("CN=Let's Encrypt".utf8)))
    }

    @Test("Find Printers lists what the search found")
    func discover() async throws {
        let network = FakeNetwork()
        network.scan.result = [.init(host: "192.168.1.60", serial: serial)]
        let service = network.service(secrets: InMemorySecretStore())

        service.discover()
        #expect(service.discovering)
        try await Task.sleep(for: .milliseconds(50))

        #expect(!service.discovering)
        #expect(service.discovered?.map(\.host) == ["192.168.1.60"])
        #expect(service.discovered?.first?.model == "P1S")
    }

    @Test("a printer that goes quiet is looked for by serial, and its access code follows it")
    func follows() async throws {
        let network = FakeNetwork()
        let store = InMemorySecretStore()
        try store.write("12345678", for: "192.168.1.50")
        let service = network.service(secrets: store)
        network.scan.result = [.init(host: "192.168.1.77", serial: serial)]
        service.watch("192.168.1.50", serial: serial)

        network.reports[0].send(.failed("Not reachable"))
        try await Task.sleep(for: .milliseconds(30))
        #expect(network.scan.count == 0)  // one failure is a blip

        network.reports[1].send(.failed("Not reachable"))
        try await Task.sleep(for: .milliseconds(50))

        #expect(network.scan.count == 1)
        #expect(service.moves["192.168.1.50"] == "192.168.1.77")
        #expect(store.read("192.168.1.77") == "12345678")
    }

    @Test("a wrong access code isn't a move, so nothing is searched")
    func wrongCodeIsNotAMove() async throws {
        let network = FakeNetwork()
        let store = InMemorySecretStore()
        try store.write("12345678", for: "192.168.1.50")
        let service = network.service(secrets: store)
        service.watch("192.168.1.50", serial: serial)

        network.reports[0].send(.failed("Wrong access code"))
        try await Task.sleep(for: .milliseconds(30))
        #expect(network.scan.count == 0)
    }
}
