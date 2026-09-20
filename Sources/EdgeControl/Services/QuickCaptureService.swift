import AppKit
import Carbon.HIToolbox

/// The global key and the window it opens.
///
/// Registered through Carbon's `RegisterEventHotKey` rather than an event
/// monitor. A monitor can watch keys but not take them, and taking them would
/// need the Accessibility permission — a large thing to ask for a text box.
/// The Carbon call needs no permission and consumes the combination, so the
/// app in front never sees it.
@MainActor
public final class QuickCaptureService {

    /// Control-Option-Space. Chosen for being unclaimed: Cmd+Shift+N would be
    /// taken from Finder's New Folder in every app on the machine, which is
    /// not a thing a dashboard should do to somebody.
    public static let keyCode = UInt32(kVK_Space)
    public static let modifiers = UInt32(controlKey | optionKey)

    /// The C callback cannot capture context, so it reaches the service the
    /// only way it can.
    private static weak var active: QuickCaptureService?

    private let store: NoteStore
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var window: QuickCaptureWindow?

    public init(store: NoteStore) {
        self.store = store
    }

    public var isRunning: Bool { hotKey != nil }

    public func start() {
        guard hotKey == nil else { return }
        Self.active = self

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                QuickCaptureService.active?.present()
                return noErr
            }, 1, &spec, nil, &handler)

        // Four letters identifying the registration, as Carbon has always
        // wanted: "ECap".
        let id = EventHotKeyID(signature: OSType(0x4543_6170), id: 1)
        let status = RegisterEventHotKey(
            Self.keyCode, Self.modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            AppLog.persistence.error("quick capture could not claim its key (\(status, privacy: .public))")
            stop()
        }
    }

    public func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        window?.orderOut(nil)
        window = nil
        if Self.active === self { Self.active = nil }
    }

    /// Opens the window, or closes it if the key is pressed while it is
    /// already open — the same key in and out, so a mistaken press costs
    /// nothing.
    public func present() {
        if let window, window.isVisible {
            dismiss()
            return
        }

        let window = self.window ?? QuickCaptureWindow()
        self.window = window
        window.onSubmit = { [weak self] line in self?.capture(line) }
        window.onCancel = { [weak self] in self?.dismiss() }
        window.prepare()

        // The app is not in front — that is the whole point — so it has to
        // come forward for the box to take a keystroke.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.orderOut(nil)
    }

    private func capture(_ line: String) {
        let id = QuickCapture.inboxNoteId
        let existing = Data(base64Encoded: store.body(id: id)).flatMap {
            NSAttributedString(rtf: $0, documentAttributes: nil)
        }
        guard
            let updated = QuickCapture.appending(
                line, to: existing,
                baseFont: QuickCapture.defaultFont(), textColor: QuickCapture.defaultTextColor())
        else {
            dismiss()
            return
        }

        let rtf = updated.rtf(
            from: NSRange(location: 0, length: updated.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        store.save(
            id: id, rtfBase64: rtf?.base64EncodedString() ?? "", plainText: updated.string)
        dismiss()
    }
}

/// The capture window: one line, nothing else.
///
/// Borderless and small on purpose. It appears over whatever was in front, so
/// it has to read as a thing that will be gone in a moment rather than as an
/// application taking the screen.
@MainActor
final class QuickCaptureWindow: NSPanel {

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let field = NSTextField()
    private let caption = NSTextField(labelWithString: "")

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .modalPanel
        hidesOnDeactivate = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let background = NSVisualEffectView(frame: contentLayoutRect)
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]

        field.placeholderString = "Capture a line"
        field.font = .systemFont(ofSize: 20, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(submit)
        field.translatesAutoresizingMaskIntoConstraints = false

        caption.stringValue = "Return saves to Inbox · Esc closes"
        caption.font = .systemFont(ofSize: 11, weight: .regular)
        caption.textColor = .secondaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(field)
        background.addSubview(caption)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 18),
            caption.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            caption.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
        ])
        contentView = background
    }

    /// A panel must say so to take the keyboard; a borderless one does not by
    /// default, and a capture box that cannot be typed in is furniture.
    override var canBecomeKey: Bool { true }

    func prepare() {
        field.stringValue = ""
        centreOnActiveScreen()
        makeFirstResponder(field)
    }

    /// On the screen the pointer is on, a little above the middle — where a
    /// thing that appeared for a moment belongs, rather than dead centre.
    private func centreOnActiveScreen() {
        let screen =
            NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        setFrameOrigin(
            NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY + visible.height * 0.12))
    }

    @objc private func submit() {
        let line = field.stringValue
        field.stringValue = ""
        onSubmit?(line)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
