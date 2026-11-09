import AppKit
import ApplicationServices

/// Moves other apps' windows out from behind the dashboard.
///
/// In kiosk mode the dashboard covers its display above every app window, so
/// a window that lands there can't be seen or reached. macOS puts windows
/// there more often than it seems it would: a new app opens on the display
/// last clicked, which is the dashboard's after any click on it; an app
/// reopens its windows where they were last closed; and windows that were on
/// the dashboard's display before it slept go back to it when it wakes. So
/// whenever an app comes forward or opens a window, and whenever the displays
/// change, any window on the dashboard's display moves to the display you're
/// using, centred there.
///
/// Moving another app's window takes the Accessibility permission. Without it
/// this does nothing.
@MainActor
public final class WindowRescueService: NSObject {
    /// The dashboard's frame while it covers its display, in AppKit screen
    /// coordinates; nil while it doesn't (window mode, hidden, parked).
    private let dashboardFrame: () -> CGRect?
    private var observers: [pid_t: AXObserver] = [:]
    public private(set) var isRunning = false

    public init(dashboardFrame: @escaping () -> CGRect?) {
        self.dashboardFrame = dashboardFrame
    }

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own prompt, which leads to the Accessibility list.
    public static func requestTrust() {
        // kAXTrustedCheckOptionPrompt's value; the constant is a C global
        // Swift 6 won't read.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        if !Self.isTrusted {
            AppLog.windows.notice("can't move windows from behind the dashboard: Accessibility isn't allowed")
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            workspace.addObserver(self, selector: #selector(appCameForward(_:)), name: name, object: nil)
        }
        workspace.addObserver(
            self, selector: #selector(appQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(sweepSoon), name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        // At launch neither the app nor the dashboard is ready yet.
        sweepSoon()
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
    }

    /// Checks every app's windows, for when something other than an app
    /// coming forward may have put one behind the dashboard.
    public func sweep() {
        guard isRunning else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            watch(app.processIdentifier)
            rescueWindows(of: app.processIdentifier)
        }
    }

    // MARK: - Where windows go

    /// Where a window that's behind the dashboard should go, or nil when it
    /// isn't behind it: centred in `target`, shrunk to fit. All three in the
    /// same coordinates.
    nonisolated static func destination(of window: CGRect, dashboard: CGRect, target: CGRect) -> CGRect? {
        guard dashboard.contains(CGPoint(x: window.midX, y: window.midY)) else { return nil }
        let width = min(window.width, target.width)
        let height = min(window.height, target.height)
        return CGRect(
            x: (target.midX - width / 2).rounded(), y: (target.midY - height / 2).rounded(), width: width,
            height: height)
    }

    /// The display you're using: the one under the pointer, unless that's
    /// the dashboard's, then the menu bar's, then any other.
    nonisolated static func targetScreen(pointer: CGPoint, screens: [CGRect], dashboard: CGRect) -> CGRect? {
        let free = screens.filter { !$0.contains(CGPoint(x: dashboard.midX, y: dashboard.midY)) }
        return free.first { $0.contains(pointer) } ?? free.first
    }

    // MARK: - Events

    @objc private func appCameForward(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let pid = app.processIdentifier
        watch(pid)
        rescueWindows(of: pid)
        // A launching app's first window appears a moment after it does.
        for delay in [0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.rescueWindows(of: pid) }
        }
    }

    @objc private func appQuit(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let observer = observers.removeValue(forKey: app.processIdentifier)
        else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// macOS puts windows back on a display when it returns, and the
    /// dashboard is placed again after a delay of its own.
    @objc private func sweepSoon() {
        for delay in [1.0, 3.0, 8.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.sweep() }
        }
    }

    /// Hears about windows an app opens while it's already in front.
    private func watch(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier, Self.isTrusted else { return }
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, refcon in
            var pid: pid_t = 0
            guard let refcon, AXUIElementGetPid(element, &pid) == .success else { return }
            let service = Unmanaged<WindowRescueService>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated {
                // Let the app finish placing it first.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { service.rescueWindows(of: pid) }
            }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        guard
            AXObserverAddNotification(
                observer, app, kAXWindowCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
                == .success
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func rescueWindows(of pid: pid_t) {
        guard isRunning, Self.isTrusted, dashboardFrame() != nil else { return }
        var value: CFTypeRef?
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return }
        windows.forEach(rescue)
    }

    // MARK: - Moving

    private func rescue(_ window: AXUIElement) {
        guard isRunning, let dashboard = dashboardFrame(), let primary = NSScreen.screens.first?.frame,
            Self.isMovable(window), let frame = Self.frame(of: window)
        else { return }
        // Accessibility measures from the top of the menu bar's display,
        // downwards; AppKit from its bottom, upwards.
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: primary.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let pointer = NSEvent.mouseLocation
        guard
            let target = Self.targetScreen(
                pointer: pointer, screens: NSScreen.screens.map(\.frame), dashboard: dashboard),
            let screen = NSScreen.screens.first(where: { $0.frame == target }),
            let destination = Self.destination(
                of: frame, dashboard: flipped(dashboard), target: flipped(screen.visibleFrame))
        else { return }

        if destination.size != frame.size { Self.set(kAXSizeAttribute, of: window, to: destination.size) }
        Self.set(kAXPositionAttribute, of: window, to: destination.origin)
        // Moving between displays can make an app adjust the size; settle it.
        if destination.size != frame.size { Self.set(kAXSizeAttribute, of: window, to: destination.size) }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "an app"
        AppLog.windows.notice(
            "moved \(app, privacy: .public)'s window from behind the dashboard to \(screen.localizedName, privacy: .public)"
        )
    }

    private static func isMovable(_ window: AXUIElement) -> Bool {
        let subrole = string(kAXSubroleAttribute, of: window)
        guard
            subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
                || subrole == kAXFloatingWindowSubrole
        else { return false }
        // A minimised window isn't behind anything; a full-screen one is its
        // own space and can't be moved.
        return bool(kAXMinimizedAttribute, of: window) != true && bool("AXFullScreen", of: window) != true
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = value(kAXPositionAttribute, of: window),
            AXValueGetValue(positionValue, .cgPoint, &position),
            let sizeValue = value(kAXSizeAttribute, of: window), AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func value(_ attribute: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ attribute: String, of element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func set(_ attribute: String, of window: AXUIElement, to point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(window, attribute as CFString, value)
    }

    private static func set(_ attribute: String, of window: AXUIElement, to size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, attribute as CFString, value)
    }
}
