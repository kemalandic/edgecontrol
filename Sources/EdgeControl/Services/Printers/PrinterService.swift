import Foundation
@preconcurrency import Network

/// Where one printer answers IPP, found over Bonjour.
public struct PrinterEndpoint: Equatable, Hashable, Sendable {
    public var host: String
    public var port: Int
    /// The `rp` TXT key: the IPP resource path, usually "ipp/print".
    public var resourcePath: String
    /// TLS: the printer advertised IPPS, or refused plain IPP with HTTP 426.
    public var secure: Bool

    public init(host: String, port: Int, resourcePath: String, secure: Bool) {
        self.host = host
        self.port = port
        self.resourcePath = resourcePath
        self.secure = secure
    }

    private var authority: String { (host.contains(":") ? "[\(host)]" : host) + ":\(port)" }
    var url: URL? { URL(string: "\(secure ? "https" : "http")://\(authority)/\(resourcePath)") }
    var printerURI: String { "\(secure ? "ipps" : "ipp")://\(authority)/\(resourcePath)" }
}

/// Injection point for IPP's HTTP POSTs, so tests run without a printer.
public protocol PrinterTransport: Sendable {
    func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionPrinterTransport: PrinterTransport {
    /// Printers are on the LAN: ten seconds without an answer means it's off.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: PrinterTrust(), delegateQueue: nil)
    }()

    public init() {}

    public func post(_ url: URL, body: Data) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/ipp", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CIError.decoding("non-HTTP response") }
        return (data, http)
    }
}

/// Printers serve IPPS with a certificate they made themselves; no certificate
/// authority has heard of "HP115A08.local". Accepting it is what macOS's own
/// printing does. Nothing secret is sent, only a request for status.
private final class PrinterTrust: NSObject, URLSessionDelegate, Sendable {
    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

/// Finds the printers on the network and keeps their status current.
///
/// Printers announce themselves over Bonjour as `_ipp._tcp` and, when they
/// speak TLS, `_ipps._tcp`, which is how macOS's print dialog finds them too.
/// Each one is asked for its status every 30 seconds, every 5 while one is
/// printing so the widget can follow a job.
@MainActor
public final class PrinterService: ObservableObject {
    public struct Printer: Identifiable, Equatable, Sendable {
        /// The Bonjour service name: stable across addresses and restarts.
        public let id: String
        public var endpoint: PrinterEndpoint?
        public var status: PrinterStatus?
        public var problem: String?

        public var name: String { status?.name ?? PrinterStatus.displayName(id) }
    }

    @Published public private(set) var printers: [Printer] = []
    /// True for the first few seconds of browsing, before an empty network
    /// can be told apart from a slow one.
    @Published public private(set) var searching = false

    private let transport: PrinterTransport
    private var browsers: [NWBrowser] = []
    private var pollTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var resolving: Set<String> = []
    /// Services seen per Bonjour type, so one printer advertising both IPP and
    /// IPPS is one printer.
    private var advertised: [String: Advertisement] = [:]

    private struct Advertisement {
        let secure: Bool
        let resourcePath: String
        let endpoint: NWEndpoint
    }

    static let interval: Duration = .seconds(30)
    static let printingInterval: Duration = .seconds(5)
    static let searchWindow: Duration = .seconds(8)

    public init(transport: PrinterTransport = URLSessionPrinterTransport()) {
        self.transport = transport
    }

