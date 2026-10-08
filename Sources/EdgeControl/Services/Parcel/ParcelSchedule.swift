import Foundation

/// When Parcel expects a delivery, and how to say so.
///
/// Parcel passes on what carriers write. Its expected dates come as Unix
/// timestamps when the carrier gave a full date, time and zone, and
/// otherwise as strings without a zone, which are local. Event dates are
/// whatever the carrier printed. The forms here are the ones seen in Parcel
/// replies; anything else is left unread, and the widget leaves the time
/// out rather than guess at it.
public enum ParcelSchedule {
    public struct Expected: Equatable, Sendable {
        public var start: Date
        public var end: Date?
        /// False when only the day is known. Carriers write midnight for
        /// "some time that day", so midnight is a day, not a time.
        public var hasTime: Bool

        public init(start: Date, end: Date? = nil, hasTime: Bool) {
            self.start = start
            self.end = end
            self.hasTime = hasTime
        }
    }

    /// A date read from a string, and whether it had a time of day.
    public struct Reading: Equatable, Sendable {
        public var date: Date
        public var hasTime: Bool
    }

    /// How the widget says when: "Tomorrow" and "2 – 6 PM".
    public struct Phrase: Equatable, Sendable {
        public var day: String
        public var time: String?
        /// The last expected day has gone by.
        public var isLate: Bool
    }

    // MARK: - Expected

    static func expected(
        timestamp: Double?, timestampEnd: Double?, date: String?, dateEnd: String?,
        calendar: Calendar, near now: Date
    ) -> Expected? {
        let start = date.flatMap { parse($0, calendar: calendar, near: now) }
        let end = dateEnd.flatMap { parse($0, calendar: calendar, near: now) }
        // A timestamp is exact, unless the string beside it says the carrier
        // only knows the day: then the timestamp is that day's midnight
        // somewhere, and the day is what's meant.
        if let instant = instant(timestamp), start?.hasTime != false {
            let until = self.instant(timestampEnd).flatMap { $0 >= instant ? $0 : nil }
            return Expected(start: instant, end: until, hasTime: true)
        }
        guard let start else { return nil }
        let until = end.flatMap { $0.date >= start.date ? $0.date : nil }
        return Expected(start: start.date, end: until, hasTime: start.hasTime || (end?.hasTime ?? false))
    }

    /// Seconds since 1970; a value too big to be seconds is milliseconds.
    static func instant(_ value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        return Date(timeIntervalSince1970: value > 100_000_000_000 ? value / 1000 : value)
    }

    // MARK: - Reading dates

    /// Reads the date forms Parcel and its carriers use, in `calendar`'s time
    /// zone unless the string names one. `now` settles dotted dates where the
    /// day and month could be either way round: the nearer reading wins.
    public static func parse(_ raw: String, calendar: Calendar, near now: Date) -> Reading? {
        let text = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard text.contains(where: \.isNumber) else { return nil }

        if let match = text.wholeMatch(of: isoWithZone) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let normalized = text.replacingOccurrences(of: " ", with: "T").replacingOccurrences(
                of: #"\.\d+"#, with: "", options: .regularExpression)
            guard let date = formatter.date(from: normalized) else { return nil }
            return Reading(date: date, hasTime: !(match.1 == "00" && match.2 == "00" && (match.3 ?? "00") == "00"))
        }
        if let match = text.wholeMatch(of: isoLocal) {
            return reading(
                year: match.1, month: Int(match.2), day: match.3, hour: match.4, minute: match.5, second: match.6,
                calendar: calendar)
        }
        if let match = text.wholeMatch(of: monthFirst), let month = month(named: match.1) {
            return reading(
                year: match.3, month: month, day: match.2, hour: match.4, minute: match.5, second: match.6,
                meridiem: match.7, zone: match.8, calendar: calendar)
        }
        if let match = text.wholeMatch(of: dayFirst), let month = month(named: match.2) {
            return reading(
                year: match.3, month: month, day: match.1, hour: match.4, minute: match.5, second: match.6,
                meridiem: match.7, zone: match.8, calendar: calendar)
        }
        if let match = text.wholeMatch(of: numeric), let first = Int(match.1), let second = Int(match.2) {
            let readings = [(month: first, day: second), (month: second, day: first)].compactMap {
                reading(
                    year: match.3, month: $0.month, day: Substring(String($0.day)), hour: match.4, minute: match.5,
                    second: match.6, meridiem: match.7, zone: nil, calendar: calendar)
            }
            return readings.min { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }
        }
        return nil
    }

