import Foundation

/// The sentences this app assembles rather than writes.
///
/// Most copy is a whole string in the source, and `Loc.t` translates it because the English
/// *is* the key. These are the ones that are not: a session title, a gap in the day, a figure
/// with a noun after it. They are built at runtime out of a number, an app's name and a
/// fragment — `"\(part) in \(app)"` — so there is no sentence to hand a translator, and a
/// table of half-clauses cannot be assembled into a language whose word order differs from
/// English. Which is most of them: in Uzbek the app name comes first and the time-of-day
/// after it, and no amount of translating "in" separately will produce that.
///
/// The fix is one format string per sentence, with positional arguments. `%1$@` and `%2$@`
/// let a translator put the pieces in whatever order the language needs, and the whole
/// sentence is a single row in the catalogue — which is the unit a translator can actually
/// work with.
///
/// **The English stays where it was.** Every function here has a counterpart that renders the
/// contract — `SessionTitle.english`, `describeBreak` — and those are what the parity suite
/// compares against `spec/`. This file is the second rendering, never the first, so a
/// translation can never move what the reference pinned.
public enum RuntimeCopy {

    /// A session's title in the reader's language: "Late night in Terminal".
    ///
    /// The day part and the category are translated as words in their own right; the app's
    /// name never is. "Firefox" is called Firefox everywhere, and translating a proper noun
    /// is how you get a timeline referring to software nobody has.
    public static func sessionTitle(_ title: SessionTitle) -> String {
        switch title {
        case let .inApp(part, app):
            String(format: Loc.t("%1$@ in %2$@"), dayPart(part), app)
        case let .category(part, category):
            String(
                format: Loc.t("%1$@ %2$@ Session"), dayPart(part), Loc.t(category.rawValue)
            )
        case let .plain(part):
            String(format: Loc.t("%@ Session"), dayPart(part))
        }
    }

    /// "Morning", "Afternoon", "Evening", "Late night" — the first word of every title.
    ///
    /// Translated through `Loc.t` like any other word. They arrive here as English strings
    /// rather than as a type because `dayPart(of:)` is contract-checked and returns one.
    public static func dayPart(_ english: String) -> String {
        // Spelled out for the same reason `partWord` below is: `Loc.t(english)` hands the key
        // scanner a variable, so these four exist in the catalogue only because other files
        // happen to name them. That is translation by coincidence, and an orphan sweep has
        // already deleted a set of day parts here once on exactly that reasoning.
        switch english {
        case "Morning": Loc.t("Morning")
        case "Afternoon": Loc.t("Afternoon")
        case "Evening": Loc.t("Evening")
        case "Late night": Loc.t("Late night")
        default: Loc.t(english)
        }
    }

    /// "Morning tends to lead with", as one sentence a translator can reorder.
    ///
    /// The app itself follows in the view, as an icon and a name, so this is the half that
    /// can move — which is the same shape the reference uses. A language that needs the
    /// application first cannot have it here; that would take the row itself being rebuilt.
    public static func ritualLead(part: String) -> String {
        String(format: Loc.t("%@ tends to lead with"), dayPart(part))
    }

    /// A gap in the day, in the reader's language.
    ///
    /// The English pair is `describeBreak`, which is generated from the reference's own
    /// `describeBreak` into `spec/grouping-and-export.json`. This mirrors its three branches
    /// and must keep mirroring them — a fourth reason added there needs one added here, which
    /// is what `BreakCopyBehaviour` checks.
    public static func describeBreak(_ item: ActivityBreak) -> BreakDescription {
        let length = formatDurationShort(item.seconds)
        switch item.reason {
        case .unrecorded:
            return BreakDescription(
                title: String(format: Loc.t("%@ not recorded"), length),
                detail: Loc.t("Replay wasn\u{2019}t running or tracking was paused")
            )
        case .away:
            return BreakDescription(
                title: String(format: Loc.t("%@ away"), length),
                detail: Loc.t("No keyboard or mouse activity")
            )
        case .idle:
            return BreakDescription(
                title: String(format: Loc.t("%@ break"), length),
                detail: item.applicationName
                    .map { String(format: Loc.t("%@ stayed in front, no switching"), $0) }
                    ?? Loc.t("No app switching")
            )
        }
    }

