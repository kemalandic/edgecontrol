import AppKit
import Foundation

/// Keeps the deliveries from a Parcel account current.
///
/// Parcel's API is part of Parcel Premium: a key from web.parcelapp.net,
/// kept in the Keychain and shared by every Parcel widget, reads the same
/// deliveries the app shows. Parcel allows 20 requests an hour per key and
/// answers from what its servers already have, so asking more often gains
/// nothing. Each list a widget shows ("active" or "recent") is asked for
/// every five minutes, every ten when both are on screen, which keeps the
/// total at twelve an hour. Nothing is asked while the displays sleep.
@MainActor
public final class ParcelService: ObservableObject {
    /// Parcel's two lists: what's on its way, and its recent list, which
    /// also has deliveries that have just arrived.
    public enum Filter: String, CaseIterable, Sendable {
        case active
        case recent
    }

    public enum Problem: Equatable, Sendable {
        case needsKey
        /// Parcel refused the key, in its own words when it gave any.
        case keyRefused(String?)
        case rateLimited(until: Date)
        case unreachable
        case failed(String)
    }

    public struct List: Equatable, Sendable {
        public var deliveries: [ParcelDelivery]
        public var updated: Date
    }

    @Published public private(set) var lists: [Filter: List] = [:]
    @Published public private(set) var problem: Problem?
    /// Carrier names by Parcel's code: "ups" is "UPS".
    @Published public private(set) var carriers: [String: String] = [:]
    @Published public private(set) var hasKey = false

    static let base = URL(string: "https://api.parcel.app/external/")!
    static let interval: TimeInterval = 5 * 60
    static let defaultBackoff: TimeInterval = 15 * 60
    static let keyAccount = "api-key"

    private let transport: CITransport
    private let secrets: CISecretStore
    private let clock: @MainActor () -> Date
    private var watchCounts: [Filter: Int] = [:]
    private var lastAsked: [Filter: Date] = [:]
    private var inFlight: Set<Filter> = []
    private var waitUntil: Date?
    private var screensAwake = true
    private var carriersAsked: Date?
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    public convenience init() {
        self.init(
            transport: URLSessionTransport(), secrets: KeychainSecretStore(service: "ai.pakslab.edgecontrol.parcel"),
            clock: { Date() })
    }

    init(transport: CITransport, secrets: CISecretStore, clock: @escaping @MainActor () -> Date) {
        self.transport = transport
        self.secrets = secrets
        self.clock = clock
        hasKey = secrets.read(Self.keyAccount) != nil
        if !hasKey { problem = .needsKey }
    }

    // MARK: - Lifecycle

