import SwiftUI

enum WidgetColors {
    static let background = Color(white: 0.08)
    static let cardBackground = Color(white: 0.12)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let textTertiary = Color(white: 0.45)
    static let border = Color(white: 0.18)

    static let cyan = Color(red: 0, green: 0.8, blue: 0.9)
    static let green = Color(red: 0.2, green: 0.85, blue: 0.4)
    static let yellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let red = Color(red: 1.0, green: 0.3, blue: 0.3)
    static let purple = Color(red: 0.7, green: 0.4, blue: 1.0)
    static let orange = Color(red: 1.0, green: 0.6, blue: 0.2)

    static func gaugeColor(for percent: Double) -> Color {
        if percent < 50 { return cyan }
        if percent < 75 { return yellow }
        return red
    }

    static func tempColor(for celsius: Double) -> Color {
        if celsius < 60 { return green }
        if celsius < 80 { return yellow }
        return red
    }
}

enum WidgetFormatters {
    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    static func temperature(_ value: Double) -> String {
        String(format: "%.0f°C", value)
    }

    static func bytesPerSec(_ value: Double) -> String {
        if value < 1024 { return String(format: "%.0f B/s", value) }
        if value < 1024 * 1024 { return String(format: "%.1f KB/s", value / 1024) }
        if value < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", value / (1024 * 1024)) }
        return String(format: "%.1f GB/s", value / (1024 * 1024 * 1024))
    }

    static func signalBars(rssi: Int) -> Int {
        if rssi >= -50 { return 4 }
        if rssi >= -60 { return 3 }
        if rssi >= -70 { return 2 }
        if rssi >= -80 { return 1 }
        return 0
    }
}

struct StaleOverlay: ViewModifier {
    let isStale: Bool
    let minutesAgo: Int

    func body(content: Content) -> some View {
        if isStale {
            content
                .opacity(0.6)
                .overlay(alignment: .bottom) {
                    Text("Updated \(minutesAgo)m ago")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(WidgetColors.textTertiary)
                        .padding(.bottom, 2)
                }
        } else {
            content
        }
    }
}

extension View {
    func staleOverlay(isStale: Bool, minutesAgo: Int) -> some View {
        modifier(StaleOverlay(isStale: isStale, minutesAgo: minutesAgo))
    }
}
