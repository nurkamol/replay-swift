@testable import ReplayCore
import Foundation
import Testing

/// The sentences this app assembles, in two languages at once.
///
/// Every case here is really the same claim: **the English is the contract and the
/// translation is a second rendering of it, never a replacement.** The parity suite already
/// compares the English against `spec/`; what it cannot see is a translation quietly becoming
/// the thing that gets checked, or a branch existing in one rendering and not the other.
@Suite("Runtime copy")
struct RuntimeCopyBehaviour {

    private static func app(_ name: String, share: Double) -> SessionApp {
        SessionApp(
            applicationName: name, bundleIdentifier: "test.\(name)", appPath: nil,
            seconds: Int(share * 1000), share: share, switches: 1
        )
    }

    /// 10:00 on a fixed day, so "Morning" is not a property of when the suite runs.
    private static func morning() -> Int64 {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 7; parts.day = 29; parts.hour = 10
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return Int64(calendar.date(from: parts)!.timeIntervalSince1970 * 1000)
    }

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test("Each branch renders the title the reference writes")
    func englishIsUnchanged() {
        #expect(SessionTitle.inApp(part: "Morning", app: "Xcode").english == "Morning in Xcode")
        #expect(
            SessionTitle.category(part: "Evening", category: .research).english
                == "Evening Research Session"
        )
        #expect(SessionTitle.plain(part: "Late night").english == "Late night Session")
    }

    @Test("The parts a session gets are the parts its English title was built from")
    func partsMatchTheTitle() {
        // The point of splitting the decision out: `nameSession` must be exactly
        // `sessionTitle` rendered in English, or a translated title could name a different
        // app from the one the timeline shows.
        let cases: [[SessionApp]] = [
            [Self.app("Xcode", share: 0.9), Self.app("Firefox", share: 0.1)],   // one app dominates
            [Self.app("Xcode", share: 0.5), Self.app("Terminal", share: 0.5)],  // a category does
            [Self.app("Preview", share: 0.5), Self.app("Finder", share: 0.5)],  // neither
            [],                                                        // nothing at all
        ]
        for apps in cases {
            let start = Self.morning()
            let named = nameSession(apps: apps, startedAt: start, calendar: Self.calendar())
            let parts = sessionTitle(apps: apps, startedAt: start, calendar: Self.calendar())
            #expect(named.title == parts.title.english)
            #expect(named.category == parts.category)
        }
    }

    @Test("With no language chosen, the translation is the English")
    func fallsBackToEnglish() {
        Loc.override = nil
        #expect(
            RuntimeCopy.sessionTitle(.inApp(part: "Morning", app: "Xcode")) == "Morning in Xcode"
        )
        // An app's name is a proper noun and is never looked up — translating "Firefox" would
        // put software nobody has into somebody's timeline.
        #expect(
            RuntimeCopy.sessionTitle(.inApp(part: "Evening", app: "Firefox"))
                .contains("Firefox")
        )
    }

    @Test("A gap is described the same way twice, once per language")
    func breaksMirrorTheContract() {
        Loc.override = nil
        for reason in [BreakReason.unrecorded, .away, .idle] {
            let gap = ActivityBreak(
                reason: reason, startedAt: 0, endedAt: 480_000, seconds: 480,
                applicationName: reason == .idle ? "Safari" : nil
            )
            // Same three branches, and with no override the words are identical. A reason
            // added to one and not the other shows up here rather than as an English line in
            // an otherwise translated timeline.
            #expect(RuntimeCopy.describeBreak(gap).title == describeBreak(gap).title)
            #expect(RuntimeCopy.describeBreak(gap).detail == describeBreak(gap).detail)
        }
    }

    @Test("The clock inside a time label is never rewritten")
    func clockSurvives() {
        Loc.override = nil
        let now = Self.morning()
        let label = RuntimeCopy.formatWhen(now, now: now, calendar: Self.calendar())
        // The reference's twelve-hour clock is checked character for character elsewhere;
        // only the words around it are allowed to move.
        #expect(label == formatWhen(now, now: now, calendar: Self.calendar()))
        #expect(label.contains("10:00 AM"))
    }
}
