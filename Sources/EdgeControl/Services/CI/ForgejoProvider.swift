import Foundation

/// Forgejo and Gitea share the `/api/v1` surface, so this provider serves both.
///
/// The payload is not GitHub-shaped: outcome lives in a single `status`, the
/// commit title is `title`, the branch is `prettyref`, and the workflow is
/// identified by filename rather than display name.
public struct ForgejoProvider: CIProvider {
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
        let index_in_repo: Int?
        let workflow_id: String?
        let title: String?
        let status: String
        let prettyref: String?
        let created: String?
        let started: String?
        let html_url: String
    }

    private struct WireUser: Decodable {
        let login: String
        let full_name: String?
    }

    private struct WireRepo: Decodable {
        let full_name: String
        let name: String
        let updated_at: String?
        /// Optional so an older Gitea/Forgejo that omits the field still
        /// decodes; absent reads as "not archived".
        let archived: Bool?
    }

    // MARK: - Request helper

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await transport.get(url, headers: [
            "Authorization": "token \(token)",
            "Accept": "application/json",
        ])
        if let error = CIError.from(response: response) { throw error }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CIError.decoding("Forgejo \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    // MARK: - CIProvider

    public func validate() async throws -> CIIdentity {
        let user = try await decode(WireUser.self, from: apiBaseURL.appendingPathComponent("user"))
        return CIIdentity(login: user.login, displayName: user.full_name)
    }

    /// One call: Forgejo's `/user/repos` already includes the organisation
    /// repositories the account can see, so no per-org fan-out is needed.
    public func discoverRepositories(activeSince: Date) async throws -> [CIRepository] {
        let url = apiBaseURL
            .appendingPathComponent("user/repos")
            .appending(queryItems: [
                URLQueryItem(name: "order_by", value: "recentupdate"),
                URLQueryItem(name: "limit", value: "50"),
            ])
        let formatter = ISO8601DateFormatter()
        return try await decode([WireRepo].self, from: url).compactMap { repo in
            // An archived repository cannot run anything again, and archiving
            // leaves updated_at where it was, so it would otherwise sit in the
            // window and fill the widget with finished history.
            guard repo.archived != true else { return nil }
            guard let raw = repo.updated_at,
                  let updated = formatter.date(from: raw),
                  updated >= activeSince else { return nil }
            return CIRepository(
                fullName: repo.full_name, shortName: repo.name, lastActivity: updated
            )
        }
    }

    public func fetchRuns(repository: CIRepository, limit: Int) async throws -> [CIRun] {
        let url = apiBaseURL
            .appendingPathComponent("repos/\(repository.fullName)/actions/runs")
            .appending(queryItems: [URLQueryItem(name: "limit", value: String(limit))])

        let envelope = try await decode(RunsEnvelope.self, from: url)
        let formatter = ISO8601DateFormatter()

        return envelope.workflow_runs.compactMap { wire in
            guard let url = URL(string: wire.html_url) else { return nil }
            // `id` is an internal database key; `index_in_repo` is the number the
            // web UI and html_url use.
            let visibleID = wire.index_in_repo ?? wire.id
            return CIRun(
                id: "\(accountID.uuidString)/\(repository.fullName)/\(visibleID)",
                accountID: accountID,
                hostLabel: hostLabel,
                repositoryName: repository.shortName,
                workflowName: wire.workflow_id ?? "workflow",
                title: wire.title ?? "",
                branch: wire.prettyref ?? "",
                state: Self.state(wire.status),
                startedAt: Self.startDate(
                    started: wire.started, created: wire.created, formatter: formatter
                ),
                url: url
            )
        }
    }

    /// Forgejo carries the whole outcome in one field. Values come from the
    /// API's own `status` enum.
    static func state(_ status: String) -> CIRunState {
        switch status {
        case "success":            return .success
        case "failure":            return .failure
        case "cancelled":          return .cancelled
        case "running":            return .running
        case "waiting", "blocked": return .queued
        case "skipped":            return .skipped
        default:                   return .unknown
        }
    }

    /// A run that has not started carries a zero date (year 0001). Fall back to
    /// `created` so queued runs sort near the top rather than the bottom.
    static func startDate(
        started: String?,
        created: String?,
        formatter: ISO8601DateFormatter
    ) -> Date {
        if let started,
           let date = formatter.date(from: started),
           date.timeIntervalSince1970 > 0 {
            return date
        }
        if let created, let date = formatter.date(from: created) {
            return date
        }
        return .distantPast
    }
}
