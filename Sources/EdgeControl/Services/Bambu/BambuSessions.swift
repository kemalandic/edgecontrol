import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Network
import Security

/// A connection the Bambu service can drop. Tests stand in for the network
/// with their own.
public protocol BambuLink: AnyObject, Sendable {
    func cancel()
}

/// A camera picture, decoded off the main thread.
public struct BambuCameraFrame: @unchecked Sendable {
    public let image: CGImage
}

/// TLS to a Bambu printer.
///
/// Printers present a certificate from Bambu's own authority, "BBL CA",
/// which macOS doesn't know, so it is accepted without checking the
/// authority. Only the access code goes out, and only to the address that
/// was typed in or found. The certificate's common name is the printer's
/// serial number, which the MQTT topics are named after.
enum BambuTLS {
    static func parameters(queue: DispatchQueue, onSerial: @escaping @Sendable (String?) -> Void) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tls.securityProtocolOptions,
            { _, trust, complete in
                let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                var serial: String?
                if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first {
                    var name: CFString?
                    SecCertificateCopyCommonName(leaf, &name)
                    serial = name as String?
                }
                onSerial(serial)
                complete(true)
            }, queue)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        return NWParameters(tls: tls, tcp: tcp)
    }

    /// Network.framework's own errors, in words a tile can hold.
    static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(.ECONNREFUSED): return "Refused the connection"
        case .tls: return "Secure connection failed"
        default: return "Not reachable"
        }
    }
}

/// Listens to one printer's MQTT reports, on a queue of its own.
///
/// After connecting it asks once for the full status ("pushall"); P1 and A1
/// printers then send only what changes. The full status is asked for again
/// every ten minutes in case a change was missed; Bambu warns that asking
/// more often slows a P1P down. Nothing is ever sent that would move or heat
/// the printer.
final class BambuMQTTSession: BambuLink, @unchecked Sendable {
    enum Event: Sendable {
        case connected(serial: String)
        /// The `print` object of a report; `complete` when it is the whole status.
        case report(BambuJSON, complete: Bool)
        case failed(String)
    }

    static let port: NWEndpoint.Port = 8883
    static let keepAlive: UInt16 = 60
    static let resyncInterval: TimeInterval = 600

    private let host: String
    private let accessCode: String
    private let handler: @MainActor @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "EdgeControl.Bambu.MQTT")

    // Touched only on `queue`.
    private var connection: NWConnection?
    private var decoder = MQTT.Decoder()
    private var serial: String?
    private var timer: DispatchSourceTimer?
    private var lastHeard = Date()
    private var lastPushAll = Date.distantPast
    private var finished = false

    init(host: String, accessCode: String, handler: @escaping @MainActor @Sendable (Event) -> Void) {
        self.host = host
        self.accessCode = accessCode
        self.handler = handler
        queue.async { self.open() }
    }

    func cancel() {
        queue.async { self.finish(nil) }
    }

    private func open() {
        let parameters = BambuTLS.parameters(queue: queue) { [weak self] serial in self?.serial = serial }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: Self.port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.ready()
            case .waiting(let error), .failed(let error): self?.finish(BambuTLS.describe(error))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func ready() {
        guard let serial, !serial.isEmpty else { return finish("Not a Bambu Lab printer") }
        let clientID = "edgecontrol-\(UUID().uuidString.prefix(8))"
        send(MQTT.connect(clientID: clientID, username: "bblp", password: accessCode, keepAlive: Self.keepAlive))
        receive()
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.lastHeard = Date()
                self.decoder.append(data)
                do {
                    while let packet = try self.decoder.next() { self.handle(packet) }
                } catch {
                    return self.finish("Unexpected reply")
                }
            }
            if done || error != nil { return self.finish("Connection closed") }
            self.receive()
        }
    }

    private func handle(_ packet: MQTT.Packet) {
        guard let serial else { return }
        switch packet {
        case .connAck(0):
            send(MQTT.subscribe("device/\(serial)/report", packetID: 1))
            emit(.connected(serial: serial))
        case .connAck(4), .connAck(5):
            finish("Wrong access code")
        case .connAck(let code):
            finish("Refused (code \(code))")
        case .subAck(_, let granted):
            guard !granted.contains(0x80) else { return finish("Refused the subscription") }
            pushAll()
            startTimer()
        case .publish(_, let payload, let packetID):
            if let packetID { send(MQTT.publishAck(packetID)) }
            guard let report = try? BambuJSON.parse(payload), let print = report["print"],
                print["command"]?.text == "push_status"
            else { return }
            emit(.report(print, complete: print["msg"]?.int == 0))
        case .pingResponse, .other:
            break
        }
    }

    private func pushAll() {
        guard let serial else { return }
        lastPushAll = Date()
        let request = #"{"pushing":{"sequence_id":"0","command":"pushall","version":1,"push_target":1}}"#
        send(MQTT.publish("device/\(serial)/request", payload: Data(request.utf8)))
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // A printer that has said nothing for two keep-alives is gone,
            // even if the socket hasn't noticed.
            if Date().timeIntervalSince(self.lastHeard) > Double(Self.keepAlive) * 2 {
                return self.finish("Stopped answering")
            }
            self.send(MQTT.pingRequest)
            if Date().timeIntervalSince(self.lastPushAll) > Self.resyncInterval { self.pushAll() }
        }
        timer.resume()
        self.timer = timer
    }

    private func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    private func finish(_ problem: String?) {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        timer = nil
        if connection?.state == .ready { send(MQTT.disconnect) }
        connection?.cancel()
        connection = nil
        if let problem { emit(.failed(problem)) }
    }

    private func emit(_ event: Event) {
        let handler = handler
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(event) } }
    }
}

