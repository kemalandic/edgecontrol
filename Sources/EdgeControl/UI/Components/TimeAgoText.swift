import SwiftUI

/// Self-ticking relative-time text. Subscribes to a 1-second timer so
/// "21s ago" actually ticks forward every second. For sub-hour ages
/// shows minute+second resolution ("1m 23s ago"). For longer ages
/// shows hour+minute or day+hour. Future timestamps render as
/// "in 5m 12s" / "in 2h 30m" / etc.
public struct TimeAgoText: View {
    public let iso: String

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(_ iso: String) {
        self.iso = iso
    }

    public var body: some View {
        Text(TimeAgoText.format(iso: iso, now: now))
            .onReceive(timer) { tick in now = tick }
    }

    public static func format(iso: String, now: Date = Date()) -> String {
        if iso.isEmpty { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let total = Int(now.timeIntervalSince(d))
        let isFuture = total < 0
        let seconds = abs(total)
        let formatted: String
        if seconds < 60 {
            formatted = "\(seconds)s"
        } else if seconds < 3600 {
            let m = seconds / 60
            let s = seconds % 60
            formatted = s == 0 ? "\(m)m" : "\(m)m \(s)s"
        } else if seconds < 86400 {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            formatted = m == 0 ? "\(h)h" : "\(h)h \(m)m"
        } else {
            let d = seconds / 86400
            let h = (seconds % 86400) / 3600
            formatted = h == 0 ? "\(d)d" : "\(d)d \(h)h"
        }
        return isFuture ? "in \(formatted)" : "\(formatted) ago"
    }
}
