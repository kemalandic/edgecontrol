import WidgetKit

struct SystemGaugeEntry: TimelineEntry, Sendable {
    let date: Date
    let cpuUsage: Double
    let memoryUsage: Double
    let memoryUsedGB: Double
    let memoryTotalGB: Double
    let isStale: Bool
    let minutesAgo: Int

    static let placeholder = SystemGaugeEntry(
        date: Date(), cpuUsage: 42, memoryUsage: 65,
        memoryUsedGB: 32, memoryTotalGB: 128, isStale: false, minutesAgo: 0
    )

    static let noData = SystemGaugeEntry(
        date: Date(), cpuUsage: 0, memoryUsage: 0,
        memoryUsedGB: 0, memoryTotalGB: 0, isStale: true, minutesAgo: 0
    )
}

struct SystemGaugeProvider: TimelineProvider {
    func placeholder(in context: Context) -> SystemGaugeEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (SystemGaugeEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SystemGaugeEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> SystemGaugeEntry {
        guard let data else { return .noData }
        return SystemGaugeEntry(
            date: data.timestamp,
            cpuUsage: data.cpuUsage,
            memoryUsage: data.memoryUsage,
            memoryUsedGB: data.memoryUsedGB,
            memoryTotalGB: data.memoryTotalGB,
            isStale: data.isStale,
            minutesAgo: data.minutesAgo
        )
    }
}
