import Foundation

/// The days most likely to hold something worth rediscovering.
///
/// Gathered from the moments, the sessions you marked, and any day full enough to have
/// something in it. Today is never among them — you do not need to be shown today — and
/// every day here is a real one from the history rather than a staged suggestion.
///
/// The choosing is left to the caller: this returns the pool, so the picking can be seeded
/// in a test and random in the app. Ported from `useSurpriseMe` in the Glaze app.
public func surprisePool(
    moments: [Moment],
    summaries: [DailySummary],
    bookmarkStarts: [Int64],
    now: Int64,
    calendar: Calendar = .current
) -> [Int64] {
    let today = startOfLocalDay(now, calendar: calendar)
    // Insertion-ordered rather than a plain set, so the pool is the same every run and a
    // seeded pick lands on the same day twice.
    var seen: Set<Int64> = []
    var pool: [Int64] = []

    func add(_ day: Int64) {
        guard day != today, !seen.contains(day) else { return }
        seen.insert(day)
        pool.append(day)
    }

    for moment in moments {
        if let day = moment.dayStart { add(day) }
    }
    // Twenty minutes: below that there is not enough of a day to be worth arriving on.
    for summary in summaries where summary.activeSeconds >= 20 * 60 {
        add(summary.dayStart)
    }
    for start in bookmarkStarts {
        add(startOfLocalDay(start, calendar: calendar))
    }

    return pool
}
