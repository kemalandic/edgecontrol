import WidgetKit

struct WiFiEntry: TimelineEntry, Sendable {
    let date: Date
    let ssid: String?
    let signalStrength: Int?
    let channel: Int?
    let band: String?
    let isStale: Bool
    let minutesAgo: Int

    static let placeholder = WiFiEntry(
        date: Date(), ssid: "MyNetwork", signalStrength: -55,
        channel: 36, band: "5 GHz", isStale: false, minutesAgo: 0
    )

    static let noData = WiFiEntry(
        date: Date(), ssid: nil, signalStrength: nil,
        channel: nil, band: nil, isStale: true, minutesAgo: 0
    )
}

struct WiFiProvider: TimelineProvider {
    func placeholder(in context: Context) -> WiFiEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WiFiEntry) -> Void) {
        completion(entry(from: WidgetData.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WiFiEntry>) -> Void) {
        let entry = entry(from: WidgetData.read())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func entry(from data: WidgetData?) -> WiFiEntry {
        guard let data else { return .noData }
        return WiFiEntry(
            date: data.timestamp,
            ssid: data.wifiSSID,
            signalStrength: data.wifiSignalStrength,
            channel: data.wifiChannel,
            band: data.wifiBand,
            isStale: data.isStale,
            minutesAgo: data.minutesAgo
        )
    }
}