// MARK: - Camera

/// The camera of a P1 or A1 printer: JPEG pictures over TLS on port 6000.
///
/// X1 and H2 printers stream RTSP instead, which AVFoundation can't play;
/// for them the connection is refused and the widget shows no camera.
final class BambuCameraSession: BambuLink, @unchecked Sendable {
    enum Event: Sendable {
        case frame(BambuCameraFrame)
        case failed(String)
    }

    static let port: NWEndpoint.Port = 6000

    private let host: String
    private let accessCode: String
    private let handler: @MainActor @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "EdgeControl.Bambu.Camera")

    private var connection: NWConnection?
    private var reader = BambuFrameReader()
    private var finished = false

    init(host: String, accessCode: String, handler: @escaping @MainActor @Sendable (Event) -> Void) {
        self.host = host
        self.accessCode = accessCode
        self.handler = handler
        queue.async { self.open() }
    }

    func cancel() {
        queue.async { self.finish(nil) }
    }

    private func open() {
        let parameters = BambuTLS.parameters(queue: queue) { _ in }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: Self.port, using: parameters)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.connection?.send(
                    content: BambuFrameReader.authPacket(accessCode: self.accessCode),
                    completion: .contentProcessed { _ in })
                self.receive()
            case .waiting(let error), .failed(let error):
                self.finish(BambuTLS.describe(error))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, done, error in
            guard let self, !self.finished else { return }
            if let data, !data.isEmpty {
                self.reader.append(data)
                do {
                    while let jpeg = try self.reader.next() {
                        if let image = Self.decode(jpeg) { self.emit(.frame(BambuCameraFrame(image: image))) }
                    }
                } catch {
                    return self.finish("Unexpected picture data")
                }
            }
            // The printer closes the stream straight away on a wrong code.
            if done || error != nil { return self.finish("Camera closed") }
            self.receive()
        }
    }

    private static func decode(_ jpeg: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func finish(_ problem: String?) {
        guard !finished else { return }
        finished = true
        connection?.cancel()
        connection = nil
        if let problem { emit(.failed(problem)) }
    }

    private func emit(_ event: Event) {
        let handler = handler
        DispatchQueue.main.async { MainActor.assumeIsolated { handler(event) } }
    }
}

/// The camera stream's framing: a 16-byte little-endian header giving the
/// JPEG's length, then the JPEG.
struct BambuFrameReader {
    enum DecodingError: Error, Equatable {
        case malformed
    }

    /// No picture from a 1280×720 camera comes near this; a larger length
    /// means the stream has lost its place.
    static let maximumFrame = 4 << 20

    private var buffer = Data()

    /// Sent first: the stream's own login, with the user "bblp" and the
    /// access code, each padded to 32 bytes.
    static func authPacket(accessCode: String) -> Data {
        var data = Data()
        for value: UInt32 in [0x40, 0x3000, 0, 0] {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        for text in ["bblp", accessCode] {
            var field = Array(text.utf8.prefix(32))
            field += Array(repeating: 0, count: 32 - field.count)
            data.append(contentsOf: field)
        }
        return data
    }

    mutating func append(_ data: Data) {
        buffer.append(data)
    }

    /// The next whole JPEG, or nil until more bytes arrive.
    mutating func next() throws -> Data? {
        guard buffer.count >= 16 else { return nil }
        let start = buffer.startIndex
        let length = buffer[start..<start + 4].enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard length > 0, length <= Self.maximumFrame else { throw DecodingError.malformed }
        guard buffer.count >= 16 + length else { return nil }
        let jpeg = Data(buffer[(start + 16)..<(start + 16 + length)])
        buffer = Data(buffer[(start + 16 + length)...])
        guard jpeg.prefix(2) == Data([0xFF, 0xD8]), jpeg.suffix(2) == Data([0xFF, 0xD9]) else {
            throw DecodingError.malformed
        }
        return jpeg
    }
}
