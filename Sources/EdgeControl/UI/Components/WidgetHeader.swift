import SwiftUI

/// Reusable widget header: colored dot + title text + spacer.
/// Used by widgets that have a "● TITLE" header pattern.
struct WidgetHeader: View {
    let title: String
    let color: Color
    @Environment(\.themeSettings) private var ts

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))
            Spacer()
        }
    }
}

// MARK: - Rate Pair

/// Two labeled rates (down/up, read/write) rendered identically wherever a
/// widget shows them, so equal box sizes produce equal layouts across
/// Network, Disk I/O and friends.
struct RatePairView: View {
    struct Entry {
        let icon: String
        let label: String
        let value: String
        let color: Color
    }

    let first: Entry
    let second: Entry
    var compact: Bool = false

    @Environment(\.themeSettings) private var ts

    var body: some View {
        HStack(spacing: 12) {
            group(first)
            group(second)
        }
    }

    private func group(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 4) {
                Image(systemName: entry.icon)
                    .font(.system(size: (compact ? 12 : 18) * ts.fontScale))
                    .foregroundStyle(entry.color)
                Text(entry.label)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
            Text(entry.value)
                .font(Theme.value(ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
