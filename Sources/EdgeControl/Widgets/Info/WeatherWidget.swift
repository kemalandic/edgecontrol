import SwiftUI

public final class WeatherWidget: DashboardWidget {
    public let widgetId = "weather"
    public let displayName = "Weather"
    public let description = "Current conditions and multi-day forecast"
    public let iconName = "cloud.sun"
    public let category: WidgetCategory = .info
    public let requiredServices: Set<ServiceKey> = [.weather]
    public let supportedSizes = WidgetSizeRange(min: .size(4, 4), max: .size(10, 6))
    public let defaultSize = WidgetSize.size(6, 6)

    public let configSchema: [ConfigSchemaEntry] = [
        ConfigSchemaEntry(key: "showForecast", label: "Show Forecast", type: .toggle, defaultValue: .bool(true))
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    private let service: WeatherDataService

    public init(service: WeatherDataService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        // No layout decision here: a row count says nothing about how many
        // points a cell has. The body measures itself — see WeatherLayout.
        WeatherWidgetBody(
            service: service,
            showForecast: config.bool("showForecast", default: true)
        )
    }
}

// MARK: - Self-contained weather rendering

private struct WeatherWidgetBody: View {
    @ObservedObject var service: WeatherDataService
    @Environment(\.themeSettings) private var ts
    @Environment(\.unitSystem) private var units
    let showForecast: Bool

