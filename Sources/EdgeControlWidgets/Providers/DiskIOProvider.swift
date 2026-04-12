import WidgetKit

struct DiskIOEntry: TimelineEntry, Sendable {
    let date: Date
    let readRate: Double
    let writeRate: Double
    let isStale: Bool
    let minutesAgo: Int

    static let placeholder = DiskIOEntry(
        date: Date(), readRate: 52_428_800, writeRate: 15_728_640, isStale: false, minutesAgo: 0
    )

    static let noData = DiskIOEntry(
        date: Date(), readRate: 0, writeRate: 0, isStale: true, minutesAgo: 0
    )
}

struct DiskIOProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiskIOEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DiskIOEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskIOEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> DiskIOEntry {
        guard let data else { return .noData }
        return DiskIOEntry(
            date: data.timestamp,
            readRate: data.diskReadRate,
            writeRate: data.diskWriteRate,
            isStale: data.isStale,
            minutesAgo: data.minutesAgo
        )
    }
}
