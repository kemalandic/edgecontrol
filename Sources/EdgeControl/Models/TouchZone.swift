import CoreGraphics
import Foundation

/// A registered touch target with an action callback.
public struct TouchZone: Identifiable, Sendable {
    public let id: String
    public let frame: CGRect
    /// Zones drawn over the dashboard, like a camera opened full screen, sit
    /// on a higher layer. While any are registered, the zones beneath them
    /// can't be hit, as the mouse can't click through the view on top.
    public let layer: Int
    public let action: @Sendable () -> Void

    public init(id: String, frame: CGRect, layer: Int = 0, action: @escaping @Sendable () -> Void) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.action = action
    }

    public func contains(_ point: CGPoint) -> Bool {
        frame.contains(point)
    }
}

/// Registry that holds all active touch zones.
@MainActor
public final class TouchZoneRegistry: ObservableObject {
    @Published public var zones: [TouchZone] = []

    public init() {}

    public func register(id: String, frame: CGRect, layer: Int = 0, action: @escaping @Sendable () -> Void) {
        zones.removeAll { $0.id == id }
        zones.append(TouchZone(id: id, frame: frame, layer: layer, action: action))
    }

    /// The highest layer with a zone on it: 0 unless something is drawn over the dashboard.
    public var topLayer: Int { zones.map(\.layer).max() ?? 0 }

    public func unregister(id: String) {
        zones.removeAll { $0.id == id }
    }

    /// Find the zone at a given point and execute its action.
    /// Returns true if a zone was hit.
    public func handleTap(at point: CGPoint) -> Bool {
        // Only the top layer can be hit; within it, the smallest zone wins
        // (most specific target).
        let top = topLayer
        let hit =
            zones
            .filter { $0.layer == top && $0.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }

        if let hit {
            hit.action()
            return true
        }
        return false
    }
}
