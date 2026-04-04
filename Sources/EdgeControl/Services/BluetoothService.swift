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
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            isAvailable = false
            return
        }

        isAvailable = true
        devices = pairedDevices.compactMap { device in
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
                id: device.addressString ?? UUID().uuidString,
                name: name,
                isConnected: device.isConnected(),
                deviceType: deviceType,
                batteryLevel: nil
            )
        }
        .sorted { ($0.isConnected ? 0 : 1) < ($1.isConnected ? 0 : 1) }
    }
}
