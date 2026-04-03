import CoreGraphics
import Foundation

public struct RawTouchSample: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var pressed: Bool

    public init(x: Int = 0, y: Int = 0, pressed: Bool = false) {
        self.x = x
        self.y = y
        self.pressed = pressed
    }
}

public struct CalibrationModel: Equatable, Codable, Sendable {
    public enum Corner: String, CaseIterable, Hashable, Codable, Sendable {
        case topLeft, topRight, bottomLeft, bottomRight

        public var label: String {
            switch self {
            case .topLeft: "TL"
            case .topRight: "TR"
            case .bottomLeft: "BL"
            case .bottomRight: "BR"
            }
        }
    }

    private var points: [Corner: CGPoint] = [:]

    public init() {}

    public mutating func set(_ corner: Corner, point: CGPoint) {
        points[corner] = point
    }

    public func point(for corner: Corner) -> CGPoint? {
        points[corner]
    }

    public var summary: String {
        Corner.allCases.compactMap { corner in
            guard let point = points[corner] else { return nil }
            return "\(corner.label)(\(Int(point.x)),\(Int(point.y)))"
        }
        .joined(separator: " ")
    }

    public func validationError() -> String? {
        guard let topLeft = points[.topLeft],
              let topRight = points[.topRight],
              let bottomLeft = points[.bottomLeft],
              let bottomRight = points[.bottomRight] else {
            return "Calibration incomplete"
        }

        let topWidth = distance(topLeft, topRight)
        let bottomWidth = distance(bottomLeft, bottomRight)
        let leftHeight = distance(topLeft, bottomLeft)
        let rightHeight = distance(topRight, bottomRight)

        if topWidth < 500 || bottomWidth < 500 || leftHeight < 500 || rightHeight < 500 {
            return "Calibration invalid: collapsed edges"
        }

        let d1 = distance(topLeft, bottomRight)
        let d2 = distance(topRight, bottomLeft)
        if d1 < 500 || d2 < 500 {
            return "Calibration invalid: collapsed quadrilateral"
        }

        return nil
    }

    public func mappedPoint(for rawPoint: CGPoint, in bounds: CGRect) -> CGPoint? {
        guard validationError() == nil,
              let topLeft = points[.topLeft],
              let topRight = points[.topRight],
              let bottomLeft = points[.bottomLeft],
              let bottomRight = points[.bottomRight] else {
            return nil
        }

        guard let uv = invertBilinear(point: rawPoint, tl: topLeft, tr: topRight, bl: bottomLeft, br: bottomRight) else {
            return nil
        }

        return CGPoint(
            x: bounds.minX + min(max(uv.x, 0), 1) * bounds.width,
            y: bounds.minY + min(max(uv.y, 0), 1) * bounds.height
        )
    }

    // Newton-Raphson bilinear inversion
    private func invertBilinear(point: CGPoint, tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint) -> CGPoint? {
        var u: CGFloat = 0.5
        var v: CGFloat = 0.5

        for _ in 0..<18 {
            let top = lerp(tl, tr, u)
            let bot = lerp(bl, br, u)
            let current = lerp(top, bot, v)
            let fx = current.x - point.x
            let fy = current.y - point.y

            if abs(fx) + abs(fy) < 0.5 { return CGPoint(x: u, y: v) }

            let du = CGPoint(x: (1 - v) * (tr.x - tl.x) + v * (br.x - bl.x),
                             y: (1 - v) * (tr.y - tl.y) + v * (br.y - bl.y))
            let dv = CGPoint(x: (1 - u) * (bl.x - tl.x) + u * (br.x - tr.x),
                             y: (1 - u) * (bl.y - tl.y) + u * (br.y - tr.y))
            let det = du.x * dv.y - du.y * dv.x
            if abs(det) < 0.0001 { return nil }

            u -= (fx * dv.y - fy * dv.x) / det
            v -= (fy * du.x - fx * du.y) / det
        }
        return CGPoint(x: u, y: v)
    }

    private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

// MARK: - Dwell Calibration State

public struct DwellCalibrationState: Equatable, Sendable {
    public private(set) var activeCornerIndex = 0
    public private(set) var stableSample: CGPoint?
    public private(set) var holdProgress: TimeInterval = 0
    public private(set) var awaitingRelease = false
    public let requiredHoldDuration: TimeInterval = 1.0

    public init() {}

    public var activeCorner: CalibrationModel.Corner? {
        guard activeCornerIndex < CalibrationModel.Corner.allCases.count else { return nil }
        return CalibrationModel.Corner.allCases[activeCornerIndex]
    }

    public var isComplete: Bool {
        activeCornerIndex >= CalibrationModel.Corner.allCases.count
    }

    public mutating func markComplete() {
        activeCornerIndex = CalibrationModel.Corner.allCases.count
        stableSample = nil
        holdProgress = requiredHoldDuration
        awaitingRelease = false
    }

    public mutating func advance() {
        activeCornerIndex += 1
        if activeCornerIndex >= CalibrationModel.Corner.allCases.count {
            markComplete()
            return
        }
        stableSample = nil
        holdProgress = 0
        awaitingRelease = true
    }

    public mutating func update(point: CGPoint?, pressed: Bool, delta: TimeInterval) -> Bool {
        guard activeCorner != nil else { return false }

        if awaitingRelease {
            if !pressed { awaitingRelease = false }
            stableSample = nil
            holdProgress = 0
            return false
        }

        guard pressed, let point else {
            stableSample = nil
            holdProgress = 0
            return false
        }

        if let stableSample, hypot(stableSample.x - point.x, stableSample.y - point.y) <= 160 {
            holdProgress += delta
        } else {
            stableSample = point
            holdProgress = delta
        }

        return holdProgress >= requiredHoldDuration
    }

    public var statusText: String {
        if awaitingRelease { return "Lift finger before next corner" }
        guard let activeCorner else { return "Calibration complete" }
        let percent = Int(min(max(holdProgress / requiredHoldDuration, 0), 1) * 100)
        return "Touch and hold \(activeCorner.label) (\(percent)%)"
    }
}

// MARK: - Persistence

public enum CalibrationPersistence {
    public static func load() -> CalibrationModel? {
        guard let data = try? Data(contentsOf: calibrationURL()) else { return nil }
        return try? JSONDecoder().decode(CalibrationModel.self, from: data)
    }

    public static func save(_ model: CalibrationModel) throws {
        let url = calibrationURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(model).write(to: url, options: .atomic)
    }

    public static func clear() throws {
        let url = calibrationURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func calibrationURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("EdgeControl", isDirectory: true)
            .appendingPathComponent("calibration.json")
    }
}
