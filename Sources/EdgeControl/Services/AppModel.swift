import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published public var availableDisplays: [DisplayDescriptor] = []
    @Published public var selectedDisplay: DisplayDescriptor?
    @Published public var selectedDisplayName: String?
    @Published public var systemMetrics: SystemMetrics?
    @Published public var currentPage: Int = 0
    public var metricsPerCore: [CoreUsage] { metricsService.perCoreUsage }

    public let weatherService = WeatherDataService()
    public let networkService = NetworkMonitorService()
    public let processService = ProcessMonitorService()
    public let touchService = HardwareTouchService()
    public let smcService = SMCService()
    public let diskIOService = DiskIOService()
    public let nowPlayingService = NowPlayingService()
    public let audioService = AudioService()
    public let wifiService = WiFiService()
    public let bluetoothService = BluetoothService()
    public let githubService = GitHubService()
    public var widgetDataBridge: WidgetDataBridge?
    public var pluginWidgetRenderer: PluginWidgetRenderer?
    private let displayManager: DisplayManager
    public let metricsService: SystemMetricsService
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    /// Currently active services — only these have running timers.
    private var activeServices: Set<ServiceKey> = []

    /// Stagger offset counter for timer coordination.
    private var staggerIndex = 0

    public init(selectedDisplayName: String? = nil) {
        self.displayManager = DisplayManager()
        self.metricsService = SystemMetricsService()
        self.selectedDisplayName = selectedDisplayName

        metricsService.$latest
            .receive(on: RunLoop.main)
            .sink { [weak self] metrics in
                self?.systemMetrics = metrics
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshDisplays()
            }
            .store(in: &cancellables)
    }

    public func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshDisplays()

        // Always start metrics (needed for system health) and touch (needed for input)
        metricsService.start()
        touchService.start()

        // React to touch swipes for page changes
        touchService.$swipeDirection
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] direction in
                guard let self else { return }
                switch direction {
                case .left:
                    self.currentPage += 1
                case .right:
                    if self.currentPage > 0 { self.currentPage -= 1 }
                }
                self.touchService.consumeSwipe()
            }
            .store(in: &cancellables)

        // Note: other services are started on-demand via updateActiveServices()
    }

    public func stop() {
        metricsService.stop()
        touchService.stop()
        // Stop all active services
        for key in activeServices {
            service(for: key)?.stop()
        }
        activeServices.removeAll()
    }

    // MARK: - Lazy Service Activation

    /// Update which services are running based on which widgets are placed on the dashboard.
    /// Called when layout changes (widget add/remove/enable/disable).
    public func updateActiveServices(neededServices: Set<ServiceKey>) {
        let toStart = neededServices.subtracting(activeServices)
        let toStop = activeServices.subtracting(neededServices)

        // Stop unneeded services
        for key in toStop {
            service(for: key)?.stop()
            activeServices.remove(key)
        }

        // Start needed services with staggered delays to avoid CPU spikes
        // Insert into activeServices immediately to prevent double-start on rapid calls
        let sortedKeys = toStart.sorted(by: { $0.rawValue < $1.rawValue })
        for key in sortedKeys {
            activeServices.insert(key)
        }
        for (index, key) in sortedKeys.enumerated() {
            let delay = Double(index) * 0.15
            if delay > 0 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                    self.service(for: key)?.start()
                }
            } else {
                service(for: key)?.start()
            }
        }
    }

    /// Resolve ServiceKey to the actual service instance.
    private func service(for key: ServiceKey) -> (any ServiceLifecycle)? {
        switch key {
        case .metrics: return metricsService
        case .smc: return smcService
        case .network: return networkService
        case .wifi: return wifiService
        case .bluetooth: return bluetoothService
        case .nowPlaying: return nowPlayingService
        case .audio: return audioService
        case .weather: return weatherService
        case .diskIO: return diskIOService
        case .process: return processService
        case .github: return githubService
        }
    }

    // MARK: - Display Management

    public func refreshDisplays() {
        availableDisplays = displayManager.availableDisplays()

        // Select display: prefer saved name, fallback to first non-main, then main
        let selected = displayManager.selectedScreen(name: selectedDisplayName)
        selectedDisplay = availableDisplays.first { $0.name == selected?.localizedName }
        if selectedDisplay == nil {
            selectedDisplay = availableDisplays.first
        }
        selectedDisplayName = selectedDisplay?.name
    }
}

// MARK: - Service Lifecycle Protocol

/// All services that can be lazily activated must conform to this.
@MainActor
public protocol ServiceLifecycle: AnyObject {
    func start()
    func stop()
}

extension SystemMetricsService: ServiceLifecycle {}
extension SMCService: ServiceLifecycle {}
extension NetworkMonitorService: ServiceLifecycle {}
extension WiFiService: ServiceLifecycle {}
extension BluetoothService: ServiceLifecycle {}
extension NowPlayingService: ServiceLifecycle {}
extension AudioService: ServiceLifecycle {}
extension WeatherDataService: ServiceLifecycle {}
extension DiskIOService: ServiceLifecycle {}
extension ProcessMonitorService: ServiceLifecycle {}
extension GitHubService: ServiceLifecycle {}
