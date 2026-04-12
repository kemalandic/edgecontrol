import WidgetKit

struct NetworkEntry: TimelineEntry, Sendable {
    let date: Date
    let upRate: Double
    let downRate: Double
    let isStale: Bool
    let minutesAgo: Int

    static let placeholder = NetworkEntry(
        date: Date(), upRate: 524_288, downRate: 2_621_440, isStale: false, minutesAgo: 0
    )

    static let noData = NetworkEntry(
        date: Date(), upRate: 0, downRate: 0, isStale: true, minutesAgo: 0
    )
}

struct NetworkProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetworkEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (NetworkEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetworkEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> NetworkEntry {
        guard let data else { return .noData }
        return NetworkEntry(
            date: data.timestamp,
            upRate: data.networkUpRate,
            downRate: data.networkDownRate,
            isStale: data.isStale,
            minutesAgo: data.minutesAgo
        )
    }
}
