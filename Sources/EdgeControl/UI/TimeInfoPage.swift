import SwiftUI

/// Page 7: World Clocks + Day Progress + Moon Phase
struct TimeInfoPage: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            worldClocksPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            divider()

            dayProgressPanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            divider()

            moonPhasePanel()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(timer) { now = $0 }
    }

    private func divider() -> some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.08), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
            .frame(width: 1).padding(.vertical, 20)
    }

    // MARK: - World Clocks

    private let worldClocks: [(city: String, tz: String, flag: String)] = [
        ("Istanbul", "Europe/Istanbul", "🇹🇷"),
        ("New York", "America/New_York", "🇺🇸"),
        ("London", "Europe/London", "🇬🇧"),
        ("Tokyo", "Asia/Tokyo", "🇯🇵"),
        ("Sydney", "Australia/Sydney", "🇦🇺"),
        ("Dubai", "Asia/Dubai", "🇦🇪"),
    ]

    private func worldClocksPanel() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentCyan).frame(width: 10, height: 10)
                Text("WORLD CLOCKS")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(worldClocks, id: \.tz) { clock in
                    clockCard(clock)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func clockCard(_ clock: (city: String, tz: String, flag: String)) -> some View {
        let tz = TimeZone(identifier: clock.tz) ?? .current
        let formatter = DateFormatter()
        formatter.timeZone = tz
        formatter.dateFormat = "HH:mm"
        let time = formatter.string(from: now)
        formatter.dateFormat = "EEE"
        let day = formatter.string(from: now)

        let hourDiff = tz.secondsFromGMT(for: now) / 3600
        let localDiff = TimeZone.current.secondsFromGMT(for: now) / 3600
        let diff = hourDiff - localDiff

        return VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(clock.flag)
                    .font(.system(size: 22))
                Text(clock.city)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            HStack {
                Text(time)
                    .font(.system(size: 36, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(day.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Text(diff >= 0 ? "+\(diff)h" : "\(diff)h")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.accentCyan)
                }
            }
        }
        .padding(12)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))
    }

    // MARK: - Day Progress

    private func dayProgressPanel() -> some View {
        let calendar = Calendar.current

        let dayProgress = Double(calendar.component(.hour, from: now) * 3600 + calendar.component(.minute, from: now) * 60 + calendar.component(.second, from: now)) / 86400.0

        let weekday = calendar.component(.weekday, from: now)
        let weekProgress = Double(weekday - calendar.firstWeekday + (weekday < calendar.firstWeekday ? 7 : 0)) / 7.0 + dayProgress / 7.0

        let day = calendar.component(.day, from: now)
        let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        let monthProgress = (Double(day - 1) + dayProgress) / Double(daysInMonth)

        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        let yearProgress = Double(dayOfYear - 1 + (dayProgress > 0 ? 1 : 0)) / Double(daysInYear)

        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentGreen).frame(width: 10, height: 10)
                Text("DAY PROGRESS")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            progressCard(label: "DAY", progress: dayProgress, color: Theme.accentCyan)
            progressCard(label: "WEEK", progress: weekProgress, color: Theme.accentGreen)
            progressCard(label: "MONTH", progress: monthProgress, color: Theme.accentPurple)
            progressCard(label: "YEAR", progress: yearProgress, color: Theme.accentOrange)

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func progressCard(label: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(String(format: "%.1f%%", progress * 100))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(progress, 1))
                }
            }
            .frame(height: 18)
        }
        .padding(14)
        .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))
    }

    // MARK: - Moon Phase

    private func moonPhasePanel() -> some View {
        let phase = lunarPhase(for: now)

        return VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accentYellow).frame(width: 10, height: 10)
                Text("MOON PHASE")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            // Moon display
            VStack(spacing: 12) {
                Text(phase.emoji)
                    .font(.system(size: 120))

                Text(phase.name.uppercased())
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text(String(format: "%.0f%% ILLUMINATED", phase.illumination * 100))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accentYellow)

                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", phase.age))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                        Text("DAYS")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", phase.nextFull))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accentYellow)
                            .monospacedDigit()
                        Text("TO FULL")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.backgroundCard, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous).strokeBorder(Theme.borderSubtle, lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Lunar Phase Calculation

    private struct LunarPhase {
        let name: String
        let emoji: String
        let illumination: Double
        let age: Double     // days into cycle
        let nextFull: Double // days until full
    }

    private func lunarPhase(for date: Date) -> LunarPhase {
        // Synodic month: 29.53059 days
        let synodicMonth = 29.53059
        // Known new moon: Jan 6, 2000
        let knownNewMoon = DateComponents(calendar: .init(identifier: .gregorian), year: 2000, month: 1, day: 6).date!
        let daysSince = date.timeIntervalSince(knownNewMoon) / 86400
        let age = daysSince.truncatingRemainder(dividingBy: synodicMonth)
        let normalizedAge = age < 0 ? age + synodicMonth : age
        let phase = normalizedAge / synodicMonth // 0 to 1

        let illumination: Double
        if phase <= 0.5 {
            illumination = phase * 2
        } else {
            illumination = (1 - phase) * 2
        }

        let name: String
        let emoji: String
        switch phase {
        case 0..<0.033: name = "New Moon"; emoji = "🌑"
        case 0.033..<0.25: name = "Waxing Crescent"; emoji = "🌒"
        case 0.25..<0.283: name = "First Quarter"; emoji = "🌓"
        case 0.283..<0.5: name = "Waxing Gibbous"; emoji = "🌔"
        case 0.5..<0.533: name = "Full Moon"; emoji = "🌕"
        case 0.533..<0.75: name = "Waning Gibbous"; emoji = "🌖"
        case 0.75..<0.783: name = "Last Quarter"; emoji = "🌗"
        default: name = "Waning Crescent"; emoji = "🌘"
        }

        let daysToFull = phase < 0.5 ? (0.5 - phase) * synodicMonth : (1.5 - phase) * synodicMonth

        return LunarPhase(name: name, emoji: emoji, illumination: illumination, age: normalizedAge, nextFull: daysToFull)
    }
}
