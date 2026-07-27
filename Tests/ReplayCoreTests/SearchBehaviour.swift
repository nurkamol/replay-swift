@testable import ReplayCore
import Foundation
import Testing

/// The parts of Search the generated contract does not reach.
///
/// `spec/` covers the two predicates — does a session match, does it use this app — because
/// the reference exports them from the view and the generator copies them out. Everything
/// around those is view-local upstream: the span a query looks back over, the phrase parser
/// that turns "last friday" into a day, and which run of text a result highlights. None of
/// it is in the contract, so none of it would fail loudly when it drifted. These are the
/// cases that would actually catch a mistake, rather than the ones that are easy to write.
@Suite("Search behaviour")
struct SearchBehaviour {

    /// A fixed calendar, so a span or an offset is not decided by the machine running this.
    private static func calendar(_ identifier: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func at(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12,
        calendar: Calendar = SearchBehaviour.calendar()
    ) -> Int64 {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return Int64(calendar.date(from: parts)!.timeIntervalSince1970 * 1000)
    }

    // ── how far back a span looks ─────────────────────────────────────────────

    @Test("A span starts at a local midnight, not at the current hour")
    func spansStartAtMidnight() {
        let calendar = Self.calendar()
        let now = Self.at(2026, 7, 15, 16, calendar: calendar)
        let midnight = startOfLocalDay(now, calendar: calendar)

        #expect(Search.Span.today.start(now: now, calendar: calendar) == midnight)
        // Seven days *including* today, which is six midnights back — not seven.
        #expect(Search.Span.week.start(now: now, calendar: calendar) == midnight - 6 * dayMillis)
        #expect(Search.Span.month.start(now: now, calendar: calendar) == midnight - 29 * dayMillis)
        #expect(Search.Span.all.start(now: now, calendar: calendar) == 0)
    }

    // ── a query that reads like a date ────────────────────────────────────────

    @Test("A phrase that names no day finds none")
    func ordinaryQueriesAreNotDates() {
        let calendar = Self.calendar()
        let now = Self.at(2026, 7, 15, calendar: calendar)
        for query in ["figma", "", "   ", "morning work", "next friday", "last quarter"] {
            #expect(Memories.day(matching: query, now: now, calendar: calendar) == nil)
        }
    }

    @Test("Today and yesterday land on their own midnights")
    func nearPhrases() {
        let calendar = Self.calendar()
        let now = Self.at(2026, 7, 15, 23, calendar: calendar)
        #expect(
            Memories.day(matching: "  Yesterday  ", now: now, calendar: calendar)
                == Self.at(2026, 7, 14, 0, calendar: calendar)
        )
        #expect(
            Memories.day(matching: "today", now: now, calendar: calendar)
                == Self.at(2026, 7, 15, 0, calendar: calendar)
        )
    }

    /// The case the whole parser is built around.
    ///
    /// JavaScript's `Date` constructor normalises an out-of-range day, so 31 March minus one
    /// month is 3 March. `Calendar.date(byAdding:)` would clamp to 28 February instead —
    /// a different day, in an app where the two are meant to agree about which day you are
    /// being shown. This is the same rule ``Memories/targets(now:calendar:)`` follows, and
    /// it has to hold here too or one route into a day disagrees with the other.
    @Test("A month back from the 31st overflows rather than clamping")
    func monthEndOverflows() {
        let calendar = Self.calendar()
        let now = Self.at(2026, 3, 31, calendar: calendar)
        #expect(
            Memories.day(matching: "last month", now: now, calendar: calendar)
                == Self.at(2026, 3, 3, 0, calendar: calendar)
        )
        // And the phrase parser and the offsets it shares arithmetic with must agree.
        let oneMonth = Memories.targets(now: now, calendar: calendar)
            .first { $0.key == "1mo" }?.dayStart
        #expect(Memories.day(matching: "a month ago", now: now, calendar: calendar) == oneMonth)
    }

    @Test("A year back from a leap day overflows to the 1st of March")
    func leapDayOverflows() {
        let calendar = Self.calendar()
        let now = Self.at(2024, 2, 29, calendar: calendar)
        #expect(
            Memories.day(matching: "one year ago", now: now, calendar: calendar)
                == Self.at(2023, 3, 1, 0, calendar: calendar)
        )
    }

    @Test("Every spelling of an offset means the same day")
    func spellingsAgree() {
        let calendar = Self.calendar()
        let now = Self.at(2026, 7, 15, calendar: calendar)
        let day = Memories.day(matching: "3 months ago", now: now, calendar: calendar)
        #expect(day == Memories.day(matching: "three months ago", now: now, calendar: calendar))
        #expect(day == Self.at(2026, 4, 15, 0, calendar: calendar))
    }

    /// 15 July 2026 is a Wednesday.
    @Test("A weekday means the most recent one, and \"last\" means the one before")
    func weekdays() {
        let calendar = Self.calendar()
        let now = Self.at(2026, 7, 15, calendar: calendar)

        // Monday, two days back.
        #expect(
            Memories.day(matching: "monday", now: now, calendar: calendar)
                == Self.at(2026, 7, 13, 0, calendar: calendar)
        )
        // Friday has not happened this week, so it is the one five days back.
        #expect(
            Memories.day(matching: "friday", now: now, calendar: calendar)
                == Self.at(2026, 7, 10, 0, calendar: calendar)
        )
        // Today *is* Wednesday, so the bare name is today...
        #expect(
            Memories.day(matching: "wednesday", now: now, calendar: calendar)
                == Self.at(2026, 7, 15, 0, calendar: calendar)
        )
        // ...and "last Wednesday" is the week before, not this morning.
        #expect(
            Memories.day(matching: "last wednesday", now: now, calendar: calendar)
                == Self.at(2026, 7, 8, 0, calendar: calendar)
        )
    }

    // ── what a result highlights ──────────────────────────────────────────────

    @Test("A highlight marks the first match, ignoring case and a leading hash")
    func highlighting() {
        let title = "Deep work in Figma"
        #expect(Search.firstMatch(of: "figma", in: title).map { String(title[$0]) } == "Figma")
        #expect(Search.firstMatch(of: "#deep", in: title).map { String(title[$0]) } == "Deep")
        #expect(Search.firstMatch(of: "  WORK ", in: title).map { String(title[$0]) } == "work")
        #expect(Search.firstMatch(of: "sketch", in: title) == nil)
        // A query that is nothing but a hash is not a match on everything.
        #expect(Search.firstMatch(of: "#", in: title) == nil)
        #expect(Search.firstMatch(of: "", in: title) == nil)
    }

    /// The predicate and the highlight have to agree about what counts as a match, or a
    /// result appears with nothing marked on it — which reads as a bug in the search.
    @Test("Anything the predicate matched by title, the highlight can find")
    func predicateAndHighlightAgree() {
        let session = ActivitySession(
            title: "Morning in Figma",
            category: .design,
            startedAt: Self.at(2026, 7, 15, 9),
            endedAt: Self.at(2026, 7, 15, 10),
            spanSeconds: 3600,
            activeSeconds: 3600,
            apps: [],
            events: [],
            switches: 1
        )
        for query in ["figma", "FIGMA", "morning", "in F"] {
            #expect(Search.matches(session: session, annotation: nil, query: query))
            #expect(Search.firstMatch(of: query, in: session.title) != nil)
        }
    }
}
