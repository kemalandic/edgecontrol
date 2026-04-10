import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    public var selectedDisplayName: String?
    public var kioskMode: Bool
    public var debugMode: Bool

    public init(
        selectedDisplayName: String? = nil,
        kioskMode: Bool = true,
        debugMode: Bool = false
    ) {
        self.selectedDisplayName = selectedDisplayName
        self.kioskMode = kioskMode
        self.debugMode = debugMode
    }
}
