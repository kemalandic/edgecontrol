import AppKit
import SwiftUI

public final class NowPlayingWidget: DashboardWidget {
    public let widgetId = "now-playing"
    public let displayName = "Now Playing"
    public let description = "Media player with artwork, controls, progress bar, and source tabs"
    public let iconName = "play.circle"
    public let category: WidgetCategory = .media
    public let requiredServices: Set<ServiceKey> = [.nowPlaying]
    public let supportedSizes = WidgetSizeRange(min: .size(6, 3), max: .size(12, 6))
    public let defaultSize = WidgetSize.size(8, 4)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showControls", label: "Show Controls", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "showArtwork", label: "Show Artwork", type: .toggle, defaultValue: .bool(true)),
        ConfigSchemaEntry(key: "showProgress", label: "Show Progress", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .purple, secondary: .cyan)

    private let service: NowPlayingService

    public init(service: NowPlayingService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        NowPlayingWidgetView(
            service: service,
            showControls: config.bool("showControls", default: true),
            showArtwork: config.bool("showArtwork", default: true),
            showProgress: config.bool("showProgress", default: true),
            isCompact: size.height <= 3
        )
    }
}

private struct NowPlayingWidgetView: View {
    @ObservedObject var service: NowPlayingService
    @EnvironmentObject private var model: AppModel
    @Environment(\.themeSettings) private var ts
    let showControls: Bool
    let showArtwork: Bool
    let showProgress: Bool
    let isCompact: Bool

    private var touchRegistry: TouchZoneRegistry { model.touchService.zoneRegistry }

    private var primary: Color { Theme.widgetPrimary("now-playing", ts: ts, default: .purple) }
    private var secondary: Color { Theme.widgetSecondary("now-playing", ts: ts, default: .cyan) ?? Theme.accentCyan }

    var body: some View {
        VStack(spacing: 0) {
            if let np = service.nowPlaying {
                // Source tabs
                if service.allSources.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(service.allSources.enumerated()), id: \.offset) { index, source in
                                Text(source.sourceName)
                                    .font(Theme.label(ts))
                                    .foregroundStyle(index == service.selectedSourceIndex ? .white : Theme.text3(ts))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        index == service.selectedSourceIndex ?
                                        primary.opacity(0.3) : Color.white.opacity(0.05),
                                        in: Capsule()
                                    )
                                    .touchTappable(id: "np-source-\(index)", registry: touchRegistry) {
                                        Task { @MainActor in service.selectSource(index) }
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }

                Spacer(minLength: 0)

                if isCompact {
                    compactLayout(np)
                } else {
                    fullLayout(np)
                }

                Spacer(minLength: 0)
            } else {
                Spacer()
                Image(systemName: "music.note")
                    .font(.system(size: 36 * ts.fontScale))
                    .foregroundStyle(Theme.text3(ts))
                Text("NO MEDIA")
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .padding(.top, 6)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.sectionSpacing)
        .widgetCard()
    }

    // Compact: horizontal layout
    private func compactLayout(_ np: NowPlayingInfo) -> some View {
        HStack(spacing: 12) {
            if showArtwork {
                artworkView(maxSize: 80)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(np.title)
                    .font(Theme.title(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .lineLimit(1)
                if !np.artist.isEmpty {
                    Text(np.artist)
                        .font(Theme.label(ts))
                        .foregroundStyle(Theme.text2(ts))
                        .lineLimit(1)
                }
            }

            Spacer()

            if showControls {
                controlButtons(fontSize: 28)
            }
        }
    }

    // Full: vertical layout
    private func fullLayout(_ np: NowPlayingInfo) -> some View {
        VStack(spacing: 8) {
            if showArtwork {
                artworkView(maxSize: 200)
            }

            Spacer(minLength: 4)

            Text(np.title)
                .font(Theme.title(ts))
                .foregroundStyle(Theme.text1(ts))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if !np.artist.isEmpty {
                Text(np.artist)
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if showProgress && np.duration > 0 {
                progressBar(np)
            }

            if showControls {
                controlButtons(fontSize: 36)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func artworkView(maxSize: CGFloat) -> some View {
        if let artwork = service.artworkImage {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: primary.opacity(0.3), radius: 12)
                .frame(maxWidth: maxSize, maxHeight: maxSize)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(
                        colors: [primary.opacity(0.3), secondary.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                Image(systemName: "music.note")
                    .font(.system(size: 32 * ts.fontScale))
                    .foregroundStyle(Theme.text3(ts))
            }
            .frame(width: min(maxSize, 120), height: min(maxSize, 120))
        }
    }

    private func progressBar(_ np: NowPlayingInfo) -> some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.10))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LinearGradient(
                            colors: [secondary, primary],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * np.progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text(np.elapsedText)
                Spacer()
                Text(np.durationText)
            }
            .font(Theme.caption(ts))
            .foregroundStyle(Theme.text3(ts))
            .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }

    private func controlButtons(fontSize: CGFloat) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "backward.fill")
                .font(.system(size: fontSize * 0.6 * ts.fontScale))
                .foregroundStyle(Theme.text2(ts))
                .frame(width: fontSize * 1.5, height: fontSize * 1.5)
                .touchTappable(id: "np-prev", registry: touchRegistry) {
                    Task { @MainActor in service.previousTrack() }
                }

            Image(systemName: service.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                .font(.system(size: fontSize * ts.fontScale))
                .foregroundStyle(Theme.text1(ts))
                .frame(width: fontSize * 1.5, height: fontSize * 1.5)
                .touchTappable(id: "np-playpause", registry: touchRegistry) {
                    Task { @MainActor in service.togglePlayPause() }
                }

            Image(systemName: "forward.fill")
                .font(.system(size: fontSize * 0.6 * ts.fontScale))
                .foregroundStyle(Theme.text2(ts))
                .frame(width: fontSize * 1.5, height: fontSize * 1.5)
                .touchTappable(id: "np-next", registry: touchRegistry) {
                    Task { @MainActor in service.nextTrack() }
                }
        }
    }
}
