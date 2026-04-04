import Darwin.Mach
import Foundation
import Metal

public struct CoreUsage: Identifiable, Equatable {
    public let id: Int
    public let usage: Double // 0-100
}

@MainActor
public final class SystemMetricsService: ObservableObject {
    @Published public private(set) var latest: SystemMetrics?
    @Published public var perCoreUsage: [CoreUsage] = []

    private let cpuBrand: String
    private let performanceCoreCount: Int
    private let efficiencyCoreCount: Int
    private let gpuName: String
    private let totalMemoryGB: Double
    private var previousCPUInfo = host_cpu_load_info()
    private var hasPreviousCPUInfo = false
    private var previousPerCore: [processor_cpu_load_info]?
    private var timer: Timer?

    public init() {
        self.cpuBrand = Self.readStringSysctl("machdep.cpu.brand_string") ?? "Unknown CPU"
        self.performanceCoreCount = Self.readIntSysctl("hw.perflevel0.physicalcpu") ?? 0
        self.efficiencyCoreCount = Self.readIntSysctl("hw.perflevel1.physicalcpu") ?? 0
        self.gpuName = MTLCreateSystemDefaultDevice()?.name ?? "Unknown GPU"
        self.totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    public func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let cpuLoadPercent = currentCPULoadPercent()
        let memory = currentMemorySnapshot()
        let storage = currentStorageSnapshot()
        perCoreUsage = currentPerCoreUsage()
        latest = SystemMetrics(
            cpuLoadPercent: cpuLoadPercent,
            memoryUsedPercent: memory.usedPercent,
            memoryUsedGB: memory.usedGB,
            memoryTotalGB: totalMemoryGB,
            memoryPressurePercent: memory.pressurePercent,
            swapUsedMB: memory.swapUsedMB,
            storageUsedPercent: storage.usedPercent,
            storageUsedGB: storage.usedGB,
            storageTotalGB: storage.totalGB,
            uptimeSeconds: ProcessInfo.processInfo.systemUptime,
            cpuBrand: cpuBrand,
            performanceCoreCount: performanceCoreCount,
            efficiencyCoreCount: efficiencyCoreCount,
            gpuName: gpuName,
            thermalState: thermalStateDescription(ProcessInfo.processInfo.thermalState),
            collectedAt: .now
        )
    }

    private func currentCPULoadPercent() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return latest?.cpuLoadPercent ?? 0 }

        if !hasPreviousCPUInfo {
            previousCPUInfo = info
            hasPreviousCPUInfo = true
            return latest?.cpuLoadPercent ?? 0
        }

        let user = Double(info.cpu_ticks.0 - previousCPUInfo.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 - previousCPUInfo.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 - previousCPUInfo.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 - previousCPUInfo.cpu_ticks.3)
        previousCPUInfo = info
        let total = user + system + idle + nice
        guard total > 0 else { return latest?.cpuLoadPercent ?? 0 }
        return ((user + system + nice) / total) * 100
    }

    private func currentMemorySnapshot() -> (usedPercent: Double, usedGB: Double, pressurePercent: Double, swapUsedMB: Double) {
        var rawPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &rawPageSize)
        let pageSize = Double(rawPageSize)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let usedPercent: Double
        let pressurePercent: Double
        let usedGB: Double
        if result == KERN_SUCCESS {
            let freePages = Double(stats.free_count + stats.speculative_count)
            let usedBytes = Double(ProcessInfo.processInfo.physicalMemory) - (freePages * pageSize)
            usedGB = max(0, usedBytes / (1024 * 1024 * 1024))
            usedPercent = min(max((usedGB / totalMemoryGB) * 100, 0), 100)
            pressurePercent = min(max(100 - ((freePages * pageSize) / Double(ProcessInfo.processInfo.physicalMemory) * 100), 0), 100)
        } else {
            usedGB = latest?.memoryUsedGB ?? 0
            usedPercent = latest?.memoryUsedPercent ?? 0
            pressurePercent = latest?.memoryPressurePercent ?? 0
        }

        let swap = currentSwapUsedMB() ?? latest?.swapUsedMB ?? 0
        return (usedPercent, usedGB, pressurePercent, swap)
    }

    private func currentStorageSnapshot() -> (usedPercent: Double, usedGB: Double, totalGB: Double) {
        let root = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? root.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return (latest?.storageUsedPercent ?? 0, latest?.storageUsedGB ?? 0, latest?.storageTotalGB ?? 0)
        }
        let totalGB = Double(Int64(total)) / (1024 * 1024 * 1024)
        let usedGB = Double(Int64(total) - Int64(available)) / (1024 * 1024 * 1024)
        return (min(max((usedGB / max(totalGB, 0.001)) * 100, 0), 100), usedGB, totalGB)
    }

    private func currentSwapUsedMB() -> Double? {
        var xsw = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let result = "vm.swapusage".withCString { sysctlbyname($0, &xsw, &size, nil, 0) }
        guard result == 0 else { return nil }
        return Double(xsw.xsu_used) / (1024 * 1024)
    }

    private func thermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }

    private static func readStringSysctl(_ key: String) -> String? {
        var size = 0
        guard key.withCString({ sysctlbyname($0, nil, &size, nil, 0) }) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard key.withCString({ sysctlbyname($0, &buffer, &size, nil, 0) }) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func readIntSysctl(_ key: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = key.withCString { sysctlbyname($0, &value, &size, nil, 0) }
        return result == 0 ? Int(value) : nil
    }

    private func currentPerCoreUsage() -> [CoreUsage] {
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUs: natural_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &cpuInfoCount)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return [] }

        defer {
            let size = vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var currentInfo: [processor_cpu_load_info] = []
        for i in 0..<Int(numCPUs) {
            let offset = Int(CPU_STATE_MAX) * i
            let user = UInt32(info[offset + Int(CPU_STATE_USER)])
            let system = UInt32(info[offset + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(info[offset + Int(CPU_STATE_IDLE)])
            let nice = UInt32(info[offset + Int(CPU_STATE_NICE)])
            var loadInfo = processor_cpu_load_info()
            loadInfo.cpu_ticks.0 = user
            loadInfo.cpu_ticks.1 = system
            loadInfo.cpu_ticks.2 = idle
            loadInfo.cpu_ticks.3 = nice
            currentInfo.append(loadInfo)
        }

        var usages: [CoreUsage] = []
        if let prev = previousPerCore, prev.count == currentInfo.count {
            for i in 0..<currentInfo.count {
                let user = Double(currentInfo[i].cpu_ticks.0 - prev[i].cpu_ticks.0)
                let system = Double(currentInfo[i].cpu_ticks.1 - prev[i].cpu_ticks.1)
                let idle = Double(currentInfo[i].cpu_ticks.2 - prev[i].cpu_ticks.2)
                let nice = Double(currentInfo[i].cpu_ticks.3 - prev[i].cpu_ticks.3)
                let total = user + system + idle + nice
                let usage = total > 0 ? ((user + system + nice) / total) * 100 : 0
                usages.append(CoreUsage(id: i, usage: usage))
            }
        }

        previousPerCore = currentInfo
        return usages
    }
}
