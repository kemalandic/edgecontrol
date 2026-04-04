import AppKit
import SwiftUI

/// Page 6: WiFi + Bluetooth + Audio
struct ConnectivityPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            wifiPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            divider()

            bluetoothPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            divider()

            audioPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func divider() -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
            .frame(width: 1).padding(.vertical, 20)
    }

    // MARK: - WiFi

    private func wifiPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentCyan).frame(width: 10, height: 10)
                Text("WI-FI")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Image(systemName: model.wifiService.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 22))
                    .foregroundStyle(model.wifiService.isConnected ? Theme.accentGreen : Theme.accentRed)
            }

            if model.wifiService.isConnected {
                // SSID
                VStack(spacing: 4) {
                    Text(model.wifiService.ssid ?? "Unknown")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    Text("CONNECTED")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accentGreen)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))

                // Signal strength bars
                HStack(spacing: 4) {
                    ForEach(1...4, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(bar <= model.wifiService.signalBars ? Theme.accentCyan : Color.white.opacity(0.10))
                            .frame(width: 24, height: CGFloat(bar) * 12 + 8)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(model.wifiService.signalQuality)%")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accentCyan)
                        Text("SIGNAL")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(14)
                .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))

                // Details
                VStack(spacing: 6) {
                    wifiRow(label: "Channel", value: "\(model.wifiService.channel)")
                    wifiRow(label: "Speed", value: String(format: "%.0f Mbps", model.wifiService.txRate))
                    wifiRow(label: "Security", value: model.wifiService.security)
                    wifiRow(label: "RSSI", value: "\(model.wifiService.signalStrength) dBm")
                }
                .padding(12)
                .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("NOT CONNECTED")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func wifiRow(label: String, value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
    }

    // MARK: - Bluetooth

    private func bluetoothPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentBlue).frame(width: 10, height: 10)
                Text("BLUETOOTH")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(model.bluetoothService.devices.filter(\.isConnected).count) CONNECTED")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            if model.bluetoothService.devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textTertiary)
                    Text("NO DEVICES")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(model.bluetoothService.devices) { device in
                            btDeviceRow(device)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func btDeviceRow(_ device: BTDevice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: device.icon)
                .font(.system(size: 22))
                .foregroundStyle(device.isConnected ? Theme.accentBlue : Theme.textTertiary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(device.isConnected ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                Text(device.isConnected ? "Connected" : "Not Connected")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(device.isConnected ? Theme.accentGreen : Theme.textTertiary)
            }

            Spacer()

            Circle()
                .fill(device.isConnected ? Theme.accentGreen : Color.white.opacity(0.15))
                .frame(width: 10, height: 10)
        }
        .padding(12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))
    }

    // MARK: - Audio

    private func audioPanel() -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentPurple).frame(width: 10, height: 10)
                Text("AUDIO")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            // Volume display
            VStack(spacing: 8) {
                Image(systemName: model.audioService.isMuted ? "speaker.slash.fill" : volumeIcon(model.audioService.volume))
                    .font(.system(size: 56))
                    .foregroundStyle(model.audioService.isMuted ? Theme.accentRed : Theme.accentPurple)

                Text(model.audioService.isMuted ? "MUTED" : "\(Int(model.audioService.volume * 100))%")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                Text("VOLUME")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))

            // Volume control buttons
            HStack(spacing: 10) {
                TouchButton(
                    id: "vol_down",
                    label: "−",
                    isActive: false,
                    activeColor: Theme.accentPurple,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.audioService.volumeDown()
                }

                // Volume bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [Theme.accentCyan, Theme.accentPurple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(model.audioService.volume))
                    }
                }
                .frame(height: 16)

                TouchButton(
                    id: "vol_up",
                    label: "+",
                    isActive: false,
                    activeColor: Theme.accentPurple,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.audioService.volumeUp()
                }
            }

            // Mute button
            TouchButton(
                id: "mute_toggle",
                label: model.audioService.isMuted ? "🔇 UNMUTE" : "🔊 MUTE",
                isActive: model.audioService.isMuted,
                activeColor: Theme.accentRed,
                registry: model.touchService.zoneRegistry
            ) {
                model.audioService.toggleMute()
            }

            // Output device
            HStack(spacing: 10) {
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accentPurple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OUTPUT DEVICE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Text(model.audioService.outputDeviceName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func volumeIcon(_ vol: Float) -> String {
        if vol <= 0 { return "speaker.fill" }
        if vol < 0.33 { return "speaker.wave.1.fill" }
        if vol < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
