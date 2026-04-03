import CoreGraphics
import Foundation

public struct TouchRuntimeState: Equatable, Sendable {
    public var rawSample: RawTouchSample
    public var mappedPoint: CGPoint?
    public var hidStatus: String
    public var calibrationStatus: String
    public var calibrationValidation: String
    public var calibrationSummary: String
    public var isCalibrated: Bool
    public var isPressed: Bool
    public var sequence: Int
    public var pressSequence: Int

    public init(
        rawSample: RawTouchSample = RawTouchSample(),
        mappedPoint: CGPoint? = nil,
        hidStatus: String = "inactive",
        calibrationStatus: String = "Not started",
        calibrationValidation: String = "",
        calibrationSummary: String = "",
        isCalibrated: Bool = false,
        isPressed: Bool = false,
        sequence: Int = 0,
        pressSequence: Int = 0
    ) {
        self.rawSample = rawSample
        self.mappedPoint = mappedPoint
        self.hidStatus = hidStatus
        self.calibrationStatus = calibrationStatus
        self.calibrationValidation = calibrationValidation
        self.calibrationSummary = calibrationSummary
        self.isCalibrated = isCalibrated
        self.isPressed = isPressed
        self.sequence = sequence
        self.pressSequence = pressSequence
    }
}
