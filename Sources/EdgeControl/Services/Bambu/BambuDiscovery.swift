import Darwin
import Foundation
@preconcurrency import Network
import Security

/// Finds Bambu Lab printers on the local network.
///
/// Bambu printers don't advertise over Bonjour, and their own announcements
/// go to a UDP port Bambu Studio holds for itself, which nothing else should
/// take from it. But every Bambu printer answers TLS on its MQTT port with a
/// certificate from Bambu's authority, "BBL CA", whose common name is the
/// printer's serial number. Opening that handshake and hanging up finds each
/// printer and its model without an access code and without sending the
/// printer anything. It runs only when asked, or when a printer that was
/// working stops answering at its address.
public enum BambuDiscovery {
    public struct Found: Equatable, Identifiable, Sendable {
        public let host: String
        public let serial: String
        public var id: String { serial }
        public var model: String? { BambuStatus.model(serial: serial) }
    }

    /// Every address on this Mac's own networks.
    public static func scan() async -> [Found] {
        await scan(hosts: localHosts())
    }

    /// Two passes: a plain connection to every address finds the few with
    /// the port open, quickly; only those get the TLS handshake, which a P1
    /// busy printing can take a couple of seconds to finish.
    static func scan(hosts: [String], concurrency: Int = 128) async -> [Found] {
        let open = await inParallel(hosts, concurrency: concurrency) { await isOpen($0, timeout: 1.5) ? $0 : nil }
        let found = await inParallel(open, concurrency: concurrency) { await probe($0, timeout: 6) }
        return found.sorted { $0.host.compare($1.host, options: .numeric) == .orderedAscending }
    }

    private static func inParallel<T: Sendable>(
        _ hosts: [String], concurrency: Int, _ work: @escaping @Sendable (String) async -> T?
    ) async -> [T] {
        var results: [T] = []
        await withTaskGroup(of: T?.self) { group in
            var pending = hosts[...]
            for _ in 0..<min(concurrency, pending.count) {
                let host = pending.removeFirst()
                group.addTask { await work(host) }
            }
            for await result in group {
                if let result { results.append(result) }
                if let host = pending.popFirst() {
                    group.addTask { await work(host) }
                }
            }
        }
        return results
    }

    /// Whether anything accepts a connection on the MQTT port.
    static func isOpen(_ host: String, timeout: TimeInterval) async -> Bool {
        let queue = DispatchQueue(label: "EdgeControl.Bambu.Discovery")
        let probe = Probe()
        return await withCheckedContinuation { continuation in
            probe.continuation = { continuation.resume(returning: $0 != nil) }
            let connection = NWConnection(host: NWEndpoint.Host(host), port: BambuMQTTSession.port, using: .tcp)
            probe.connection = connection
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: probe.finish(Found(host: host, serial: ""))
                case .waiting, .failed: probe.finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { probe.finish(nil) }
        }
    }

    /// One handshake: a Bambu printer if the certificate says so.
    static func probe(_ host: String, timeout: TimeInterval) async -> Found? {
        let queue = DispatchQueue(label: "EdgeControl.Bambu.Discovery")
        let probe = Probe()
        return await withCheckedContinuation { continuation in
            probe.continuation = { continuation.resume(returning: $0) }
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, trust, complete in
                    let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                    if let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate], let leaf = chain.first {
                        var name: CFString?
                        SecCertificateCopyCommonName(leaf, &name)
                        let issuer = SecCertificateCopyNormalizedIssuerSequence(leaf) as Data?
                        if let serial = name as String?, let issuer, isBambuIssuer(issuer), isSerial(serial) {
                            probe.serial = serial
                        }
                    }
                    // Nothing is sent either way: the handshake is all that's needed.
                    complete(true)
                }, queue)
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = Int(timeout.rounded(.up))
            let connection = NWConnection(
                host: NWEndpoint.Host(host), port: BambuMQTTSession.port, using: NWParameters(tls: tls, tcp: tcp))
            probe.connection = connection
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: probe.finish(probe.serial.map { Found(host: host, serial: $0) })
                case .waiting, .failed: probe.finish(nil)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { probe.finish(nil) }
        }
    }

    /// Resumes its continuation once, whichever of answer, refusal or timeout comes first.
    private final class Probe: @unchecked Sendable {
        var continuation: ((Found?) -> Void)?
        var connection: NWConnection?
        var serial: String?

        func finish(_ result: Found?) {
            guard let continuation else { return }
            self.continuation = nil
            connection?.cancel()
            continuation(result)
        }
    }

    /// The issuer's distinguished name, as DER, names Bambu's authority.
    static func isBambuIssuer(_ issuer: Data) -> Bool {
        issuer.range(of: Data("BBL".utf8)) != nil
    }

    /// Bambu serial numbers are 15 letters and digits.
    static func isSerial(_ text: String) -> Bool {
        text.count == 15 && text.allSatisfy { $0.isASCII && ($0.isNumber || $0.isUppercase) }
    }

    // MARK: - Addresses

    /// The addresses on each of this Mac's IPv4 networks. A network bigger
    /// than 256 addresses is narrowed to the 256 around this Mac, which is
    /// where a home printer is; VPN and link-local interfaces are skipped.
    static func localHosts() -> [String] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }
        var hosts: [String] = []
        var seen = Set<String>()
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, flags & IFF_POINTOPOINT == 0,
                let address = interface.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                let mask = interface.pointee.ifa_netmask
            else { continue }
            let ip = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            for host in Self.hosts(address: ip, mask: netmask) where seen.insert(host).inserted {
                hosts.append(host)
            }
        }
        return hosts
    }

    static func hosts(address: UInt32, mask: UInt32) -> [String] {
        // 169.254.0.0/16 is link-local: no printer set up on a home network.
        guard address >> 16 != 0xA9FE else { return [] }
        let mask = max(mask, 0xFFFF_FF00)
        let network = address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return ((network + 1)..<broadcast).filter { $0 != address }.map(Self.dotted)
    }

    static func dotted(_ address: UInt32) -> String {
        "\(address >> 24).\(address >> 16 & 0xFF).\(address >> 8 & 0xFF).\(address & 0xFF)"
    }
}
