import Foundation
import Testing
@testable import EdgeControl

private let english = Locale(identifier: "en_US")

/// Formatters put thin and narrow spaces around times; the tests compare words.
private func plain(_ text: String?) -> String? {
    text.map { String($0.map { $0.isWhitespace ? " " : $0 }) }
}

private func phrase(_ expected: ParcelSchedule.Expected) -> ParcelSchedule.Phrase {
    ParcelSchedule.phrase(for: expected, now: parcelNow, calendar: newYork, locale: english)
}

@Suite("Parcel dates")
struct ParcelScheduleTests {
    @Test(
        "the forms Parcel and carriers write",
        arguments: [
            ("2026-10-09 09:00:00", newYorkDate(2026, 10, 9, 9), true),
            ("2026-10-09T09:00", newYorkDate(2026, 10, 9, 9), true),
            ("2026-10-09  \t09:00:00", newYorkDate(2026, 10, 9, 9), true),
            ("2026-10-09", newYorkDate(2026, 10, 9), false),
            ("2026-10-09 00:00:00", newYorkDate(2026, 10, 9), false),
            ("2026-10-09T13:00:00Z", newYorkDate(2026, 10, 9, 9), true),
            ("2026-10-09T09:00:00.250-04:00", newYorkDate(2026, 10, 9, 9), true),
            ("October 9, 2026", newYorkDate(2026, 10, 9), false),
            ("Oct 9 2026 14:30", newYorkDate(2026, 10, 9, 14, 30), true),
            ("Friday, October 9, 2026 2:30 PM", newYorkDate(2026, 10, 9, 14, 30), true),
            ("October 7, 2026 2:41 PM EDT", newYorkDate(2026, 10, 7, 14, 41), true),
            ("October 7, 2026 11:41 AM PDT", newYorkDate(2026, 10, 7, 14, 41), true),
            ("Sept 9, 2026 12:05 AM", newYorkDate(2026, 9, 9, 0, 5), true),
            ("9 October 2026 14:30", newYorkDate(2026, 10, 9, 14, 30), true),
            ("13.10.2026 08:15", newYorkDate(2026, 10, 13, 8, 15), true),
            ("10/13/2026 8:15 AM", newYorkDate(2026, 10, 13, 8, 15), true),
        ])
    func reads(raw: String, date: Date, hasTime: Bool) {
        let reading = ParcelSchedule.parse(raw, calendar: newYork, near: parcelNow)
        #expect(reading == .init(date: date, hasTime: hasTime))
    }

