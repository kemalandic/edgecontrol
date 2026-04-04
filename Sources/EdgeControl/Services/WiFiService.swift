import CoreWLAN
import Foundation

@MainActor
public final class WiFiService: ObservableObject {
    @Published public var ssid: String?
    @Published public var signalStrength: Int = 0 // rssi dBm
    @Published public var channel: Int = 0
    @Published public var txRate: Double = 0 // Mbps
    @Published public var security: String = ""
    @Published public var bssid: String?
    @Published public var isConnected: Bool = false

    private var timer: Timer?
    private let client = CWWiFiClient.shared()

    public init() {}

    public func start() {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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
        guard let interface = client.interface() else {
            isConnected = false
            return
        }

        ssid = interface.ssid()
        isConnected = ssid != nil
        signalStrength = interface.rssiValue()
        channel = interface.wlanChannel()?.channelNumber ?? 0
        txRate = interface.transmitRate()
        bssid = interface.bssid()

        security = securityString(interface.security())
    }

    private func securityString(_ security: CWSecurity) -> String {
        switch security {
        case .none: return "Open"
        case .WEP: return "WEP"
        case .wpaPersonal: return "WPA"
        case .wpa2Personal: return "WPA2"
        case .wpa3Personal: return "WPA3"
        case .wpaEnterprise: return "WPA-E"
        case .wpa2Enterprise: return "WPA2-E"
        case .wpa3Enterprise: return "WPA3-E"
        default: return "Unknown"
        }
    }

    /// Signal quality 0-100% from RSSI
    public var signalQuality: Int {
        let rssi = signalStrength
        if rssi >= -50 { return 100 }
        if rssi <= -100 { return 0 }
        return 2 * (rssi + 100)
    }

    /// Signal bar count (1-4)
    public var signalBars: Int {
        let q = signalQuality
        if q >= 75 { return 4 }
        if q >= 50 { return 3 }
        if q >= 25 { return 2 }
        return 1
    }
}
