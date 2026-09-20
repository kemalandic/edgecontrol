import CoreGraphics
import Testing
@testable import EdgeControl

@Suite("Calibration model")
struct CalibrationModelTests {

    /// A well-formed square calibration: every edge and diagonal clears the
    /// 500-unit collapse threshold.
    private func square(_ side: CGFloat = 1000) -> CalibrationModel {
        var m = CalibrationModel()
        m.set(.topLeft, point: CGPoint(x: 0, y: 0))
        m.set(.topRight, point: CGPoint(x: side, y: 0))
        m.set(.bottomLeft, point: CGPoint(x: 0, y: side))
        m.set(.bottomRight, point: CGPoint(x: side, y: side))
        return m
    }

    /// A panel mounted slightly off-square — the case bilinear inversion exists
    /// for. A plain affine map would not reproduce this.
    private func trapezoid() -> CalibrationModel {
        var m = CalibrationModel()
        m.set(.topLeft, point: CGPoint(x: 120, y: 60))
        m.set(.topRight, point: CGPoint(x: 1880, y: 140))
        m.set(.bottomLeft, point: CGPoint(x: 40, y: 1020))
        m.set(.bottomRight, point: CGPoint(x: 1960, y: 940))
        return m
    }

    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 720)

    // MARK: validation

    @Test("an empty model reports incomplete")
    func emptyModelIsIncomplete() {
        #expect(CalibrationModel().validationError() == "Calibration incomplete")
    }

    @Test("three corners is still incomplete")
    func threeCornersIsIncomplete() {
        var partial = CalibrationModel()
        partial.set(.topLeft, point: CGPoint(x: 0, y: 0))
        partial.set(.topRight, point: CGPoint(x: 1000, y: 0))
        partial.set(.bottomLeft, point: CGPoint(x: 0, y: 1000))
        #expect(partial.validationError() == "Calibration incomplete")
    }

    @Test("a full-size square validates")
    func squareValidates() {
        #expect(square().validationError() == nil)
    }

    /// Tapping four points too close together is the realistic mis-calibration:
    /// the mapping would explode, so it must be refused.
    @Test("edges shorter than the threshold are refused")
    func collapsedEdgesRefused() {
        #expect(square(100).validationError() == "Calibration invalid: collapsed edges")
    }

    @Test("a valid quadrilateral that is not square still validates")
    func trapezoidValidates() {
        #expect(trapezoid().validationError() == nil)
    }

    // MARK: mapping

    @Test("an invalid model maps nothing")
    func invalidModelMapsNothing() {
        #expect(CalibrationModel().mappedPoint(for: CGPoint(x: 10, y: 10), in: screen) == nil)
        #expect(square(100).mappedPoint(for: CGPoint(x: 10, y: 10), in: screen) == nil)
    }

    /// The defining property, and it must hold for any valid quadrilateral, not
    /// just a square: each calibrated corner lands on the matching screen corner.
    @Test("calibrated corners map to screen corners", arguments: ["square", "trapezoid"])
    func cornersMapToScreenCorners(shape: String) {
        let m = shape == "square" ? square() : trapezoid()
        let expected: [CalibrationModel.Corner: CGPoint] = [
            .topLeft: CGPoint(x: screen.minX, y: screen.minY),
            .topRight: CGPoint(x: screen.maxX, y: screen.minY),
            .bottomLeft: CGPoint(x: screen.minX, y: screen.maxY),
            .bottomRight: CGPoint(x: screen.maxX, y: screen.maxY),
        ]
        for (corner, target) in expected {
            let raw = m.point(for: corner)!
            let mapped = m.mappedPoint(for: raw, in: screen)
            #expect(mapped != nil, "\(shape) \(corner.label) did not map")
            if let mapped {
                #expect(abs(mapped.x - target.x) < 2, "\(shape) \(corner.label) x")
                #expect(abs(mapped.y - target.y) < 2, "\(shape) \(corner.label) y")
            }
        }
    }

    @Test("the centre of a square maps to the centre of the screen")
    func centreMapsToCentre() {
        let mapped = square().mappedPoint(for: CGPoint(x: 500, y: 500), in: screen)
        #expect(mapped != nil)
        if let mapped {
            #expect(abs(mapped.x - screen.midX) < 2)
            #expect(abs(mapped.y - screen.midY) < 2)
        }
    }

    /// A touch outside the calibrated quadrilateral must be pulled to the edge,
    /// never reported off-screen — a widget hit test would otherwise miss.
    @Test("touches outside the calibrated area clamp to the screen")
    func outsideTouchesClamp() {
        let m = square()
        let before = m.mappedPoint(for: CGPoint(x: -800, y: -800), in: screen)
        let after = m.mappedPoint(for: CGPoint(x: 1800, y: 1800), in: screen)
        #expect(before == CGPoint(x: screen.minX, y: screen.minY))
        #expect(after == CGPoint(x: screen.maxX, y: screen.maxY))
    }

    /// The dashboard window does not always sit at the origin.
    @Test("mapping respects a bounds origin that is not zero")
    func nonZeroOriginRespected() {
        let offset = CGRect(x: 100, y: 50, width: 800, height: 400)
        let mapped = square().mappedPoint(for: CGPoint(x: 500, y: 500), in: offset)
        #expect(mapped != nil)
        if let mapped {
            #expect(abs(mapped.x - offset.midX) < 2)
            #expect(abs(mapped.y - offset.midY) < 2)
        }
    }
}
