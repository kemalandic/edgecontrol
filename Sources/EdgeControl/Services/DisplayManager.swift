import AppKit
import Foundation

@MainActor
public final class DisplayManager {
    private let xeneonNames = ["xeneon", "xeneon edge"]

    public func availableDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.map { screen in
            let id = screen.displayIdentifier
            let name = screen.localizedName
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            return DisplayDescriptor(
                id: id,
                name: name,
                width: Int(frame.width * scale),
                height: Int(frame.height * scale),
                scaleFactor: scale,
                isMain: screen == NSScreen.main
            )
        }
    }

    public func xeneonScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            let name = screen.localizedName.lowercased()
            if xeneonNames.contains(where: { name.contains($0) }) { return true }
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            let w = Int(frame.width * scale)
            let h = Int(frame.height * scale)
            return w == 2560 && h == 720
        }
    }

    public func selectedScreen(for settings: AppSettings) -> NSScreen? {
        if let name = settings.selectedDisplayName {
            return NSScreen.screens.first { $0.localizedName == name }
        }
        return xeneonScreen()
    }
}
