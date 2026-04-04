import AppKit
import SwiftUI

/// Page 5: Now Playing / Media dashboard
struct NowPlayingPage: View {
    @EnvironmentObject private var model: AppModel

    private var info: NowPlayingInfo? { model.nowPlayingService.nowPlaying }

    var body: some View {
        if let info {
            HStack(spacing: 0) {
                // LEFT: Album art / app icon area
                artworkPanel(info)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                divider()

                // CENTER: Track info + progress
                trackInfoPanel(info)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                divider()

                // RIGHT: Playback stats
                statsPanel(info)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // No media playing
            VStack(spacing: 16) {
                Image(systemName: "music.note.tv")
                    .font(.system(size: 80))
                    .foregroundStyle(Theme.textTertiary)
                Text("NO MEDIA PLAYING")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Text("Play something in any app — YouTube Music, Apple Music, Spotify, or any browser")
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
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 20)
    }

    // MARK: - Artwork

    private func artworkPanel(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 16) {
            // Large music icon or artwork
            if let data = info.artworkData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Theme.accentPurple.opacity(0.3), radius: 20)
                    .frame(maxWidth: 300, maxHeight: 300)
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
                .frame(width: 250, height: 250)
            }

            // Playing indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(info.isPlaying ? Theme.accentGreen : Theme.accentOrange)
                    .frame(width: 10, height: 10)
                Text(info.isPlaying ? "PLAYING" : "PAUSED")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Track Info

    private func trackInfoPanel(_ info: NowPlayingInfo) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()

            // App name
            HStack(spacing: 8) {
                Image(systemName: appIcon(info.appName))
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accentCyan)
                Text(info.appName.uppercased())
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            // Title
            Text(info.title)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.5)

            // Artist
            Text(info.artist)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

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
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.10))
                                .frame(height: 6)

                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Theme.accentCyan, Theme.accentPurple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * info.progress, height: 6)

                            Circle()
                                .fill(.white)
                                .frame(width: 12, height: 12)
                                .shadow(color: Theme.accentCyan.opacity(0.5), radius: 4)
                                .offset(x: max(0, geo.size.width * info.progress - 6))
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text(info.elapsedText)
                        Spacer()
                        Text(info.durationText)
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
                }
            }

            Spacer()
        }
        .padding(24)
    }

    // MARK: - Stats

    private func statsPanel(_ info: NowPlayingInfo) -> some View {
        VStack(spacing: 16) {
            Spacer()

            statCard(icon: "music.note", label: "TRACK", value: info.title)
            statCard(icon: "person.fill", label: "ARTIST", value: info.artist)
            statCard(icon: "opticaldisc", label: "ALBUM", value: info.album.isEmpty ? "—" : info.album)
            statCard(icon: "app.fill", label: "SOURCE", value: info.appName)

            if info.duration > 0 {
                statCard(icon: "clock", label: "DURATION", value: info.durationText)
            }

            Spacer()
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func statCard(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Theme.accentCyan.opacity(0.7))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                .strokeBorder(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func appIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "music": return "music.note"
        case "spotify": return "music.note.list"
        case "safari", "google chrome", "arc", "firefox": return "globe"
        default: return "app.fill"
        }
    }
}
