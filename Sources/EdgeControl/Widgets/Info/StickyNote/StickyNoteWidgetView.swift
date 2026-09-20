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
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    @State private var activeId = ""
    @State private var rtfDraft = ""
    @State private var plainDraft = ""
    @State private var lastSaved = ""
    @State private var seeded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var hovering = false

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
            onFontSizeReset: { persistFontSize(18) },
            writeMedia: { data in
                guard !activeId.isEmpty else { return nil }
                return store.writeMedia(data, for: activeId)
            },
            readMedia: { name in
                guard !activeId.isEmpty else { return nil }
                return store.mediaData(named: name, for: activeId)
            },
            promoteToReminders: { titles in promote(titles) }
        )
        .padding(Theme.compactPadding)
        .background(primary.opacity(tintOpacity))
        .widgetCard()
        // A note in a six-row cell is a note you cannot write in. The panel
        // is right there — this is the way to borrow all of it, and the way
        // back is the backdrop, the corner button or Esc.
        .overlay(alignment: .topTrailing) {
            if hovering, !instanceId.isEmpty, !pageId.isEmpty,
                !layoutEngine.isFocused(pageId: pageId, instanceId: instanceId)
            {
                Button {
                    layoutEngine.focus(pageId: pageId, instanceId: instanceId)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(5)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .padding(4)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
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

    // MARK: - Reminders

    /// Puts the to-dos into Reminders, skipping the ones already waiting
    /// there, and answers with a line to show for it.
    ///
    /// The service is started on demand: it normally runs only while a
    /// Reminders widget is placed, and a note should not need one on the
    /// dashboard to reach the same database. Starting it is also what
    /// prompts for access the first time.
    private func promote(_ titles: [String]) -> String {
        let service = model.remindersService
        service.start()
        // `items` is filled by an asynchronous fetch, so the very first
        // promotion after launch may not see what is already there. It
        // settles from the second one on, and a duplicate reminder is a
        // smaller problem than a missing one.
        let fresh = ReminderPromotion.newTitles(titles, existing: service.items.map(\.title))
        for title in fresh { service.add(title: title) }
        return ReminderPromotion.summary(added: fresh.count, skipped: titles.count - fresh.count)
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
