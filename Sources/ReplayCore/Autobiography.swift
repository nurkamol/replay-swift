import Foundation

/// Your history, told back to you a week, a month or a year at a time.
///
/// Every sentence is a template filled from real numbers in the durable daily headlines.
/// Nothing is generated, guessed or exaggerated: when the data does not support a sentence,
/// the sentence simply does not appear. Offline, no model — just the history, arranged into
/// a paragraph (SPEC §8).
///
/// Ported from `summarizePeriod` in the Glaze app.
public struct Autobiography: Equatable, Sendable {
    public struct App: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String
        public var appPath: String?
        public var days: Int
    }

    public struct BusiestDay: Equatable, Sendable {
        public var day: Int64
        public var activeSeconds: Int
    }

    public var period: Period
    public var activeDays: Int
    public var totalActiveSeconds: Int
    public var dominantCategory: SessionCategory?
    public var topApps: [App]
    public var busiestDay: BusiestDay?
    public var reflectionCount: Int
    /// The story, as a handful of plain sentences drawn only from the above.
    public var sentences: [String]
}

/// A span the history can be told over.
public struct Period: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case week, month, year
    }

    public var kind: Kind
    /// Inclusive local-midnight start.
    public var start: Int64
    /// Inclusive local-midnight start of the period's *last day*, not its end instant.
    public var end: Int64
    public var label: String
    public var key: String

    public var id: String { key }
}

private let autobiographyMonths = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]

/// The weeks, months and years the history touches, newest first.
public func listPeriods(
    _ summaries: [DailySummary], calendar: Calendar = .current, locale: Locale = .current
) -> [Period] {
    let active = summaries.filter { $0.activeSeconds > 0 }
    if active.isEmpty { return [] }

    var weeks: [String: Period] = [:]
    var months: [String: Period] = [:]
    var years: [String: Period] = [:]

    for summary in active {
        let date = Date(timeIntervalSince1970: Double(summary.dayStart) / 1000)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)

        let weekStart = startOfWeek(summary.dayStart, calendar: calendar)
        let weekKey = "w-\(weekStart)"
        if weeks[weekKey] == nil {
            weeks[weekKey] = Period(
                kind: .week,
                start: weekStart,
                // Six days on by arithmetic, as upstream — not a calendar week's end.
                end: weekStart + 6 * dayMillis,
                label: "Week of \(shortDayLabel(weekStart, calendar: calendar, locale: locale))",
                key: weekKey
            )
        }

        let monthKey = "m-\(year)-\(month - 1)"
        if months[monthKey] == nil {
            let start = midnight(year: year, month: month, day: 1, calendar: calendar)
            // Day zero of the next month is the last day of this one, as in the reference.
            let end = midnight(year: year, month: month + 1, day: 0, calendar: calendar)
            months[monthKey] = Period(
                kind: .month, start: start, end: end,
                label: "\(autobiographyMonths[month - 1]) \(year)", key: monthKey
            )
        }

        let yearKey = "y-\(year)"
        if years[yearKey] == nil {
            years[yearKey] = Period(
                kind: .year,
                start: midnight(year: year, month: 1, day: 1, calendar: calendar),
                end: midnight(year: year, month: 12, day: 31, calendar: calendar),
                label: "\(year)", key: yearKey
            )
        }
    }

    // Weeks, then months, then years, each newest first — the reference concatenates the
    // three maps in that order and sorts by start, and JavaScript's sort is stable, so a
    // week and a month beginning on the same day keep that order.
    let all = weeks.values.sorted { $0.start > $1.start }
        + months.values.sorted { $0.start > $1.start }
        + years.values.sorted { $0.start > $1.start }
    return all.enumerated()
        .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start > $1.element.start }
        .map(\.element)
}

