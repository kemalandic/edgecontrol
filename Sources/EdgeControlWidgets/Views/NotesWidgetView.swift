import SwiftUI
import WidgetKit

struct NotesWidget: Widget {
    let kind = "Notes"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NotesProvider()) { entry in
            NotesWidgetView(entry: entry)
                .containerBackground(WidgetColors.background, for: .widget)
        }
        .configurationDisplayName("Note")
        .description("The to-dos of a note from the dashboard")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NotesWidgetView: View {
    let entry: NotesEntry

    @Environment(\.widgetFamily) var family

    /// What fits at a size somebody can read from across a desk.
    private var maxItems: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 5
        case .systemLarge: return 11
        default: return 5
        }
    }

    /// The unfinished ones come first from the app, so taking the head of the
    /// list shows what is left rather than what has been ticked off.
    private var shown: [WidgetNoteItem] {
        Array(entry.items.prefix(maxItems))
    }

    private var remaining: Int {
        max(0, entry.items.count - shown.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if let note = entry.statusNote {
                Spacer(minLength: 0)
                Text(note)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
                Spacer(minLength: 0)
            } else {
                ForEach(shown) { item in
                    row(item)
                }
                if remaining > 0 {
                    Text("+\(remaining) more")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(WidgetColors.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(entry.isStale ? 0.55 : 1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 14))
                .foregroundStyle(WidgetColors.yellow)
            Text(entry.title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetColors.textSecondary)
                .lineLimit(1)
            Spacer()
            if let progress = WidgetNoteItem.progress(entry.items) {
                Text(progress)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(WidgetColors.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    private func row(_ item: WidgetNoteItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: item.done ? "checkmark.square.fill" : "square")
                .font(.system(size: 11))
                .foregroundStyle(item.done ? WidgetColors.green : WidgetColors.textTertiary)
            Text(item.text)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(item.done ? WidgetColors.textTertiary : WidgetColors.textPrimary)
                .strikethrough(item.done, color: WidgetColors.textTertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
