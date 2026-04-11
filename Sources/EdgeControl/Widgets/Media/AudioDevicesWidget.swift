import SwiftUI

public final class AudioDevicesWidget: DashboardWidget {
    public let widgetId = "audio-devices"
    public let displayName = "Audio"
    public let description = "Current audio output device with volume control"
    public let iconName = "speaker.wave.2"
    public let category: WidgetCategory = .media
    public let requiredServices: Set<ServiceKey> = [.audio]
    public let supportedSizes = WidgetSizeRange(min: .size(3, 2), max: .size(6, 4))
    public let defaultSize = WidgetSize.size(4, 3)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showVolume", label: "Show Volume", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    private let service: AudioService

    public init(service: AudioService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        AudioDevicesWidgetView(
            service: service,
            showVolume: config.bool("showVolume", default: true),
            isCompact: size.height <= 2
        )
    }
}

private struct AudioDevicesWidgetView: View {
    @ObservedObject var service: AudioService
    @Environment(\.themeSettings) private var ts
    let showVolume: Bool
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
            HStack(spacing: 8) {
                Image(systemName: service.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: (isCompact ? 16 : 22) * ts.fontScale))
                    .foregroundStyle(service.isMuted ? Theme.accentRed : Theme.widgetPrimary("audio-devices", ts: ts, default: .cyan))

                if !isCompact {
                    Text("Audio")
                        .font(Theme.title(ts))
                        .foregroundStyle(Theme.text2(ts))
                }
                Spacer()
            }

            Text(service.outputDeviceName)
                .font(Theme.value(ts))
                .foregroundStyle(Theme.text1(ts))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if showVolume {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(service.isMuted ? Theme.accentRed : Theme.widgetPrimary("audio-devices", ts: ts, default: .cyan))
                            .frame(width: geo.size.width * CGFloat(service.volume))
                    }
                }
                .frame(height: isCompact ? 6 : 10)

                Text(service.isMuted ? "MUTED" : String(format: "%.0f%%", service.volume * 100))
                    .font(Theme.body(ts))
                    .foregroundStyle(service.isMuted ? Theme.accentRed : Theme.text2(ts))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)
        }
        .padding(isCompact ? Theme.compactPadding : Theme.widgetPadding)
        .widgetCard()
    }
}
