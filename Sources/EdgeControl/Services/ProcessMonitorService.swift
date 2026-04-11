import AppKit
import Foundation

public struct ProcessInfo_EC: Identifiable, Equatable {
    public let id: Int32          // pid
    public let name: String
    public let cpuPercent: Double
    public let memoryMB: Double
    public var icon: NSImage?
}

/// Raw process snapshot without icons or CPU delta — produced off-main-actor.
private struct RawProcessSnapshot: Sendable {
    let pid: Int32
    let name: String
    let totalCPUTime: UInt64
    let memoryMB: Double
    let sampleTime: UInt64
}

@MainActor
public final class ProcessMonitorService: ObservableObject {
    @Published public var topProcesses: [ProcessInfo_EC] = []

    private var timer: Timer?
    private var iconCache: [Int32: NSImage] = [:]

    /// Previous CPU time per PID — MainActor-isolated, no data race.
    private var previousCPUTime: [Int32: UInt64] = [:]
    private var previousSampleTime: UInt64 = 0

    public init() {}

    public func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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
        Task.detached {
            let snapshots = Self.fetchRawSnapshots()
            await MainActor.run {
                self.processSnapshots(snapshots)
            }
        }
    }

    /// Process raw snapshots on MainActor: compute CPU delta, resolve icons, publish.
    private func processSnapshots(_ snapshots: [RawProcessSnapshot]) {
        // Calculate elapsed time
        let elapsedNs: UInt64
        if let first = snapshots.first, previousSampleTime > 0 {
            var timebaseInfo = mach_timebase_info_data_t()
            mach_timebase_info(&timebaseInfo)
            let rawElapsed = first.sampleTime - previousSampleTime
            elapsedNs = rawElapsed * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        } else {
            elapsedNs = 0
        }

        // Build results with delta-based CPU percentage
        var results: [ProcessInfo_EC] = []
        var newCPUTime: [Int32: UInt64] = [:]

        for snap in snapshots {
            newCPUTime[snap.pid] = snap.totalCPUTime

            let cpuPercent: Double
            if elapsedNs > 0, let prevTime = previousCPUTime[snap.pid] {
                let delta = snap.totalCPUTime > prevTime ? snap.totalCPUTime - prevTime : 0
                cpuPercent = (Double(delta) / Double(elapsedNs)) * 100.0
            } else {
                cpuPercent = 0
            }

            results.append(ProcessInfo_EC(
                id: snap.pid,
                name: snap.name,
                cpuPercent: cpuPercent,
                memoryMB: snap.memoryMB,
                icon: nil
            ))
        }

        // Update stored state for next delta
        previousCPUTime = newCPUTime
        if let first = snapshots.first {
            previousSampleTime = first.sampleTime
        }

        // Sort, take top 5, resolve icons
        let top5 = Array(results.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
        resolveIcons(for: top5)
    }

    /// Resolve app icons on MainActor.
    private func resolveIcons(for processes: [ProcessInfo_EC]) {
        let runningApps = NSWorkspace.shared.runningApplications
        var resolved: [ProcessInfo_EC] = []
        for var proc in processes {
            if let cached = iconCache[proc.id] {
                proc.icon = cached
            } else if let app = runningApps.first(where: { $0.processIdentifier == proc.id }) {
                proc.icon = app.icon
                if let ic = proc.icon { iconCache[proc.id] = ic }
            }
            resolved.append(proc)
        }
        if iconCache.count > 200 {
            let livePids = Set(resolved.map(\.id))
            iconCache = iconCache.filter { livePids.contains($0.key) }
        }
        topProcesses = resolved
    }

    /// Fetch raw process data off-main-actor. Pure function — no shared mutable state.
    nonisolated private static func fetchRawSnapshots() -> [RawProcessSnapshot] {
        var pids = [pid_t](repeating: 0, count: 1024)
        let bytesUsed = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        let pidCount = Int(bytesUsed) / MemoryLayout<pid_t>.size
        let now = mach_absolute_time()

        var snapshots: [RawProcessSnapshot] = []

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let infoSize = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            guard infoSize > 0 else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            if name.isEmpty { continue }
            if name.hasPrefix("(") || name == "EdgeControl" { continue }

            snapshots.append(RawProcessSnapshot(
                pid: pid,
                name: name,
                totalCPUTime: taskInfo.pti_total_user + taskInfo.pti_total_system,
                memoryMB: Double(taskInfo.pti_resident_size) / (1024.0 * 1024.0),
                sampleTime: now
            ))
        }

        return snapshots
    }
}
