import Foundation

public struct WorkflowRun: Identifiable, Equatable, Sendable {
    public let id: Int
    public let repoName: String
    public let workflowName: String
    public let displayTitle: String
    public let status: String      // "completed", "in_progress", "queued"
    public let conclusion: String?  // "success", "failure", "cancelled", nil
    public let branch: String
    public let startedAt: String
    public let url: String
}

@MainActor
public final class GitHubService: ObservableObject {
    @Published public var runs: [WorkflowRun] = []

    private var runTimer: Timer?
    private var repoTimer: Timer?
    private var activeRepos: [String] = []
    private var token: String?

    nonisolated private static let cacheURL: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("EdgeControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("active_repos.json")
    }()

    public init() {}

    public func start() {
        stop()
        token = Self.resolveToken()
        guard token != nil else { return }

        let cached = Self.loadCache()
        if !cached.repos.isEmpty {
            activeRepos = cached.repos
            fetchRuns()
        }
        if cached.repos.isEmpty || cached.isStale {
            refreshRepos()
        }
        startRunTimer()
        repoTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRepos()
            }
        }
    }

    public func stop() {
        runTimer?.invalidate()
        runTimer = nil
        repoTimer?.invalidate()
        repoTimer = nil
    }

    private func startRunTimer() {
        runTimer?.invalidate()
        runTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchRuns()
            }
        }
    }

    private func refreshRepos() {
        guard let token else { return }
        let tok = token
        Task.detached {
            let repos = await Self.discoverActiveRepos(token: tok)
            Self.saveCache(repos: repos)
            await MainActor.run {
                self.activeRepos = repos
                self.fetchRuns()
            }
        }
    }

    private func fetchRuns() {
        let repos = activeRepos
        guard let token, !repos.isEmpty else { return }
        let tok = token
        Task.detached {
            var allRuns: [WorkflowRun] = []
            for repo in repos {
                let repoRuns = await Self.fetchWorkflowRuns(repo: repo, token: tok)
                allRuns.append(contentsOf: repoRuns)
            }
            allRuns.sort { a, b in
                if a.status == "in_progress" && b.status != "in_progress" { return true }
                if a.status != "in_progress" && b.status == "in_progress" { return false }
                return a.startedAt > b.startedAt
            }
            let sorted = allRuns
            await MainActor.run {
                self.runs = sorted
            }
        }
    }

    // MARK: - GitHub API

    private static func apiGet(path: String, token: String) async -> Data? {
        guard let url = URL(string: "https://api.github.com\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        return try? await URLSession.shared.data(for: request).0
    }

    private static func discoverActiveRepos(token: String) async -> [String] {
        // Get username
        guard let userData = await apiGet(path: "/user", token: token),
              let userJSON = try? JSONSerialization.jsonObject(with: userData) as? [String: Any],
              let username = userJSON["login"] as? String else { return [] }

        // Get orgs
        var orgs: [String] = []
        if let orgData = await apiGet(path: "/user/orgs?per_page=100", token: token),
           let orgJSON = try? JSONSerialization.jsonObject(with: orgData) as? [[String: Any]] {
            orgs = orgJSON.compactMap { $0["login"] as? String }
        }

        // Fetch recently pushed repos from user + orgs
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86400))
        var candidateRepos: [String] = []

        // User repos
        if let data = await apiGet(path: "/user/repos?sort=pushed&per_page=30&type=all", token: token),
           let repos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for repo in repos {
                guard let name = repo["full_name"] as? String,
                      let pushed = repo["pushed_at"] as? String,
                      pushed > since else { continue }
                candidateRepos.append(name)
            }
        }

        // Org repos
        for org in orgs {
            if let data = await apiGet(path: "/orgs/\(org)/repos?sort=pushed&per_page=30&type=all", token: token),
               let repos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for repo in repos {
                    guard let name = repo["full_name"] as? String,
                          let pushed = repo["pushed_at"] as? String,
                          pushed > since else { continue }
                    if !candidateRepos.contains(name) {
                        candidateRepos.append(name)
                    }
                }
            }
        }

        // Filter: only repos with workflow runs
        var activeRepos: [String] = []
        for repo in candidateRepos {
            let runs = await fetchWorkflowRuns(repo: repo, token: token, limit: 1)
            if !runs.isEmpty {
                activeRepos.append(repo)
            }
        }

        return activeRepos
    }

    private static func fetchWorkflowRuns(repo: String, token: String, limit: Int = 3) async -> [WorkflowRun] {
        guard let data = await apiGet(path: "/repos/\(repo)/actions/runs?per_page=\(limit)", token: token),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runs = json["workflow_runs"] as? [[String: Any]] else { return [] }

        let shortRepo = repo.split(separator: "/").last.map(String.init) ?? repo

        return runs.compactMap { run in
            guard let id = run["id"] as? Int,
                  let name = run["name"] as? String,
                  let title = run["display_title"] as? String,
                  let status = run["status"] as? String,
                  let branch = run["head_branch"] as? String,
                  let started = run["run_started_at"] as? String,
                  let url = run["html_url"] as? String else { return nil }
            let conclusion = run["conclusion"] as? String
            return WorkflowRun(
                id: id,
                repoName: shortRepo,
                workflowName: name,
                displayTitle: title,
                status: status,
                conclusion: conclusion,
                branch: branch,
                startedAt: started,
                url: url
            )
        }
    }

    // MARK: - Token Resolution

    nonisolated private static func resolveToken() -> String? {
        // Try gh auth token first
        for ghPath in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] {
            guard FileManager.default.fileExists(atPath: ghPath) else { continue }
            let pipe = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = ["auth", "token"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !token.isEmpty { return token }
            } catch { continue }
        }
        return nil
    }

    // MARK: - Repo Cache

    private struct RepoCache: Codable {
        let repos: [String]
        let updatedAt: Date
        var isStale: Bool { Date().timeIntervalSince(updatedAt) > 3600 }
    }

    nonisolated private static func loadCache() -> RepoCache {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(RepoCache.self, from: data) else {
            return RepoCache(repos: [], updatedAt: .distantPast)
        }
        return cache
    }

    nonisolated private static func saveCache(repos: [String]) {
        let cache = RepoCache(repos: repos, updatedAt: Date())
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }
}
