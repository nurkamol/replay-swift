import Foundation
import SQLite3

/// The memories worth rediscovering, found in your own data.
///
/// Not achievements and not scores — the handful of things from a history that answer "what
/// would I be glad to be reminded of?": the longest stretch of focus, the fullest day, the
/// first time something was opened, where it all began. Nothing is invented, and a moment
/// only appears when the data genuinely supports it (SPEC §8).
///
/// Ported from `detectMoments` in the Glaze app.
public struct Moment: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case longestFocus = "longest-focus"
        case peakDay = "peak-day"
        case busyMix = "busy-mix"
        case nightOwl = "night-owl"
        case streak
        case newApp = "new-app"
        case origin
    }

    public var kind: Kind
    public var key: String
    public var title: String
    public var detail: String
    /// For a first-time-in moment, so the real icon can be shown.
    public var appPath: String?
    /// A day to open when the moment is chosen.
    public var dayStart: Int64?
    /// The values ``title`` and ``detail`` were assembled from, kept so they can be assembled
    /// again in another language.
    ///
    /// The English above is the reference's own wording and stays exactly as it is; this is
    /// what lets `RuntimeCopy.moment(_:)` say the same thing in a language whose word order
    /// differs. Without it the whole of Memories reads English inside a translated frame,
    /// which is what it did until now.
    public var facts = Facts()

    /// Whatever a moment needs to be re-said. Not every field is used by every kind — `kind`
    /// already discriminates, so this stays one flat value rather than seven associated ones,
    /// and adding a producer does not mean adding a case to a second type.
    public struct Facts: Equatable, Sendable {
        /// A duration being described, in seconds.
        public var seconds = 0
        /// A count: applications in a day, days in a run, days since the beginning.
        public var count = 0
        /// An application's display name. Never translated — a proper noun.
        public var app: String?
        /// The instant being described, for a clock or a relative day.
        public var at: Int64 = 0

        public init(seconds: Int = 0, count: Int = 0, app: String? = nil, at: Int64 = 0) {
            self.seconds = seconds
            self.count = count
            self.app = app
            self.at = at
        }
    }
}

/// All-history facts, gathered beyond any bounded window.
public struct MomentSeed: Equatable, Sendable {
    public struct FirstSeen: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String
        public var appPath: String?
        public var firstAt: Int64

        public init(
            applicationName: String, bundleIdentifier: String,
            appPath: String?, firstAt: Int64
        ) {
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
            self.appPath = appPath
            self.firstAt = firstAt
        }
    }

    public var firstEventAt: Int64?
    public var appCount: Int
    /// Newest first.
    public var appFirstSeen: [FirstSeen]

    public init(firstEventAt: Int64?, appCount: Int, appFirstSeen: [FirstSeen]) {
        self.firstEventAt = firstEventAt
        self.appCount = appCount
        self.appFirstSeen = appFirstSeen
    }
}

