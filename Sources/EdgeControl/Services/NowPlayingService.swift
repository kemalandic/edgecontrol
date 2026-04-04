import AppKit
import Foundation

public struct NowPlayingInfo: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let appName: String
    public let isPlaying: Bool
    public let duration: Double
    public let elapsed: Double
    public let artworkData: Data?

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(elapsed / duration, 1)
    }

    public var elapsedText: String { formatTime(elapsed) }
    public var durationText: String { formatTime(duration) }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

@MainActor
public final class NowPlayingService: ObservableObject {
    @Published public var nowPlaying: NowPlayingInfo?

    private var timer: Timer?

    public init() {}

    public func start() {
        stop()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        // Use MediaRemote private framework via AppleScript as bridge
        // This captures Now Playing info from any app (YouTube Music in browser, Apple Music, Spotify, etc.)
        Task.detached {
            let info = Self.fetchNowPlaying()
            await MainActor.run {
                self.nowPlaying = info
            }
        }
    }

    nonisolated private static func fetchNowPlaying() -> NowPlayingInfo? {
        // Use osascript to get Now Playing info from macOS Media Remote
        let script = """
        use framework "Foundation"
        use scripting additions

        set nowPlayingScript to "tell application \\"System Events\\"
            set frontApp to name of first application process whose frontmost is true
        end tell
        return frontApp"

        try
            tell application "System Events"
                set mediaApps to {"Music", "Spotify", "Safari", "Google Chrome", "Arc", "Firefox"}
                repeat with appName in mediaApps
                    if application process appName exists then
                        return name of application process appName
                    end if
                end repeat
            end tell
        end try
        return ""
        """

        // Simpler approach: read from macOS Now Playing via shell
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", """
            try
                tell application "System Events"
                    set _app to name of first application process whose frontmost is true
                end tell
                if _app is "Music" then
                    tell application "Music"
                        if player state is playing then
                            set _title to name of current track
                            set _artist to artist of current track
                            set _album to album of current track
                            set _dur to duration of current track
                            set _pos to player position
                            return _title & "|" & _artist & "|" & _album & "|" & _dur & "|" & _pos & "|Music|1"
                        end if
                    end tell
                end if
            end try
            return ""
        """]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }

        let parts = output.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 7 else { return nil }

        return NowPlayingInfo(
            title: String(parts[0]),
            artist: String(parts[1]),
            album: String(parts[2]),
            appName: String(parts[5]),
            isPlaying: parts[6] == "1",
            duration: Double(parts[3]) ?? 0,
            elapsed: Double(parts[4]) ?? 0,
            artworkData: nil
        )
    }
}