    /// "Today at 10:37 PM", in the reader's language.
    ///
    /// Mirrors ``formatWhen``, which is the contract — the clock itself comes from there
    /// unchanged, because the reference's twelve-hour format is checked character for
    /// character and a locale-aware clock would fail it. Only the words around it move.
    public static func formatWhen(
        _ timestamp: Int64, now: Int64,
        calendar: Calendar = .current
    ) -> String {
        let english = ReplayCore.formatWhen(
            timestamp, now: now, calendar: calendar, locale: Loc.locale
        )
        // The clock is everything after the last " at ", which is the one part that stays.
        guard let separator = english.range(of: " at ", options: .backwards) else {
            return english
        }
        let when = String(english[english.startIndex..<separator.lowerBound])
        let clock = String(english[separator.upperBound...])
        switch when {
        case "Today": return String(format: Loc.t("Today at %@"), clock)
        case "Yesterday": return String(format: Loc.t("Yesterday at %@"), clock)
        // A weekday or a date, already in the reader's locale from the formatter above.
        default: return String(format: Loc.t("%1$@ at %2$@"), when, clock)
        }
    }

    /// "Today", "Yesterday", "3 days ago", "Jul 25" — the day, in the reader's language.
    public static func relativeDayLabel(
        _ timestamp: Int64, now: Int64, calendar: Calendar = .current
    ) -> String {
        let english = ReplayCore.relativeDayLabel(
            timestamp, now: now, calendar: calendar, locale: Loc.locale
        )
        switch english {
        case "Today": return Loc.t("Today")
        case "Yesterday": return Loc.t("Yesterday")
        default:
            // "%@ days ago", or an absolute date the formatter already localised.
            guard english.hasSuffix(" days ago") else { return english }
            let days = english.replacingOccurrences(of: " days ago", with: "")
            return String(format: Loc.t("%@ days ago"), days)
        }
    }

    // ── Memories ──────────────────────────────────────────────────────────────

    /// A moment's title and detail in the reader's language.
    ///
    /// Memories is the surface this was written for. Its frame translated and every card
    /// inside it stayed English, because each card is a sentence assembled from a number, an
    /// application's name and a day — the exact shape that has no key.
    ///
    /// The English on `Moment` is the reference's own wording and is left alone; this reads
    /// `Moment.facts` and says the same thing again. Where a producer has nothing to say the
    /// English is returned unchanged, so a kind added upstream degrades to English rather
    /// than to nothing.
    public static func moment(
        _ moment: Moment, now: Int64, calendar: Calendar = .current
    ) -> (title: String, detail: String) {
        let facts = moment.facts
        let duration = formatDurationShort(facts.seconds)
        let when = relativeDay(facts.at, now: now, calendar: calendar)
        let date = memoryDateLabel(facts.at, calendar: calendar, locale: Loc.locale)

        switch moment.kind {
        case .longestFocus:
            let title = Loc.t("Your longest focus")
            // Two shapes rather than one with an empty middle: a language that puts the app
            // before the duration cannot be served by gluing ", in X" onto the end.
            guard let app = facts.app else {
                return (title, String(
                    format: Loc.t("%1$@ without switching away — %2$@."), duration, when
                ))
            }
            return (title, String(
                format: Loc.t("%1$@ without switching away, in %2$@ — %3$@."),
                duration, app, when
            ))

        case .peakDay:
            let title = Loc.t("Your most active day")
            guard let app = facts.app else {
                return (title, String(format: Loc.t("%1$@ active on %2$@."), duration, date))
            }
            return (title, String(
                format: Loc.t("%1$@ active on %2$@, mostly in %3$@."), duration, date, app
            ))

        case .busyMix:
            return (
                Loc.t("Your busiest mix"),
                String(
                    format: Loc.t("%1$@ different apps in a single day — %2$@."),
                    "\(facts.count)", when
                )
            )

        case .nightOwl:
            return (
                Loc.t("A late night"),
                String(
                    format: Loc.t("You were still going at %1$@ — %2$@."),
                    clockLabel(facts.at, calendar: calendar, locale: Loc.locale), when
                )
            )

        case .streak:
            return (
                Loc.t("A steady stretch"),
                String(
                    format: Loc.t("You were active %1$@ in a row, ending %2$@."),
                    Loc.count(facts.count, "%@ day", "%@ days"), when
                )
            )

        case .newApp:
            guard let app = facts.app else { return (moment.title, moment.detail) }
            return (
                String(format: Loc.t("First time in %@"), app),
                String(format: Loc.t("You opened %1$@ for the first time %2$@."), app, when)
            )

        case .origin:
            let title = Loc.t("Where it began")
            guard facts.count > 0 else {
                return (title, Loc.t("You started building this memory today."))
            }
            // `Loc.count`, not a bare "%@ days": the English branch beside this one has a
            // singular and dropping it here meant a memory one day old read "for 1 days".
            // Correct in Uzbek by accident — it does not inflect after a numeral — and wrong
            // in English and in every language that does.
            return (title, String(
                format: Loc.t("You've been building this memory for %1$@ — since %2$@."),
                Loc.count(facts.count, "%@ day", "%@ days"), date
            ))
        }
    }