    var body: some View {
        GeometryReader { geo in
            content(availableHeight: geo.size.height)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// The setting being on is not enough — an empty forecast draws nothing,
    /// and the space it would have taken belongs to the today row instead.
    private var showsForecast: Bool {
        showForecast && !service.dailyForecast.isEmpty
    }

    @ViewBuilder
    private func content(availableHeight: CGFloat) -> some View {
        if let w = service.current {
            let layout = WeatherLayout(
                mode: WeatherLayout.mode(availableHeight: availableHeight, showsForecast: showsForecast, theme: ts)
            )
            VStack(spacing: 0) {
                // Spare height goes to the today row, where the reading people
                // actually look at lives, rather than to the forecast strip.
                todayRow(w, layout)
                    .frame(maxHeight: .infinity)

                if showsForecast {
                    Divider().background(Theme.border(ts))
                    forecastRow(layout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetCard()
        } else if service.error != nil {
            VStack(spacing: 8) {
                Image(systemName: "cloud.slash")
                    .font(.system(size: 28 * ts.fontScale))
                    .foregroundStyle(Theme.text3(ts))
                Text("WEATHER UNAVAILABLE")
                    .font(Theme.label(ts))
                    .foregroundStyle(Theme.text2(ts))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetCard()
        } else {
            VStack(spacing: 8) {
                ProgressView().tint(Theme.widgetPrimary("weather", ts: ts, default: .cyan))
                Text("LOADING")
                    .font(Theme.caption(ts))
                    .foregroundStyle(Theme.text3(ts))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetCard()
        }
    }

    private func todayRow(_ w: CurrentWeatherData, _ layout: WeatherLayout) -> some View {
        HStack(spacing: layout.columnSpacing) {
            VStack(spacing: layout.heroSpacing) {
                Image(systemName: w.symbolName)
                    .font(.system(size: layout.conditionIconSize * ts.fontScale))
                    .symbolRenderingMode(.multicolor)

                Text(units.degrees(fromCelsius: w.temperature))
                    .font(Theme.font(size: layout.temperatureSize, weight: .light, settings: ts))
                    .foregroundStyle(Theme.text1(ts))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)

                Text(w.conditionText.uppercased())
                    .font(layout.isCompact ? Theme.caption(ts) : Theme.title(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: layout.statSpacing) {
                statRow(icon: "humidity.fill", label: "Humidity", value: "\(w.humidity)%", layout)
                statRow(
                    icon: "wind", label: "Wind",
                    value: units.windSpeedText(fromKilometresPerHour: w.windSpeed), layout
                )

                if let today = service.dailyForecast.first {
                    statRow(
                        icon: "thermometer.high", label: "High",
                        value: units.degrees(fromCelsius: today.highTemp), layout
                    )
                    statRow(
                        icon: "thermometer.low", label: "Low",
                        value: units.degrees(fromCelsius: today.lowTemp), layout
                    )
                }

                if let alert = findUpcomingChange() {
                    HStack(spacing: 6) {
                        Image(systemName: alert.icon)
                            .font(.system(size: layout.statIconSize * ts.fontScale))
                            .foregroundStyle(alert.color)
                        Text(alert.message)
                            .font(layout.isCompact ? Theme.caption(ts) : Theme.title(ts))
                            .foregroundStyle(alert.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(layout.alertPadding)
                    .background(alert.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(layout.padding)
    }

    private func forecastRow(_ layout: WeatherLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(service.dailyForecast.enumerated()), id: \.element.id) { index, day in
                dayCard(day, index: index, layout)
                    .frame(maxWidth: .infinity)
                    // The separator rides as an overlay instead of standing in
                    // the stack as a sibling. A Rectangle is greedy in both
                    // axes, and as a sibling it stretched the strip to swallow
                    // every spare point in the cell, leaving the day cards
                    // marooned in the middle of an empty band.
                    .overlay(alignment: .trailing) {
                        if index < service.dailyForecast.count - 1 {
                            Rectangle()
                                .fill(Theme.border(ts))
                                .frame(width: 1)
                                .padding(.vertical, layout.forecastPadding)
                        }
                    }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, layout.forecastPadding)
    }

    private func dayCard(_ day: DayForecast, index: Int, _ layout: WeatherLayout) -> some View {
        VStack(spacing: layout.daySpacing) {
            Text(dayLabel(day.date, index: index))
                .font(layout.isCompact ? Theme.caption(ts) : Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))

            Image(systemName: day.symbolName)
                .font(.system(size: layout.dayIconSize * ts.fontScale))
                .symbolRenderingMode(.multicolor)
                .frame(height: layout.dayIconBox)

            HStack(spacing: 3) {
                Text(units.degrees(fromCelsius: day.highTemp))
                    .font(layout.isCompact ? Theme.body(ts) : Theme.value(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .monospacedDigit()
                Text(units.degrees(fromCelsius: day.lowTemp))
                    .font(layout.isCompact ? Theme.caption(ts) : Theme.value(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .monospacedDigit()
            }

            if layout.showsDayCondition {
                Text(day.conditionText)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.vertical, layout.dayPadding)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private struct WeatherAlert {
        let icon: String
        let message: String
        let color: Color
    }

    private func findUpcomingChange() -> WeatherAlert? {
        guard service.dailyForecast.count >= 2 else { return nil }
        let today = service.dailyForecast[0]
        let tomorrow = service.dailyForecast[1]

        switch tomorrow.weatherCode {
        case 61, 63, 65, 80, 81, 82:
            return WeatherAlert(icon: "cloud.rain.fill", message: "Rain expected tomorrow", color: Theme.accentBlue)
        case 71, 73, 75, 85, 86:
            return WeatherAlert(icon: "cloud.snow.fill", message: "Snow expected tomorrow", color: Theme.accentCyan)
        case 95, 96, 99:
            return WeatherAlert(icon: "cloud.bolt.fill", message: "Storms expected tomorrow", color: Theme.accentOrange)
        default: break
        }

        // High against high. Measuring tomorrow's high from the temperature
        // right now makes the alert a function of the time of day: at night the
        // current reading sits near the daily low, so nearly every evening
        // announced a warm-up that was really just sunrise.
        // Threshold stays in Celsius so what counts as "worth mentioning" does
        // not move when the display units do.
        let diff = tomorrow.highTemp - today.highTemp
        if abs(diff) >= 7 {
            let direction = diff > 0 ? "warmer" : "colder"
            return WeatherAlert(
                icon: diff > 0 ? "thermometer.sun.fill" : "thermometer.snowflake",
                message: String(
                    format: "%.0f° %@ tomorrow",
                    abs(units.temperatureDifference(fromCelsius: diff)),
                    direction
                ),
                color: diff > 0 ? Theme.accentOrange : Theme.accentCyan
            )
        }
        return nil
    }

    private func statRow(icon: String, label: String, value: String, _ layout: WeatherLayout) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: layout.statIconSize * ts.fontScale))
                .foregroundStyle(Theme.widgetPrimary("weather", ts: ts, default: .cyan).opacity(0.7))
                .frame(width: 22)
            Text(label)
                .font(layout.isCompact ? Theme.caption(ts) : Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
            Spacer()
            Text(value)
                .font(layout.isCompact ? Theme.label(ts) : Theme.value(ts))
                .foregroundStyle(Theme.text1(ts))
                .monospacedDigit()
        }
    }

    private func dayLabel(_ dateStr: String, index: Int) -> String {
        if index == 0 { return "Today" }
        if index == 1 { return "Tmrw" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE"
        return dayFormatter.string(from: date)
    }
}
