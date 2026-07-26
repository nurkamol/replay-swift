import Foundation

/// Rediscovering what you were doing on this date in the past.
///
/// Built entirely from the durable daily headlines — the per-day summaries that survive
/// after raw events are pruned (SPEC §6) — so a memory can still be shown when its full
/// timeline is long gone. That is the whole reason retention keeps them.
///
/// Matches are looked up at fixed *calendar* offsets rather than "N days ago", so "one year
/// ago" lands on the same calendar day rather than 365 sleeps back.
public enum Memories {

    /// How far back the furthest offset reaches, and therefore how wide a window to fetch.
    public static let lookbackDays = 366 * 2 + 2

    public struct Range: Equatable, Sendable {
        public var key: String
        public var label: String
        /// Local midnight of the day this offset lands on.
        public var dayStart: Int64
    }

    public struct Memory: Equatable, Sendable {
        public var range: Range
        public var summary: DailySummary
    }

    /// The calendar offsets looked back through, nearest first.
    ///
    /// The arithmetic here is deliberately *not* `Calendar.date(byAdding:)`, which clamps an
    /// overflowing day to the end of the month: 31 March minus one month becomes 28
    /// February. JavaScript's `Date` constructor normalises instead, so the reference lands
    /// on **3 March**, and a memory dated "one month ago" has to mean the same day in both
    /// apps. Building a `DateComponents` with an out-of-range day and letting
    /// `Calendar.date(from:)` normalise it reproduces that exactly — checked at three
    /// month-end cases and a leap day.
    public static func targets(now: Int64, calendar: Calendar = .current) -> [Range] {
        let today = Date(timeIntervalSince1970: Double(startOfLocalDay(now, calendar: calendar)) / 1000)
        let parts = calendar.dateComponents([.year, .month, .day], from: today)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [] }

        func shift(years: Int = 0, months: Int = 0, days: Int = 0) -> Int64? {
            var components = DateComponents()
            components.year = year - years
            components.month = month - months
            components.day = day - days
            guard let date = calendar.date(from: components) else { return nil }
            return Int64((date.timeIntervalSince1970 * 1000).rounded())
        }

        let offsets: [(key: String, label: String, value: Int64?)] = [
            ("1d", "Yesterday", shift(days: 1)),
            ("1w", "One week ago", shift(days: 7)),
            ("1mo", "One month ago", shift(months: 1)),
            ("3mo", "Three months ago", shift(months: 3)),
            ("6mo", "Six months ago", shift(months: 6)),
            ("1y", "One year ago", shift(years: 1)),
            ("2y", "Two years ago", shift(years: 2)),
        ]
        return offsets.compactMap { offset in
            offset.value.map { Range(key: offset.key, label: offset.label, dayStart: $0) }
        }
    }

    /// Every offset that actually has recorded activity, nearest first.
    ///
    /// A day with a headline of zero is not a memory — it is a day the app was running and
    /// nothing happened, which is worth nothing to show.
    public static func find(
        in summaries: [DailySummary], now: Int64, calendar: Calendar = .current
    ) -> [Memory] {
        var byDay: [Int64: DailySummary] = [:]
        for summary in summaries { byDay[summary.dayStart] = summary }

        return targets(now: now, calendar: calendar).compactMap { range in
            guard let summary = byDay[range.dayStart], summary.activeSeconds > 0 else { return nil }
            return Memory(range: range, summary: summary)
        }
    }
}
