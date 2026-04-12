import Combine
import Foundation
import WidgetKit

/// Observes main app services and writes snapshots to the shared App Group container.
/// Widget extension reads this data via WidgetData.read().
@MainActor
public final class WidgetDataBridge {
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []
    private var writeScheduled = false

    public init(model: AppModel) {
        self.model = model
    }

    public func start() {
        // Observe metrics changes (2s interval from SystemMetricsService)
        model.metricsService.$latest
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        // Observe temperature changes (3s interval from SMCService)
        model.smcService.$cpuTemperature
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        // Observe network changes
        model.networkService.$downloadSpeed
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        // Observe disk I/O changes
        model.diskIOService.$readBytesPerSec
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        // Observe WiFi changes (5s interval)
        model.wifiService.$ssid
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        // Observe CI/CD changes
        model.githubService.$runs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
    }

    /// Debounced write — max once every 30 seconds.
    private func scheduleWrite() {
        guard !writeScheduled else { return }
        writeScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            self.writeSnapshot()
            self.writeScheduled = false
        }
    }

    private func writeSnapshot() {
        let metrics = model.systemMetrics
        let smc = model.smcService
        let net = model.networkService
        let disk = model.diskIOService
        let wifi = model.wifiService
        let github = model.githubService

        let data = WidgetData(
            timestamp: Date(),
            cpuUsage: metrics?.cpuLoadPercent ?? 0,
            memoryUsage: metrics?.memoryUsedPercent ?? 0,
            memoryUsedGB: metrics?.memoryUsedGB ?? 0,
            memoryTotalGB: metrics?.memoryTotalGB ?? 0,
            cpuTemp: smc.cpuTemperature,
            gpuTemp: smc.gpuTemperature,
            ssdTemp: smc.ssdTemperature,
            diskReadRate: disk.readBytesPerSec,
            diskWriteRate: disk.writeBytesPerSec,
            networkUpRate: net.uploadSpeed,
            networkDownRate: net.downloadSpeed,
            wifiSSID: wifi.ssid,
            wifiSignalStrength: wifi.isConnected ? wifi.signalStrength : nil,
            wifiChannel: wifi.isConnected ? wifi.channel : nil,
            wifiBand: nil,
            cicdRuns: github.runs.prefix(10).map { run in
                WidgetCICDRun(
                    id: run.id,
                    repoName: run.repoName,
                    title: run.displayTitle,
                    status: run.status,
                    conclusion: run.conclusion,
                    url: run.url,
                    updatedAt: Date()
                )
            }
        )

        data.write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Force immediate write (called on app termination).
    public func flush() {
        writeSnapshot()
    }
}
