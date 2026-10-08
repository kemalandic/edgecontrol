import CoreGraphics
import Foundation

/// Whether a finger on the panel is paging the dashboard or holding
/// something.
///
/// A page swipe moves sideways straight away. A finger that rests first is
/// holding: pressing and dragging a control inside a widget, a slider say.
/// The system touch driver that many XENEON EDGE owners run draws the same
/// line, at the same 300 ms and 8 points, and turns a held finger into a
/// mouse drag; paging the dashboard as well would move it out from under
/// that drag.
struct SwipeIntent: Equatable {
    static let holdDelay: TimeInterval = 0.3
    static let stillRadius: CGFloat = 8

    private(set) var isHold = false
    private var moved = false

    /// Call with every sample while the finger is down.
    mutating func track(distanceFromStart: CGFloat, elapsed: TimeInterval) {
        guard !moved, !isHold else { return }
        if elapsed >= Self.holdDelay {
            isHold = true
        } else if distanceFromStart >= Self.stillRadius {
            moved = true
        }
    }
}