/// Find the moments worth surfacing, in the order they deserve attention.
public func detectMoments(
    seed: MomentSeed?,
    summaries: [DailySummary],
    events: [ActivityEvent],
    now: Int64,
    calendar: Calendar = .current,
    locale: Locale = .current
) -> [Moment] {
    let today = startOfLocalDay(now, calendar: calendar)
    var moments: [Moment] = []

    /// "today", "yesterday", "4 days ago", or "on Saturday, 25 July 2024".
    func relativeDay(_ millis: Int64) -> String {
        let diff = Int((Double(today - startOfLocalDay(millis, calendar: calendar))
            / Double(dayMillis)).rounded())
        if diff <= 0 { return "today" }
        if diff == 1 { return "yesterday" }
        if diff < 7 { return "\(diff) days ago" }
        return "on \(memoryDateLabel(millis, calendar: calendar, locale: locale))"
    }

    // The longest uninterrupted stretch of focus in the recent window. `max(by:)` keeps the
    // first of equal elements, which is the reduce's behaviour upstream.
    let sessions = sessionsForWeek(events, now: now, calendar: calendar)
    if let longest = sessions.max(by: { $0.activeSeconds < $1.activeSeconds }),
       longest.activeSeconds >= 20 * 60 {
        let inApp = longest.apps.first.map { ", in \($0.applicationName)" } ?? ""
        moments.append(Moment(
            kind: .longestFocus,
            key: "longest-\(longest.startedAt)",
            title: "Your longest focus",
            detail: "\(formatDurationShort(longest.activeSeconds)) without switching away"
                + "\(inApp) — \(relativeDay(longest.startedAt)).",
            dayStart: startOfLocalDay(longest.startedAt, calendar: calendar),
            facts: .init(
                seconds: longest.activeSeconds,
                app: longest.apps.first?.applicationName,
                at: longest.startedAt
            )
        ))
    }

    // The most active day, from the durable headlines — complete days only.
    if let peak = summaries.max(by: { $0.activeSeconds < $1.activeSeconds }),
       peak.activeSeconds >= 30 * 60 {
        let mostly = peak.topAppName.map { ", mostly in \($0)" } ?? ""
        moments.append(Moment(
            kind: .peakDay,
            key: "peak-\(peak.dayStart)",
            title: "Your most active day",
            detail: "\(formatDurationShort(peak.activeSeconds)) active on "
                + "\(memoryDateLabel(peak.dayStart, calendar: calendar, locale: locale))\(mostly).",
            dayStart: peak.dayStart,
            facts: .init(seconds: peak.activeSeconds, app: peak.topAppName, at: peak.dayStart)
        ))
    }

    // The day that touched the most different applications.
    var appsByDay: [Int64: Set<String>] = [:]
    var dayOrder: [Int64] = []
    for event in events where event.type == .activated {
        guard let bundleID = event.bundleIdentifier else { continue }
        let day = startOfLocalDay(event.startedAt, calendar: calendar)
        if appsByDay[day] == nil { dayOrder.append(day) }
        appsByDay[day, default: []].insert(bundleID)
    }
    // Strictly greater in insertion order, so the first day to reach the count keeps it.
    var busiest: (day: Int64, count: Int)?
    for day in dayOrder where busiest == nil || appsByDay[day]!.count > busiest!.count {
        busiest = (day, appsByDay[day]!.count)
    }
    if let busiest, busiest.count >= 8 {
        moments.append(Moment(
            kind: .busyMix,
            key: "mix-\(busiest.day)",
            title: "Your busiest mix",
            detail: "\(busiest.count) different apps in a single day — \(relativeDay(busiest.day)).",
            dayStart: busiest.day,
            facts: .init(count: busiest.count, at: busiest.day)
        ))
    }

    // The latest you were still going in the small hours. Between 1 and 5 in the morning:
    // late enough to be worth remembering, rather than just "evening".
    var latestNight: (at: Int64, minutes: Int)?
    for event in events where event.type == .activated {
        let date = Date(timeIntervalSince1970: Double(event.startedAt) / 1000)
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        if minutes >= 60, minutes <= 5 * 60, latestNight == nil || minutes > latestNight!.minutes {
            latestNight = (event.startedAt, minutes)
        }
    }
    if let latestNight {
        moments.append(Moment(
            kind: .nightOwl,
            key: "night-\(startOfLocalDay(latestNight.at, calendar: calendar))",
            title: "A late night",
            detail: "You were still going at "
                + "\(clockLabel(latestNight.at, calendar: calendar, locale: locale)) — "
                + "\(relativeDay(latestNight.at)).",
            dayStart: startOfLocalDay(latestNight.at, calendar: calendar),
            facts: .init(at: latestNight.at)
        ))
    }

    // The longest run of consecutive active days.
    let activeDays = summaries
        .filter { $0.activeSeconds >= 10 * 60 }
        .map { startOfLocalDay($0.dayStart, calendar: calendar) }
        .sorted()
    var bestRun = 0
    var bestEnd: Int64 = 0
    var run = 0
    var previous: Int64 = 0
    for day in activeDays {
        let consecutive = previous != 0
            && Int((Double(day - previous) / Double(dayMillis)).rounded()) == 1
        run = consecutive ? run + 1 : 1
        if run > bestRun {
            bestRun = run
            bestEnd = day
        }
        previous = day
    }
    if bestRun >= 3 {
        moments.append(Moment(
            kind: .streak,
            key: "streak-\(bestEnd)",
            title: "A steady stretch",
            detail: "You were active \(bestRun) days in a row, ending \(relativeDay(bestEnd)).",
            dayStart: bestEnd,
            facts: .init(count: bestRun, at: bestEnd)
        ))
    }

    if let firstEventAt = seed?.firstEventAt {
        // Only once there is enough history that a newly-tried app is genuinely notable —
        // on day one, everything is new.
        let established = today - startOfLocalDay(firstEventAt, calendar: calendar) > 3 * dayMillis
        if established {
            for app in seed!.appFirstSeen.filter({ now - $0.firstAt < 7 * dayMillis }).prefix(2) {
                moments.append(Moment(
                    kind: .newApp,
                    key: "new-\(app.bundleIdentifier)",
                    title: "First time in \(app.applicationName)",
                    detail: "You opened \(app.applicationName) for the first time "
                        + "\(relativeDay(app.firstAt)).",
                    appPath: app.appPath,
                    dayStart: startOfLocalDay(app.firstAt, calendar: calendar),
                    facts: .init(app: app.applicationName, at: app.firstAt)
                ))
            }
        }

        // Where it began — a gentle anchor, always last.
        let firstDay = startOfLocalDay(firstEventAt, calendar: calendar)
        let days = Int((Double(today - firstDay) / Double(dayMillis)).rounded())
        moments.append(Moment(
            kind: .origin,
            key: "origin",
            title: "Where it began",
            detail: days <= 0
                ? "You started building this memory today."
                // A straight apostrophe, matching the reference character for character.
                : "You've been building this memory for \(days) "
                    + "\(days == 1 ? "day" : "days") — since "
                    + "\(memoryDateLabel(firstDay, calendar: calendar, locale: locale)).",
            dayStart: firstDay,
            facts: .init(count: days, at: firstDay)
        ))
    }

    return moments
}