    public func start() {
        guard loop == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.screensAwake = false }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screensAwake = true
                    self?.poke()
                }
            },
        ]
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    // MARK: - Watching

    /// A widget showing `filter` is on screen.
    public func watch(_ filter: Filter) {
        watchCounts[filter, default: 0] += 1
        if watchCounts[filter] == 1 { poke() }
    }

    public func unwatch(_ filter: Filter) {
        guard let count = watchCounts[filter] else { return }
        watchCounts[filter] = count > 1 ? count - 1 : nil
    }

    /// How long each watched list waits between asks: five minutes for one
    /// list, ten for two, so a key never comes near Parcel's limit.
    var spacing: TimeInterval { Self.interval * Double(max(1, watchCounts.count)) }

    // MARK: - The key

    public func setKey(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        try secrets.write(key, for: Self.keyAccount)
        hasKey = true
        problem = nil
        // Parcel's limit is per key, so a new key starts afresh.
        lastAsked.removeAll()
        lists.removeAll()
        waitUntil = nil
        if loop != nil, watchCounts.isEmpty {
            // No widget on screen yet: one ask still tells the settings
            // whether the key works.
            Task { [weak self] in await self?.fetch(.active) }
        } else {
            poke()
        }
    }

    public func removeKey() {
        secrets.delete(Self.keyAccount)
        hasKey = false
        lists.removeAll()
        lastAsked.removeAll()
        problem = .needsKey
    }

    // MARK: - Asking Parcel

    /// Asks now rather than at the next half-minute, while running.
    private func poke() {
        guard loop != nil else { return }
        Task { [weak self] in await self?.tick() }
    }

    /// Asks for each watched list that's due, the carrier names once, and
    /// nothing while the screens sleep or Parcel has asked for a pause.
    func tick() async {
        let now = clock()
        guard screensAwake, hasKey else { return }
        if let waitUntil, now < waitUntil { return }
        waitUntil = nil
        if carriers.isEmpty, carriersAsked.map({ now.timeIntervalSince($0) > 3600 }) ?? true {
            carriersAsked = now
            await fetchCarriers()
        }
        for filter in Filter.allCases where watchCounts[filter] != nil && !inFlight.contains(filter) {
            if let last = lastAsked[filter], now.timeIntervalSince(last) < spacing { continue }
            await fetch(filter)
            if waitUntil != nil || problem.map(Self.stopsAsking) == true { return }
        }
    }

    private static func stopsAsking(_ problem: Problem) -> Bool {
        switch problem {
        case .needsKey, .keyRefused, .rateLimited: return true
        case .unreachable, .failed: return false
        }
    }

    func fetch(_ filter: Filter) async {
        guard let key = secrets.read(Self.keyAccount) else {
            problem = .needsKey
            return
        }
        inFlight.insert(filter)
        defer { inFlight.remove(filter) }
        lastAsked[filter] = clock()
        let url = Self.base.appending(path: "deliveries/").appending(queryItems: [
            URLQueryItem(name: "filter_mode", value: filter.rawValue)
        ])
        do {
            let (data, response) = try await transport.get(
                url, headers: ["api-key": key, "Accept": "application/json"])
            let now = clock()
            switch response.statusCode {
            case 200..<300:
                let reply = try ParcelAPI.decodeDeliveries(data, now: now)
                if reply.success {
                    lists[filter] = List(deliveries: reply.deliveries, updated: now)
                    problem = nil
                } else {
                    problem = .failed(reply.errorMessage ?? "Parcel refused the request")
                }
            case 401, 403:
                problem = .keyRefused(ParcelAPI.errorMessage(data))
            case 429:
                let until = now.addingTimeInterval(Self.retryAfter(response) ?? Self.defaultBackoff)
                waitUntil = until
                problem = .rateLimited(until: until)
            default:
                problem = .failed(ParcelAPI.errorMessage(data) ?? "Error \(response.statusCode)")
            }
        } catch is ParcelAPI.DecodingError {
            problem = .failed("Unexpected reply")
        } catch {
            problem = .unreachable
        }
    }

    /// `Retry-After` in seconds, kept between a minute and a day.
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
            let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces))
        else { return nil }
        return min(max(seconds, 60), 86_400)
    }

    private func fetchCarriers() async {
        let url = Self.base.appending(path: "supported_carriers.json")
        guard let (data, response) = try? await transport.get(url, headers: [:]),
            (200..<300).contains(response.statusCode)
        else { return }
        carriers = ParcelAPI.decodeCarriers(data)
    }

    // MARK: - For widgets

    /// The deliveries a widget shows, the ones that need doing something
    /// about or are nearest first.
    public func deliveries(_ filter: Filter) -> [ParcelDelivery]? {
        lists[filter]?.deliveries.sorted(by: Self.precedes)
    }

    public func carrierName(_ code: String) -> String {
        carriers[code] ?? code.uppercased()
    }

    static func precedes(_ a: ParcelDelivery, _ b: ParcelDelivery) -> Bool {
        let (rankA, rankB) = (rank(a.status), rank(b.status))
        if rankA != rankB { return rankA < rankB }
        switch (a.expected?.start, b.expected?.start) {
        case (let x?, let y?) where x != y: return x < y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    /// Out for delivery and waiting to be collected come first; then what
    /// needs attention; then the rest by how far along it is.
    private static func rank(_ status: ParcelDelivery.Status) -> Int {
        switch status {
        case .outForDelivery: 0
        case .awaitingPickup: 1
        case .failedAttempt: 2
        case .exception: 3
        case .inTransit: 4
        case .infoReceived: 5
        case .notFound: 6
        case .frozen: 7
        case .unknown: 8
        case .delivered: 9
        }
    }
}