    public func start() {
        guard browsers.isEmpty else { return }
        for (type, secure) in [("_ipps._tcp", true), ("_ipp._tcp", false)] {
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: NWParameters())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                MainActor.assumeIsolated { self?.found(results, secure: secure) }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: Self.searchWindow)
            if !Task.isCancelled { self?.searching = false }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshAll()
                let busy = self.printers.contains { $0.status?.state == .printing }
                try? await Task.sleep(for: busy ? Self.printingInterval : Self.interval)
            }
        }
    }

    public func stop() {
        browsers.forEach { $0.cancel() }
        browsers.removeAll()
        pollTask?.cancel()
        pollTask = nil
        searchTask?.cancel()
        searchTask = nil
        searching = false
    }

    // MARK: - Discovery

    private func found(_ results: Set<NWBrowser.Result>, secure: Bool) {
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            var path = "ipp/print"
            if case .bonjour(let txt) = result.metadata, let rp = txt["rp"], !rp.isEmpty { path = rp }
            // IPPS wins when a printer offers both.
            if let known = advertised[name], known.secure, !secure { continue }
            advertised[name] = Advertisement(secure: secure, resourcePath: path, endpoint: result.endpoint)
            if !printers.contains(where: { $0.id == name }) {
                printers.append(Printer(id: name))
                printers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
            resolve(name)
        }
    }

    /// Bonjour gives a service name; IPP needs an address. A connection to the
    /// service resolves it, and is dropped as soon as it has.
    private func resolve(_ name: String) {
        guard let service = advertised[name], !resolving.contains(name) else { return }
        resolving.insert(name)
        let parameters = NWParameters.tcp
        // An IPv4 address keeps the URL free of IPv6 scope IDs.
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: service.endpoint, using: parameters)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    if case .hostPort(let host, let port)? = connection.currentPath?.remoteEndpoint {
                        self?.resolved(name, host: Self.address(host), port: Int(port.rawValue), service: service)
                    }
                    connection.cancel()
                case .failed, .waiting:
                    connection.cancel()
                case .cancelled:
                    self?.resolving.remove(name)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func resolved(_ name: String, host: String, port: Int, service: Advertisement) {
        guard let index = printers.firstIndex(where: { $0.id == name }) else { return }
        let endpoint = PrinterEndpoint(
            host: host, port: port, resourcePath: service.resourcePath, secure: service.secure)
        guard printers[index].endpoint != endpoint else { return }
        printers[index].endpoint = endpoint
        Task { await refresh(name) }
    }

    /// The address as a URL can carry it. Network.framework writes the
    /// interface after a resolved address, IPv4 included ("192.168.1.20%en0"),
    /// and a "%" there makes the URL invalid.
    static func address(_ host: NWEndpoint.Host) -> String {
        let text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): return name
        @unknown default: text = "\(host)"
        }
        return text.components(separatedBy: "%")[0]
    }

    // MARK: - Status

    /// Adds a printer without Bonjour; tests use it, and nothing else needs to.
    func add(id: String, endpoint: PrinterEndpoint) {
        printers.removeAll { $0.id == id }
        printers.append(Printer(id: id, endpoint: endpoint))
    }

    public func refreshAll() async {
        for printer in printers { await refresh(printer.id) }
    }

    public func refresh(_ id: String) async {
        guard let endpoint = printers.first(where: { $0.id == id })?.endpoint else { return }
        let outcome = await fetch(endpoint, name: id)
        guard let index = printers.firstIndex(where: { $0.id == id }) else { return }
        switch outcome {
        case .success(let status, let usedEndpoint):
            printers[index].status = status
            printers[index].endpoint = usedEndpoint
            printers[index].problem = nil
        case .failure(let problem):
            // Keep the last status: ink doesn't vanish because a printer slept.
            printers[index].problem = problem
        }
    }

    enum Outcome: Equatable {
        case success(PrinterStatus, PrinterEndpoint)
        case failure(String)
    }

    func fetch(_ endpoint: PrinterEndpoint, name: String) async -> Outcome {
        do {
            guard let url = endpoint.url else { return .failure("Bad address") }
            let request = IPP.getPrinterAttributes(printerURI: endpoint.printerURI)
            let (data, response) = try await transport.post(url, body: request)
            // "Upgrade Required": this printer only does IPP over TLS.
            if response.statusCode == 426, !endpoint.secure {
                var secure = endpoint
                secure.secure = true
                return await fetch(secure, name: name)
            }
            guard (200..<300).contains(response.statusCode) else { return .failure("Error \(response.statusCode)") }
            let reply = try IPP.parse(data)
            guard reply.succeeded else { return .failure("Refused the request") }
            return .success(PrinterStatus(reply, fallbackName: name), endpoint)
        } catch is IPP.DecodingError {
            return .failure("Unexpected reply")
        } catch {
            return .failure("Not responding")
        }
    }
}
