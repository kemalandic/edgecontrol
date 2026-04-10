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
