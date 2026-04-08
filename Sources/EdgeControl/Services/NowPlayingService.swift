import AppKit
import Foundation

public struct NowPlayingInfo: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let sourceName: String
    public let isPlaying: Bool
    public let duration: Double
    public let elapsed: Double
    public let artworkURL: String?
    public let tabLocation: String? // "W1T2" format for Safari tab targeting

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1)
    }

    public var elapsedText: String { formatTime(elapsed) }
    public var durationText: String { formatTime(duration) }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Now Playing Service (Safari via osascript subprocess)

@MainActor
public final class NowPlayingService: ObservableObject {
    @Published public var nowPlaying: NowPlayingInfo?
    @Published public var allSources: [NowPlayingInfo] = []
    @Published public var selectedSourceIndex: Int = 0
    @Published public var artworkImage: NSImage?

    private var timer: Timer?
    private var lastArtworkURL: String?

    public init() {}

    public func start() {
        stop()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetch()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func fetch() {
        Task.detached {
            let sources = Self.queryAllSources()
            await MainActor.run {
                self.allSources = sources

                // Clamp selected index
                if self.selectedSourceIndex >= sources.count {
                    self.selectedSourceIndex = max(0, sources.count - 1)
                }

                // Set active nowPlaying
                if sources.isEmpty {
                    self.nowPlaying = nil
                } else {
                    // Prefer playing over paused
                    if let playingIndex = sources.firstIndex(where: { $0.isPlaying }) {
                        if self.nowPlaying == nil {
                            self.selectedSourceIndex = playingIndex
                        }
                    }
                    self.nowPlaying = sources.indices.contains(self.selectedSourceIndex) ? sources[self.selectedSourceIndex] : sources.first
                }

                // Load artwork if URL changed
                if let url = self.nowPlaying?.artworkURL, !url.isEmpty, url != self.lastArtworkURL {
                    self.lastArtworkURL = url
                    self.loadArtwork(url)
                } else if self.nowPlaying?.artworkURL == nil || self.nowPlaying?.artworkURL?.isEmpty == true {
                    self.lastArtworkURL = nil
                    self.artworkImage = nil
                }
            }
        }
    }

    public func selectSource(_ index: Int) {
        guard allSources.indices.contains(index) else { return }
        selectedSourceIndex = index
        nowPlaying = allSources[index]
        lastArtworkURL = nil
        artworkImage = nil
        if let url = nowPlaying?.artworkURL, !url.isEmpty {
            loadArtwork(url)
        }
    }

    private func loadArtwork(_ urlString: String) {
        Task.detached {
            guard let url = URL(string: urlString),
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            await MainActor.run {
                self.artworkImage = image
            }
        }
    }

    // MARK: - Media Controls

    public func togglePlayPause() {
        guard let loc = nowPlaying?.tabLocation else { return }
        // Optimistic UI update
        if var np = nowPlaying {
            np = NowPlayingInfo(title: np.title, artist: np.artist, album: np.album, sourceName: np.sourceName, isPlaying: !np.isPlaying, duration: np.duration, elapsed: np.elapsed, artworkURL: np.artworkURL, tabLocation: np.tabLocation)
            nowPlaying = np
            if let idx = allSources.firstIndex(where: { $0.tabLocation == loc }) {
                allSources[idx] = np
            }
        }
        executeMediaAction(location: loc, js: "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}")
    }

    public func nextTrack() {
        guard let loc = nowPlaying?.tabLocation else { return }
        executeMediaAction(location: loc, js: "var b=document.querySelector('.next-button,.ytp-next-button,.skipControl__next,.playControls__next,button[aria-label=Next],button[aria-label=Sonraki]');if(b){b.click();}else{var v=document.querySelector('video');if(v){v.currentTime=v.duration;}}")
    }

    public func previousTrack() {
        guard let loc = nowPlaying?.tabLocation else { return }
        executeMediaAction(location: loc, js: "var b=document.querySelector('.previous-button,.ytp-prev-button,.skipControl__previous,.playControls__previous,button[aria-label=Previous]');if(b){b.click();}else{var v=document.querySelector('video');if(v){v.currentTime=0;}}")
    }

    public func seekForward(_ seconds: Double = 10) {
        guard let loc = nowPlaying?.tabLocation else { return }
        // Optimistic UI update
        if var np = nowPlaying {
            let newElapsed = min(np.elapsed + seconds, np.duration)
            np = NowPlayingInfo(title: np.title, artist: np.artist, album: np.album, sourceName: np.sourceName, isPlaying: np.isPlaying, duration: np.duration, elapsed: newElapsed, artworkURL: np.artworkURL, tabLocation: np.tabLocation)
            nowPlaying = np
        }
        executeMediaAction(location: loc, js: "var v=document.querySelector('video');if(v){v.currentTime=Math.min(v.currentTime+\(seconds),v.duration);}")
    }

    public func seekBackward(_ seconds: Double = 10) {
        guard let loc = nowPlaying?.tabLocation else { return }
        // Optimistic UI update
        if var np = nowPlaying {
            let newElapsed = max(np.elapsed - seconds, 0)
            np = NowPlayingInfo(title: np.title, artist: np.artist, album: np.album, sourceName: np.sourceName, isPlaying: np.isPlaying, duration: np.duration, elapsed: newElapsed, artworkURL: np.artworkURL, tabLocation: np.tabLocation)
            nowPlaying = np
        }
        executeMediaAction(location: loc, js: "var v=document.querySelector('video');if(v){v.currentTime=Math.max(v.currentTime-\(seconds),0);}")
    }

    private func executeMediaAction(location: String, js: String) {
        // Parse W{n}T{n} format
        let parts = location.replacingOccurrences(of: "W", with: "").split(separator: "T")
        guard parts.count == 2, let w = Int(parts[0]), let t = Int(parts[1]) else { return }

        // Build AppleScript lines — use multiple -e args to avoid string escaping issues
        // The JS is passed via stdin to osascript to avoid shell/AppleScript quote conflicts
        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: " ")

        let script = "tell application \"Safari\" to do JavaScript \"\(escapedJS)\" in tab \(t) of window \(w)"

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()

            // Refresh with real data after action completes
            await MainActor.run { self.fetch() }
        }
    }

    // MARK: - Query ALL media sources across all Safari windows/tabs

    nonisolated private static func queryAllSources() -> [NowPlayingInfo] {
        let apps = NSWorkspace.shared.runningApplications
        let safariRunning = apps.contains { $0.bundleIdentifier == "com.apple.Safari" }
        guard safariRunning else { return [] }

        // This script scans ALL windows and ALL tabs in Safari
        let script = """
        tell application "Safari"
            set results to ""
            set winCount to count of windows
            repeat with w from 1 to winCount
                set tabCount to count of tabs of window w
                repeat with t from 1 to tabCount
                    try
                        set jsResult to do JavaScript "\\
                            (function() {\\
                                try {\\
                                    var m = navigator.mediaSession;\\
                                    if (!m || !m.metadata || !m.metadata.title) return '';\\
                                    var title = m.metadata.title || '';\\
                                    var artist = m.metadata.artist || '';\\
                                    var album = m.metadata.album || '';\\
                                    var artwork = '';\\
                                    if (m.metadata.artwork && m.metadata.artwork.length > 0) {\\
                                        artwork = m.metadata.artwork[m.metadata.artwork.length - 1].src || '';\\
                                    }\\
                                    var video = document.querySelector('video');\\
                                    var duration = 0;\\
                                    var currentTime = 0;\\
                                    var paused = true;\\
                                    if (video) {\\
                                        duration = video.duration || 0;\\
                                        currentTime = video.currentTime || 0;\\
                                        paused = video.paused;\\
                                    }\\
                                    return title + '|' + artist + '|' + album + '|' + duration + '|' + currentTime + '|' + (paused ? '0' : '1') + '|' + artwork;\\
                                } catch(e) { return ''; }\\
                            })()" in tab t of window w
                        if jsResult is not "" then
                            if results is not "" then set results to results & "###"
                            set tabName to name of tab t of window w
                            set results to results & jsResult & "|W" & w & "T" & t & "|" & tabName
                        end if
                    end try
                end repeat
            end repeat
            return results
        end tell
        """

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        // Also check Safari Web Apps (like YT Music installed as web app)
        var webAppSources = queryWebApps()

        // Parse Safari tab sources separated by ###
        let safariSources: [NowPlayingInfo] = output.split(separator: "###").compactMap { entry -> NowPlayingInfo? in
            let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6, !parts[0].isEmpty else { return nil }

            // parts[7] = tab location (W1T2), parts[8] = tab name
            let tabLocation = parts.count > 7 ? parts[7] : nil
            let tabName = parts.count > 8 ? parts[8] : "Safari"
            let sourceName = tabName.contains("YouTube Music") ? "YouTube Music" :
                             tabName.contains("YouTube") ? "YouTube" :
                             tabName.contains("SoundCloud") ? "SoundCloud" :
                             tabName.contains("Spotify") ? "Spotify Web" : "Safari"

            return NowPlayingInfo(
                title: parts[0],
                artist: parts.count > 1 ? parts[1] : "",
                album: parts.count > 2 ? parts[2] : "",
                sourceName: sourceName,
                isPlaying: parts.count > 5 && parts[5] == "1",
                duration: parts.count > 3 ? (Double(parts[3]) ?? 0) : 0,
                elapsed: parts.count > 4 ? (Double(parts[4]) ?? 0) : 0,
                artworkURL: parts.count > 6 ? parts[6] : nil,
                tabLocation: tabLocation
            )
        }

        return safariSources + webAppSources
    }

    /// Query Safari Web Apps (installed as macOS apps) via window title
    nonisolated private static func queryWebApps() -> [NowPlayingInfo] {
        let script = """
        tell application "System Events"
            set results to ""
            set allProcs to every process whose background only is false
            repeat with proc in allProcs
                set procName to name of proc
                if procName is "Web App" then
                    try
                        set winTitle to name of front window of proc
                        if winTitle contains "YouTube Music" or winTitle contains "SoundCloud" or winTitle contains "Spotify" then
                            if results is not "" then set results to results & "###"
                            set results to results & winTitle
                        end if
                    end try
                end if
            end repeat
            return results
        end tell
        """

        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return []
        }

        return output.split(separator: "###").compactMap { entry -> NowPlayingInfo? in
            let title = String(entry).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            // Parse "Song Name | YouTube Music" format
            let parts = title.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let songTitle = parts.first ?? title
            let source = parts.count > 1 ? parts[1] : "Web App"

            return NowPlayingInfo(
                title: songTitle,
                artist: "",
                album: "",
                sourceName: source,
                isPlaying: true, // Can't determine from title alone
                duration: 0,
                elapsed: 0,
                artworkURL: nil,
                tabLocation: nil
            )
        }
    }
}
