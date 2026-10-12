import CoreGraphics
import Testing

@testable import EdgeControl

@Suite("Flip clock layout")
struct FlipClockLayoutTests {
    @Test(
        "cards fit every tile size, with or without seconds, AM/PM and the date",
        arguments: [
            CGSize(width: 380, height: 236), CGSize(width: 508, height: 236), CGSize(width: 508, height: 356),
            CGSize(width: 764, height: 356), CGSize(width: 1020, height: 476), CGSize(width: 250, height: 116),
        ])
    func cardsFit(size: CGSize) {
        for seconds in [false, true] {
            for meridiem in [false, true] {
                let l = FlipClockLayout(size: size, seconds: seconds, meridiem: meridiem, date: true)
                let cards: CGFloat = seconds ? 6 : 4
                let groups: CGFloat = seconds ? 3 : 2
                let width =
                    cards * l.cardWidth + (cards - groups) * l.cardGap + (groups - 1) * l.colonWidth
                    + (meridiem ? l.groupGap + l.meridiemWidth : 0)
                let height = l.cardHeight + (l.showsDate ? l.dateSpacing + l.dateSize * 1.3 : 0)
                #expect(width <= size.width + 0.5)
                #expect(height <= size.height + 0.5)
            }
        }
    }

    @Test("every clock style has a display name for the Style picker")
    func styleNames() {
        let style = ClockWidget().configSchema.first { $0.key == "clockStyle" }
        #expect(style?.optionLabels?["flip"] == "Flip Clock")
        #expect(style?.optionLabels?["dotMatrix"] == "Dot Matrix")
        #expect(style?.options?.allSatisfy { style?.optionLabels?[$0] != nil } == true)
    }
}
