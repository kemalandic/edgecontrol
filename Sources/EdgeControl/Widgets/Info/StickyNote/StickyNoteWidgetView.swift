import AppKit
import SwiftUI

// The SwiftUI side: colours, font size persistence, and saving into the note store.

struct StickyNoteWidgetView: View {
    let store: NoteStore
    let noteId: String
    let colorName: String
    let textColorName: String
    let tintOpacity: Double
    let fontFamily: String
    let fontSize: Double
    let pageId: String
    let instanceId: String
    let baseConfig: WidgetConfig

    @EnvironmentObject private var layoutEngine: LayoutEngine
    @Environment(\.themeSettings) private var ts
    @State private var activeId = ""
    @State private var rtfDraft = ""
    @State private var plainDraft = ""
    @State private var lastSaved = ""
    @State private var seeded = false
    @State private var saveTask: Task<Void, Never>?

    private var primary: Color { StickyNotePalette.tint(colorName, ts: ts) }
    private var textNSColor: NSColor { StickyNotePalette.text(textColorName) }

    var body: some View {
        RichStickyTextView(
            rtfBase64: $rtfDraft,
            plainText: $plainDraft,
            // Nothing legacy reaches the editor any more: a pre-RTF note is
            // converted once, on its way into the store.
            legacyMarkdown: "",
            baseFont: RichStickyTextView.makeFont(family: fontFamily, size: fontSize * ts.fontScale),
            textColor: textNSColor,
            linkColor: NSColor(primary),
            onFontSizeDelta: { delta in persistFontSize(fontSize + delta) },
            onFontSizeReset: { persistFontSize(18) }
        )
        .padding(Theme.compactPadding)
        .background(primary.opacity(tintOpacity))
        .widgetCard()
        .onAppear { seed() }
        // The id can arrive after the first render — a widget dropped on the
        // dashboard gets its note on appear, and the new configuration comes
        // back round as a changed prop.
        .onChange(of: noteId) { _, incoming in
            guard !incoming.isEmpty, incoming != activeId else { return }
            seeded = false
            seed()
        }
        // Debounced: a save writes three small files, and doing that per
        // keystroke is what the debounce on the old layout write was for.
        .onChange(of: rtfDraft) { _, _ in
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                save()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            save()
        }
    }

    // MARK: - Loading

    private func seed() {
        guard !seeded else { return }
        seeded = true
        let id = resolvedNoteId()
        guard !id.isEmpty else { return }
        activeId = id
        rtfDraft = store.body(id: id)
        plainDraft = store.plainText(id: id)
        lastSaved = rtfDraft
    }

    /// The note this widget shows, creating one the first time.
    ///
    /// A widget placed after the startup migration has run has no note yet, so
    /// it makes the same plan the migration would have made — one widget's
    /// worth — and writes it back.
    ///
    /// Returns an empty id for a widget with no placement, which is the
    /// preview drawn in the widget catalog: it edits like a note and saves
    /// nowhere, which is what a preview should do.
    private func resolvedNoteId() -> String {
        if !noteId.isEmpty { return noteId }
        guard !instanceId.isEmpty, !pageId.isEmpty,
            let plan = NoteMigration.plan(config: persistableConfig, id: UUID().uuidString)
        else { return "" }
        store.adopt(plan)
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: plan.config)
        return plan.noteId
    }

    // MARK: - Saving

    private func save() {
        guard !activeId.isEmpty, rtfDraft != lastSaved else { return }
        store.save(id: activeId, rtfBase64: rtfDraft, plainText: plainDraft)
        lastSaved = rtfDraft
    }

    /// 18 is the schema default; Cmd+0 snaps back to it.
    private func persistFontSize(_ newSize: Double) {
        guard !instanceId.isEmpty else { return }
        var config = persistableConfig
        config["fontSize"] = .double(min(24, max(10, newSize)))
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
    }

    /// The configuration without the keys the render pass injects: they
    /// describe where the widget is being drawn, not what it is.
    private var persistableConfig: WidgetConfig {
        var config = baseConfig
        config["_pageId"] = nil
        config["_instanceId"] = nil
        return config
    }
}

// MARK: - Rich text view
