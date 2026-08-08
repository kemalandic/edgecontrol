import Foundation

public struct GitHubProvider: CIProvider {
    private let accountID: UUID
    private let hostLabel: String
    private let apiBaseURL: URL
    private let token: String
    private let transport: CITransport

    public init(
        accountID: UUID,
        hostLabel: String,
        apiBaseURL: URL,
        token: String,
        transport: CITransport
    ) {
        self.accountID = accountID
        self.hostLabel = hostLabel
        self.apiBaseURL = apiBaseURL
        self.token = token
        self.transport = transport
    }

    // MARK: - Wire types

    private struct RunsEnvelope: Decodable {
        let workflow_runs: [WireRun]
    }

    private struct WireRun: Decodable {
        let id: Int
        let name: String?
        let display_title: String?
        let status: String
        let conclusion: String?
        let head_branch: String?
        let run_started_at: String?
        let html_url: String
    }

    private struct WireUser: Decodable {
        let login: String
        let name: String?
    }

    private struct WireOrg: Decodable {
        let login: String
    }

    private struct WireRepo: Decodable {
        let full_name: String
        let name: String
        let pushed_at: String?
        /// Optional so a host that omits the field still decodes; absent reads
        /// as "not archived", which is the safe direction — a repository is
        /// only ever hidden on a positive signal.
        let archived: Bool?
    }

    // MARK: - Request helper

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await transport.get(url, headers: [
            "Authorization": "Bearer \(token)",
            "Accept": "application/vnd.github+json",
        ])
        if let error = CIError.from(response: response) { throw error }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CIError.decoding("GitHub \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - CIProvider

    public func validate() async throws -> CIIdentity {
        let user = try await decode(WireUser.self, from: apiBaseURL.appendingPathComponent("user"))
        return CIIdentity(login: user.login, displayName: user.name)
    }

    public func discoverRepositories(activeSince: Date) async throws -> [CIRepository] {
        let formatter = ISO8601DateFormatter()
        var seen = Set<String>()
        var result: [CIRepository] = []

        func absorb(_ repos: [WireRepo]) {
            for repo in repos {
                guard !seen.contains(repo.full_name) else { continue }
                // Archiving does not move pushed_at, so an archived repository
                // keeps sorting near the top and passes the activity window for
                // as long as its last push is recent. It can never produce
                // another run, so it is dropped here rather than filling the
                // widget with history.
                guard repo.archived != true else { continue }
                guard let raw = repo.pushed_at,
                      let pushed = formatter.date(from: raw),
                      pushed >= activeSince else { continue }
                seen.insert(repo.full_name)
                result.append(CIRepository(
                    fullName: repo.full_name, shortName: repo.name, lastActivity: pushed
                ))
            }
        }

        let userRepos = apiBaseURL
            .appendingPathComponent("user/repos")
            .appending(queryItems: [
                URLQueryItem(name: "sort", value: "pushed"),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "type", value: "all"),
            ])
        absorb(try await decode([WireRepo].self, from: userRepos))

        // Organisation repositories are not returned by /user/repos, so each org
        // is queried separately.
        let orgs = try await decode(
            [WireOrg].self,
            from: apiBaseURL.appendingPathComponent("user/orgs")
                .appending(queryItems: [URLQueryItem(name: "per_page", value: "100")])
        )
        for org in orgs {
            let url = apiBaseURL
                .appendingPathComponent("orgs/\(org.login)/repos")
                .appending(queryItems: [
                    URLQueryItem(name: "sort", value: "pushed"),
                    URLQueryItem(name: "per_page", value: "100"),
                ])
            absorb(try await decode([WireRepo].self, from: url))
        }

        return result
    }

    public func fetchRuns(repository: CIRepository, limit: Int) async throws -> [CIRun] {
        let url = apiBaseURL
            .appendingPathComponent("repos/\(repository.fullName)/actions/runs")
            .appending(queryItems: [URLQueryItem(name: "per_page", value: String(limit))])

        let envelope = try await decode(RunsEnvelope.self, from: url)
        let formatter = ISO8601DateFormatter()

        return envelope.workflow_runs.compactMap { wire in
            guard let url = URL(string: wire.html_url) else { return nil }
            return CIRun(
                id: "\(accountID.uuidString)/\(repository.fullName)/\(wire.id)",
                accountID: accountID,
                hostLabel: hostLabel,
                repositoryName: repository.shortName,
                workflowName: wire.name ?? "workflow",
                title: wire.display_title ?? "",
                branch: wire.head_branch ?? "",
                state: Self.state(status: wire.status, conclusion: wire.conclusion),
                startedAt: wire.run_started_at.flatMap(formatter.date(from:)) ?? .distantPast,
                url: url
            )
        }
    }

    /// GitHub carries outcome in two fields: `status` until the run finishes,
    /// then `conclusion`.
    static func state(status: String, conclusion: String?) -> CIRunState {
        switch status {
        case "queued", "waiting", "pending", "requested":
            return .queued
        case "in_progress":
            return .running
        default:
            break
        }
        switch conclusion {
        case "success":              return .success
        case "failure", "timed_out": return .failure
        case "cancelled":            return .cancelled
        case "skipped", "neutral":   return .skipped
        default:                     return .unknown
        }
    }
}
