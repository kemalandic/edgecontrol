import AppKit
import SwiftUI

/// Page 5: Now Playing / Media dashboard
struct NowPlayingPage: View {
    @EnvironmentObject private var model: AppModel

    private var info: NowPlayingInfo? { model.nowPlayingService.nowPlaying }
    private var artwork: NSImage? { model.nowPlayingService.artworkImage }

    var body: some View {
        if let info {
            HStack(spacing: 0) {
                // LEFT: Artwork
                artworkPanel(info)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                divider()

                // CENTER: Track info + progress
                trackInfoPanel(info)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                divider()

                // RIGHT: Sources + Stats
                sourcesPanel(info)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "music.note.tv")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.textTertiary)
                Text("NO MEDIA PLAYING")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("Play something in Safari — YouTube Music, SoundCloud, or any website with audio")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func divider() -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
            .frame(width: 1).padding(.vertical, 20)
    }

    // MARK: - Artwork

    private func artworkPanel(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 16) {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Theme.accentPurple.opacity(0.3), radius: 20)
                    .frame(maxWidth: 320, maxHeight: 320)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.accentPurple.opacity(0.3), Theme.accentCyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "music.note")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 260, height: 260)
            }

            // Playing indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(info.isPlaying ? Theme.accentGreen : Theme.accentOrange)
                    .frame(width: 12, height: 12)
                Text(info.isPlaying ? "PLAYING" : "PAUSED")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Track Info

    private func trackInfoPanel(_ info: NowPlayingInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            // Source
            HStack(spacing: 8) {
                Image(systemName: "safari")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accentCyan)
                Text(info.sourceName.uppercased())
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            // Title
            Text(info.title)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.4)

            // Artist
            if !info.artist.isEmpty {
                Text(info.artist)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            // Album
            if !info.album.isEmpty {
                Text(info.album)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            // Progress bar
            if info.duration > 0 {
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.accentCyan, Theme.accentPurple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * info.progress, height: 8)

                            Circle()
                                .fill(.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: Theme.accentCyan.opacity(0.5), radius: 4)
                                .offset(x: max(0, geo.size.width * info.progress - 7))
                        }
                    }
                    .frame(height: 14)

                    HStack {
                        Text(info.elapsedText)
                        Spacer()
                        Text(info.durationText)
                    }
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                }
            }

            // Action buttons
            HStack(spacing: 10) {
                TouchButton(
                    id: "media_seek_back",
                    label: "⏪ -10s",
                    isActive: false,
                    activeColor: Theme.accentCyan,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.nowPlayingService.seekBackward()
                }

                TouchButton(
                    id: "media_prev",
                    label: "⏮ PREV",
                    isActive: false,
                    activeColor: Theme.accentPurple,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.nowPlayingService.previousTrack()
                }

                TouchButton(
                    id: "media_play_pause",
                    label: info.isPlaying ? "⏸ PAUSE" : "▶ PLAY",
                    isActive: info.isPlaying,
                    activeColor: Theme.accentCyan,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.nowPlayingService.togglePlayPause()
                }

                TouchButton(
                    id: "media_next",
                    label: "NEXT ⏭",
                    isActive: false,
                    activeColor: Theme.accentPurple,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.nowPlayingService.nextTrack()
                }

                TouchButton(
                    id: "media_seek_fwd",
                    label: "+10s ⏩",
                    isActive: false,
                    activeColor: Theme.accentCyan,
                    registry: model.touchService.zoneRegistry
                ) {
                    model.nowPlayingService.seekForward()
                }
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Sources Panel

    private func sourcesPanel(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(Theme.accentPurple).frame(width: 12, height: 12)
                Text("SOURCES")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(model.nowPlayingService.allSources.count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            if model.nowPlayingService.allSources.count > 1 {
                // Multiple sources — show selector
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(Array(model.nowPlayingService.allSources.enumerated()), id: \.offset) { index, source in
                            sourceRow(source, index: index, isSelected: index == model.nowPlayingService.selectedSourceIndex)
                        }
                    }
                }
            }

            Spacer()

            // Current source info
            VStack(spacing: 12) {
                statRow(icon: "music.note", label: "TRACK", value: info.title)
                if !info.artist.isEmpty {
                    statRow(icon: "person.fill", label: "ARTIST", value: info.artist)
                }
                statRow(icon: sourceIcon(info.sourceName), label: "SOURCE", value: info.sourceName)
                if info.duration > 0 {
                    statRow(icon: "clock", label: "DURATION", value: info.durationText)
                }
            }

            Spacer()
        }
        .padding(16)
    }

    private func sourceRow(_ source: NowPlayingInfo, index: Int, isSelected: Bool) -> some View {
        TouchButton(
            id: "media_source_\(index)",
            label: "\n\n",
            isActive: isSelected,
            activeColor: Theme.accentPurple,
            registry: model.touchService.zoneRegistry
        ) {
            model.nowPlayingService.selectSource(index)
        }
        .overlay {
            HStack(spacing: 12) {
                // Playing indicator
                Circle()
                    .fill(source.isPlaying ? Theme.accentGreen : Theme.accentOrange)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : Theme.textSecondary)
                        .lineLimit(1)
                    Text(source.sourceName + (source.artist.isEmpty ? "" : " · \(source.artist)"))
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accentPurple)
                }
            }
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
        }
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.accentCyan.opacity(0.7))
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Spacer()
        }
    }

    private func sourceIcon(_ name: String) -> String {
        switch name {
        case "YouTube Music": return "music.note.list"
        case "YouTube": return "play.rectangle.fill"
        case "SoundCloud": return "cloud.fill"
        case "Spotify Web": return "music.note"
        default: return "safari"
        }
    }
}
