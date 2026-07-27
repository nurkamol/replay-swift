import Foundation

/// Your history, divided into the eras it naturally fell into.
///
/// A chapter is a run of days that shared a character — a stretch where the work leaned the
/// same way. Read straight from the durable daily headlines, each of which already knows the
/// app that led it, so chapters reach across *all* kept history and cost nothing to keep:
/// they survive the retention prune that takes the raw rows away.
///
/// Nothing is invented. A chapter only ever says what the days beneath it actually hold.
///
/// Ported from `detectChapters` in the Glaze app.
public struct Chapter: Equatable, Sendable {
    public struct App: Equatable, Sendable {
        public var bundleIdentifier: String
        public var applicationName: String
        public var appPath: String?
        /// Days of the chapter this app led.
        public var days: Int
        public var activeSeconds: Int
    }

    /// The chapter's first day, as a string — stable, and what a custom name is stored under.
    public var id: String
    public var startDay: Int64
    public var endDay: Int64
    public var category: SessionCategory
    /// Active days the chapter spans, not calendar days.
    public var dayCount: Int
    public var totalActiveSeconds: Int
    /// The apps that led the chapter's days, most days first.
    public var apps: [App]
    /// The chapter's fullest single day.
    public var representativeDay: Int64
    /// The active days it holds, newest first — for reopening any of them.
    public var days: [Int64]
}

/// A day under this much active time is too quiet to anchor a chapter.
private let chapterMinDaySeconds = 5 * 60
/// A gap longer than this ends a chapter, even when the character is unchanged.
private let chapterMaxGapDays = 16

/// Fold the daily headlines into chapters.
///
/// Consecutive active days that share a dominant category, split where the character changes
/// or a long gap opens. Newest chapter first.
///
/// `appPaths` supplies an icon for a bundle identifier where one is known; the headlines
/// themselves store no path, because the app that led a day two years ago may no longer be
/// installed.
public func detectChapters(
    _ summaries: [DailySummary],
    appPaths: [String: String] = [:],
    calendar: Calendar = .current
) -> [Chapter] {
    let days = summaries
        .filter { $0.activeSeconds >= chapterMinDaySeconds && $0.topAppName != nil }
        .sorted { $0.dayStart < $1.dayStart }
    if days.isEmpty { return [] }

    struct Run {
        var startDay: Int64
        var endDay: Int64
        var category: SessionCategory
        var days: [DailySummary]
    }
    var runs: [Run] = []
    for day in days {
        let category = categorizeApp(day.topAppName ?? "")
        // Rounded, because two local midnights are not always 24 hours apart.
        let gapDays = runs.last.map {
            Int((Double(day.dayStart - $0.endDay) / Double(dayMillis)).rounded())
        }
        if var current = runs.last, current.category == category,
           let gapDays, gapDays <= chapterMaxGapDays {
            current.endDay = day.dayStart
            current.days.append(day)
            runs[runs.count - 1] = current
        } else {
            runs.append(Run(startDay: day.dayStart, endDay: day.dayStart, category: category, days: [day]))
        }
    }

    return runs
        .map { run -> Chapter in
            var apps: [String: (app: Chapter.App, order: Int)] = [:]
            var totalActiveSeconds = 0
            var representativeDay = run.startDay
            var bestSeconds = -1
            for day in run.days {
                totalActiveSeconds += day.activeSeconds
                // Strictly greater, so the *first* of two equally full days represents the
                // chapter rather than the last.
                if day.activeSeconds > bestSeconds {
                    bestSeconds = day.activeSeconds
                    representativeDay = day.dayStart
                }
                let key = day.topBundleID ?? day.topAppName ?? "unknown"
                if apps[key] != nil {
                    apps[key]!.app.days += 1
                    apps[key]!.app.activeSeconds += day.topSeconds
                } else {
                    apps[key] = (
                        Chapter.App(
                            bundleIdentifier: day.topBundleID ?? key,
                            applicationName: day.topAppName ?? key,
                            appPath: day.topBundleID.flatMap { appPaths[$0] },
                            days: 1,
                            activeSeconds: day.topSeconds
                        ),
                        apps.count
                    )
                }
            }
            return Chapter(
                id: String(run.startDay),
                startDay: run.startDay,
                endDay: run.endDay,
                category: run.category,
                dayCount: run.days.count,
                totalActiveSeconds: totalActiveSeconds,
                apps: apps.values
                    .sorted {
                        if $0.app.days != $1.app.days { return $0.app.days > $1.app.days }
                        if $0.app.activeSeconds != $1.app.activeSeconds {
                            return $0.app.activeSeconds > $1.app.activeSeconds
                        }
                        return $0.order < $1.order
                    }
                    .map(\.app),
                representativeDay: representativeDay,
                days: run.days.map(\.dayStart).sorted(by: >)
            )
        }
        .sorted { $0.startDay > $1.startDay }
}

