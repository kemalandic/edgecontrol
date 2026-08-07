import WidgetKit

struct CICDEntry: TimelineEntry, Sendable {
    let date: Date
    let runs: [WidgetCICDRun]
    let isStale: Bool
    let minutesAgo: Int
    /// Why there is nothing to show, when there is nothing to show.
    /// Previously this case rendered as empty space with no explanation.
    let statusNote: String?

    static let placeholder = CICDEntry(
        date: Date(),
        runs: [
            WidgetCICDRun(
                id: "preview/my-app/1", hostLabel: "github.com", repoName: "my-app",
                title: "Deploy", state: .success, url: "", updatedAt: Date()
            ),
            WidgetCICDRun(
                id: "preview/api/2", hostLabel: "git.example.dev", repoName: "api",
                title: "Tests", state: .running, url: "", updatedAt: Date()
            ),
        ],
        isStale: false,
        minutesAgo: 0,
        statusNote: nil
    )

    /// Also covers the schema-mismatch case: `WidgetData.read()` returns nil
    /// for a snapshot written by a different app version.
    static let noData = CICDEntry(
        date: Date(),
        runs: [],
        isStale: true,
        minutesAgo: 0,
        statusNote: "Open EdgeControl to refresh"
    )
}

struct CICDProvider: TimelineProvider {
    func placeholder(in context: Context) -> CICDEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (CICDEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CICDEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> CICDEntry {
        guard let data else { return .noData }
        return CICDEntry(
            date: data.timestamp,
            runs: data.cicdRuns,
            isStale: data.isStale,
            minutesAgo: data.minutesAgo,
            statusNote: data.cicdStatusNote
        )
    }
}
