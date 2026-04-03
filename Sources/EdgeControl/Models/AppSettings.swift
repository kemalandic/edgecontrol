import Foundation

public struct AppSettings: Codable, Hashable, Sendable {
    public var selectedDisplayID: String?
    public var kioskMode: Bool
    public var debugMode: Bool

    public init(
        selectedDisplayID: String? = nil,
        kioskMode: Bool = true,
        debugMode: Bool = false
    ) {
        self.selectedDisplayID = selectedDisplayID
        self.kioskMode = kioskMode
        self.debugMode = debugMode
    }
}
