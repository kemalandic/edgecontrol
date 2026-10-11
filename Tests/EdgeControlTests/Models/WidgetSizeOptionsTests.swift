import Testing

@testable import EdgeControl

/// The named sizes offered when adding a widget from the catalog.
@Suite struct WidgetSizeOptionsTests {
    private func options(
        min: WidgetSize, max: WidgetSize, default size: WidgetSize, columns: Int = 20, rows: Int = 6
    )
        -> [WidgetSizeOption]
    {
        WidgetSizeOptions.options(
            range: WidgetSizeRange(min: min, max: max), defaultSize: size, columns: columns, rows: rows)
    }

    @Test func aRoomyWidgetOffersFiveNamedSizes() {
        let offered = options(min: .size(4, 3), max: .size(24, 12), default: .size(8, 5))
        #expect(offered.map(\.name) == ["Small", "Medium", "Large", "Wide", "Tall"])
    }

    @Test func smallIsTheMinimumAndMediumTheDefault() {
        let offered = options(min: .size(4, 3), max: .size(24, 12), default: .size(8, 5))
        #expect(offered.first { $0.name == "Small" }?.size == .size(4, 3))
        #expect(offered.first { $0.name == "Medium" }?.size == .size(8, 5))
    }

    @Test func tallFillsThePageHeight() {
        let offered = options(min: .size(4, 3), max: .size(24, 12), default: .size(8, 5))
        #expect(offered.first { $0.name == "Tall" }?.size == .size(8, 6))
    }

    @Test func noOptionExceedsThePageOrRepeats() {
        let offered = options(min: .size(1, 1), max: .size(24, 12), default: .size(4, 3))
        #expect(offered.allSatisfy { $0.size.width <= 20 && $0.size.height <= 6 })
        #expect(Set(offered.map(\.size)).count == offered.count)
    }

    @Test func aFixedSizeWidgetOffersOneSize() {
        let offered = options(min: .size(2, 2), max: .size(2, 2), default: .size(2, 2))
        #expect(offered.map(\.size) == [.size(2, 2)])
    }

    @Test func aDefaultTooLargeForTheScreenIsClamped() {
        let offered = options(min: .size(4, 5), max: .size(24, 12), default: .size(8, 6), columns: 10, rows: 7)
        #expect(offered.allSatisfy { $0.size.width <= 10 && $0.size.height <= 7 && $0.size.height >= 5 })
    }

    @Test func aWidgetThatCannotFitThePageOffersNothing() {
        #expect(options(min: .size(8, 8), max: .size(12, 12), default: .size(8, 8)).isEmpty)
    }
}
