import SwiftUI
import UniformTypeIdentifiers

public final class StickyNoteWidget: DashboardWidget {
    public let widgetId = "sticky-note"
    public let displayName = "Sticky Note"
    public let description = "A free-form note, edited in place and saved with the layout"
    public let iconName = "note.text"
    public let category: WidgetCategory = .info
    public let requiredServices: Set<ServiceKey> = []
    public let supportedSizes = WidgetSizeRange(min: .size(2, 1), max: .size(8, 6))
    public let defaultSize = WidgetSize.size(3, 2)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "note", label: "Note", type: .text, defaultValue: .string("")),
        ConfigSchemaEntry(key: "color", label: "Color", type: .picker, defaultValue: .string("yellow"),
                          options: ["yellow", "orange", "pink", "red", "green", "mint", "blue", "purple", "gray"]),
        ConfigSchemaEntry(key: "opacity", label: "Opacity", type: .slider, defaultValue: .double(0.12),
                          minValue: 0.0, maxValue: 1.0, step: 0.05),
    ]
    public let defaultColors = WidgetColors(primary: .yellow)

    public init() {}

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        StickyNoteWidgetView(
            note: config.string("note"),
            colorName: config.string("color", default: "yellow"),
            tintOpacity: config.double("opacity", default: 0.12),
            pageId: config.string("_pageId"),
            instanceId: config.string("_instanceId"),
            baseConfig: config
        )
    }
}

/// The note stores links as inline markdown — `[title](url)` — and renders
/// them as tappable titles. No other markdown is interpreted.
private struct StickyNoteWidgetView: View {
    let note: String
    let colorName: String
    let tintOpacity: Double
    let pageId: String
    let instanceId: String
    let baseConfig: WidgetConfig

    @EnvironmentObject private var layoutEngine: LayoutEngine
    @Environment(\.themeSettings) private var ts
    @State private var draft = ""
    @State private var seeded = false
    @State private var isEditingNote = false
    // A bare-URL paste prompts for a title; the URL and the cursor offset it
    // will be inserted at wait here while the prompt is up.
    @State private var pendingLinkURL: String?
    @State private var pendingInsertOffset: Int = 0
    @State private var linkTitle = ""

    private var primary: Color {
        switch colorName {
        case "orange": .orange
        case "pink": .pink
        case "red": .red
        case "green": .green
        case "mint": .mint
        case "blue": .blue
        case "purple": .purple
        case "gray": .gray
        default: Theme.widgetPrimary("sticky-note", ts: ts, default: .yellow)
        }
    }

    var body: some View {
        Group {
            if isEditingNote {
                editor
            } else {
                display
            }
        }
        .padding(Theme.compactPadding)
        .background(primary.opacity(tintOpacity))
        .widgetCard()
        .onAppear {
            if !seeded {
                draft = note
                seeded = true
            }
        }
        // External edits (settings field, layout import) win over a
        // stale on-screen draft only when they actually differ.
        .onChange(of: note) { _, newValue in
            if newValue != draft { draft = newValue }
        }
        .onChange(of: draft) { _, newValue in
            save(newValue)
        }
        .alert("Name this link", isPresented: Binding(
            get: { pendingLinkURL != nil },
            set: { if !$0 { pendingLinkURL = nil } }
        )) {
            TextField("Title", text: $linkTitle)
            Button("Add Link") { commitPendingLink() }
            Button("Cancel", role: .cancel) { pendingLinkURL = nil }
        } message: {
            Text("The note shows the title; the link stays underneath.")
        }
    }

    // MARK: - Display mode

    private var display: some View {
        ZStack(alignment: .topLeading) {
            // Empty-area clicks enter editing; clicks on rendered text (and
            // its links) go to the Text itself.
            Color.white.opacity(0.001)
                .onTapGesture { isEditingNote = true }
            if draft.isEmpty {
                Text("Click to write…")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
            } else {
                Text(rendered)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .tint(primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                isEditingNote = true
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.text3(ts).opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Edit note")
        }
    }

    private var rendered: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: draft, options: options))
            ?? AttributedString(draft)
    }

    // MARK: - Edit mode

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if #available(macOS 15.0, *) {
                LinkingTextEditor(
                    text: $draft,
                    onPromptLink: { url, offset in
                        linkTitle = ""
                        pendingInsertOffset = offset
                        pendingLinkURL = url
                    }
                )
                .font(Theme.body(ts))
            } else {
                TextEditor(text: $draft)
                    .font(Theme.body(ts))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
            }
            Button("Done") { isEditingNote = false }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private func commitPendingLink() {
        guard let url = pendingLinkURL else { return }
        let title = linkTitle.trimmingCharacters(in: .whitespaces)
        let display = title.isEmpty ? (URL(string: url)?.host ?? "link") : title
        let insertion = "[\(display)](\(url))"
        let offset = min(max(pendingInsertOffset, 0), draft.count)
        let idx = draft.index(draft.startIndex, offsetBy: offset)
        draft.insert(contentsOf: insertion, at: idx)
        pendingLinkURL = nil
    }

    private func save(_ text: String) {
        guard !instanceId.isEmpty, text != note else { return }
        // Strip the injected identity keys: they describe the render pass,
        // not the widget's persistent state.
        var config = baseConfig
        config["note"] = .string(text)
        config["_pageId"] = nil
        config["_instanceId"] = nil
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
    }
}

// MARK: - Linking editor (macOS 15+)

/// TextEditor with selection tracking and paste interception: pasting a URL
/// over selected text turns the selection into `[selection](url)`; pasting a
/// bare URL asks the parent to prompt for a title. Everything else pastes
/// normally.
@available(macOS 15.0, *)
private struct LinkingTextEditor: View {
    @Binding var text: String
    /// (url, character offset to insert at) — parent shows the title prompt.
    let onPromptLink: (String, Int) -> Void

    @State private var selection: TextSelection?
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $text, selection: $selection)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .focused($focused)
            .onAppear {
                focused = true
                // onPasteCommand never fires here: the focused NSTextView
                // consumes Cmd+V itself. A local monitor sees the keystroke
                // first; URL pastes are ours, everything else passes through
                // to the text view's native paste.
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard focused,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                          event.charactersIgnoringModifiers?.lowercased() == "v",
                          let pasted = NSPasteboard.general.string(forType: .string)?
                              .trimmingCharacters(in: .whitespacesAndNewlines),
                          isLink(pasted)
                    else { return event }
                    handleLinkPaste(pasted)
                    return nil
                }
            }
            .onDisappear {
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                keyMonitor = nil
            }
    }

    private func handleLinkPaste(_ pasted: String) {
        let selectedRange = currentRange()
        if let range = selectedRange, !range.isEmpty {
            // Slack-style: the selected words become the link title.
            let title = String(text[range])
            replace(range: range, with: "[\(title)](\(pasted))")
        } else {
            let idx = selectedRange?.lowerBound ?? text.endIndex
            onPromptLink(pasted, text.distance(from: text.startIndex, to: idx))
        }
    }

    private func currentRange() -> Range<String.Index>? {
        guard let selection, case .selection(let range) = selection.indices else { return nil }
        return range
    }

    private func replace(range: Range<String.Index>?, with insertion: String) {
        // Selection indices go stale the moment the string changes; clear
        // first so SwiftUI never resolves them against the new text.
        selection = nil
        if let range {
            text.replaceSubrange(range, with: insertion)
        } else {
            text.append(insertion)
        }
    }

    private func isLink(_ s: String) -> Bool {
        guard !s.contains(" "), let url = URL(string: s),
              let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
