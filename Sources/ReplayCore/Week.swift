import Foundation

/// A week the user can look back on.
///
/// Ported from `computeWeekSummary` in the Glaze app. Descriptive throughout: the figures
/// answer "what did my week look like" and the rhythm grid answers "when am I usually
/// around". There is no target and no score, and an empty day is rest rather than a gap to
/// explain (SPEC §8).
public struct WeekSummary: Equatable, Sendable {
    /// One of the seven days, oldest first, so the row reads left to right like a calendar.
    public struct Day: Equatable, Sendable {
        public var dayStart: Int64
        public var weekdayShort: String
        public var dayOfMonth: Int
        public var activeSeconds: Int
        public var sessionCount: Int
        /// Active seconds per hour, index 0–23 — the sparkline under the day.
        public var arc: [Int]
        public var isToday: Bool
        public var isEmpty: Bool
    }

    /// One application's week: how long, what share of it, and how many days it appeared on.
    public struct App: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String?
        public var appPath: String?
        public var seconds: Int
        public var share: Double
        /// Which of the week's days this app was used on, 0–7.
        public var daysUsed: Int
    }

    /// The busiest single weekday-hour cell, for a plain-language note.
    public struct Peak: Equatable, Sendable {
        public var weekday: Int
        public var hour: Int
        public var seconds: Int

        /// Public so the parity suite can name a cell directly rather than arranging a
        /// week that happens to peak where the case needs it to.
        public init(weekday: Int, hour: Int, seconds: Int) {
            self.weekday = weekday
            self.hour = hour
            self.seconds = seconds
        }
    }

    public var days: [Day]
    public var activeSeconds: Int
    public var activeLabel: String
    public var sessionCount: Int
    public var appsUsed: Int
    public var apps: [App]
    /// Weekday × hour intensity, [7][24], for the rhythm heatmap.
    public var rhythm: [[Int]]
    public var peak: Peak?
}

private let weekdayShort = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

