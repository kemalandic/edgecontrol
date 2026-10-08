import AppKit
import WebKit

/// Delivers touch to the dashboard window as the mouse and scroll events its
/// views already handle, without moving the pointer or bringing EdgeControl
/// forward over the app being worked in.
///
/// Points are in the dashboard's own coordinates: top-left origin, the size
/// of the window's content.
@MainActor
final class TouchEventInjector {
    weak var window: NSWindow?

    /// Where a scroll is going: a web view takes scroll events; native
    /// content scrolls by dragging (TouchScrollView), so it gets a drag.
    private enum ScrollTarget {
        case web(NSView)
        case drag
    }
    private var scrollTarget: ScrollTarget?

    func click(at point: CGPoint) {
        mouse(.leftMouseDown, at: point)
        mouse(.leftMouseUp, at: point)
    }

    func press(at point: CGPoint) { mouse(.leftMouseDown, at: point) }
    func drag(to point: CGPoint) { mouse(.leftMouseDragged, at: point) }
    func release(at point: CGPoint) { mouse(.leftMouseUp, at: point) }

    func beginScroll(at point: CGPoint) {
        if let hit = hitView(at: point), let web = Self.webView(containing: hit) {
            scrollTarget = .web(web)
            scrollWheel(phase: .began, dx: 0, dy: 0, at: point)
        } else {
            scrollTarget = .drag
            mouse(.leftMouseDown, at: point)
        }
    }

    func scroll(dx: CGFloat, dy: CGFloat, at point: CGPoint) {
        switch scrollTarget {
        case .web: scrollWheel(phase: .changed, dx: dx, dy: dy, at: point)
        case .drag: mouse(.leftMouseDragged, at: point)
        case nil: break
        }
    }

    func endScroll(at point: CGPoint) {
        switch scrollTarget {
        case .web: scrollWheel(phase: .ended, dx: 0, dy: 0, at: point)
        case .drag: mouse(.leftMouseUp, at: point)
        case nil: break
        }
        scrollTarget = nil
    }

    // MARK: - Events

    private func windowPoint(_ point: CGPoint) -> NSPoint? {
        guard let content = window?.contentView else { return nil }
        return content.convert(
            NSPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y), to: nil)
    }

    private func mouse(_ type: NSEvent.EventType, at point: CGPoint) {
        guard let window, let location = windowPoint(point),
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1)
        else { return }
        NSApp.sendEvent(event)
    }

    /// Scroll events can't be made for a window, only from a CGEvent, and one
    /// with no window reports its screen point as its window point. So it is
    /// placed where that reads as the right window point, and handed to the
    /// web view directly. Finger travel is content travel, as on a phone.
    private func scrollWheel(phase: CGScrollPhase, dx: CGFloat, dy: CGFloat, at point: CGPoint) {
        guard case .web(let target) = scrollTarget, let location = windowPoint(point),
            let cg = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(dy.rounded()),
                wheel2: Int32(dx.rounded()), wheel3: 0)
        else { return }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: location.x, y: primaryHeight - location.y)
        guard let event = NSEvent(cgEvent: cg) else { return }
        target.scrollWheel(with: event)
    }

    private func hitView(at point: CGPoint) -> NSView? {
        guard let content = window?.contentView, let location = windowPoint(point),
            let superview = content.superview ?? Optional(content)
        else { return nil }
        return content.hitTest(superview.convert(location, from: nil))
    }

    private static func webView(containing view: NSView) -> NSView? {
        var current: NSView? = view
        while let candidate = current {
            if candidate is WKWebView { return candidate }
            current = candidate.superview
        }
        return nil
    }
}
