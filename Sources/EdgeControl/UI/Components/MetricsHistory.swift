import Foundation
import SwiftUI

/// Shared history buffer for CPU and memory graphs.
/// Records normalized values (0-1) from SystemMetrics.
/// Widgets read from here for time-series display.
@MainActor
public final class MetricsHistory: ObservableObject {
    @Published public var cpuHistory: [Double] = []
    @Published public var memoryHistory: [Double] = []
    public let maxPoints: Int

    public init(maxPoints: Int = 120) {
        self.maxPoints = maxPoints
    }

    public func record(cpu: Double, memory: Double) {
        cpuHistory.append(cpu / 100)
        memoryHistory.append(memory / 100)
        if cpuHistory.count > maxPoints { cpuHistory.removeFirst() }
        if memoryHistory.count > maxPoints { memoryHistory.removeFirst() }
    }
}
