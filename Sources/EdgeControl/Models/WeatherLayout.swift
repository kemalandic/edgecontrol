import CoreGraphics

/// Which of the weather widget's two layouts a cell was given.
public enum WeatherLayoutMode: String, Sendable, Equatable {
    case compact
    case full
}

/// Every size the weather widget draws itself with, and the rule that picks
/// between its two layouts.
///
/// The rule is the point. The widget used to choose from its row count, and a
/// row is not a size: the dashboard divides whatever display it is on into the
/// configured number of rows, so four rows is ~470pt on a 2560x720 panel and
/// half that on a tall monitor carved into twelve. One threshold meant two
/// different things. `size.height <= 3` never fired at all, because the widget
/// cannot be placed smaller than 4x4; raising it to `<= 4` made every weather
/// widget at its minimum size compact, including ones with room to spare.
///
/// So the widget measures its cell and asks for the layout that fits. That
/// needs the full layout's height before anything is drawn, which is what
/// `fullHeight` computes — from the same constants the views render with, so
/// the estimate and the drawing cannot drift apart.
public struct WeatherLayout: Sendable, Equatable {
    public let mode: WeatherLayoutMode

    public init(mode: WeatherLayoutMode) {
        self.mode = mode
    }

    public var isCompact: Bool { mode == .compact }

    // MARK: - Today row

    /// Padding around the whole today row.
    public var padding: CGFloat { isCompact ? 10 : 16 }
    /// Between the hero column and the stats column.
    public var columnSpacing: CGFloat { isCompact ? 12 : 20 }
    /// Condition symbol above the temperature.
    public var conditionIconSize: CGFloat { isCompact ? 36 : 64 }
    /// The temperature reading itself.
    public var temperatureSize: CGFloat { isCompact ? 36 : 72 }
    /// Between the icon, the temperature and the condition text.
    public var heroSpacing: CGFloat { 4 }
    /// Between humidity / wind / high / low.
    public var statSpacing: CGFloat { isCompact ? 6 : 10 }
    /// The symbol that leads each stat row.
    public var statIconSize: CGFloat { isCompact ? 14 : 20 }
    /// Padding inside the "rain expected tomorrow" pill.
    public var alertPadding: CGFloat { isCompact ? 6 : 10 }

    // MARK: - Forecast strip

    /// Padding around the whole forecast strip.
    public var forecastPadding: CGFloat { 8 }
    /// Padding inside one day's card.
    public var dayPadding: CGFloat { isCompact ? 4 : 8 }
    /// Between a day's label, symbol and temperatures.
    public var daySpacing: CGFloat { isCompact ? 3 : 6 }
    /// Point size of a day's weather symbol.
    public var dayIconSize: CGFloat { isCompact ? 18 : 32 }
    /// Fixed box the symbol sits in, so days with tall and short glyphs line up.
    public var dayIconBox: CGFloat { isCompact ? 22 : 36 }
    /// The full layout names each day's conditions under its temperatures;
    /// the compact one has no room and drops the line.
    public var showsDayCondition: Bool { mode == .full }

    // MARK: - Choosing a layout

    /// A line of text is taller than its point size. The exact ratio belongs to
    /// the font, and this type has no text engine to ask, so it takes an
    /// upper bound: SF sits near 1.19, and rounding up to 1.3 means the
    /// estimate errs toward asking for more height than the drawing needs.
    /// That direction matters — underestimating would pick the full layout for
    /// a cell that clips it, while overestimating only drops to compact one
    /// notch earlier than strictly necessary.
    static let lineHeightRatio: CGFloat = 1.3

    /// Height the full layout needs, in points.
    ///
    /// `showsForecast` is whether the strip will actually be drawn — the
    /// setting being on is not enough if no forecast arrived.
    public static func fullHeight(showsForecast: Bool, theme: ThemeSettings) -> CGFloat {
        let full = WeatherLayout(mode: .full)
        let scale = CGFloat(theme.fontScale)

        func line(_ pointSize: Double) -> CGFloat {
            CGFloat(pointSize) * scale * lineHeightRatio
        }

        // Hero column: symbol, temperature, condition name.
        let hero =
            full.conditionIconSize * scale
            + full.heroSpacing + line(Double(full.temperatureSize))
            + full.heroSpacing + line(theme.fontSizeTitle)

        // Stats column: four rows, then the upcoming-change pill. The pill is
        // reserved whether or not one is showing. It is worth ~50pt, and a
        // widget that swapped layouts the day rain was forecast would look
        // broken in a way no setting explains.
        let statRow = max(full.statIconSize * scale, line(theme.fontSizeValue))
        let alert = full.alertPadding * 2 + max(full.statIconSize * scale, line(theme.fontSizeTitle))
        let stats = statRow * 4 + full.statSpacing * 4 + alert

        var height = max(hero, stats) + full.padding * 2

        if showsForecast {
            let day =
                full.dayPadding * 2
                + line(theme.fontSizeTitle)
                + full.daySpacing + full.dayIconBox
                + full.daySpacing + line(theme.fontSizeValue)
                + full.daySpacing + line(theme.fontSizeBody)
            height += 1  // divider
            height += day + full.forecastPadding * 2
        }

        return height
    }

    /// The layout that fits `availableHeight`.
    public static func mode(availableHeight: CGFloat, showsForecast: Bool, theme: ThemeSettings) -> WeatherLayoutMode {
        // A height of zero is what a view reports before it has been laid out.
        // Answering `.compact` there would show the small layout for one frame
        // and then swap, so an unmeasured cell keeps the roomier layout.
        guard availableHeight > 0 else { return .full }
        return availableHeight >= fullHeight(showsForecast: showsForecast, theme: theme) ? .full : .compact
    }
}
