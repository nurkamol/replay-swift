@testable import ReplayCore
import Foundation
import Testing

/// Pausing that ends on its own.
///
/// The rules are small and two of them are easy to get wrong in a way nobody notices for a
/// day: what "until tomorrow" means, and whether a deadline that passed while the Mac was
/// asleep counts. Both fail silently — the app simply does not record — which is the failure
/// this feature exists to prevent, so it is the failure worth testing hardest.
@Suite("Pausing")
struct PauseBehaviour {

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func at(_ hour: Int, _ minute: Int = 0) -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 7
        parts.day = 29
        parts.hour = hour
        parts.minute = minute
        return calendar().date(from: parts)!
    }

    @Test("The short spans are what they say")
    func shortSpans() {
        let now = Self.at(14, 20)
        #expect(Pause.ends(.fifteenMinutes, from: now, calendar: Self.calendar())
            == now.addingTimeInterval(900))
        #expect(Pause.ends(.hour, from: now, calendar: Self.calendar())
            == now.addingTimeInterval(3600))
    }

    @Test("Until tomorrow is the next midnight, not this time tomorrow")
    func untilTomorrowIsMidnight() {
        // The case that matters: pausing in the afternoon should give the day back at
        // midnight, not eat until 2pm the following day.
        let afternoon = Self.at(14, 20)
        #expect(Pause.ends(.untilTomorrow, from: afternoon, calendar: Self.calendar())
            == Self.at(24))
    }

    @Test("Until tomorrow just after midnight is only hours, not a whole day")
    func untilTomorrowFromTheSmallHours() {
        // Somebody pausing at half past midnight means "the rest of tonight" — the next
        // midnight is 23 and a half hours away, and that is the honest reading. This is here
        // because the naïve "add 24 hours" would silently cost the whole of the next day.
        let lateNight = Self.at(0, 30)
        #expect(Pause.ends(.untilTomorrow, from: lateNight, calendar: Self.calendar())
            == Self.at(24))
    }

    @Test("A deadline that has passed is over, including one slept through")
    func deadlinesExpire() {
        let deadline = Self.at(15)
        #expect(!Pause.isOver(until: deadline, now: Self.at(14, 59)))
        #expect(Pause.isOver(until: deadline, now: deadline))
        // The Mac was shut at 2pm and opened at 6pm. Nothing was running to notice 3pm, and
        // a comparison against the clock does not need to have been.
        #expect(Pause.isOver(until: deadline, now: Self.at(18)))
    }

    @Test("An indefinite pause never ends by itself")
    func indefiniteNeverExpires() {
        #expect(!Pause.isOver(until: nil, now: Self.at(23, 59)))
        #expect(!Pause.stillPaused(until: nil, now: Self.at(9)))
    }

    @Test("A timed pause survives a relaunch; an expired one does not")
    func survivesALaunch() {
        let deadline = Self.at(15)
        #expect(Pause.stillPaused(until: deadline, now: Self.at(14, 30)))
        #expect(!Pause.stillPaused(until: deadline, now: Self.at(15, 1)))
    }
}
