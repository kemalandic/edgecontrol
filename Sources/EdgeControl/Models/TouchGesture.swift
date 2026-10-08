import CoreGraphics
import Foundation

/// What a finger on the panel means, decided the way a system touch driver
/// decides it, so every widget gets the mouse and scroll events it already
/// understands. Plugins included: a web view has no touch zones, but it
/// knows what a click, a press, a drag and a scroll are.
///
/// - A finger that lifts before it moves or rests is a tap.
/// - One that moves within 300 ms and 8 points is a swipe. Sideways it pages
///   the dashboard; up or down it scrolls what's under it.
/// - One that rests first is a press: it holds what's under it, and drags it
///   as it moves. A slider, a long press, a widget in edit mode.
struct TouchGesture: Equatable {
    static let holdDelay: TimeInterval = 0.3
    static let moveThreshold: CGFloat = 8

    enum Event: Equatable {
        case tap(CGPoint)
        case pressBegan(CGPoint)
        case pressMoved(CGPoint)
        case pressEnded(CGPoint)
        case scrollBegan(CGPoint)
        case scrolled(dx: CGFloat, dy: CGFloat, at: CGPoint)
        case scrollEnded(CGPoint)
        /// Sideways travel from where the finger went down, while it pages.
        case paging(dx: CGFloat)
        case pageEnded(dx: CGFloat)
    }

    private enum Phase: Equatable {
        case idle
        case pending(start: CGPoint, since: TimeInterval)
        case pressing
        case scrolling(last: CGPoint)
        case paging(start: CGPoint)
    }

    private var phase = Phase.idle

    var isIdle: Bool { phase == .idle }

    mutating func began(at point: CGPoint, time: TimeInterval) -> [Event] {
        phase = .pending(start: point, since: time)
        return []
    }

    mutating func moved(to point: CGPoint, time: TimeInterval) -> [Event] {
        switch phase {
        case .idle:
            return []
        case .pending(let start, let since):
            let dx = point.x - start.x
            let dy = point.y - start.y
            // Rested, then moved before the hold timer came round.
            if time - since >= Self.holdDelay {
                phase = .pressing
                return [.pressBegan(start), .pressMoved(point)]
            }
            guard hypot(dx, dy) >= Self.moveThreshold else { return [] }
            if abs(dx) > abs(dy) * 1.5 {
                phase = .paging(start: start)
                return [.paging(dx: dx)]
            }
            phase = .scrolling(last: point)
            return [.scrollBegan(start), .scrolled(dx: dx, dy: dy, at: point)]
        case .pressing:
            return [.pressMoved(point)]
        case .scrolling(let last):
            phase = .scrolling(last: point)
            return [.scrolled(dx: point.x - last.x, dy: point.y - last.y, at: point)]
        case .paging(let start):
            return [.paging(dx: point.x - start.x)]
        }
    }

    /// The hold timer: a finger still resting after `holdDelay` presses.
    mutating func holdElapsed(time: TimeInterval) -> [Event] {
        guard case .pending(let start, let since) = phase, time - since >= Self.holdDelay else { return [] }
        phase = .pressing
        return [.pressBegan(start)]
    }

    mutating func ended(at point: CGPoint, time: TimeInterval) -> [Event] {
        defer { phase = .idle }
        switch phase {
        case .idle:
            return []
        case .pending(let start, let since):
            // A rest the timer didn't get to is still a press, not a tap.
            return time - since >= Self.holdDelay ? [.pressBegan(start), .pressEnded(point)] : [.tap(start)]
        case .pressing:
            return [.pressEnded(point)]
        case .scrolling:
            return [.scrollEnded(point)]
        case .paging(let start):
            return [.pageEnded(dx: point.x - start.x)]
        }
    }
}

/// The panel's own coordinates, mapped straight onto the dashboard, the way
/// the panel reports them: 0…16,383 across and 0…9,599 down on a XENEON
/// EDGE. No calibration is needed. A fingertip held "in the corner" sits
/// 30–40 points in from it, so calibrating by dwelling on corners skews the
/// map rather than correcting it.
struct PanelMapping: Equatable {
    var maxX: Int = 16_383
    var maxY: Int = 9_599

    func point(x: Int, y: Int, in size: CGSize) -> CGPoint {
        let nx = CGFloat(min(max(x, 0), maxX)) / CGFloat(max(1, maxX))
        let ny = CGFloat(min(max(y, 0), maxY)) / CGFloat(max(1, maxY))
        return CGPoint(x: nx * size.width, y: ny * size.height)
    }
}