/// Aggregate a span of events into a week.
///
/// `dayStarts` is the seven local midnights to report, oldest first: the view owns the
/// calendar and this only fills it in. Idle stretches are excluded everywhere, so "active"
/// means time actually at the keyboard.
///
/// The two grids are built differently on purpose, matching the reference. A day's `arc`
/// buckets by *arithmetic* hours from its midnight, while `rhythm` buckets by the local
/// clock hour each moment falls in. They agree except across a DST boundary, and the
/// reference's shapes are what the fixtures pin.
public func computeWeekSummary(
    events: [ActivityEvent],
    dayStarts: [Int64],
    now: Int64,
    calendar: Calendar = .current
) -> WeekSummary {
    let active = excludeIdleStretches(events, now: now)
    let today = startOfLocalDay(now, calendar: calendar)

    let days = dayStarts.map { dayStart -> WeekSummary.Day in
        let dayEnd = dayStart + dayMillis
        let dayEvents = active.filter { $0.startedAt >= dayStart && $0.startedAt < dayEnd }
        let timeline = buildTimeline(dayEvents, now: now, calendar: calendar)
        let sessionCount = timeline.reduce(0) { count, item in
            if case .session = item { return count + 1 } else { return count }
        }
        // The same per-hour arc Today draws, so a day reads identically in both places.
        let arc = dayArc(dayEvents, dayStart: dayStart, now: now)
        let date = Date(timeIntervalSince1970: Double(dayStart) / 1000)
        return WeekSummary.Day(
            dayStart: dayStart,
            // `component(.weekday:)` is 1-based with Sunday at 1; the reference's
            // `getDay()` is 0-based with Sunday at 0.
            weekdayShort: weekdayShort[calendar.component(.weekday, from: date) - 1],
            dayOfMonth: calendar.component(.day, from: date),
            activeSeconds: arc.reduce(0, +),
            sessionCount: sessionCount,
            arc: arc,
            isToday: dayStart == today,
            isEmpty: arc.reduce(0, +) < 1
        )
    }

    // App totals, and how many distinct days each appeared on. Insertion order is kept
    // because the sort below is by seconds alone: JavaScript's sort is stable, so two apps
    // with equal time hold the order they were first seen in, and Swift's is not.
    struct Accumulating {
        var app: WeekSummary.App
        var daySet: Set<Int64>
        var order: Int
    }
    var byApp: [String: Accumulating] = [:]
    var weekSeconds = 0
    for event in active {
        let seconds = event.effectiveDuration(now: now)
        weekSeconds += seconds
        let key = event.bundleIdentifier ?? event.applicationName
        let day = startOfLocalDay(event.startedAt, calendar: calendar)
        if var existing = byApp[key] {
            existing.app.seconds += seconds
            existing.daySet.insert(day)
            if existing.app.appPath == nil { existing.app.appPath = event.appPath }
            byApp[key] = existing
        } else {
            byApp[key] = Accumulating(
                app: WeekSummary.App(
                    applicationName: event.applicationName,
                    bundleIdentifier: event.bundleIdentifier,
                    appPath: event.appPath,
                    seconds: seconds,
                    share: 0,
                    daysUsed: 0
                ),
                daySet: [day],
                order: byApp.count
            )
        }
    }
    let denominator = weekSeconds == 0 ? 1 : weekSeconds
    let apps = byApp.values
        .sorted { $0.app.seconds == $1.app.seconds ? $0.order < $1.order : $0.app.seconds > $1.app.seconds }
        .map { entry -> WeekSummary.App in
            var app = entry.app
            app.share = Double(app.seconds) / Double(denominator)
            app.daysUsed = entry.daySet.count
            return app
        }

    // Rhythm: each event is spread across the clock hours it covers, so a long stretch
    // reads as a band rather than one bright cell.
    var rhythm = [[Int]](repeating: [Int](repeating: 0, count: 24), count: 7)
    var peak: WeekSummary.Peak?
    for event in active {
        let from = event.startedAt
        let to = event.endedAt ?? from + Int64(event.effectiveDuration(now: now)) * 1000
        var cursor = from
        while cursor < to {
            let at = Date(timeIntervalSince1970: Double(cursor) / 1000)
            // The end of the clock hour `cursor` falls in, so a stretch crossing an hour
            // boundary is split at the boundary rather than at a fixed offset.
            let hourEnd = endOfClockHour(at, calendar: calendar)
            let sliceEnd = min(to, hourEnd)
            let seconds = Int((Double(sliceEnd - cursor) / 1000).rounded(.down))
            let weekday = calendar.component(.weekday, from: at) - 1
            let hour = calendar.component(.hour, from: at)
            rhythm[weekday][hour] += seconds
            // Strictly greater, checked on every increment, so the first cell to reach the
            // running maximum keeps it — the reference's behaviour on a tie.
            if peak == nil || rhythm[weekday][hour] > peak!.seconds {
                peak = WeekSummary.Peak(
                    weekday: weekday, hour: hour, seconds: rhythm[weekday][hour]
                )
            }
            cursor = sliceEnd
        }
    }

    return WeekSummary(
        days: days,
        activeSeconds: weekSeconds,
        activeLabel: formatDurationShort(weekSeconds),
        sessionCount: days.reduce(0) { $0 + $1.sessionCount },
        appsUsed: apps.count,
        apps: apps,
        rhythm: rhythm,
        peak: (peak?.seconds ?? 0) > 0 ? peak : nil
    )
}

/// One millisecond past the last of the clock hour this moment falls in.
///
/// The reference gets here by setting minutes, seconds and milliseconds to their maxima and
/// adding one. Done through `Calendar` rather than by arithmetic so an hour that is not
/// 3600 seconds long — the repeated hour when clocks go back — still ends where the clock
/// says it does.
private func endOfClockHour(_ date: Date, calendar: Calendar) -> Int64 {
    var parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
    parts.minute = 59
    parts.second = 59
    parts.nanosecond = 999_000_000
    guard let end = calendar.date(from: parts) else {
        return Int64(date.timeIntervalSince1970 * 1000) + 1
    }
    return Int64((end.timeIntervalSince1970 * 1000).rounded(.down)) + 1
}

/// "Tuesday evenings", "Monday mornings" — a plain-language read of the peak.
public func describePeak(_ peak: WeekSummary.Peak) -> String {
    let weekday = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ][peak.weekday]
    let partOfDay: String
    switch peak.hour {
    case ..<5: partOfDay = "late nights"
    case ..<12: partOfDay = "mornings"
    case ..<17: partOfDay = "afternoons"
    case ..<22: partOfDay = "evenings"
    default: partOfDay = "late nights"
    }
    return "\(weekday) \(partOfDay)"
}
