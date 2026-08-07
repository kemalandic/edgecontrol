import Foundation

/// User-controlled CI/CD preferences, persisted to UserDefaults.
///
/// These used to be plain `var`s on `CICDService`, so the Settings pickers
/// appeared to work but reset on every launch. Keeping them in one Codable
/// value means adding a preference cannot silently forget to persist it.
/// A repository on a specific host.
///
/// Host-qualified because `owner/name` alone is ambiguous once more than one
/// account is configured: an unqualified pin was applied to *every* account,
/// so a Forgejo repository ended up being polled against github.com too.
public struct CIRepositoryRef: Hashable, Codable, Sendable, Comparable {
    /// Matches `CIAccount.host`, e.g. `git.example.dev`.
    public let host: String
    /// `owner/name`.
    public let fullName: String

    public init(host: String, fullName: String) {
        self.host = host
        self.fullName = fullName
    }

    public var displayName: String { "\(host) · \(fullName)" }

    public static func < (a: CIRepositoryRef, b: CIRepositoryRef) -> Bool {
        (a.host, a.fullName) < (b.host, b.fullName)
    }
}

public struct CICDSettings: Codable, Equatable, Sendable {
    /// The *healthy* poll interval. Accounts in backoff use their backoff delay.
    public var pollInterval: TimeInterval
    /// Repositories with activity inside this window are discovered.
    public var activityWindowDays: Int
    /// Always shown, whatever the activity window says.
    public var pinnedRepositories: Set<CIRepositoryRef>
    /// Never shown, and never polled.
    public var hiddenRepositories: Set<CIRepositoryRef>

    public static let `default` = CICDSettings(
        pollInterval: 30,
        activityWindowDays: 14,
        pinnedRepositories: [],
        hiddenRepositories: []
    )

    public init(
        pollInterval: TimeInterval = 30,
        activityWindowDays: Int = 14,
        pinnedRepositories: Set<CIRepositoryRef> = [],
        hiddenRepositories: Set<CIRepositoryRef> = []
    ) {
        self.pollInterval = pollInterval
        self.activityWindowDays = activityWindowDays
        self.pinnedRepositories = pinnedRepositories
        self.hiddenRepositories = hiddenRepositories
    }

    /// Decodes leniently: the repository lists were once unqualified strings,
    /// and an unreadable list must not take the interval and window down with
    /// it. Unreadable entries are dropped, not defaulted around.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? 30
        activityWindowDays = try c.decodeIfPresent(Int.self, forKey: .activityWindowDays) ?? 14
        pinnedRepositories =
            (try? c.decode(Set<CIRepositoryRef>.self, forKey: .pinnedRepositories)) ?? []
        hiddenRepositories =
            (try? c.decode(Set<CIRepositoryRef>.self, forKey: .hiddenRepositories)) ?? []
    }
}

extension CICDSettings {
    static let defaultsKey = "cicd.settings"

    /// Falls back to defaults when nothing is stored or the stored value is
    /// unreadable — a corrupt preference should not leave the widget unusable.
    public static func load(from defaults: UserDefaults = .standard) -> CICDSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(CICDSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    public func save(to defaults: UserDefaults = .standard) {
        do {
            defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
        } catch {
            AppLog.cicd.error(
                "encoding CI settings failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
