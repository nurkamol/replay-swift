import Foundation

/// A quiet look back at the day just gone, before this one begins.
///
/// Not a dashboard and not a list of things to do: a few lines about yesterday and one thing
/// worth carrying into today. It belongs to the morning and is absent by lunchtime, and it
/// is absent entirely when yesterday holds nothing to reflect on — a briefing that appears
/// every day regardless of whether there is anything in it is a widget, not a greeting.
///
/// Ported from `useMorningBriefing` in the Glaze app.
public struct MorningBriefing: Equatable, Sendable {
    /// Today's local midnight — the day this belongs to, and its dismissal key.
    public var dayStart: Int64
    public var yesterdayActiveSeconds: Int
    public var yesterdayTopApp: String?
    public var longestFocusSeconds: Int?
    public var continuedProject: (id: String, name: String)?
    public var monthAgo: (dayStart: Int64, topApp: String?)?
    public var pendingBookmark: Int64?

    public static func == (a: MorningBriefing, b: MorningBriefing) -> Bool {
        a.dayStart == b.dayStart
            && a.yesterdayActiveSeconds == b.yesterdayActiveSeconds
            && a.yesterdayTopApp == b.yesterdayTopApp
            && a.longestFocusSeconds == b.longestFocusSeconds
            && a.continuedProject?.id == b.continuedProject?.id
            && a.monthAgo?.dayStart == b.monthAgo?.dayStart
            && a.pendingBookmark == b.pendingBookmark
    }
}

/// The briefing belongs to the morning; past this hour the day is underway.
public let morningUntilHour = 12

/// Assemble the briefing, or nothing when it should not appear.
///
/// `bookmarkStarts` and the memory are passed in because they live in other tables; every
/// other line is read from yesterday's rows and headline.
public func buildMorningBriefing(
    now: Int64,
    yesterdayEvents: [ActivityEvent],
    summaries: [DailySummary],
    projects: [MemoryProject],
    monthAgo: (dayStart: Int64, topApp: String?)?,
    bookmarkStarts: [Int64],
    calendar: Calendar = .current
) -> MorningBriefing? {
    let todayStart = startOfLocalDay(now, calendar: calendar)
    let yesterdayStart = todayStart - dayMillis

    let hour = calendar.component(.hour, from: Date(timeIntervalSince1970: Double(now) / 1000))
    guard hour < morningUntilHour else { return nil }

    let yesterdaySummary = summaries.first { $0.dayStart == yesterdayStart }
    let sessions = buildTimeline(yesterdayEvents, now: now, calendar: calendar)
        .compactMap { item -> ActivitySession? in
            if case .session(let session) = item { return session } else { return nil }
        }

    let activeSeconds = yesterdaySummary?.activeSeconds ?? 0
    // Nothing to say, so nothing is said.
    if activeSeconds <= 0 && sessions.isEmpty { return nil }

    // `max(by:)` keeps the first of equal elements, matching the reference's reduce.
    let longest = sessions.max { $0.activeSeconds < $1.activeSeconds }

    // A project touched yesterday that has been returned to before — worth continuing.
    let continued = projects
        .filter { project in
            project.sessionCount >= 2
                && project.sessionStarts.contains {
                    $0 >= yesterdayStart && $0 < todayStart
                }
        }
        .enumerated()
        .sorted {
            $0.element.meaning == $1.element.meaning
                ? $0.offset < $1.offset
                : $0.element.meaning > $1.element.meaning
        }
        .first?.element

    return MorningBriefing(
        dayStart: todayStart,
        yesterdayActiveSeconds: activeSeconds,
        yesterdayTopApp: yesterdaySummary?.topAppName,
        longestFocusSeconds: longest?.activeSeconds,
        continuedProject: continued.map { ($0.id, $0.name) },
        monthAgo: monthAgo,
        // The oldest bookmark still waiting to be revisited.
        pendingBookmark: bookmarkStarts.min().map {
            startOfLocalDay($0, calendar: calendar)
        }
    )
}