/// One moment to feature as the day's quote.
///
/// Chosen from the day itself rather than at random, so it is stable through the day and
/// gently rotates from one to the next — a page that reshuffled on every visit would be a
/// slot machine rather than a memory.
public func pickDailyQuote(
    _ moments: [Moment], now: Int64, calendar: Calendar = .current
) -> Moment? {
    if moments.isEmpty { return nil }
    let dayIndex = Int(startOfLocalDay(now, calendar: calendar) / dayMillis)
    return moments[dayIndex % moments.count]
}

/// "2:14 AM" — the locale's own short time, unlike the hand-built clock in `formatWhen`.
///
/// The narrow no-break space is folded to an ordinary one. Current macOS puts U+202F before
/// AM/PM; the ICU the reference runs against emits a plain space, and the fixture caught the
/// two disagreeing on a string that looks identical in a terminal. Folding is the smaller
/// wrong: it keeps the two apps saying the same thing, and the difference is a runtime's ICU
/// version rather than anything either app decided.
/// "5:00 AM" — a time of day, in the reader's locale.
///
/// Internal rather than private since `RuntimeCopy` re-says the night-owl moment and must
/// format the clock the same way the English one does.
func clockLabel(_ millis: Int64, calendar: Calendar, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("jmm")
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
        .replacingOccurrences(of: "\u{202F}", with: " ")
}

extension ActivityStore {
    /// The all-history facts moments need, which no bounded query can answer.
    ///
    /// Three queries rather than one: they aggregate over the whole `events` table
    /// differently, and a single joined statement would be harder to read against the
    /// reference's SQL than three that each say one thing.
    public func momentSeed() throws -> MomentSeed {
        let first = try query(
            "SELECT MIN(started_at) AS t FROM events WHERE type = 'activated'",
            row: { statement -> Int64? in
                sqlite3_column_type(statement, 0) == SQLITE_NULL
                    ? nil : sqlite3_column_int64(statement, 0)
            }
        ).first ?? nil

        let appCount = try query(
            """
            SELECT COUNT(DISTINCT bundle_identifier) FROM events
            WHERE type = 'activated' AND bundle_identifier IS NOT NULL
            """,
            row: { Int(sqlite3_column_int64($0, 0)) }
        ).first ?? 0

        let firstSeen = try query(
            """
            SELECT application_name, bundle_identifier, MIN(started_at) AS first_at, metadata
            FROM events
            WHERE type = 'activated' AND bundle_identifier IS NOT NULL
            GROUP BY bundle_identifier
            ORDER BY first_at DESC
            """,
            row: { statement -> MomentSeed.FirstSeen in
                func column(_ index: Int32) -> String? {
                    sqlite3_column_text(statement, index).map { String(cString: $0) }
                }
                // The path lives in the row's JSON metadata, as everywhere else.
                let appPath = column(3)
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    .flatMap { $0["appPath"] as? String }
                return MomentSeed.FirstSeen(
                    applicationName: column(0) ?? "",
                    bundleIdentifier: column(1) ?? "",
                    appPath: appPath,
                    firstAt: sqlite3_column_int64(statement, 2)
                )
            }
        )

        return MomentSeed(firstEventAt: first, appCount: appCount, appFirstSeen: firstSeen)
    }
}