    @Test("dotted dates that could go either way are read the way that's nearer today")
    func ambiguous() {
        // UPS writes month first, others day first; on 8 October both of
        // these mean today, not 10 August.
        #expect(
            ParcelSchedule.parse("10.08.2026 07:05", calendar: newYork, near: parcelNow)?.date
                == newYorkDate(2026, 10, 8, 7, 5))
        #expect(
            ParcelSchedule.parse("08.10.2026", calendar: newYork, near: parcelNow)?.date == newYorkDate(2026, 10, 8))
    }

    @Test(
        "placeholders, words and impossible dates stay unread",
        arguments: [
            "", "--//--", "soon", "2026-02-30", "2026-10-09 25:00", "February 30, 2026", "13:00 PM October 9, 2026",
            "Thursday, 8 October 5:26 am",
        ])
    func unread(raw: String) {
        #expect(ParcelSchedule.parse(raw, calendar: newYork, near: parcelNow) == nil)
    }

    @Test("timestamps win, unless the string beside them says only the day is known")
    func timestamps() {
        let exact = ParcelSchedule.expected(
            timestamp: 1_791_468_000, timestampEnd: 1_791_482_400, date: "2026-10-08 10:00:00", dateEnd: nil,
            calendar: newYork, near: parcelNow)
        #expect(exact?.start == Date(timeIntervalSince1970: 1_791_468_000))
        #expect(exact?.end == Date(timeIntervalSince1970: 1_791_482_400))
        #expect(exact?.hasTime == true)

        // Midnight UTC is the evening before in New York; the string's day is meant.
        let day = ParcelSchedule.expected(
            timestamp: 1_791_417_600, timestampEnd: nil, date: "2026-10-08", dateEnd: nil, calendar: newYork,
            near: parcelNow)
        #expect(day == .init(start: newYorkDate(2026, 10, 8), hasTime: false))

        let milliseconds = ParcelSchedule.expected(
            timestamp: 1_791_468_000_000, timestampEnd: 1_791_400_000, date: nil, dateEnd: nil, calendar: newYork,
            near: parcelNow)
        #expect(milliseconds == .init(start: Date(timeIntervalSince1970: 1_791_468_000), hasTime: true))
        #expect(
            ParcelSchedule.expected(
                timestamp: 0, timestampEnd: nil, date: "--//--", dateEnd: nil, calendar: newYork, near: parcelNow)
                == nil)
    }

    @Test(
        "days read the way people say them",
        arguments: [
            (newYorkDate(2026, 10, 8), "Today"), (newYorkDate(2026, 10, 9), "Tomorrow"),
            (newYorkDate(2026, 10, 7), "Yesterday"), (newYorkDate(2026, 10, 11), "Sunday"),
            (newYorkDate(2026, 10, 20), "Oct 20"),
        ])
    func days(day: Date, text: String) {
        #expect(phrase(.init(start: day, hasTime: false)).day == text)
    }

    @Test("a window is its day and its hours")
    func window() {
        let said = phrase(.init(start: newYorkDate(2026, 10, 9, 9), end: newYorkDate(2026, 10, 9, 13), hasTime: true))
        #expect(said.day == "Tomorrow")
        #expect(plain(said.time) == "9 AM – 1 PM")
        #expect(!said.isLate)
        #expect(plain(phrase(.init(start: newYorkDate(2026, 10, 8, 14, 30), hasTime: true)).time) == "2:30 PM")
        #expect(phrase(.init(start: newYorkDate(2026, 10, 8), hasTime: false)).time == nil)
    }

    @Test("several days are a range of days, without a time")
    func range() {
        let said = phrase(.init(start: newYorkDate(2026, 10, 9, 9), end: newYorkDate(2026, 10, 11, 17), hasTime: true))
        #expect(said.day == "Tomorrow–Sun")
        #expect(said.time == nil)
    }

    @Test("a window that ends at midnight belongs to its own day")
    func toMidnight() {
        let said = phrase(.init(start: newYorkDate(2026, 10, 9, 20), end: newYorkDate(2026, 10, 10), hasTime: true))
        #expect(said.day == "Tomorrow")
        #expect(plain(said.time) == "8 PM – 12 AM")
    }

    @Test("late only once the last expected day has gone by")
    func late() {
        #expect(!phrase(.init(start: newYorkDate(2026, 10, 6), end: newYorkDate(2026, 10, 8), hasTime: false)).isLate)
        #expect(phrase(.init(start: newYorkDate(2026, 10, 6), end: newYorkDate(2026, 10, 7), hasTime: false)).isLate)
        #expect(phrase(.init(start: newYorkDate(2026, 10, 7, 9), hasTime: true)).isLate)
    }

    @Test(
        "an event's time is the time if it was today, else its day",
        arguments: [
            ("Thursday, October 8, 2026 6:12 AM", "6:12 AM"), ("October 7, 2026 2:41 PM EDT", "Yesterday"),
            ("2026-10-08", "Today"), ("2026-10-05 10:00", "Oct 5"),
        ])
    func when(raw: String, text: String) {
        #expect(plain(ParcelSchedule.when(raw, now: parcelNow, calendar: newYork, locale: english)) == text)
    }

    @Test("an event date nobody can read gives no time at all")
    func unreadEvent() {
        #expect(ParcelSchedule.when("Saturday, 31 May 5:26 am", now: parcelNow, calendar: newYork) == nil)
        #expect(ParcelSchedule.when("", now: parcelNow, calendar: newYork) == nil)
    }
}
