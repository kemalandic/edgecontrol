import Foundation

@MainActor
public final class DiskIOService: ObservableObject {
    @Published public var readBytesPerSec: Double = 0
    @Published public var writeBytesPerSec: Double = 0
    @Published public var readHistory: [Double] = []
    @Published public var writeHistory: [Double] = []

    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var hasPrevious = false
    private var timer: Timer?
    private let maxHistory = 60

    public init() {}

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
        let (read, write) = readDiskCounters()

        if hasPrevious {
            let deltaRead = read >= previousRead ? read - previousRead : 0
            let deltaWrite = write >= previousWrite ? write - previousWrite : 0
            readBytesPerSec = Double(deltaRead) / 2.0
            writeBytesPerSec = Double(deltaWrite) / 2.0

            readHistory.append(readBytesPerSec)
            writeHistory.append(writeBytesPerSec)
            if readHistory.count > maxHistory { readHistory.removeFirst() }
            if writeHistory.count > maxHistory { writeHistory.removeFirst() }
        }

        previousRead = read
        previousWrite = write
        hasPrevious = true
    }

    private func readDiskCounters() -> (UInt64, UInt64) {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/iostat")
        process.arguments = ["-d", "-c", "1"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (previousRead, previousWrite)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return (previousRead, previousWrite)
        }

        // Parse iostat output — KB/t, tps, MB/s columns
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 3 else { return (previousRead, previousWrite) }

        let dataLine = lines.last ?? ""
        let parts = dataLine.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)

        // iostat -d: KB/t  tps  MB/s
        guard parts.count >= 3 else { return (previousRead, previousWrite) }

        let mbPerSec = Double(parts[2]) ?? 0
        // Approximate read vs write — iostat -d doesn't split them
        // Use total as read estimate, write comes from delta
        let totalBytes = UInt64(mbPerSec * 1024 * 1024 * 2) // 2 second interval

        return (previousRead + totalBytes / 2, previousWrite + totalBytes / 2)
    }

    public static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 {
            return String(format: "%.0f B/s", bytesPerSec)
        } else if bytesPerSec < 1024 * 1024 {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        } else if bytesPerSec < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else {
            return String(format: "%.2f GB/s", bytesPerSec / (1024 * 1024 * 1024))
        }
    }
}
