import Foundation

/// What Replay can be asked, in one sentence each.
///
/// The bodies of the App Intents live here rather than beside their `AppIntent`
/// conformances, for two reasons. `AppIntents` is unavailable to `ParityKit`, so anything
/// written next to an intent cannot be tested — and these are exactly the sentences that
/// have to be right, because a Shortcut is read aloud or dropped into another app, with no
/// interface around it to give it context. And an intent may run while the app is not, so
/// this opens the store itself and closes it again; nothing here touches a running model.
///
/// **Read-only, without exception.** Everything an intent can ask for is a question, and
/// nothing it can do changes the record. That is not a limitation to lift later: a Shortcut
/// runs unattended, and an unattended thing that can delete a day is a bad trade for any
/// convenience it buys.
public enum Answers {

    /// A day, answered.
    public struct Day: Equatable, Sendable {
        public var dayStart: Int64
        public var activeSeconds: Int
        public var sessionCount: Int
        public var appsUsed: Int
        public var topApp: String?
        /// The whole answer, as a person would say it.
        public var sentence: String
    }

    /// How long a given day held, and what most of it was.
    ///
    /// Runs the same `computeDaySummary` the app's own headline does, over the same
    /// "began that day" filter (SPEC §5), so an answer given in Shortcuts and the figure at
    /// the top of Today can never disagree. That mattered enough to be worth the extra
    /// query: two numbers for one day, differing by a session that crossed midnight, would
    /// be the kind of bug nobody reports and nobody trusts the app after.
    public static func day(
        _ dayStart: Int64, store: ActivityStore, now: Int64, calendar: Calendar = .current,
        locale: Locale = .current
    ) throws -> Day {
        let start = startOfLocalDay(dayStart, calendar: calendar)
        let events = try store.sessions(from: start, to: start + dayMillis)
            .filter { $0.startedAt >= start }
        let timeline = buildTimeline(events, now: now)
        let summary = computeDaySummary(
            events: events, timeline: timeline, dayStart: start, now: now
        )
        let label = dayLabel(start, now: now, calendar: calendar, locale: locale)
        return Day(
            dayStart: start,
            activeSeconds: summary.activeSeconds,
            sessionCount: summary.sessionCount,
            appsUsed: summary.appsUsed,
            topApp: summary.mostUsed?.applicationName,
            sentence: sentence(label: label, summary: summary)
        )
    }

    /// Says what is known and stops.
    ///
    /// A day with nothing in it gets "nothing recorded" rather than "0m active", because
    /// zero minutes and no record are different claims and only one of them is true when
    /// Replay was not running.
    private static func sentence(label: String, summary: DaySummary) -> String {
        guard summary.activeSeconds > 0 else { return "\(label): nothing recorded." }
        var text = "\(label): \(formatDurationShort(summary.activeSeconds)) active"
        if let top = summary.mostUsed?.applicationName { text += ", mostly in \(top)" }
        if summary.sessionCount > 0 {
            let sessions = summary.sessionCount == 1 ? "session" : "sessions"
            text += ", across \(summary.sessionCount) \(sessions)"
        }
        return text + "."
    }

    /// "Today", "Yesterday", or the date — the same words the rest of the app uses.
    private static func dayLabel(
        _ dayStart: Int64, now: Int64, calendar: Calendar, locale: Locale
    ) -> String {
        let today = startOfLocalDay(now, calendar: calendar)
        if dayStart == today { return "Today" }
        if dayStart == startOfLocalDay(today - dayMillis, calendar: calendar) {
            return "Yesterday"
        }
        return fullDayLabel(dayStart, calendar: calendar, locale: locale)
    }

    /// How long one application had, on a given day.
    ///
    /// Answers by name, matched case- and diacritic-insensitively, because the name is
    /// typed or spoken into a Shortcut rather than picked from a list — "xcode" has to find
    /// Xcode or the intent is a quiz.
    public static func application(
        named name: String, on dayStart: Int64, store: ActivityStore, now: Int64,
        calendar: Calendar = .current
    ) throws -> (name: String, seconds: Int)? {
        let start = startOfLocalDay(dayStart, calendar: calendar)
        let events = try store.sessions(from: start, to: start + dayMillis)
            .filter { $0.startedAt >= start }
        let (apps, _) = summarizeApps(excludeIdleStretches(events, now: now), now: now)
        let wanted = apps.first {
            $0.applicationName.compare(
                name, options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
        guard let wanted else { return nil }
        return (wanted.applicationName, wanted.seconds)
    }
}