    /// One line of a day's story, in the reader's language.
    ///
    /// The four openings stay four separate sentences rather than one with a slot in it. They
    /// are not variations on a phrase — "You began the morning in X" and "The day opened in
    /// the afternoon, in X" put the subject in different places — and a translator handed a
    /// stem plus a word cannot recover that.
    public static func dayStory(_ line: DayStory.Line) -> String {
        switch line {
        case let .openedMorning(app):
            return String(format: Loc.t("You began the morning in %@."), app)
        case let .openedAfternoon(app):
            return String(format: Loc.t("The day opened in the afternoon, in %@."), app)
        case let .openedEvening(app):
            return String(format: Loc.t("The day began in the evening, in %@."), app)
        case let .openedOther(part, app):
            return String(
                format: Loc.t("You started in %1$@, in %2$@."), partWord(part), app
            )
        case let .longestFocus(duration, app, part):
            return String(
                format: Loc.t("Your longest focus was %1$@ in %2$@, %3$@."),
                duration, app, partPhrase(part)
            )
        case let .ranged(apps, sessions):
            return String(
                format: Loc.t("In all you moved through %1$@ across %2$@."),
                Loc.count(apps, "%@ app", "%@ apps"),
                Loc.count(sessions, "%@ session", "%@ sessions")
            )
        case let .woundDown(app):
            return String(format: Loc.t("The day wound down in %@."), app)
        }
    }

    /// "the morning", "the small hours" — a part of the day as prose rather than a label.
    ///
    /// Separate from ``dayPart(_:)``, which translates the label a session title uses. English
    /// happens to reuse the same words in both; most languages will not, and a shared key
    /// would force them to.
    private static func partWord(_ english: String) -> String {
        // Spelled out, not `Loc.t(english.lowercased())`. That handed the scanner a variable,
        // so "morning", "afternoon" and "evening" were never keys — and the orphan sweep then
        // deleted the translations somebody had written, because nothing could prove they
        // were used. The story read "…that evening" in the middle of an Uzbek sentence.
        switch english {
        case "Morning": return Loc.t("morning")
        case "Afternoon": return Loc.t("afternoon")
        case "Evening": return Loc.t("evening")
        default: return Loc.t("the small hours")
        }
    }