    /// "2026-10-08T14:30:00Z", "2026-10-08 14:30:00.5-04:00"
    private nonisolated(unsafe) static let isoWithZone =
        /\d{4}-\d{2}-\d{2}[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})/
    /// "2026-10-08", "2026-10-08 14:30", "2026-10-08T14:30:00"
    private nonisolated(unsafe) static let isoLocal =
        /(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?/
    /// "October 8, 2026", "Thursday, October 8, 2026 2:30 PM EDT", "Oct 8 2026 14:30"
    private nonisolated(unsafe) static let monthFirst =
        /(?:[A-Za-z]+,? )?([A-Za-z]+)\.? (\d{1,2}),? (\d{4})(?:,? (\d{1,2}):(\d{2})(?::(\d{2}))? ?([AaPp]\.?[Mm]\.?)?(?: ([A-Z]{2,5}))?)?/
    /// "8 October 2026 14:30", "Thursday, 8 Oct 2026"
    private nonisolated(unsafe) static let dayFirst =
        /(?:[A-Za-z]+,? )?(\d{1,2}) ([A-Za-z]+)\.?,? (\d{4})(?:,? (\d{1,2}):(\d{2})(?::(\d{2}))? ?([AaPp]\.?[Mm]\.?)?(?: ([A-Z]{2,5}))?)?/
    /// "10.08.2026 14:30", "08/10/2026 2:30 PM"
    private nonisolated(unsafe) static let numeric =
        /(\d{1,2})[.\/](\d{1,2})[.\/](\d{4})(?:,? (\d{1,2}):(\d{2})(?::(\d{2}))? ?([AaPp]\.?[Mm]\.?)?)?/

    private static func month(named name: Substring) -> Int? {
        // Without a locale a calendar names its months "M01", "M02"…
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_US_POSIX")
        let key = name.lowercased()
        let names = english.monthSymbols.map { $0.lowercased() }
        if let index = names.firstIndex(of: key) { return index + 1 }
        // "Sept" as well as "Sep".
        guard key.count >= 3 else { return nil }
        return names.firstIndex { $0.hasPrefix(key) }.map { $0 + 1 }
    }

    /// Builds the date, refusing values that would roll over (October 32,
    /// 25 o'clock) rather than land on a different day than the one written.
    private static func reading(
        year: Substring, month: Int?, day: Substring, hour: Substring?, minute: Substring?, second: Substring?,
        meridiem: Substring? = nil, zone: Substring? = nil, calendar: Calendar
    ) -> Reading? {
        guard let year = Int(year), let month, let day = Int(day), (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        var hours = hour.flatMap { Int($0) } ?? 0
        let minutes = minute.flatMap { Int($0) } ?? 0
        let seconds = second.flatMap { Int($0) } ?? 0
        if let meridiem {
            guard (1...12).contains(hours) else { return nil }
            let pm = meridiem.lowercased().hasPrefix("p")
            hours = hours % 12 + (pm ? 12 : 0)
        }
        guard hours < 24, minutes < 60, seconds < 60 else { return nil }

        var calendar = calendar
        if let zone, let timeZone = TimeZone(abbreviation: String(zone)) { calendar.timeZone = timeZone }
        let components = DateComponents(
            year: year, month: month, day: day, hour: hours, minute: minutes, second: seconds)
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month
        else { return nil }
        return Reading(date: date, hasTime: hour != nil && (hours, minutes, seconds) != (0, 0, 0))
    }

    // MARK: - Saying when

    /// "Today", "Tomorrow", a weekday this week, or a date; a range of days
    /// when the carrier gives one; and the time or window when it's known.
    public static func phrase(
        for expected: Expected, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> Phrase {
        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: expected.start)
        var lastDay = startDay
        if let end = expected.end {
            // A window "8 PM until midnight" is over when the next day starts.
            let closing = expected.hasTime && end == calendar.startOfDay(for: end) && end > expected.start
            lastDay = calendar.startOfDay(for: closing ? end.addingTimeInterval(-1) : end)
        }
        let isLate = lastDay < today

        guard lastDay > startDay else {
            let time = expected.hasTime ? timeText(expected, calendar: calendar, locale: locale) : nil
            return Phrase(
                day: dayName(startDay, today: today, calendar: calendar, locale: locale), time: time, isLate: isLate)
        }
        // Several days: the days are the news, and a time would only be
        // the first day's.
        let first = shortDayName(startDay, today: today, calendar: calendar, locale: locale)
        let last = shortDayName(lastDay, today: today, calendar: calendar, locale: locale)
        return Phrase(day: first + "–" + last, time: nil, isLate: isLate)
    }

    /// A tracking event's date as the widget shows it: the time if it was
    /// today, else the day. Nil when the carrier's form can't be read.
    public static func when(
        _ raw: String, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> String? {
        guard let reading = parse(raw, calendar: calendar, near: now) else { return nil }
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: reading.date)
        if day == today, reading.hasTime {
            return formatter("jmm", calendar: calendar, locale: locale).string(from: reading.date)
        }
        return dayName(day, today: today, calendar: calendar, locale: locale)
    }

    static func dayName(_ day: Date, today: Date, calendar: Calendar, locale: Locale) -> String {
        switch calendar.dateComponents([.day], from: today, to: day).day ?? 0 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...6: return formatter("EEEE", calendar: calendar, locale: locale).string(from: day)
        default: return formatter("MMMd", calendar: calendar, locale: locale).string(from: day)
        }
    }

    private static func shortDayName(_ day: Date, today: Date, calendar: Calendar, locale: Locale) -> String {
        switch calendar.dateComponents([.day], from: today, to: day).day ?? 0 {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6: return formatter("EEE", calendar: calendar, locale: locale).string(from: day)
        default: return formatter("MMMd", calendar: calendar, locale: locale).string(from: day)
        }
    }

    /// "2:30 PM", or "9 AM – 1 PM". Each end is formatted on its own: an
    /// interval formatter adds the dates when a window ends at midnight.
    private static func timeText(_ expected: Expected, calendar: Calendar, locale: Locale) -> String {
        let ends = [expected.start] + (expected.end.map { $0 > expected.start ? [$0] : [] } ?? [])
        let onTheHour = ends.allSatisfy { calendar.component(.minute, from: $0) == 0 }
        let time = formatter(onTheHour ? "j" : "jmm", calendar: calendar, locale: locale)
        return ends.map(time.string(from:)).joined(separator: " – ")
    }

    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
