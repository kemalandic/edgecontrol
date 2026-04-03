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
    }

    public func stop() {
        metricsService.stop()
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
