import Foundation

public struct SystemMetrics: Equatable, Sendable {
    public let cpuLoadPercent: Double
    public let memoryUsedPercent: Double
    public let memoryUsedGB: Double
    public let memoryTotalGB: Double
    public let memoryPressurePercent: Double
    public let swapUsedMB: Double
    public let storageUsedPercent: Double
    public let storageUsedGB: Double
    public let storageTotalGB: Double
    public let uptimeSeconds: Double
    public let cpuBrand: String
    public let performanceCoreCount: Int
    public let efficiencyCoreCount: Int
    public let gpuName: String
    public let thermalState: String
    public let collectedAt: Date
}
