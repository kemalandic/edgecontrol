import Foundation
import IOBluetooth

public struct BTDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let isConnected: Bool
    public let deviceType: String
    public let batteryLevel: Int? // 0-100 if available

    public var icon: String {
        switch deviceType.lowercased() {
        case let t where t.contains("headphone") || t.contains("headset") || t.contains("airpod"): return "headphones"
        case let t where t.contains("keyboard"): return "keyboard"
        case let t where t.contains("mouse") || t.contains("trackpad"): return "computermouse"
        case let t where t.contains("speaker"): return "hifispeaker"
        case let t where t.contains("phone"): return "iphone"
        case let t where t.contains("watch"): return "applewatch"
        case let t where t.contains("gamepad") || t.contains("controller"): return "gamecontroller"
        default: return "wave.3.right"
        }
    }
}

@MainActor
public final class BluetoothService: ObservableObject {
    @Published public var devices: [BTDevice] = []
    @Published public var isAvailable: Bool = false

    private var timer: Timer?

    /// Dedicated utility-QoS queue for IOBluetooth calls. `IOBluetoothDevice
    /// .pairedDevices()` is synchronous and can block for several seconds —
    /// most painfully on the first call after wake/unlock, when
    /// `IOBluetoothCoreBluetoothCoordinator init` parks on a semaphore until
    /// CoreBluetooth finishes bringing the subsystem back up. Calling it on
    /// the main actor froze the UI = beachball-on-hover the user reported
    /// 2026-05-21. Keep IOBluetooth strictly on this queue.
    private static let bluetoothQueue = DispatchQueue(
        label: "dev.imaznation.edgecontrol.bluetooth",
        qos: .utility
    )

    public init() {}

    public func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
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
        Self.bluetoothQueue.async {
            // collectPairedDevices is nonisolated + returns Sendable values;
            // safe to call from a background dispatch queue, and the result
            // hops back to the main actor for the @Published assignment.
            let snapshot = Self.collectPairedDevices()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAvailable = snapshot.available
                self.devices = snapshot.devices
            }
        }
    }

    /// Background-thread helper: calls the blocking IOBluetooth API and
    /// extracts Sendable BTDevice values so nothing non-Sendable crosses
    /// actor boundaries. nonisolated so the enclosing @MainActor class
    /// doesn't pull this back onto the main thread.
    nonisolated private static func collectPairedDevices() -> (available: Bool, devices: [BTDevice]) {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return (false, [])
        }
        let list = pairedDevices.compactMap { device -> BTDevice? in
            guard let name = device.name, !name.isEmpty else { return nil }

            let deviceClass = device.deviceClassMajor
            let deviceType: String
            switch deviceClass {
            case 1: deviceType = "Computer"
            case 2: deviceType = "Phone"
            case 4: deviceType = "Audio/Headphone"
            case 5: deviceType = "Peripheral/Keyboard/Mouse"
            case 6: deviceType = "Camera"
            default: deviceType = "Other"
            }

            return BTDevice(
                id: device.addressString ?? "bt-\(name.hashValue)",
                name: name,
                isConnected: device.isConnected(),
                deviceType: deviceType,
                batteryLevel: nil
            )
        }
        .sorted { ($0.isConnected ? 0 : 1) < ($1.isConnected ? 0 : 1) }
        return (true, list)
    }
}
