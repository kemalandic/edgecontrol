import CoreGraphics
import Testing

@testable import EdgeControl

/// The regression these guard against: the widget used to choose its layout
/// from its row count. A row is not a unit of length — the dashboard divides
/// whatever display it is on into the configured number of rows — so the same
/// threshold meant a roomy cell on one screen and a cramped one on another.
@Suite("Weather layout")
struct WeatherLayoutTests {

    /// Grid height on the 14.5" panel: 720pt of display, less the 8pt the
    /// dashboard pads the page with on each edge, divided into six rows. A
    /// four-row widget then keeps all but the 4pt gap drawn around each cell.
    private static let fourRowsOnTheEdgePanel = (720.0 - 16) / 6 * 4 - 8

    @Test("A four-row widget on the 14.5in panel has room for the full layout")
    func fourRowCellIsFull() {
        let mode = WeatherLayout.mode(
            availableHeight: CGFloat(Self.fourRowsOnTheEdgePanel),
            showsForecast: true,
            theme: ThemeSettings()
        )
        #expect(mode == .full)
    }

    @Test("The same four rows on a display carved into twelve are compact")
    func crowdedGridIsCompact() {
        // Twelve rows of the same panel: four of them is less than half the
        // height, and a row count alone could not tell the two cases apart.
        let height = CGFloat((720.0 - 16) / 12 * 4 - 8)
        #expect(WeatherLayout.mode(availableHeight: height, showsForecast: true, theme: ThemeSettings()) == .compact)
    }

    @Test("An unmeasured cell keeps the roomier layout")
    func zeroHeightStaysFull() {
        // A view reports zero before it is laid out. Answering compact there
        // would draw the small layout for a frame and then swap it out.
        #expect(WeatherLayout.mode(availableHeight: 0, showsForecast: true, theme: ThemeSettings()) == .full)
    }

    @Test("Scaling the type up flips a cell that used to fit")
    func largerTypeFlipsToCompact() {
        let height = CGFloat(Self.fourRowsOnTheEdgePanel)
        let big = ThemeSettings(fontScale: 1.4)
        #expect(WeatherLayout.mode(availableHeight: height, showsForecast: true, theme: ThemeSettings()) == .full)
        #expect(WeatherLayout.mode(availableHeight: height, showsForecast: true, theme: big) == .compact)
    }

    @Test("Hiding the forecast lowers what the full layout needs")
    func forecastCostsHeight() {
        let theme = ThemeSettings()
        let withStrip = WeatherLayout.fullHeight(showsForecast: true, theme: theme)
        let without = WeatherLayout.fullHeight(showsForecast: false, theme: theme)
        #expect(without < withStrip)
        // The strip is a real share of the widget, not a rounding difference.
        #expect(withStrip - without > 100)
    }

    @Test("Required height rises with the font scale", arguments: [0.7, 1.0, 1.25, 1.5])
    func heightRisesWithScale(scale: Double) {
        let smaller = WeatherLayout.fullHeight(showsForecast: true, theme: ThemeSettings(fontScale: scale - 0.1))
        let here = WeatherLayout.fullHeight(showsForecast: true, theme: ThemeSettings(fontScale: scale))
        #expect(here > smaller)
    }

    @Test("Every compact size is smaller than its full counterpart")
    func compactIsSmallerThroughout() {
        let compact = WeatherLayout(mode: .compact)
        let full = WeatherLayout(mode: .full)
        let sizes: [(String, KeyPath<WeatherLayout, CGFloat>)] = [
            ("padding", \.padding),
            ("columnSpacing", \.columnSpacing),
            ("conditionIconSize", \.conditionIconSize),
            ("temperatureSize", \.temperatureSize),
            ("statSpacing", \.statSpacing),
            ("statIconSize", \.statIconSize),
            ("alertPadding", \.alertPadding),
            ("dayPadding", \.dayPadding),
            ("daySpacing", \.daySpacing),
            ("dayIconSize", \.dayIconSize),
            ("dayIconBox", \.dayIconBox),
        ]
        for (name, size) in sizes {
            #expect(compact[keyPath: size] < full[keyPath: size], "\(name) is not smaller in the compact layout")
        }
        #expect(compact.isCompact)
        #expect(!full.isCompact)
        // The per-day condition line is the one thing compact drops outright.
        #expect(!compact.showsDayCondition)
        #expect(full.showsDayCondition)
    }

    @Test("A cell one point short of the requirement goes compact")
    func thresholdIsExact() {
        let theme = ThemeSettings()
        let needed = WeatherLayout.fullHeight(showsForecast: true, theme: theme)
        #expect(WeatherLayout.mode(availableHeight: needed, showsForecast: true, theme: theme) == .full)
        #expect(WeatherLayout.mode(availableHeight: needed - 1, showsForecast: true, theme: theme) == .compact)
    }
}
