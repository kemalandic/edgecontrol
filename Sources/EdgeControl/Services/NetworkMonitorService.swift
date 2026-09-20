import Foundation

@MainActor
public final class NetworkMonitorService: ObservableObject {
    @Published public var downloadSpeed: Double = 0 // bytes/sec
    @Published public var uploadSpeed: Double = 0   // bytes/sec
    @Published public var totalDownloaded: UInt64 = 0
    @Published public var totalUploaded: UInt64 = 0

    /// Monotonic, so the rate is divided by the interval that actually
    /// elapsed rather than the one the timer was asked for.
    private var lastSampleNanos: UInt64 = 0
    private var previousIn: UInt64 = 0
    private var previousOut: UInt64 = 0
    private var hasPrevious = false
    private var timer: Timer?

    public init() {}

    public func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sample()
            }
        }
        timer?.tolerance = 0.2
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let (bytesIn, bytesOut) = readNetworkCounters()
        totalDownloaded = bytesIn
        totalUploaded = bytesOut

        let nowNanos = DispatchTime.now().uptimeNanoseconds
        let elapsed = ByteRate.elapsedSeconds(since: lastSampleNanos, now: nowNanos)

        if hasPrevious {
            downloadSpeed = ByteRate.perSecond(previous: previousIn, current: bytesIn, elapsed: elapsed)
            uploadSpeed = ByteRate.perSecond(previous: previousOut, current: bytesOut, elapsed: elapsed)
        }

        lastSampleNanos = nowNanos
        previousIn = bytesIn
        previousOut = bytesOut
        hasPrevious = true
    }

    private func readNetworkCounters() -> (UInt64, UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ptr = firstAddr
        while true {
            let name = String(cString: ptr.pointee.ifa_name)
            // Only count physical interfaces (en0 = Wi-Fi, en1-enX = Ethernet, etc.)
            if name.hasPrefix("en") || name.hasPrefix("bridge") {
                if let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self)
                    totalIn += UInt64(networkData.pointee.ifi_ibytes)
                    totalOut += UInt64(networkData.pointee.ifi_obytes)
                }
            }
            guard let next = ptr.pointee.ifa_next else { break }
            ptr = next
        }

        return (totalIn, totalOut)
    }
}

// MARK: - Formatting

extension NetworkMonitorService {

    public static func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        } else {
            return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
        }
    }
}
