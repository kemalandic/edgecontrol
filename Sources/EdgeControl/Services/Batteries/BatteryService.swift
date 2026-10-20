import Foundation

/// Battery levels for the Batteries widget: this Mac's every 5 seconds, so
/// plugging in shows straight away, and accessories' every 30, which is as
/// often as they change.
@MainActor
public final class BatteryService: ObservableObject {
    @Published public private(set) var readings: [BatteryReading] = []
    /// False until the first read, so the widget can wait rather than say
    /// there's nothing.
    @Published public private(set) var hasRead = false

    private var timer: Timer?
    private var ticks = 0
    private var accessories: [BatteryReading] = []

    /// System Information takes a moment, and the registry and power
    /// sources are IPC: none of it belongs on the main thread.
    private static let queue = DispatchQueue(label: "ai.pakslab.edgecontrol.batteries", qos: .utility)

    public init() {}

    public func start() {
        stop()
        ticks = 0
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        timer?.tolerance = 1
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let readAccessories = ticks % 6 == 0
        ticks += 1
        Self.queue.async { [weak self] in
            guard self != nil else { return }
            let power = BatteryReader.powerSources()
            let accessories =
                readAccessories ? BatteryReader.registryAccessories() + BatteryReader.bluetoothReport() : nil
            Task { @MainActor in
                guard let self else { return }
                if let accessories { self.accessories = accessories }
                let merged = BatteryReader.merge(power, self.accessories)
                if merged != self.readings { self.readings = merged }
                self.hasRead = true
            }
        }
    }
}
