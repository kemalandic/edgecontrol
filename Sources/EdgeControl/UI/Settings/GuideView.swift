import SwiftUI

/// A long-form, scrollable reference for the dashboard and its widgets.
/// Most of the sticky note's markdown-lite behavior is invisible until you
/// know to type it, so it's written down here.
struct GuideView: View {
    @EnvironmentObject private var layoutEngine: LayoutEngine

    private var accent: Color {
        Theme.accent(layoutEngine.document.globalSettings.theme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guide")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 22) {
                    section("Dashboard", rows: [
                        ("Swipe left/right", "Move between pages — pages follow your finger."),
                        ("Tap a widget", "Launches its configured app (set per widget under Pages)."),
                        ("⌘ + hover", "A gear appears in the widget's corner; click it to jump straight to that widget's settings."),
                        ("Right-click", "\"Edit This Widget's Settings\" jumps to the same place."),
                    ])
                    section("Edit Mode", rows: [
                        ("Drag anywhere", "Widgets go inert while editing; any point on the card drags it."),
                        ("Tap", "Selects a widget (selection floats it above overlaps)."),
                        ("Corner handle", "Drag the bottom-right handle to resize."),
                        ("Layer buttons", "On the selected widget: send to back / bring to front — for reaching widgets stacked on one another."),
                        ("✕", "Removes the widget from the page."),
                    ])
                    section("Sticky Note — typing", rows: [
                        ("- or *", "Space, then any character → bullet item."),
                        ("1.", "Any number, a dot, then space → numbered item. Numbers keep themselves in order as you insert, delete and convert; a blank line starts the count fresh."),
                        ("- [ ]", "Checkbox — converts at the closing bracket, so \"[x]\" can start one checked."),
                        ("# ## ###", "Headings, three levels."),
                        ("---", "Return turns it into a horizontal rule."),
                        ("Switch type", "On an existing item, type another marker after it: \"1. \" on a bullet makes it numbered, \"[ ]\" makes it a checkbox, \"-\" or \"*\" makes it a bullet again."),
                        ("Return", "Continues the list; on an empty item it ends the list instead."),
                        ("Tab / ⇧Tab", "Indent / unindent the line, from anywhere in it."),
                        ("Paste a URL", "Over selected text, that text becomes the link. On its own, you're asked for a title."),
                        ("Return in a link", "Opens the link instead of breaking the line."),
                    ])
                    section("Sticky Note — shortcuts", rows: [
                        ("⌘B / ⌘I / ⌘U", "Bold, italic, underline."),
                        ("⌘⇧X", "Strikethrough."),
                        ("⌘↩", "Check / uncheck the todo on the caret's line — or every checkbox line in a selection."),
                        ("⌘= / ⌘-", "Bigger / smaller text."),
                        ("⌘0", "Snap back to the configured font size."),
                        ("⌘⇧0", "Body text — clears heading size, bold/italic, underline and strikethrough."),
                        ("Click a box", "Toggles the checkbox; works by touch too."),
                    ])
                    section("Reminders", rows: [
                        ("Add field", "Type and press Return to create a real reminder in the configured list."),
                        ("\"in…\" field", "\":30\" = 30 minutes, \"2\" = 2 hours, \"2:15\" = two hours fifteen — sets the due time relative to now."),
                        ("Due Today", "When on (and no \"in…\" is typed), new reminders come due at the configured Due Time and notify then."),
                        ("Circle", "Tap to complete the reminder everywhere."),
                    ])
                    section("Widget Catalog", rows: [
                        ("+", "Adds the widget to the current page; a full page stages it as an overlap to resolve in edit mode."),
                        ("Eye", "Previews the widget at its minimum, default and maximum sizes."),
                        ("Check", "Shown when placed; click removes the most recent copy. x2/x3 marks multiples."),
                    ])
                }
                .padding(.bottom, 16)
            }
        }
        .padding(16)
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows, id: \.0) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.0)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                            .frame(width: 130, alignment: .leading)
                        Text(row.1)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
