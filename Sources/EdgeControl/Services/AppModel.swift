import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
public final class AppModel: ObservableObject {
    @Published public var settings: AppSettings
    @Published public var availableDisplays: [DisplayDescriptor] = []
    @Published public var selectedDisplay: DisplayDescriptor?
    @Published public var systemMetrics: SystemMetrics?
    @Published public var isDevKitMode = false
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

    private let settingsStore: SettingsStore
    private let displayManager: DisplayManager
    private let metricsService: SystemMetricsService
    private var hasStarted = false
    private var cancellables: Set<AnyCancellable> = []

    public init() {
        let store = SettingsStore()
        self.settingsStore = store
        self.displayManager = DisplayManager()
        self.metricsService = SystemMetricsService()
        self.settings = store.load()

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
        metricsService.start()
        weatherService.start()
        networkService.start()
        processService.start()
        smcService.start()
        diskIOService.start()
        nowPlayingService.start()
        audioService.start()
        wifiService.start()
        bluetoothService.start()
        if !isDevKitMode {
            touchService.start()
        }

        // React to touch swipes for page changes
        touchService.$swipeDirection
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] direction in
                guard let self else { return }
                switch direction {
                case .left:
                    if self.currentPage < 6 { self.currentPage += 1 }
                case .right:
                    if self.currentPage > 0 { self.currentPage -= 1 }
                }
                self.touchService.consumeSwipe()
            }
            .store(in: &cancellables)
    }

    public func stop() {
        metricsService.stop()
        weatherService.stop()
        networkService.stop()
        processService.stop()
        touchService.stop()
        smcService.stop()
        diskIOService.stop()
        nowPlayingService.stop()
        audioService.stop()
        wifiService.stop()
        bluetoothService.stop()
    }

    public func refreshDisplays() {
        availableDisplays = displayManager.availableDisplays()
        let xeneonScreen = displayManager.xeneonScreen()
        isDevKitMode = xeneonScreen == nil

        let selected = displayManager.selectedScreen(for: settings)
        let selectedID = selected?.displayIdentifier
        selectedDisplay = availableDisplays.first { $0.id == selectedID }

        if settings.selectedDisplayID == nil, !isDevKitMode {
            settings.selectedDisplayID = selectedDisplay?.id
            saveSettings()
        }
    }

    public func saveSettings() {
        settingsStore.save(settings)
    }
}
