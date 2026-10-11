import AppKit
import Foundation

public struct DisplayDescriptor: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int
    public let scaleFactor: CGFloat
    public let isMain: Bool

    public var summary: String {
        "\(name) \(width)×\(height)@\(Int(scaleFactor))x\(isMain ? " (main)" : "")"
    }
}

extension NSScreen {
    var displayIdentifier: String {
        let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        return "\(id)"
    }
}

/// A disconnected preferred display stays preferred; availability is separate.
enum DisplaySelection {
    static func resolve(_ displays: [DisplayDescriptor], preferredName: String?) -> DisplayDescriptor? {
        if let preferredName { return displays.first { $0.name == preferredName } }
        return displays.first { !$0.isMain } ?? displays.first
    }
}
