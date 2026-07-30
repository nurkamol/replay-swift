@testable import ReplayCore
import Foundation
import Testing

/// Memories, said twice — once as the reference writes it and once in the reader's language.
///
/// The risk this guards is not a wrong translation; it is a *missing* one. Every card on that
/// surface is a sentence assembled from a number, an app's name and a day, so a producer added
/// upstream arrives with English `title`/`detail` and no localised counterpart, and the surface
/// silently goes back to being half English. These cases walk every kind rather than the ones
/// that happened to be written first.
@Suite("Moment copy")
struct MomentCopyBehaviour {

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func at(_ day: Int) -> Int64 {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 7; parts.day = day; parts.hour = 10
        return Int64(calendar().date(from: parts)!.timeIntervalSince1970 * 1000)
    }

    /// One of every kind, with facts filled in as its producer fills them.
    private static func everyKind() -> [Moment] {
        [
            Moment(kind: .longestFocus, key: "a", title: "T", detail: "D",
                   facts: .init(seconds: 4_500, app: "Firefox", at: at(24))),
            Moment(kind: .peakDay, key: "b", title: "T", detail: "D",
                   facts: .init(seconds: 35_220, app: "Terminal", at: at(25))),
            Moment(kind: .busyMix, key: "c", title: "T", detail: "D",
                   facts: .init(count: 43, at: at(25))),
            Moment(kind: .nightOwl, key: "d", title: "T", detail: "D", facts: .init(at: at(28))),
            Moment(kind: .streak, key: "e", title: "T", detail: "D",
                   facts: .init(count: 6, at: at(29))),
            Moment(kind: .newApp, key: "f", title: "T", detail: "D",
                   facts: .init(app: "Screen Sharing", at: at(29))),
            Moment(kind: .origin, key: "g", title: "T", detail: "D",
                   facts: .init(count: 6, at: at(24))),
        ]
    }

    @Test("Every kind says something, and never the placeholder it was given")
    func everyKindIsSaid() {
        Loc.override = nil
        let now = Self.at(30)
        for moment in Self.everyKind() {
            let said = RuntimeCopy.moment(moment, now: now, calendar: Self.calendar())
            #expect(!said.title.isEmpty)
            #expect(!said.detail.isEmpty)
            // "T"/"D" are what the producer would return if a kind fell through to the
            // English — which is the failure this suite exists to catch.
            #expect(said.title != "T")
            #expect(said.detail != "D")
        }
    }

    @Test("Every kind covers all seven, so a new one cannot be forgotten")
    func coversEveryKind() {
        #expect(Set(Self.everyKind().map(\.kind)).count == 7)
    }

    @Test("An app's name is carried through and never translated")
    func appNamesSurvive() {
        Loc.override = nil
        let now = Self.at(30)
        for moment in Self.everyKind() where moment.facts.app != nil {
            let said = RuntimeCopy.moment(moment, now: now, calendar: Self.calendar())
            let app = moment.facts.app!
            #expect(said.title.contains(app) || said.detail.contains(app))
        }
    }

    @Test("A day is named by how far away it is")
    func relativeDays() {
        Loc.override = nil
        let now = Self.at(30)
        let calendar = Self.calendar()
        #expect(RuntimeCopy.relativeDay(Self.at(30), now: now, calendar: calendar) == "today")
        #expect(RuntimeCopy.relativeDay(Self.at(29), now: now, calendar: calendar) == "yesterday")
        #expect(RuntimeCopy.relativeDay(Self.at(27), now: now, calendar: calendar) == "3 days ago")
        // Past a week it becomes a date rather than a count somebody has to do arithmetic on.
        let far = RuntimeCopy.relativeDay(Self.at(20), now: now, calendar: calendar)
        #expect(far.hasPrefix("on "))
    }

    @Test("A first day says so instead of counting zero")
    func originOnDayOne() {
        Loc.override = nil
        let moment = Moment(kind: .origin, key: "g", title: "T", detail: "D",
                            facts: .init(count: 0, at: Self.at(30)))
        let said = RuntimeCopy.moment(moment, now: Self.at(30), calendar: Self.calendar())
        #expect(said.detail.contains("today"))
    }
}
