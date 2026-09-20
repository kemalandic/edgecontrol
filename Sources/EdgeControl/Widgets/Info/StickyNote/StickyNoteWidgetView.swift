import AppKit
import SwiftUI

// The SwiftUI side: colours, font size persistence, and saving into the layout.

struct StickyNoteWidgetView: View {
    let note: String
    let rtf: String
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
    @State private var rtfDraft = ""
    @State private var plainDraft = ""
    @State private var seeded = false
    @State private var saveTask: Task<Void, Never>?

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

    /// "soft white" is a touch darker than pure white — easier on the eyes
    /// against the tinted card.
    private var textNSColor: NSColor {
        switch textColorName {
        case "white": .white
        case "gray": .systemGray
        case "black": .black
        case "yellow": .systemYellow
        case "orange": .systemOrange
        case "pink": .systemPink
        case "red": .systemRed
        case "green": .systemGreen
        case "mint": .systemMint
        case "blue": .systemBlue
        case "purple": .systemPurple
        default: NSColor(white: 0.85, alpha: 1)
        }
    }

    var body: some View {
        RichStickyTextView(
            rtfBase64: $rtfDraft,
            plainText: $plainDraft,
            legacyMarkdown: note,
            baseFont: RichStickyTextView.makeFont(family: fontFamily, size: fontSize * ts.fontScale),
            textColor: textNSColor,
            linkColor: NSColor(primary),
            onFontSizeDelta: { delta in persistFontSize(fontSize + delta) },
            onFontSizeReset: { persistFontSize(18) }
        )
        .padding(Theme.compactPadding)
        .background(primary.opacity(tintOpacity))
        .widgetCard()
        .onAppear {
            if !seeded {
                rtfDraft = rtf
                plainDraft = note
                seeded = true
            }
        }
        // External edits (settings field, layout import) win over a stale
        // on-screen draft only when they actually differ.
        .onChange(of: rtf) { _, newValue in
            if newValue != rtfDraft { rtfDraft = newValue }
        }
        // Debounced: saving mutates the layout document, and doing that per
        // keystroke re-rendered every widget on the dashboard per character.
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

    /// 18 is the schema default; Cmd+0 snaps back to it.
    private func persistFontSize(_ newSize: Double) {
        guard !instanceId.isEmpty else { return }
        var config = baseConfig
        config["fontSize"] = .double(min(24, max(10, newSize)))
        // Carry the live drafts so the size write can't clobber newer text
        // than the config snapshot holds.
        config["rtf"] = .string(rtfDraft)
        config["note"] = .string(plainDraft)
        config["_pageId"] = nil
        config["_instanceId"] = nil
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
    }

    private func save() {
        guard !instanceId.isEmpty, rtfDraft != rtf else { return }
        // Strip the injected identity keys: they describe the render pass,
        // not the widget's persistent state.
        var config = baseConfig
        config["rtf"] = .string(rtfDraft)
        config["note"] = .string(plainDraft)
        config["_pageId"] = nil
        config["_instanceId"] = nil
        layoutEngine.updateWidgetConfig(pageId: pageId, instanceId: instanceId, config: config)
    }
}

// MARK: - Rich text view
