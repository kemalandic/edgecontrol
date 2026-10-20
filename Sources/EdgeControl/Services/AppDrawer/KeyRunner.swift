import AppKit
import CoreGraphics
import Foundation

/// Runs what App Drawer's keys do: open apps, links and files, run
/// Shortcuts, copy or type text, and press hotkeys and media keys.
///
/// Keyboard keys post keyboard events, as a Stream Deck does, which macOS
/// allows only once EdgeControl is switched on in System Settings › Privacy &
/// Security › Accessibility. EdgeControl asks once (which adds it to that
/// list, switched off) and otherwise only says what's missing; the switch is
/// the user's.
///
/// The events go to the app in front. A tap on the dashboard doesn't bring
/// EdgeControl forward, but if it's in front anyway, after a click with the
/// mouse, say, the app used before it comes back first.
@MainActor
final class KeyRunner {
    /// The last app in front that wasn't EdgeControl.
    var workApp: NSRunningApplication?
    var shortcuts: () -> [DrawerShortcut] = { [] }
    private var askedForAccess = false

    static let accessMessage = "Allow EdgeControl in System Settings › Privacy & Security › Accessibility"

    var canPostEvents: Bool { CGPreflightPostEventAccess() }

    func noteFront(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        workApp = app
    }

    /// Runs an action: nil when it worked, otherwise what went wrong, for the tile.
    func run(_ action: KeyAction) async -> String? {
        switch action.kind {
        case .app:
            return await launch(action.bundleId ?? "")
        case .shortcut:
            return await runShortcut(action.shortcutId ?? action.name ?? "")
        case .url:
            return openLink(action.url ?? "")
        case .file:
            return openFile(action.path ?? "")
        case .text:
            if action.typesText { return await type(action.text ?? "") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(action.text ?? "", forType: .string)
            return nil
        case .hotkey:
            return await press(keyCode: action.keyCode, modifiers: action.modifiers ?? [])
        case .media:
            return pressMedia(MediaKey(rawValue: action.key ?? ""))
        case .multi:
            // In order, a moment apart; a step that fails stops the rest.
            for step in action.steps ?? [] where step.kind != .folder && step.kind != .multi {
                if let failure = await run(step) { return failure }
                try? await Task.sleep(for: .milliseconds(150))
            }
            return nil
        case .wait:
            try? await Task.sleep(for: .seconds(min(max(action.seconds ?? 0.5, 0), 30)))
            return nil
        case .folder:
            return nil
        case nil:
            return "This EdgeControl can't run \(action.type) keys yet"
        }
    }

    // MARK: - Apps, links, files

    /// Only apps actually installed, by bundle id: never a path.
    func launch(_ bundleId: String) async -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return "That app isn't installed"
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            AppLog.appDrawer.error("Opening \(bundleId, privacy: .public) failed: \(error.localizedDescription)")
            return "Couldn't open it"
        }
        // If EdgeControl takes focus back straight after the tap, bring the
        // app forward once more. (Not if another app came forward: that may
        // be the next step of a multi-action.)
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
        }
        // A moment for it to take the keyboard, for a hotkey that follows.
        try? await Task.sleep(for: .milliseconds(400))
        return nil
    }

    /// Web links and app links ("obsidian://…", a System Settings pane).
    /// Files have their own key type, so a link can't name one.
    func openLink(_ text: String) -> String? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), let scheme = url.scheme?.lowercased(),
            scheme != "file"
        else { return "That isn't a link" }
        return NSWorkspace.shared.open(url) ? nil : "Nothing on this Mac opens \(scheme): links"
    }

    /// A file or folder opens as a double-click in Finder would open it.
    func openFile(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return "That file isn't there any more" }
        return NSWorkspace.shared.open(URL(fileURLWithPath: expanded)) ? nil : "Couldn't open it"
    }

    // MARK: - Shortcuts

    func runShortcut(_ idOrName: String) async -> String? {
        guard !idOrName.isEmpty else { return "No Shortcut chosen" }
        let name = shortcuts().first { $0.id == idOrName }?.name ?? idOrName
        let (status, message) = await Task.detached { () -> (Int32, String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", idOrName]
            let errors = Pipe()
            process.standardError = errors
            process.standardOutput = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, "Couldn't start Shortcuts") }
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: data, as: UTF8.self))
        }.value
        guard status != 0 else { return nil }
        let reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "\(name) didn't finish" : reason
    }

    // MARK: - Keyboard

    private func checkAccess() -> String? {
        guard !canPostEvents else { return nil }
        if !askedForAccess {
            askedForAccess = true
            _ = CGRequestPostEventAccess()
        }
        return Self.accessMessage
    }

    /// Brings back the app being worked in if EdgeControl is in front.
    private func workAppInFront() async {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            let app = workApp, !app.isTerminated
        else { return }
        app.activate()
        try? await Task.sleep(for: .milliseconds(250))
    }

    static let modifierFlags: [String: CGEventFlags] = [
        "control": .maskControl, "option": .maskAlternate, "shift": .maskShift, "command": .maskCommand,
    ]
    /// Arrow and navigation keys carry these on a real keyboard, and some
    /// system shortcuts (Mission Control's Control-Up) only answer when
    /// they're there.
    static let navigationKeys: Set<Int> = [115, 116, 117, 119, 121, 123, 124, 125, 126]

    static func flags(keyCode: Int, modifiers: [String]) -> CGEventFlags {
        var flags = modifiers.reduce(into: CGEventFlags()) { $0.insert(modifierFlags[$1] ?? []) }
        if navigationKeys.contains(keyCode) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        return flags
    }

    func press(keyCode: Int?, modifiers: [String]) async -> String? {
        guard let keyCode, (0...127).contains(keyCode) else { return "This key has no shortcut recorded yet" }
        if let missing = checkAccess() { return missing }
        await workAppInFront()
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = Self.flags(keyCode: keyCode, modifiers: modifiers)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
        return nil
    }

    /// Splits text into what's typed as characters, a few to an event, and
    /// returns and tabs, which go as their own keys since some apps ignore
    /// them as text.
    enum Typed: Equatable {
        case characters([UniChar])
        case key(Int)
    }

    static func typingPlan(_ text: String) -> [Typed] {
        var plan: [Typed] = []
        var run: [UniChar] = []
        func flush() {
            if !run.isEmpty { plan.append(.characters(run)) }
            run = []
        }
        for character in text {
            switch character {
            case "\n", "\r\n", "\r":
                flush()
                plan.append(.key(36))
            case "\t":
                flush()
                plan.append(.key(48))
            default:
                let units = Array(String(character).utf16)
                // A keyboard event holds about 20 UTF-16 units reliably.
                if run.count + units.count > 20 { flush() }
                run += units
            }
        }
        flush()
        return plan
    }

    func type(_ text: String) async -> String? {
        guard !text.isEmpty else { return nil }
        if let missing = checkAccess() { return missing }
        await workAppInFront()
        let plan = Self.typingPlan(text)
        await Task.detached {
            let source = CGEventSource(stateID: .hidSystemState)
            for step in plan {
                for down in [true, false] {
                    let code: Int
                    var units: [UniChar] = []
                    switch step {
                    case .characters(let characters):
                        code = 0
                        units = characters
                    case .key(let key):
                        code = key
                    }
                    guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
                    else { continue }
                    event.flags = []
                    if !units.isEmpty {
                        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    }
                    event.post(tap: .cghidEventTap)
                }
                usleep(6000)
            }
        }.value
        return nil
    }

    /// Media keys go as the keyboard's own keys, so they show the system's
    /// volume overlay and reach whichever app is playing.
    func pressMedia(_ key: MediaKey?) -> String? {
        guard let key else { return "That isn't a media key" }
        if let missing = checkAccess() { return missing }
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: (key.systemCode << 16) | (state << 8),
                data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        return nil
    }
}
