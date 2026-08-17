import Combine
import Foundation
import WidgetKit

/// Observes main app services and writes snapshots to the shared App Group container.
/// Widget extension reads this data via WidgetData.read().
@MainActor
public final class WidgetDataBridge {
    private let model: AppModel
    private let layoutEngine: LayoutEngine
    private var cancellables: Set<AnyCancellable> = []
    private var writeScheduled = false

    public init(model: AppModel, layoutEngine: LayoutEngine) {
        self.model = model
        self.layoutEngine = layoutEngine
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
        model.cicdService.$runs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)

        // Settings carried in the snapshot, currently the unit system. Without
        // this the desktop widget keeps the old units until some unrelated
        // metric happens to move.
        layoutEngine.$document
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleWrite() }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
    }

    /// Serial so snapshots land in order; off-main because a wedged
    /// filesystem operation on the group container once froze the entire UI
    /// from a main-thread write here.
    private static let snapshotWriteQueue = DispatchQueue(
        label: "ai.pakslab.edgecontrol.widget-snapshot",
        qos: .utility
    )

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
        let cicd = model.cicdService

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
            cicdRuns: cicd.runs.prefix(10).map { run in
                WidgetCICDRun(
                    id: run.id,
                    hostLabel: run.hostLabel,
                    repoName: run.repositoryName,
                    title: run.title,
                    state: run.state,
                    url: run.url.absoluteString,
                    updatedAt: run.startedAt
                )
            },
            cicdStatusNote: Self.statusNote(
                runs: cicd.runs,
                accounts: model.accountStore.accounts,
                states: cicd.accountStates
            ),
            unitSystem: layoutEngine.document.globalSettings.units
        )

        // State is gathered on the main actor above; the file write goes to
        // a background queue so a slow or stuck disk can never block the UI.
        Self.snapshotWriteQueue.async {
            data.write()
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Force immediate write (called on app termination).
    public func flush() {
        writeSnapshot()
    }

    /// Why the desktop widget has no runs to show, phrased for the user.
    ///
    /// Shares `CICDWidgetState` with the in-app widget so both surfaces always
    /// agree — the desktop widget previously rendered blank space for every one
    /// of these cases.
    nonisolated static func statusNote(
        runs: [CIRun],
        accounts: [CIAccount],
        states: [UUID: CIAccountState]
    ) -> String? {
        switch CICDWidgetState.resolve(runs: runs, accounts: accounts, states: states) {
        case .noAccounts:
            return "No accounts configured"
        case .accountError(let host, let error):
            return "\(host) — \(error.widgetMessage)"
        case .empty:
            return "No recent runs"
        case .runs:
            return nil
        }
    }
}
