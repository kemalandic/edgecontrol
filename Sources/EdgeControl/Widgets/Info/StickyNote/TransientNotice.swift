import AppKit

/// A line of text that appears over a widget and takes itself away.
///
/// Promoting a to-do writes to a database on another device. Nothing on the
/// panel changes, so without a word the person is left pressing the key again
/// to find out whether the first press worked — which is exactly the thing
/// the duplicate check then has to undo.
///
/// An alert would be the usual answer and the wrong one: it takes the
/// keyboard, it has to be dismissed, and it is far more ceremony than "done".
@MainActor
final class TransientNotice {

    private weak var owner: NSView?
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    init(owner: NSView) {
        self.owner = owner
    }

    /// Shows `text` over the owner for a moment.
    func show(_ text: String, for duration: Duration = .milliseconds(1600)) {
        guard let owner, let window = owner.window else { return }

        dismissal?.cancel()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: background.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -10),
        ])

        let size = background.fittingSize
        hide()
        let created = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        created.isFloatingPanel = true
        created.level = .popUpMenu
        created.hidesOnDeactivate = false
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        // Nothing to press, so nothing to take the pointer from what is
        // underneath.
        created.ignoresMouseEvents = true
        background.frame = NSRect(origin: .zero, size: size)
        background.autoresizingMask = [.width, .height]
        created.contentView = background

        let ownerFrame = window.convertToScreen(owner.convert(owner.bounds, to: nil))
        created.setFrameOrigin(
            NSPoint(x: ownerFrame.midX - size.width / 2, y: ownerFrame.maxY - size.height - 12))
        window.addChildWindow(created, ordered: .above)
        panel = created

        dismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
    }
}
