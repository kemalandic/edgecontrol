import AppKit
import Foundation

public struct ProcessInfo_EC: Identifiable, Equatable {
    public let id: Int32          // pid
    public let name: String
    public let cpuPercent: Double
    public let memoryMB: Double
    public let icon: NSImage?
}

@MainActor
public final class ProcessMonitorService: ObservableObject {
    @Published public var topProcesses: [ProcessInfo_EC] = []

    private var timer: Timer?

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
            let processes = Self.fetchTopProcesses()
            await MainActor.run {
                self.topProcesses = processes
            }
        }
    }

    nonisolated private static func fetchTopProcesses() -> [ProcessInfo_EC] {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Aceo", "pid,pcpu,rss,comm"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var results: [ProcessInfo_EC] = []
        let lines = output.components(separatedBy: "\n").dropFirst() // skip header

        for line in lines {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4 else { continue }

            guard let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let rssKB = Double(parts[2]) else { continue }

            let name = String(parts[3])
                .components(separatedBy: "/").last ?? String(parts[3])

            // Skip system daemons and self
            if name.hasPrefix("(") || name == "ps" || name == "edgecontrol" || name == "EdgeControl" { continue }

            let memMB = rssKB / 1024.0

            // Get app icon
            let icon: NSImage? = {
                let workspace = NSWorkspace.shared
                if let app = workspace.runningApplications.first(where: { $0.processIdentifier == pid }) {
                    return app.icon
                }
                return nil
            }()

            results.append(ProcessInfo_EC(
                id: pid,
                name: name,
                cpuPercent: cpu,
                memoryMB: memMB,
                icon: icon
            ))
        }

        // Sort by CPU usage, take top 5
        return Array(results.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5))
    }
}
