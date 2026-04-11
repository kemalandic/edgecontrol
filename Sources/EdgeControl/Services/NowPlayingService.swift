import AppKit
import Foundation

/// Identifies how to control the media source.
public enum MediaSourceType: Equatable, Sendable {
    case safari(tabLocation: String)  // W1T2 format — JS inject via osascript
    case chrome(tabLocation: String)  // W1T2 format — JS inject via Google Chrome AppleScript
    case edge(tabLocation: String)    // W1T2 format — JS inject via Microsoft Edge AppleScript
    case spotify                       // AppleScript tell application "Spotify"
    case appleMusic                    // AppleScript tell application "Music"
    case webApp                        // Safari Web App — limited controls
}

public struct NowPlayingInfo: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let sourceName: String
    public let isPlaying: Bool
    public let duration: Double
    public let elapsed: Double
    public let artworkURL: String?
    public let sourceType: MediaSourceType

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

// MARK: - Now Playing Service

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
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
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
        let runningApps = NSWorkspace.shared.runningApplications
        Task.detached {
            // Query all sources sequentially — each osascript has its own process timeout
            var sources: [NowPlayingInfo] = []
            sources.append(contentsOf: Self.querySafariSources(runningApps: runningApps))
            sources.append(contentsOf: Self.querySpotify(runningApps: runningApps))
            sources.append(contentsOf: Self.queryAppleMusic(runningApps: runningApps))
            sources.append(contentsOf: Self.queryChromiumSources(app: "Google Chrome", bundleId: "com.google.Chrome", runningApps: runningApps))
            sources.append(contentsOf: Self.queryChromiumSources(app: "Microsoft Edge", bundleId: "com.microsoft.edgemac", runningApps: runningApps))
            sources.append(contentsOf: Self.queryWebApps(runningApps: runningApps))

            await MainActor.run {
                self.allSources = sources

                if self.selectedSourceIndex >= sources.count {
                    self.selectedSourceIndex = max(0, sources.count - 1)
                }

                if sources.isEmpty {
                    self.nowPlaying = nil
                } else {
                    if let playingIndex = sources.firstIndex(where: { $0.isPlaying }) {
                        if self.nowPlaying == nil {
                            self.selectedSourceIndex = playingIndex
                        }
                    }
                    self.nowPlaying = sources.indices.contains(self.selectedSourceIndex) ? sources[self.selectedSourceIndex] : sources.first
                }

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

    // MARK: - Media Controls (dispatched by sourceType)

    public func togglePlayPause() {
        guard let np = nowPlaying else { return }
        // Optimistic UI update
        let updated = NowPlayingInfo(
            title: np.title, artist: np.artist, album: np.album, sourceName: np.sourceName,
            isPlaying: !np.isPlaying, duration: np.duration, elapsed: np.elapsed,
            artworkURL: np.artworkURL, sourceType: np.sourceType
        )
        nowPlaying = updated
        if let idx = allSources.firstIndex(where: { $0.sourceType == np.sourceType && $0.title == np.title }) {
            allSources[idx] = updated
        }

        switch np.sourceType {
        case .safari(let loc):
            executeBrowserJS(app: "Safari", location: loc, js: "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}")
        case .chrome(let loc):
            executeBrowserJS(app: "Google Chrome", location: loc, js: "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}")
        case .edge(let loc):
            executeBrowserJS(app: "Microsoft Edge", location: loc, js: "var v=document.querySelector('video');if(v){v.paused?v.play():v.pause();}")
        case .spotify:
            executeAppleScript("tell application \"Spotify\" to playpause")
        case .appleMusic:
            executeAppleScript("tell application \"Music\" to playpause")
        case .webApp:
            break
        }
    }

    public func nextTrack() {
        guard let np = nowPlaying else { return }
        let nextJS = "var b=document.querySelector('.next-button,.ytp-next-button,.skipControl__next,.playControls__next,button[aria-label=Next],button[aria-label=Sonraki]');if(b){b.click();}else{var v=document.querySelector('video');if(v){v.currentTime=v.duration;}}"
        switch np.sourceType {
        case .safari(let loc):
            executeBrowserJS(app: "Safari", location: loc, js: nextJS)
        case .chrome(let loc):
            executeBrowserJS(app: "Google Chrome", location: loc, js: nextJS)
        case .edge(let loc):
            executeBrowserJS(app: "Microsoft Edge", location: loc, js: nextJS)
        case .spotify:
            executeAppleScript("tell application \"Spotify\" to next track")
        case .appleMusic:
            executeAppleScript("tell application \"Music\" to next track")
        case .webApp:
            break
        }
    }

    public func previousTrack() {
        guard let np = nowPlaying else { return }
        let prevJS = "var b=document.querySelector('.previous-button,.ytp-prev-button,.skipControl__previous,.playControls__previous,button[aria-label=Previous]');if(b){b.click();}else{var v=document.querySelector('video');if(v){v.currentTime=0;}}"
        switch np.sourceType {
        case .safari(let loc):
            executeBrowserJS(app: "Safari", location: loc, js: prevJS)
        case .chrome(let loc):
            executeBrowserJS(app: "Google Chrome", location: loc, js: prevJS)
        case .edge(let loc):
            executeBrowserJS(app: "Microsoft Edge", location: loc, js: prevJS)
        case .spotify:
            executeAppleScript("tell application \"Spotify\" to previous track")
        case .appleMusic:
            executeAppleScript("tell application \"Music\" to back track")
        case .webApp:
            break
        }
    }

    public func seekForward(_ seconds: Double = 10) {
        guard let np = nowPlaying else { return }
        let newElapsed = min(np.elapsed + seconds, np.duration)
        let updated = NowPlayingInfo(
            title: np.title, artist: np.artist, album: np.album, sourceName: np.sourceName,
            isPlaying: np.isPlaying, duration: np.duration, elapsed: newElapsed,
            artworkURL: np.artworkURL, sourceType: np.sourceType
        )
        nowPlaying = updated

        let seekJS = "var v=document.querySelector('video');if(v){v.currentTime=Math.min(v.currentTime+\(seconds),v.duration);}"
        switch np.sourceType {
        case .safari(let loc):
            executeBrowserJS(app: "Safari", location: loc, js: seekJS)
        case .chrome(let loc):
            executeBrowserJS(app: "Google Chrome", location: loc, js: seekJS)
        case .edge(let loc):
            executeBrowserJS(app: "Microsoft Edge", location: loc, js: seekJS)
        case .spotify:
            executeAppleScript("tell application \"Spotify\" to set player position to (player position + \(seconds))")
        case .appleMusic:
            executeAppleScript("tell application \"Music\" to set player position to (player position + \(seconds))")
        case .webApp:
            break
        }
    }

    public func seekBackward(_ seconds: Double = 10) {
        guard let np = nowPlaying else { return }
        let newElapsed = max(np.elapsed - seconds, 0)
        let updated = NowPlayingInfo(
            title: np.title, artist: np.artist, album: np.album, sourceName: np.sourceName,
            isPlaying: np.isPlaying, duration: np.duration, elapsed: newElapsed,
            artworkURL: np.artworkURL, sourceType: np.sourceType
        )
        nowPlaying = updated

        let seekJS = "var v=document.querySelector('video');if(v){v.currentTime=Math.max(v.currentTime-\(seconds),0);}"
        switch np.sourceType {
        case .safari(let loc):
            executeBrowserJS(app: "Safari", location: loc, js: seekJS)
        case .chrome(let loc):
            executeBrowserJS(app: "Google Chrome", location: loc, js: seekJS)
        case .edge(let loc):
            executeBrowserJS(app: "Microsoft Edge", location: loc, js: seekJS)
        case .spotify:
            executeAppleScript("tell application \"Spotify\" to set player position to (player position - \(seconds))")
        case .appleMusic:
            executeAppleScript("tell application \"Music\" to set player position to (player position - \(seconds))")
        case .webApp:
            break
        }
    }

    // MARK: - Execution Helpers

    /// Execute JavaScript in a browser tab (Safari, Chrome, or Edge).
    private func executeBrowserJS(app: String, location: String, js: String) {
        let parts = location.replacingOccurrences(of: "W", with: "").split(separator: "T")
        guard parts.count == 2, let w = Int(parts[0]), let t = Int(parts[1]) else { return }

        let escapedJS = js.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "\"", with: "\\\"")
                          .replacingOccurrences(of: "\n", with: " ")

        let script: String
        if app == "Safari" {
            script = "tell application \"Safari\" to do JavaScript \"\(escapedJS)\" in tab \(t) of window \(w)"
        } else {
            // Chrome and Edge use the same AppleScript syntax
            script = "tell application \"\(app)\" to execute tab \(t) of window \(w) javascript \"\(escapedJS)\""
        }

        Task.detached {
            Self.runOsascript(script)
            await MainActor.run { self.fetch() }
        }
    }

    private func executeAppleScript(_ script: String) {
        Task.detached {
            Self.runOsascript(script)
            await MainActor.run { self.fetch() }
        }
    }

    nonisolated private static func runOsascript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Query: Safari Tabs

    nonisolated private static func querySafariSources(runningApps: [NSRunningApplication]) -> [NowPlayingInfo] {
        guard runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Safari" }) else { return [] }

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

        let output = runOsascriptCapture(script)
        guard !output.isEmpty else { return [] }

        return output.split(separator: "###").compactMap { entry -> NowPlayingInfo? in
            let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6, !parts[0].isEmpty else { return nil }

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
                sourceType: tabLocation.map { .safari(tabLocation: $0) } ?? .webApp
            )
        }
    }

    // MARK: - Query: Chrome / Edge (Chromium-based)

    nonisolated private static func queryChromiumSources(app: String, bundleId: String, runningApps: [NSRunningApplication]) -> [NowPlayingInfo] {
        guard runningApps.contains(where: { $0.bundleIdentifier == bundleId }) else { return [] }

        // Chromium: first check tab titles, only inject JS into media-likely tabs
        // This avoids injecting JS into 18+ tabs which causes timeout
        let script = """
        tell application "\(app)"
            set results to ""
            set winCount to count of windows
            repeat with w from 1 to winCount
                set tabCount to count of tabs of window w
                repeat with t from 1 to tabCount
                    try
                        set tabTitle to title of tab t of window w
                        set tabURL to URL of tab t of window w
                        -- Only inject JS into tabs likely to have media
                        if tabTitle contains "YouTube" or tabTitle contains "Spotify" or tabTitle contains "SoundCloud" or tabTitle contains "Music" or tabTitle contains "Deezer" or tabTitle contains "Tidal" or tabURL contains "youtube.com" or tabURL contains "music.apple.com" or tabURL contains "spotify.com" or tabURL contains "soundcloud.com" then
                            set jsResult to execute tab t of window w javascript "\\
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
                                })()"
                            if jsResult is not "" then
                                if results is not "" then set results to results & "###"
                                set results to results & jsResult & "|W" & w & "T" & t & "|" & tabTitle
                            end if
                        end if
                    end try
                end repeat
            end repeat
            return results
        end tell
        """

        let output = runOsascriptCapture(script)
        guard !output.isEmpty else { return [] }

        let isEdge = app.contains("Edge")
        let makeSourceType: (String) -> MediaSourceType = { loc in
            isEdge ? .edge(tabLocation: loc) : .chrome(tabLocation: loc)
        }

        return output.split(separator: "###").compactMap { entry -> NowPlayingInfo? in
            let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6, !parts[0].isEmpty else { return nil }

            let tabLocation = parts.count > 7 ? parts[7] : nil
            let tabName = parts.count > 8 ? parts[8] : app
            let sourceName = tabName.contains("YouTube Music") ? "YouTube Music" :
                             tabName.contains("YouTube") ? "YouTube" :
                             tabName.contains("SoundCloud") ? "SoundCloud" :
                             tabName.contains("Spotify") ? "Spotify Web" :
                             app.contains("Edge") ? "Edge" : "Chrome"

            return NowPlayingInfo(
                title: parts[0],
                artist: parts.count > 1 ? parts[1] : "",
                album: parts.count > 2 ? parts[2] : "",
                sourceName: sourceName,
                isPlaying: parts.count > 5 && parts[5] == "1",
                duration: parts.count > 3 ? (Double(parts[3]) ?? 0) : 0,
                elapsed: parts.count > 4 ? (Double(parts[4]) ?? 0) : 0,
                artworkURL: parts.count > 6 ? parts[6] : nil,
                sourceType: tabLocation.map { makeSourceType($0) } ?? .webApp
            )
        }
    }

    // MARK: - Query: Spotify

    nonisolated private static func querySpotify(runningApps: [NSRunningApplication]) -> [NowPlayingInfo] {
        guard runningApps.contains(where: { $0.bundleIdentifier == "com.spotify.client" }) else { return [] }

        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to (duration of current track) / 1000
            set trackPosition to player position
            set trackPlaying to (player state is playing)
            set trackArtwork to artwork url of current track
            return trackName & "|" & trackArtist & "|" & trackAlbum & "|" & trackDuration & "|" & trackPosition & "|" & trackPlaying & "|" & trackArtwork
        end tell
        """

        let output = runOsascriptCapture(script)
        guard !output.isEmpty else { return [] }

        let parts = output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6, !parts[0].isEmpty else { return [] }

        return [NowPlayingInfo(
            title: parts[0],
            artist: parts.count > 1 ? parts[1] : "",
            album: parts.count > 2 ? parts[2] : "",
            sourceName: "Spotify",
            isPlaying: parts.count > 5 && parts[5] == "true",
            duration: parts.count > 3 ? (Double(parts[3]) ?? 0) : 0,
            elapsed: parts.count > 4 ? (Double(parts[4]) ?? 0) : 0,
            artworkURL: parts.count > 6 ? parts[6] : nil,
            sourceType: .spotify
        )]
    }

    // MARK: - Query: Apple Music

    nonisolated private static func queryAppleMusic(runningApps: [NSRunningApplication]) -> [NowPlayingInfo] {
        guard runningApps.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) else { return [] }

        let script = """
        tell application "Music"
            if player state is stopped then return ""
            set trackName to name of current track
            set trackArtist to artist of current track
            set trackAlbum to album of current track
            set trackDuration to duration of current track
            set trackPosition to player position
            set trackPlaying to (player state is playing)
            try
                set artData to raw data of artwork 1 of current track
            end try
            return trackName & "|" & trackArtist & "|" & trackAlbum & "|" & trackDuration & "|" & trackPosition & "|" & trackPlaying
        end tell
        """

        let output = runOsascriptCapture(script)
        guard !output.isEmpty else { return [] }

        let parts = output.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 6, !parts[0].isEmpty else { return [] }

        return [NowPlayingInfo(
            title: parts[0],
            artist: parts.count > 1 ? parts[1] : "",
            album: parts.count > 2 ? parts[2] : "",
            sourceName: "Apple Music",
            isPlaying: parts.count > 5 && parts[5] == "true",
            duration: parts.count > 3 ? (Double(parts[3]) ?? 0) : 0,
            elapsed: parts.count > 4 ? (Double(parts[4]) ?? 0) : 0,
            artworkURL: nil, // Apple Music artwork loaded separately via AppleScript binary data
            sourceType: .appleMusic
        )]
    }

    // MARK: - Query: Safari Web Apps

    nonisolated private static func queryWebApps(runningApps: [NSRunningApplication]) -> [NowPlayingInfo] {
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

        let output = runOsascriptCapture(script)
        guard !output.isEmpty else { return [] }

        return output.split(separator: "###").compactMap { entry -> NowPlayingInfo? in
            let title = String(entry).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            let parts = title.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let songTitle = parts.first ?? title
            let source = parts.count > 1 ? parts[1] : "Web App"

            return NowPlayingInfo(
                title: songTitle,
                artist: "",
                album: "",
                sourceName: source,
                isPlaying: true,
                duration: 0,
                elapsed: 0,
                artworkURL: nil,
                sourceType: .webApp
            )
        }
    }

    // MARK: - osascript Helper

    nonisolated private static func runOsascriptCapture(_ script: String, timeout: TimeInterval = 4.0) -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        // Wait with timeout — kill if too slow
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
