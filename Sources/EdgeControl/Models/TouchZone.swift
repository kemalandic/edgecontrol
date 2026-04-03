import CoreGraphics
import Foundation

/// A registered touch target with an action callback.
public struct TouchZone: Identifiable, Sendable {
    public let id: String
    public let frame: CGRect
    public let action: @Sendable () -> Void

    public init(id: String, frame: CGRect, action: @escaping @Sendable () -> Void) {
        self.id = id
        self.frame = frame
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

    public func register(id: String, frame: CGRect, action: @escaping @Sendable () -> Void) {
        zones.removeAll { $0.id == id }
        zones.append(TouchZone(id: id, frame: frame, action: action))
    }

    public func unregister(id: String) {
        zones.removeAll { $0.id == id }
    }

    /// Find the zone at a given point and execute its action.
    /// Returns true if a zone was hit.
    public func handleTap(at point: CGPoint) -> Bool {
        // Smallest zone wins (most specific target)
        let hit = zones
            .filter { $0.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }

        if let hit {
            hit.action()
            return true
        }
        return false
    }
}