/// Tell the story of one period.
///
/// `reflectionCount` is passed in because reflections live in their own table; everything
/// else is read from the daily headlines the period contains.
public func summarizePeriod(
    _ period: Period,
    summaries: [DailySummary],
    appPaths: [String: String] = [:],
    reflectionCount: Int,
    calendar: Calendar = .current,
    locale: Locale = .current
) -> Autobiography {
    let inRange = summaries.filter {
        $0.dayStart >= period.start && $0.dayStart <= period.end && $0.activeSeconds > 0
    }

    var totalActiveSeconds = 0
    var busiestDay: Autobiography.BusiestDay?
    var appDays: [String: (app: Autobiography.App, order: Int)] = [:]
    var categoryDays: [SessionCategory: (days: Int, order: Int)] = [:]

    for day in inRange {
        totalActiveSeconds += day.activeSeconds
        // Strictly greater, so the first of two equally full days wins.
        if busiestDay == nil || day.activeSeconds > busiestDay!.activeSeconds {
            busiestDay = Autobiography.BusiestDay(day: day.dayStart, activeSeconds: day.activeSeconds)
        }
        let key = day.topBundleID ?? day.topAppName ?? "unknown"
        if appDays[key] != nil {
            appDays[key]!.app.days += 1
        } else {
            appDays[key] = (
                Autobiography.App(
                    applicationName: day.topAppName ?? key,
                    bundleIdentifier: day.topBundleID ?? key,
                    appPath: day.topBundleID.flatMap { appPaths[$0] },
                    days: 1
                ),
                appDays.count
            )
        }
        let category = categorizeApp(day.topAppName ?? "")
        if categoryDays[category] != nil {
            categoryDays[category]!.days += 1
        } else {
            categoryDays[category] = (1, categoryDays.count)
        }
    }

    let topApps = appDays.values
        .sorted { $0.app.days == $1.app.days ? $0.order < $1.order : $0.app.days > $1.app.days }
        .prefix(5)
        .map(\.app)

    var dominantCategory: SessionCategory?
    var bestDays = 0
    for (category, entry) in categoryDays.sorted(by: { $0.value.order < $1.value.order })
    where entry.days > bestDays {
        bestDays = entry.days
        dominantCategory = category
    }

    let activeDays = inRange.count
    let thisPeriod = switch period.kind {
    case .week: "this week"
    case .month: "this month"
    case .year: "this year"
    }
    // "In July 2026" and "In 2026" read straight from the label; a week needs the article to
    // read naturally — "In the week of Jul 21".
    let openLabel = period.kind == .week
        ? "the week of \(shortDayLabel(period.start, calendar: calendar, locale: locale))"
        : period.label

    var sentences: [String] = []
    if activeDays > 0 {
        sentences.append(
            "In \(openLabel), you were active on \(activeDays) "
                + "\(activeDays == 1 ? "day" : "days"), for "
                + "\(formatDurationShort(totalActiveSeconds)) in all."
        )
    }
    if let dominantCategory, dominantCategory != .other {
        sentences.append("Your time leaned toward \(categoryWord(dominantCategory)).")
    }
    if !topApps.isEmpty {
        let names = topApps.prefix(3).map(\.applicationName)
        let list = names.count == 1
            ? names[0]
            : "\(names.dropLast().joined(separator: ", ")) and \(names.last!)"
        sentences.append("You reached most often for \(list).")
    }
    // Only past one active day: "your fullest day was Tuesday" is a strange thing to say
    // about the only day there was.
    if let busiestDay, activeDays > 1 {
        sentences.append(
            "Your fullest day was "
                + "\(memoryDateLabel(busiestDay.day, calendar: calendar, locale: locale)), "
                + "with \(formatDurationShort(busiestDay.activeSeconds))."
        )
    }
    if reflectionCount > 0 {
        sentences.append(
            "You wrote \(reflectionCount) "
                + "\(reflectionCount == 1 ? "reflection" : "reflections") \(thisPeriod)."
        )
    }

    return Autobiography(
        period: period,
        activeDays: activeDays,
        totalActiveSeconds: totalActiveSeconds,
        dominantCategory: dominantCategory,
        topApps: topApps,
        busiestDay: busiestDay,
        reflectionCount: reflectionCount,
        sentences: sentences
    )
}

/// A softer word for a couple of categories, so a sentence reads naturally.
private func categoryWord(_ category: SessionCategory) -> String {
    switch category {
    case .admin: "utilities"
    case .other: "a mix of things"
    default: category.rawValue.lowercased()
    }
}

/// The local-midnight Monday that starts the week a moment falls in.
private func startOfWeek(_ millis: Int64, calendar: Calendar) -> Int64 {
    let day = startOfLocalDay(millis, calendar: calendar)
    let date = Date(timeIntervalSince1970: Double(day) / 1000)
    // `weekday` is 1-based with Sunday at 1; the reference works from a 0-based Sunday and
    // shifts so Monday is zero.
    let sinceMonday = (calendar.component(.weekday, from: date) - 1 + 6) % 7
    var parts = calendar.dateComponents([.year, .month, .day], from: date)
    parts.day! -= sinceMonday
    // Built from components rather than by subtracting milliseconds, so a week that crosses
    // a daylight-saving boundary still starts at midnight.
    guard let start = calendar.date(from: parts) else { return day }
    return Int64((start.timeIntervalSince1970 * 1000).rounded())
}

/// Local midnight for a date given in components, allowing day 0 to mean "the last day of
/// the previous month" as `new Date(y, m + 1, 0)` does.
private func midnight(year: Int, month: Int, day: Int, calendar: Calendar) -> Int64 {
    var parts = DateComponents()
    parts.year = year
    parts.month = month
    parts.day = day
    guard let date = calendar.date(from: parts) else { return 0 }
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
}

/// "Jul 21" — a short month and day.
func shortDayLabel(_ millis: Int64, calendar: Calendar, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
}

/// "Tuesday, 21 July 2026" — a day named in full, for a sentence.
public func memoryDateLabel(
    _ dayStart: Int64, calendar: Calendar = .current, locale: Locale = .current
) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMdy")
    return formatter.string(from: Date(timeIntervalSince1970: Double(dayStart) / 1000))
}
