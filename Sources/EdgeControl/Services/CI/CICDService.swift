import Combine
import Foundation

public enum CIAccountState: Equatable, Sendable {
    case idle
    case syncing
    case ok(lastSync: Date)
    case failed(CIError, at: Date)

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Owns the configured accounts' polling, and publishes one merged run list.
///
/// Replaces `GitHubService`, which combined token resolution, discovery, HTTP,
/// model mapping and caching in a single type and failed silently at every one
/// of them.
@MainActor
public final class CICDService: ObservableObject {
    /// Merged, sorted runs from every configured account.
    @Published public private(set) var runs: [CIRun] = []
    /// Health of each account, keyed by account ID. Drives the widget's error
    /// states and the Settings rows.
    @Published public private(set) var accountStates: [UUID: CIAccountState] = [:]
    /// Latest quota each account's host reported, keyed by account ID. Empty
    /// for hosts that do not publish one — Forgejo does not.
    @Published public private(set) var rateLimits: [UUID: CIRateLimit] = [:]

    /// User preferences. Assigning re-persists them and, when discovery is
    /// affected, drops the repository cache so the change takes effect on the
    /// next poll rather than up to an hour later.
    @Published public var settings: CICDSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            if settings.activityWindowDays != oldValue.activityWindowDays
                || settings.pinnedRepositories != oldValue.pinnedRepositories
                || settings.hiddenRepositories != oldValue.hiddenRepositories {
                repositoryCache.removeAll()
            }
        }
    }

    private let accountStore: CIAccountStore
    private let defaults: UserDefaults
    private let transport: CITransport
    private let importer: CredentialImporter

    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private var runsByAccount: [UUID: [CIRun]] = [:]
    private var repositoryCache: [UUID: (repos: [CIRepository], fetched: Date)] = [:]
    private var consecutiveFailures: [UUID: Int] = [:]
    /// Guards against re-importing a rotated token in a tight loop.
    private var reimportAttempted: Set<UUID> = []

    public init(
        accountStore: CIAccountStore,
        // Conditional requests by default: a 304 costs no GitHub quota, and the
        // same URLs are re-fetched every poll. The quota tracker sits outside so
        // it also sees the 304s.
        transport: CITransport = RateLimitTrackingTransport(
            wrapping: ConditionalGETTransport(wrapping: URLSessionTransport())
        ),
        importer: CredentialImporter = CredentialImporter(),
        defaults: UserDefaults = .standard
    ) {
        self.accountStore = accountStore
        self.defaults = defaults
        self.settings = CICDSettings.load(from: defaults)
        self.transport = transport
        self.importer = importer
    }

    // MARK: - Lifecycle

    public func start() {
        stop()
        for account in accountStore.accounts {
            accountStates[account.id] = .idle
            pollTasks[account.id] = Task { [weak self] in
                await self?.pollLoop(account)
            }
        }
        rebuildRuns()
    }

    public func stop() {
        pollTasks.values.forEach { $0.cancel() }
        pollTasks.removeAll()
    }

    // MARK: - Polling

    private func pollLoop(_ account: CIAccount) async {
        while !Task.isCancelled {
            let delay: TimeInterval
            do {
                try await syncOnce(account)
                consecutiveFailures[account.id] = 0
                reimportAttempted.remove(account.id)
                accountStates[account.id] = .ok(lastSync: Date())
                refreshRateLimit(for: account)
                delay = settings.pollInterval
            } catch let error as CIError {
                let failures = (consecutiveFailures[account.id] ?? 0) + 1
                consecutiveFailures[account.id] = failures
                accountStates[account.id] = .failed(error, at: Date())
                delay = Self.backoffDelay(forConsecutiveFailures: failures)
            } catch {
                let failures = (consecutiveFailures[account.id] ?? 0) + 1
                consecutiveFailures[account.id] = failures
                accountStates[account.id] = .failed(.unreachable, at: Date())
                delay = Self.backoffDelay(forConsecutiveFailures: failures)
            }
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func syncOnce(_ account: CIAccount) async throws {
        guard let token = accountStore.token(for: account) else { throw CIError.unauthorized }
        accountStates[account.id] = .syncing

        do {
            try await sync(account, token: token)
        } catch CIError.unauthorized where !reimportAttempted.contains(account.id) {
            // The CLI may have rotated the token since it was imported. Try
            // once, then surface the failure rather than looping.
            reimportAttempted.insert(account.id)
            guard let fresh = importer.discover().first(where: { $0.host == account.host })?.token
            else { throw CIError.unauthorized }
            try accountStore.updateToken(fresh, for: account)
            try await sync(account, token: fresh)
        }
    }

    private func sync(_ account: CIAccount, token: String) async throws {
        let provider = makeProvider(account, token: token)
        let repos = try await repositories(for: account, provider: provider)

        var collected: [CIRun] = []
        // Bounded concurrency: a user with 30 repositories should not open 30
        // sockets at once, but strictly sequential fetching is needlessly slow.
        for chunk in repos.chunked(into: 4) {
            let chunkRuns = try await withThrowingTaskGroup(of: [CIRun].self) { group in
                for repo in chunk {
                    group.addTask {
                        do {
                            return try await provider.fetchRuns(repository: repo, limit: 3)
                        } catch let error as CIError where Self.isPerRepository(error) {
                            // A repository with Actions disabled 404s on this
                            // endpoint. That is a fact about one repository, not
                            // a fault of the account — letting it throw would
                            // blind the whole host.
                            AppLog.cicd.debug(
                                "skipping \(repo.fullName, privacy: .public): \(String(describing: error), privacy: .public)"
                            )
                            return []
                        }
                    }
                }
                var acc: [CIRun] = []
                for try await runs in group { acc.append(contentsOf: runs) }
                return acc
            }
            collected.append(contentsOf: chunkRuns)
        }
        runsByAccount[account.id] = collected
        rebuildRuns()
    }

    private func repositories(
        for account: CIAccount,
        provider: CIProvider
    ) async throws -> [CIRepository] {
        if let cached = repositoryCache[account.id],
           Date().timeIntervalSince(cached.fetched) < 3600 {
            return cached.repos
        }
        let cutoff = Date().addingTimeInterval(-Double(settings.activityWindowDays) * 86_400)
        var discovered = try await provider.discoverRepositories(activeSince: cutoff)

        // Only this account's entries apply; a pin for another host must not
        // leak in here.
        let hiddenHere = Set(
            settings.hiddenRepositories.filter { $0.host == account.host }.map(\.fullName)
        )
        let pinnedHere = settings.pinnedRepositories
            .filter { $0.host == account.host }
            .map(\.fullName)
        discovered.removeAll { hiddenHere.contains($0.fullName) }

        // Keep only repositories that actually have runs. Without this the poll
        // loop re-queries every repository whose host has Actions disabled —
        // 13 of 38 on one real Forgejo instance — every 30 seconds, forever.
        // The probe costs one request per candidate but runs hourly, against a
        // full fetch per candidate per poll.
        var active: [CIRepository] = []
        for chunk in discovered.chunked(into: 4) {
            let kept = await withTaskGroup(of: CIRepository?.self) { group in
                for repo in chunk {
                    group.addTask {
                        let runs = try? await provider.fetchRuns(repository: repo, limit: 1)
                        return (runs?.isEmpty == false) ? repo : nil
                    }
                }
                var acc: [CIRepository] = []
                for await repo in group { if let repo { acc.append(repo) } }
                return acc
            }
            active.append(contentsOf: kept)
        }

        // Pinned repositories bypass both the activity window and the probe, so
        // a repository the user is watching shows its first run on the next
        // poll rather than after the next hourly discovery.
        for pinned in pinnedHere
        where !active.contains(where: { $0.fullName == pinned })
            && !hiddenHere.contains(pinned) {
            let short = pinned.split(separator: "/").last.map(String.init) ?? pinned
            active.append(
                CIRepository(fullName: pinned, shortName: short, lastActivity: .distantPast)
            )
        }

        // notice, not debug: one line per account per hour, and the only
        // record of how many repositories the poll loop is actually working on.
        AppLog.cicd.notice(
            "\(account.host, privacy: .public): \(discovered.count) candidates -> \(active.count) with runs"
        )
        repositoryCache[account.id] = (active, Date())
        return active
    }

    private func makeProvider(_ account: CIAccount, token: String) -> CIProvider {
        switch account.kind {
        case .github:
            return GitHubProvider(
                accountID: account.id,
                hostLabel: account.host,
                apiBaseURL: account.apiBaseURL,
                token: token,
                transport: transport
            )
        case .forgejo:
            return ForgejoProvider(
                accountID: account.id,
                hostLabel: account.host,
                apiBaseURL: account.apiBaseURL,
                token: token,
                transport: transport
            )
        }
    }

    /// Copies the tracker's latest reading for this account's API host.
    private func refreshRateLimit(for account: CIAccount) {
        guard let tracker = transport as? RateLimitTrackingTransport,
              let host = account.apiBaseURL.host else { return }
        if let limit = tracker.rateLimit(forHost: host) {
            rateLimits[account.id] = limit
        }
    }

    private func rebuildRuns() {
        runs = Self.merge(Array(runsByAccount.values))
    }

    // MARK: - Pure helpers

    // `nonisolated`: these touch no state, and callers (including tests and the
    // widget bridge) should not have to hop to the main actor to use them.

    /// Active runs first, then newest first. Capped so the list stays bounded
    /// no matter how many accounts are configured.
    public nonisolated static func merge(_ groups: [[CIRun]]) -> [CIRun] {
        groups
            .flatMap { $0 }
            .sorted { a, b in
                if a.state.isActive != b.state.isActive { return a.state.isActive }
                return a.startedAt > b.startedAt
            }
            .prefix(50)
            .map { $0 }
    }

    /// Whether an error describes one repository rather than the account.
    ///
    /// Only 404 qualifies: the endpoint does not exist for that repository,
    /// which is what a host returns when Actions is disabled there. Everything
    /// else — a dead token, an exhausted quota, an unreachable host — applies
    /// to every repository and must surface as an account failure.
    public nonisolated static func isPerRepository(_ error: CIError) -> Bool {
        if case .httpStatus(404) = error { return true }
        return false
    }

    public nonisolated static func backoffDelay(forConsecutiveFailures failures: Int) -> TimeInterval {
        let schedule: [TimeInterval] = [30, 60, 120, 300, 900]
        guard failures > 0 else { return schedule[0] }
        return schedule[min(failures - 1, schedule.count - 1)]
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
