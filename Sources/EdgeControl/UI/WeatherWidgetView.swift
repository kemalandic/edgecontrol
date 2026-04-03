import SwiftUI

struct WeatherWidgetView: View {
    @EnvironmentObject private var model: AppModel

    private var weather: CurrentWeatherData? { model.weatherService.current }
    private var daily: [DayForecast] { model.weatherService.dailyForecast }
    private var error: String? { model.weatherService.error }

    var body: some View {
        if let w = weather {
            VStack(spacing: 0) {
                // ROW 1: Today — current conditions
                todayRow(w)

                Divider().background(Theme.borderSubtle)

                // ROW 2: Next 5 days — flush inside same card
                HStack(spacing: 0) {
                    ForEach(Array(daily.enumerated()), id: \.element.id) { index, day in
                        dayCard(day, index: index)
                            .frame(maxWidth: .infinity)
                        if index < daily.count - 1 {
                            Rectangle()
                                .fill(Theme.borderSubtle)
                                .frame(width: 1)
                                .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous)
                    .strokeBorder(Theme.borderSubtle, lineWidth: 1)
            )
        } else if error != nil {
            VStack(spacing: 10) {
                Image(systemName: "cloud.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.textTertiary)
                Text("WEATHER UNAVAILABLE")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.accentCyan)
                    .scaleEffect(1.5)
                Text("LOADING")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - ROW 1: Today

    private func todayRow(_ w: CurrentWeatherData) -> some View {
        HStack(spacing: 20) {
            // Left: icon + temp + condition
            VStack(spacing: 6) {
                Image(systemName: w.symbolName)
                    .font(.system(size: 64))
                    .symbolRenderingMode(.multicolor)

                Text(String(format: "%.0f°", w.temperature))
                    .font(.system(size: 72, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)

                Text(w.conditionText.uppercased())
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity)

            // Right: stats
            VStack(alignment: .leading, spacing: 10) {
                statRow(icon: "humidity.fill", label: "Humidity", value: "\(w.humidity)%")
                statRow(icon: "wind", label: "Wind", value: String(format: "%.0f km/h", w.windSpeed))

                if let today = daily.first {
                    statRow(icon: "thermometer.high", label: "High", value: String(format: "%.0f°", today.highTemp))
                    statRow(icon: "thermometer.low", label: "Low", value: String(format: "%.0f°", today.lowTemp))
                }

                // Alert for upcoming weather change
                if let alert = findUpcomingChange() {
                    HStack(spacing: 8) {
                        Image(systemName: alert.icon)
                            .font(.system(size: 20))
                            .foregroundStyle(alert.color)
                        Text(alert.message)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(alert.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(10)
                    .background(alert.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    // MARK: - ROW 2: Day Cards

    private func dayCard(_ day: DayForecast, index: Int) -> some View {
        VStack(spacing: 6) {
            Text(dayLabel(day.date, index: index))
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            Image(systemName: day.symbolName)
                .font(.system(size: 32))
                .symbolRenderingMode(.multicolor)
                .frame(height: 36)

            HStack(spacing: 3) {
                Text(String(format: "%.0f°", day.highTemp))
                    .font(.system(size: 33, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(String(format: "%.0f°", day.lowTemp))
                    .font(.system(size: 27, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }

            Text(day.conditionText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    // MARK: - Alert Detection

    private struct WeatherAlert {
        let icon: String
        let message: String
        let color: Color
    }

    private func findUpcomingChange() -> WeatherAlert? {
        guard let current = weather, daily.count >= 2 else { return nil }

        let tomorrow = daily[1]

        // Rain/snow/storm tomorrow
        switch tomorrow.weatherCode {
        case 61, 63, 65, 80, 81, 82:
            return WeatherAlert(icon: "cloud.rain.fill", message: "Yarın yağmur bekleniyor", color: Theme.accentBlue)
        case 71, 73, 75, 85, 86:
            return WeatherAlert(icon: "cloud.snow.fill", message: "Yarın kar bekleniyor", color: .white)
        case 95, 96, 99:
            return WeatherAlert(icon: "cloud.bolt.fill", message: "Yarın fırtına bekleniyor", color: Theme.accentOrange)
        default:
            break
        }

        // Big temperature swing
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

    // MARK: - Helpers

    private func statRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Theme.accentCyan.opacity(0.7))
                .frame(width: 26)
            Text(label)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
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
