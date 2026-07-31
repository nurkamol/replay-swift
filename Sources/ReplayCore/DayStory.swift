import Foundation

/// A day, told back as a few plain sentences.
///
/// Given a day's real sessions, this narrates its shape: where it began, the stretch that
/// anchored it, how far it ranged, where it wound down.
///
/// Every clause is filled from recorded activity — an app that was actually in front, a
/// duration that was actually spent. **Nothing is inferred and presented as fact** (SPEC §8):
/// if the day cannot support a sentence, the sentence is not written, and a day with nothing
/// to say gets no story at all. That is the whole design. A narrator that always has
/// something to say is a narrator making things up.
public enum DayStory {

    /// A stretch has to be this long before it is worth calling the day's anchor.
    static let longestFocusSeconds = 20 * 60
    /// A day has to have ranged at least this far before saying so is interesting.
    static let rangingSessions = 4
    static let rangingApps = 5

    /// "morning", "afternoon", "evening", "the small hours" — a part of the day, in prose.
    static func partWord(_ millis: Int64, _ calendar: Calendar) -> String {
        let part = dayPart(of: millis, calendar: calendar)
        return part == "Late night" ? "the small hours" : part.lowercased()
    }

    /// " that afternoon", " in the small hours" — a soft time anchor for a clause.
    static func partSuffix(_ millis: Int64, _ calendar: Calendar) -> String {
        let part = dayPart(of: millis, calendar: calendar)
        return part == "Late night" ? " in the small hours" : " that \(part.lowercased())"
    }

    static func opening(_ first: ActivitySession, _ calendar: Calendar) -> String? {
        guard let app = first.apps.first?.applicationName else { return nil }
        switch dayPart(of: first.startedAt, calendar: calendar) {
        case "Morning": return "You began the morning in \(app)."
        case "Afternoon": return "The day opened in the afternoon, in \(app)."
        case "Evening": return "The day began in the evening, in \(app)."
        default: return "You started in \(partWord(first.startedAt, calendar)), in \(app)."
        }
    }

    /// One sentence of a day's story, before it is a sentence.
    ///
    /// The English below is checked against `spec/` character for character, so it cannot
    /// move. This is the shape the decision produces, so `RuntimeCopy.dayStory(_:)` can say
    /// the same thing in another language — where the clause order is not English's. The day
    /// part travels as its English word because `dayPart(of:)` is contract-checked and returns
    /// one; both renderings translate it themselves.
    public enum Line: Equatable, Sendable {
        case openedMorning(app: String)
        case openedAfternoon(app: String)
        case openedEvening(app: String)
        /// The small hours, and any part the three named cases do not cover.
        case openedOther(part: String, app: String)
        case longestFocus(duration: String, app: String, part: String)
        case ranged(apps: Int, sessions: Int)
        case woundDown(app: String)

        /// The reference's own wording. Nothing here changes without the reference changing.
        public var english: String {
            switch self {
            case let .openedMorning(app): "You began the morning in \(app)."
            case let .openedAfternoon(app): "The day opened in the afternoon, in \(app)."
            case let .openedEvening(app): "The day began in the evening, in \(app)."
            case let .openedOther(part, app):
                "You started in \(part == "Late night" ? "the small hours" : part.lowercased()), in \(app)."
            case let .longestFocus(duration, app, part):
                "Your longest focus was \(duration) in \(app)"
                    + (part == "Late night" ? " in the small hours" : " that \(part.lowercased())")
                    + "."
            case let .ranged(apps, sessions):
                "In all you moved through \(apps) \(apps == 1 ? "app" : "apps") across "
                    + "\(sessions) \(sessions == 1 ? "session" : "sessions")."
            case let .woundDown(app): "The day wound down in \(app)."
            }
        }
    }

    /// A day's story as English sentences — the contract.
    public static func build(
        _ sessions: [ActivitySession], calendar: Calendar = .current
    ) -> [String] {
        lines(sessions, calendar: calendar).map(\.english)
    }

    /// The same story, as the decisions behind it.
    public static func lines(
        _ sessions: [ActivitySession], calendar: Calendar = .current
    ) -> [Line] {
        guard !sessions.isEmpty else { return [] }

        let ordered = sessions.sorted { $0.startedAt < $1.startedAt }
        guard let first = ordered.first, let last = ordered.last else { return [] }

        // First-wins on a tie, matching the reference's `reduce`, which keeps `best`.
        //
        // `max(by:)` happens to do the same today, but which element it returns on a tie is
        // not documented, so relying on it would make the narration depend on a detail of
        // the standard library. Written out, the guarantee is local and visible. The
        // fixture covers a day whose two longest stretches tie, so a change here is caught
        // rather than merely hoped against.
        var longest = sessions[0]
        for session in sessions.dropFirst() where session.activeSeconds > longest.activeSeconds {
            longest = session
        }

        var distinctApps = Set<String>()
        for session in sessions {
            for app in session.apps {
                distinctApps.insert(app.bundleIdentifier ?? app.applicationName)
            }
        }

        var sentences: [Line] = []

        if let app = first.apps.first?.applicationName {
            switch dayPart(of: first.startedAt, calendar: calendar) {
            case "Morning": sentences.append(.openedMorning(app: app))
            case "Afternoon": sentences.append(.openedAfternoon(app: app))
            case "Evening": sentences.append(.openedEvening(app: app))
            case let part: sentences.append(.openedOther(part: part, app: app))
            }
        }

        // The stretch that anchored the day — worth a sentence when it was real focus and
        // not simply the opening session again.
        if longest.activeSeconds >= longestFocusSeconds, longest.startedAt != first.startedAt,
           let app = longest.apps.first?.applicationName {
            sentences.append(.longestFocus(
                duration: formatDurationShort(longest.activeSeconds),
                app: app,
                part: dayPart(of: longest.startedAt, calendar: calendar)
            ))
        }

        // How far the day ranged — only when it genuinely moved around.
        if sessions.count >= rangingSessions || distinctApps.count >= rangingApps {
            sentences.append(.ranged(apps: distinctApps.count, sessions: sessions.count))
        }

        // Where it settled — only when the day ended somewhere other than it began, in a
        // different part of the day. Otherwise it is the opening sentence again.
        if let lastApp = last.apps.first?.applicationName,
           last.startedAt != first.startedAt,
           dayPart(of: last.startedAt, calendar: calendar)
               != dayPart(of: first.startedAt, calendar: calendar) {
            sentences.append(.woundDown(app: lastApp))
        }

        return sentences
    }
}
