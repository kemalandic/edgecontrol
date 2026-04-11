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
        ConfigSchemaEntry(key: "showForecast", label: "Show Forecast", type: .toggle, defaultValue: .bool(true)),
    ]
    public let defaultColors = WidgetColors(primary: .cyan)

    private let service: WeatherDataService

    public init(service: WeatherDataService) {
        self.service = service
    }

    @MainActor
    public func body(size: WidgetSize, config: WidgetConfig) -> any View {
        WeatherWidgetBody(
            service: service,
            showForecast: config.bool("showForecast", default: true),
            isCompact: size.height <= 3
        )
    }
}

// MARK: - Self-contained weather rendering

private struct WeatherWidgetBody: View {
    @ObservedObject var service: WeatherDataService
    @Environment(\.themeSettings) private var ts
    let showForecast: Bool
    let isCompact: Bool

    var body: some View {
        if let w = service.current {
            VStack(spacing: 0) {
                todayRow(w)

                if showForecast && !service.dailyForecast.isEmpty {
                    Divider().background(Theme.border(ts))
                    forecastRow()
                }
            }
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

    private func todayRow(_ w: CurrentWeatherData) -> some View {
        HStack(spacing: isCompact ? 12 : 20) {
            VStack(spacing: 4) {
                Image(systemName: w.symbolName)
                    .font(.system(size: (isCompact ? 36 : 64) * ts.fontScale))
                    .symbolRenderingMode(.multicolor)

                Text(String(format: "%.0f°", w.temperature))
                    .font(Theme.font(size: isCompact ? 36 : 72, weight: .light, settings: ts))
                    .foregroundStyle(Theme.text1(ts))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)

                Text(w.conditionText.uppercased())
                    .font(isCompact ? Theme.caption(ts) : Theme.title(ts))
                    .foregroundStyle(Theme.text2(ts))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
                statRow(icon: "humidity.fill", label: "Humidity", value: "\(w.humidity)%")
                statRow(icon: "wind", label: "Wind", value: String(format: "%.0f km/h", w.windSpeed))

                if let today = service.dailyForecast.first {
                    statRow(icon: "thermometer.high", label: "High", value: String(format: "%.0f°", today.highTemp))
                    statRow(icon: "thermometer.low", label: "Low", value: String(format: "%.0f°", today.lowTemp))
                }

                if let alert = findUpcomingChange() {
                    HStack(spacing: 6) {
                        Image(systemName: alert.icon)
                            .font(.system(size: (isCompact ? 14 : 20) * ts.fontScale))
                            .foregroundStyle(alert.color)
                        Text(alert.message)
                            .font(isCompact ? Theme.caption(ts) : Theme.title(ts))
                            .foregroundStyle(alert.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(isCompact ? 6 : 10)
                    .background(alert.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(isCompact ? 10 : 16)
    }

    private func forecastRow() -> some View {
        HStack(spacing: 0) {
            ForEach(Array(service.dailyForecast.enumerated()), id: \.element.id) { index, day in
                dayCard(day, index: index)
                    .frame(maxWidth: .infinity)
                if index < service.dailyForecast.count - 1 {
                    Rectangle()
                        .fill(Theme.border(ts))
                        .frame(width: 1)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func dayCard(_ day: DayForecast, index: Int) -> some View {
        VStack(spacing: isCompact ? 3 : 6) {
            Text(dayLabel(day.date, index: index))
                .font(isCompact ? Theme.caption(ts) : Theme.title(ts))
                .foregroundStyle(Theme.text2(ts))

            Image(systemName: day.symbolName)
                .font(.system(size: (isCompact ? 18 : 32) * ts.fontScale))
                .symbolRenderingMode(.multicolor)
                .frame(height: isCompact ? 22 : 36)

            HStack(spacing: 3) {
                Text(String(format: "%.0f°", day.highTemp))
                    .font(isCompact ? Theme.body(ts) : Theme.value(ts))
                    .foregroundStyle(Theme.text1(ts))
                    .monospacedDigit()
                Text(String(format: "%.0f°", day.lowTemp))
                    .font(isCompact ? Theme.caption(ts) : Theme.value(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .monospacedDigit()
            }

            if !isCompact {
                Text(day.conditionText)
                    .font(Theme.body(ts))
                    .foregroundStyle(Theme.text3(ts))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .padding(.vertical, isCompact ? 4 : 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private struct WeatherAlert {
        let icon: String
        let message: String
        let color: Color
    }

    private func findUpcomingChange() -> WeatherAlert? {
        guard let current = service.current, service.dailyForecast.count >= 2 else { return nil }
        let tomorrow = service.dailyForecast[1]

        switch tomorrow.weatherCode {
        case 61, 63, 65, 80, 81, 82:
            return WeatherAlert(icon: "cloud.rain.fill", message: "Yarın yağmur bekleniyor", color: Theme.accentBlue)
        case 71, 73, 75, 85, 86:
            return WeatherAlert(icon: "cloud.snow.fill", message: "Yarın kar bekleniyor", color: Theme.accentCyan)
        case 95, 96, 99:
            return WeatherAlert(icon: "cloud.bolt.fill", message: "Yarın fırtına bekleniyor", color: Theme.accentOrange)
        default: break
        }

        let diff = tomorrow.highTemp - current.temperature
        if abs(diff) >= 7 {
            let direction = diff > 0 ? "artış" : "düşüş"
            return WeatherAlert(
                icon: diff > 0 ? "thermometer.sun.fill" : "thermometer.snowflake",
                message: String(format: "Yarın %.0f° %@", abs(diff), direction),
                color: diff > 0 ? Theme.accentOrange : Theme.accentCyan
            )
        }
        return nil
    }

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: (isCompact ? 14 : 20) * ts.fontScale))
                .foregroundStyle(Theme.widgetPrimary("weather", ts: ts, default: .cyan).opacity(0.7))
                .frame(width: 22)
            Text(label)
                .font(isCompact ? Theme.caption(ts) : Theme.body(ts))
                .foregroundStyle(Theme.text3(ts))
            Spacer()
            Text(value)
                .font(isCompact ? Theme.label(ts) : Theme.value(ts))
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
