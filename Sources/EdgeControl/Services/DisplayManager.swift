import AppKit
import Foundation

@MainActor
public final class DisplayManager {
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

    public func selectedScreen(name: String?) -> NSScreen? {
        guard let name else {
            // Fallback: prefer first non-main display, then main
            return NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
        }
        return NSScreen.screens.first { $0.localizedName == name }
    }
}