private let chapterMonths = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

/// "Development · Jul 2026", "Research · Jul–Sep 2026" — descriptive, and renameable.
///
/// The month names are the reference's own hard-coded English abbreviations rather than the
/// locale's, because the reference hard-codes them. Matching a less correct implementation
/// is the point when it is the one people already use.
public func chapterDefaultName(_ chapter: Chapter, calendar: Calendar = .current) -> String {
    func month(_ millis: Int64) -> Int {
        calendar.component(.month, from: Date(timeIntervalSince1970: Double(millis) / 1000)) - 1
    }
    func year(_ millis: Int64) -> Int {
        calendar.component(.year, from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
    func label(_ millis: Int64) -> String { "\(chapterMonths[month(millis)]) \(year(millis))" }

    let lead: String = {
        switch chapter.category {
        case .other: chapter.apps.first?.applicationName ?? "Mixed"
        case .admin: "Utilities"
        default: chapter.category.rawValue
        }
    }()

    if month(chapter.startDay) == month(chapter.endDay),
       year(chapter.startDay) == year(chapter.endDay) {
        return "\(lead) · \(label(chapter.startDay))"
    }
    let startPart = year(chapter.startDay) == year(chapter.endDay)
        ? chapterMonths[month(chapter.startDay)]
        : label(chapter.startDay)
    return "\(lead) · \(startPart)–\(label(chapter.endDay))"
}

/// The chapter's shown name — custom if one was typed, else the descriptive default.
public func resolveChapterName(
    _ chapter: Chapter, names: [String: String], calendar: Calendar = .current
) -> String {
    let custom = names[chapter.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return custom.isEmpty ? chapterDefaultName(chapter, calendar: calendar) : custom
}

// ── a day's place in the story ────────────────────────────────────────────────

/// Where a past day sits: the chapter it belonged to, and the days around it.
public struct ChapterContext: Equatable, Sendable {
    public var chapter: Chapter
    /// The nearest other days in the same chapter, newest first.
    public var nearbyDays: [Int64]
}

/// How old a day has to be before it is given its context.
///
/// A day grows richer as it ages: a chapter is a stretch of weeks, so a day from this week
/// has no distance to be seen from and would be told it belongs to the chapter it is still
/// in the middle of. The reference's week, kept.
public let chapterContextMinimumAge = 7 * dayMillis

/// How many neighbouring days are offered. A handful either side, not the whole chapter —
/// there is a chapter screen for that.
public let chapterContextNearbyLimit = 4

/// The chapter a day belonged to, once the day is old enough to have one.
public func chapterContext(
    for dayStart: Int64, now: Int64, chapters: [Chapter]
) -> ChapterContext? {
    guard now - dayStart >= chapterContextMinimumAge else { return nil }
    guard let chapter = chapters.first(where: {
        dayStart >= $0.startDay && dayStart <= $0.endDay
    }) else { return nil }

    // Nearest first, then read back in order. Sorted on (distance, position) rather than
    // distance alone: a day the same number of days before and after ties exactly, and
    // Swift's sort is not stable where JavaScript's is — without the tie-break the two apps
    // would offer different neighbours for a day in the middle of a chapter.
    let nearby = chapter.days
        .filter { $0 != dayStart }
        .enumerated()
        .sorted {
            let left = abs($0.element - dayStart)
            let right = abs($1.element - dayStart)
            return left != right ? left < right : $0.offset < $1.offset
        }
        .prefix(chapterContextNearbyLimit)
        .map(\.element)
        .sorted(by: >)

    return ChapterContext(chapter: chapter, nearbyDays: nearby)
}