    /// "that afternoon", "in the small hours" — the time anchor on the focus sentence.
    private static func partPhrase(_ english: String) -> String {
        switch english {
        case "Morning": return Loc.t("that morning")
        case "Afternoon": return Loc.t("that afternoon")
        case "Evening": return Loc.t("that evening")
        default: return Loc.t("in the small hours")
        }
    }

    /// "today", "yesterday", "6 days ago", "on Saturday, July 25" — in the reader's language.
    ///
    /// Mirrors the private helper inside `moments(...)`, which produces the English. Kept in
    /// step by ``MomentCopyBehaviour``, which walks every kind and checks the two agree about
    /// which branch a day falls in.
    public static func relativeDay(
        _ millis: Int64, now: Int64, calendar: Calendar = .current
    ) -> String {
        let today = startOfLocalDay(now, calendar: calendar)
        let day = startOfLocalDay(millis, calendar: calendar)
        let diff = Int((Double(today - day) / Double(dayMillis)).rounded())
        if diff <= 0 { return Loc.t("today") }
        if diff == 1 { return Loc.t("yesterday") }
        if diff < 7 { return String(format: Loc.t("%@ days ago"), "\(diff)") }
        return String(
            format: Loc.t("on %@"),
            memoryDateLabel(day, calendar: calendar, locale: Loc.locale)
        )
    }
}

public extension ActivitySession {
    /// This session's title in the reader's language.
    ///
    /// Re-derived from the session's own apps and start rather than stored, because `title`
    /// is the contract and a second stored field would be a second thing to keep in step.
    /// The inputs are the same ones `nameSession` was given — `buildTimeline` puts that exact
    /// array on the session — so the branch taken here is the branch taken there.
    var localizedTitle: String {
        RuntimeCopy.sessionTitle(
            ReplayCore.sessionTitle(apps: apps, startedAt: startedAt).title
        )
    }
}

// MARK: - The spans a surface can be looking at

/// The scope controls: "Today", "This Week", "Last 7 Days", "All time".
///
/// **These read from `spec/constants.json`, so the enums cannot be translated where they are
/// defined.** `AppWindow.label`, `TimeRange.label` and `Search.Span.label` are compared
/// against the reference by the parity suite; changing what they return would fail 971 checks
/// for a reason that has nothing to do with the port drifting. Same seam, and same reason, as
/// `SessionTitle.english` having a counterpart here rather than a translation in place.
///
/// **Every case is spelled out rather than looked up from the enum's own value.** A
/// `Loc.t(window.label)` would be one line and would hand the scanner a variable, so none of
/// these would become keys — which is exactly how "morning", "afternoon" and "evening" ended
/// up untranslated and then deleted as orphans. Written this way they are ordinary literals
/// that `translate.mjs` finds, and the compiler fails if a case is ever added without one.
extension RuntimeCopy {

    public static func label(_ window: AppWindow) -> String {
        switch window {
        case .today: Loc.t("Today")
        case .week: Loc.t("This Week")
        case .month: Loc.t("This Month")
        }
    }

    public static func subtitle(_ window: AppWindow) -> String {
        switch window {
        case .today: Loc.t("Where your time went today.")
        case .week: Loc.t("Where your time went this week.")
        case .month: Loc.t("Where your time went this month.")
        }
    }

    public static func label(_ range: TimeRange) -> String {
        switch range {
        case .today: Loc.t("Today")
        case .yesterday: Loc.t("Yesterday")
        case .week: Loc.t("Last 7 Days")
        case .month: Loc.t("Last 30 Days")
        }
    }

    public static func subtitle(_ range: TimeRange) -> String {
        switch range {
        case .today: Loc.t("Everything you did today.")
        case .yesterday: Loc.t("A look back at yesterday.")
        case .week: Loc.t("Your last seven days, newest first.")
        case .month: Loc.t("The last month, newest first.")
        }
    }

    public static func label(_ span: Search.Span) -> String {
        switch span {
        case .all: Loc.t("All time")
        case .today: Loc.t("Today")
        case .week: Loc.t("Week")
        case .month: Loc.t("Month")
        }
    }
}
