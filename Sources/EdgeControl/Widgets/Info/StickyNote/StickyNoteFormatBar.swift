import AppKit

/// The formatting bar that appears over a selection.
///
/// The panel this app runs on is touch-first and usually has no keyboard in
/// front of it, and the kiosk window has no menu bar showing — so Cmd+B is
/// not an answer for the person actually standing at the screen. A bar that
/// appears when text is selected is.
///
/// It is a window rather than a subview because a widget's cell is clipped:
/// on the 14.5" panel a cell can be shorter than the bar, and a subview would
/// be cut off exactly when the note is small enough to need the help.
@MainActor
final class StickyNoteFormatBar {

    private struct Action {
        let symbol: String
        let help: String
        let selector: Selector
    }

    private static let actions: [Action] = [
        Action(symbol: "bold", help: "Bold", selector: Selector(("formatBold:"))),
        Action(symbol: "italic", help: "Italic", selector: Selector(("formatItalic:"))),
        Action(symbol: "strikethrough", help: "Strikethrough", selector: Selector(("toggleStrikethrough:"))),
        Action(
            symbol: "chevron.left.forwardslash.chevron.right", help: "Code",
            selector: Selector(("toggleCodeSpan:"))),
    ]

    private weak var owner: NSTextView?
    private var panel: NSPanel?

    init(owner: NSTextView) {
        self.owner = owner
    }

    /// Shows the bar over `rect` (in the owner's coordinates), or hides it
    /// when there is nothing selected.
    func update(selectionRect rect: NSRect?, visible: Bool) {
        guard visible, let rect, let owner, let window = owner.window else {
            hide()
            return
        }

        let panel = existingPanel(near: window)
        let size = panel.frame.size
        let inWindow = owner.convert(rect, to: nil)
        let onScreen = window.convertToScreen(inWindow)

        // Above the selection, centred on it, and nudged back inside the
        // screen when the selection is near an edge — on a 2560x720 strip a
        // note can easily sit hard against one.
        var origin = NSPoint(
            x: onScreen.midX - size.width / 2,
            y: onScreen.maxY + 8)
        if let visibleFrame = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX + 4), visibleFrame.maxX - size.width - 4)
            if origin.y + size.height > visibleFrame.maxY {
                origin.y = onScreen.minY - size.height - 8
            }
        }
        panel.setFrameOrigin(origin)
        if !panel.isVisible { window.addChildWindow(panel, ordered: .above) }
    }

    func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func existingPanel(near window: NSWindow) -> NSPanel {
        if let panel { return panel }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)

        for action in Self.actions {
            let button = NSButton()
            button.bezelStyle = .texturedRounded
            button.isBordered = false
            button.image = NSImage(systemSymbolName: action.symbol, accessibilityDescription: action.help)
            button.toolTip = action.help
            button.target = owner
            button.action = action.selector
            // The selection has to survive the tap, so the bar never takes
            // first responder away from the text.
            button.refusesFirstResponder = true
            button.setButtonType(.momentaryChange)
            button.widthAnchor.constraint(equalToConstant: 30).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(button)
        }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor),
        ])

        let fitting = stack.fittingSize
        let created = NSPanel(
            contentRect: NSRect(origin: .zero, size: fitting),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        created.isFloatingPanel = true
        created.level = .popUpMenu
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.ignoresMouseEvents = false
        background.frame = NSRect(origin: .zero, size: fitting)
        background.autoresizingMask = [.width, .height]
        created.contentView = background

        panel = created
        return created
    }
}
