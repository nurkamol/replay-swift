import Foundation

/// Finding a session again.
///
/// Everything here is a filter over sessions already derived — there is no index, and
/// deliberately so: a month is a few thousand rows, the derivation is already the cost, and
/// an index would be a second copy of the truth to keep in step. If history ever outgrows
/// that, the fix is to bound the window, not to build a search engine.
public enum Search {

    /// A named slice a phrase points at, rather than a literal match.
    ///
    /// Recognising a handful of words is not intelligence and is not presented as any: the
    /// label says exactly which rule fired, so a result is never mistaken for insight.
    public struct Concept: Equatable, Sendable {
        public var label: String
        public var sessions: [ActivitySession]
    }

    /// How many sessions a concept will show. The reference's cap, kept because a concept
    /// is a shortcut to a handful, not a way to list a month.
    public static let conceptLimit = 12

    /// How many applications a query answers with. Also the reference's: naming an app is
    /// a way of asking "which one did I mean", and thirty candidates is not an answer.
    public static let appLimit = 6

    /// How far back a query looks.
    ///
    /// A narrowing, not a second search: the same predicates run, over fewer days. `all` is
    /// the whole searchable window rather than all history — nothing outside it is loaded.
    public enum Span: String, CaseIterable, Sendable, Identifiable {
        case all, today, week, month

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .all: "All time"
            case .today: "Today"
            case .week: "Week"
            case .month: "Month"
            }
        }

        /// The earliest instant this span admits. `all` admits everything.
        public func start(now: Int64, calendar: Calendar = .current) -> Int64 {
            let today = startOfLocalDay(now, calendar: calendar)
            switch self {
            case .all: return 0
            case .today: return today
            case .week: return today - 6 * dayMillis
            case .month: return today - 29 * dayMillis
            }
        }
    }

    /// Where the query first appears in a piece of text, for highlighting it.
    ///
    /// Case-insensitive by comparison rather than by lowercasing both sides and taking an
    /// index into one of them — which is what the reference does, and which is off by a
    /// character whenever a case fold changes a string's length. Same answer for every
    /// query anyone will type, and correct for the rest.
    public static func firstMatch(of query: String, in text: String) -> Range<String.Index>? {
        var needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while needle.hasPrefix("#") { needle.removeFirst() }
        guard !needle.isEmpty else { return nil }
        // Case only. Not diacritic-insensitive: the predicate that *found* this result is
        // not, so a fold here would highlight a word the search did not actually match on.
        return text.range(of: needle, options: [.caseInsensitive])
    }

    /// Does a session match a typed query, by its name or by what was written on it?
    ///
    /// A leading `#` is dropped so a tag can be typed the way it is displayed. Tags match on
    /// a substring like everything else, so "deep" finds "deep work".
    public static func matches(
        session: ActivitySession, annotation: SessionAnnotation?, query: String
    ) -> Bool {
        var needle = query.lowercased()
        while needle.hasPrefix("#") { needle.removeFirst() }
        guard !needle.isEmpty else { return false }

        if session.title.lowercased().contains(needle) { return true }
        if let annotation {
            if annotation.note.lowercased().contains(needle) { return true }
            if annotation.tags.contains(where: { $0.contains(needle) }) { return true }
        }
        return false
    }

    /// Does a session involve this application?
    ///
    /// An **exact** name match, not a substring one, because this is what a chosen app
    /// sends — you click "Safari" in a result list and get the sessions that used Safari,
    /// not the ones that used "Safari Technology Preview" as well. Substring discovery is
    /// ``apps(matching:in:)``; the two are different questions and the reference keeps them
    /// apart. Getting this wrong is invisible until an app name is a prefix of another.
    public static func usesApp(session: ActivitySession, applicationName: String) -> Bool {
        session.apps.contains { $0.applicationName == applicationName }
    }

    /// Map a phrase to a slice of history, or `nil` when the query is an ordinary one.
    public static func concept(
        for query: String,
        sessions: [ActivitySession],
        annotations: [Int64: SessionAnnotation],
        calendar: Calendar = .current
    ) -> Concept? {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }

        // Ordered so "late night" is tested before "night" alone could claim it.
        let dayParts: [(words: [String], part: String, label: String)] = [
            (["morning"], "Morning", "Morning work"),
            (["afternoon"], "Afternoon", "Afternoon work"),
            (["evening"], "Evening", "Evening work"),
            (["late night", "night", "late"], "Late night", "Late-night work"),
        ]
        for entry in dayParts where entry.words.contains(where: { needle.contains($0) }) {
            let matched = sessions.filter {
                dayPart(of: $0.startedAt, calendar: calendar) == entry.part
            }
            if !matched.isEmpty {
                return Concept(label: entry.label, sessions: Array(matched.prefix(conceptLimit)))
            }
        }

        if needle.contains("longest") || needle.contains("deepest focus") {
            if let longest = sessions.max(by: { $0.activeSeconds < $1.activeSeconds }) {
                return Concept(label: "Longest session", sessions: [longest])
            }
        }

        if needle.contains("bookmark") {
            let marked = sessions.filter { annotations[$0.startedAt]?.bookmarked == true }
            if !marked.isEmpty {
                return Concept(label: "Bookmarked", sessions: Array(marked.prefix(conceptLimit)))
            }
        }

        return nil
    }

    /// An application the query matched, with how much of it there is to find.
    public struct AppHit: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String?
        public var appPath: String?
        public var seconds: Int
        public var sessionCount: Int
    }

    /// Applications whose name contains the query, most-used first.
    public static func apps(matching query: String, in sessions: [ActivitySession]) -> [AppHit] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return [] }

        var hits: [String: AppHit] = [:]
        for session in sessions {
            for app in session.apps where app.applicationName.lowercased().contains(needle) {
                let key = app.bundleIdentifier ?? app.applicationName
                if var existing = hits[key] {
                    existing.seconds += app.seconds
                    existing.sessionCount += 1
                    if existing.appPath == nil { existing.appPath = app.appPath }
                    hits[key] = existing
                } else {
                    hits[key] = AppHit(
                        applicationName: app.applicationName,
                        bundleIdentifier: app.bundleIdentifier,
                        appPath: app.appPath,
                        seconds: app.seconds,
                        sessionCount: 1
                    )
                }
            }
        }
        // Sorted on (seconds, name) rather than seconds alone: Swift's sort is not stable,
        // and two apps with equal time would otherwise reorder between keystrokes.
        let ranked = hits.values.sorted {
            $0.seconds != $1.seconds
                ? $0.seconds > $1.seconds
                : $0.applicationName < $1.applicationName
        }
        return Array(ranked.prefix(appLimit))
    }
}
