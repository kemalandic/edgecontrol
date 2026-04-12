import WidgetKit

struct CICDEntry: TimelineEntry, Sendable {
    let date: Date
    let runs: [WidgetCICDRun]
    let isStale: Bool
    let minutesAgo: Int

    static let placeholder = CICDEntry(
        date: Date(),
        runs: [
            WidgetCICDRun(id: 1, repoName: "my-app", title: "Deploy", status: "completed", conclusion: "success", url: "", updatedAt: Date()),
            WidgetCICDRun(id: 2, repoName: "api", title: "Tests", status: "in_progress", conclusion: nil, url: "", updatedAt: Date()),
        ],
        isStale: false,
        minutesAgo: 0
    )

    static let noData = CICDEntry(
        date: Date(), runs: [], isStale: true, minutesAgo: 0
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
            minutesAgo: data.minutesAgo
        )
    }
}
