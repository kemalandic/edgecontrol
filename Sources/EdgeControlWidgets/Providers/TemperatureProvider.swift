import WidgetKit

struct TemperatureEntry: TimelineEntry, Sendable {
    let date: Date
    let cpuTemp: Double?
    let gpuTemp: Double?
    let ssdTemp: Double?
    let isStale: Bool
    let minutesAgo: Int

    static let placeholder = TemperatureEntry(
        date: Date(), cpuTemp: 52, gpuTemp: 45, ssdTemp: 38, isStale: false, minutesAgo: 0
    )

    static let noData = TemperatureEntry(
        date: Date(), cpuTemp: nil, gpuTemp: nil, ssdTemp: nil, isStale: true, minutesAgo: 0
    )
}

struct TemperatureProvider: TimelineProvider {
    func placeholder(in context: Context) -> TemperatureEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (TemperatureEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TemperatureEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> TemperatureEntry {
        guard let data else { return .noData }
        return TemperatureEntry(
            date: data.timestamp,
            cpuTemp: data.cpuTemp,
            gpuTemp: data.gpuTemp,
            ssdTemp: data.ssdTemp,
            isStale: data.isStale,
            minutesAgo: data.minutesAgo
        )
    }
}
