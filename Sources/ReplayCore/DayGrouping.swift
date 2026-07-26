import Foundation

/// One calendar day's worth of raw events.
public struct DayGroup: Equatable, Sendable {
    /// Local midnight of the day — the key everything else in the app buckets by.
    public var dayStart: Int64
    /// The day's events, oldest first.
    public var events: [ActivityEvent]

    public init(dayStart: Int64, events: [ActivityEvent]) {
        self.dayStart = dayStart
        self.events = events
    }
}

/// Group events by the calendar day each run *began* — newest day first, chronological
/// within a day.
///
/// Bucketing by `startedAt` is what makes the app strictly day-scoped (SPEC §5): a stretch
/// of work from 11:50 PM to 12:30 AM becomes an "Evening" session on one day and a "Late
/// night" session on the next, each named for its own day-part, rather than one session
/// belonging to two days at once.
///
/// Sessions are built *per group*, never across the whole range, which is what keeps a
/// session from straddling midnight in the first place.
public func groupByDay(_ events: [ActivityEvent], calendar: Calendar = .current) -> [DayGroup] {
    var buckets: [Int64: [ActivityEvent]] = [:]
    for event in events {
        buckets[startOfLocalDay(event.startedAt, calendar: calendar), default: []].append(event)
    }
    return buckets
        .map { DayGroup(dayStart: $0.key, events: $0.value.sorted { $0.startedAt < $1.startedAt }) }
        .sorted { $0.dayStart > $1.dayStart }
}
