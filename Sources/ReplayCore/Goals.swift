import Foundation

/// An opt-in daily focus target the user sets for themselves.
///
/// Replay describes the day rather than grading it, so a goal exists only because its owner
/// asked for one (SPEC §8). Everything here follows from that: it is off by default, the
/// progress it reports never turns red, and an unfinished today never *breaks* a streak —
/// it simply has not extended it yet.
public enum Goals {

    /// The targets offered as one-click choices: every whole hour from 1 to 8.
    ///
    /// Anything off that grid is a real target too — a 45-minute practice habit, a 5½-hour
    /// working day — which is what the custom bounds are for. Shared by Settings and the
    /// card on Today, so the two cannot drift into offering different sets of the same
    /// choice.
    public static let presetMinutes = [60, 120, 180, 240, 300, 360, 420, 480]

    public static let customDefaultMinutes = 90
    /// Below a quarter of an hour a "daily focus goal" stops meaning anything.
    public static let minCustomMinutes = 15
    /// Matches the reference's own clamp.
    public static let maxCustomMinutes = 16 * 60

    /// A goal's length in words: "45m", "1 hour", "5h 30m".
    ///
    /// Deliberately not `formatDurationShort`: a goal is a thing you chose, and "1 hour"
    /// reads like a decision where "1h" reads like a measurement.
    public static func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return hours == 1 ? "1 hour" : "\(hours) hours" }
        return "\(hours)h \(mins)m"
    }

    /// Whether a stored goal was hand-set rather than picked from the presets.
    public static func isCustom(_ minutes: Int) -> Bool { !presetMinutes.contains(minutes) }

    public struct Progress: Equatable, Sendable {
        public var goalSeconds: Int
        public var activeSeconds: Int
        /// 0–1, clamped — for the ring.
        public var fraction: Double
        public var met: Bool
        /// Seconds still to go; zero once met.
        public var remainingSeconds: Int
    }

    public static func progress(activeSeconds: Int, goalMinutes: Int) -> Progress {
        let goalSeconds = goalMinutes * 60
        return Progress(
            goalSeconds: goalSeconds,
            activeSeconds: activeSeconds,
            fraction: goalSeconds > 0
                ? min(1, Double(activeSeconds) / Double(goalSeconds)) : 0,
            met: activeSeconds >= goalSeconds,
            remainingSeconds: max(0, goalSeconds - activeSeconds)
        )
    }

    /// How many days in a row the goal has been met, counting back from today.
    ///
    /// Today counts once it is met. Until then the streak is whatever run ended yesterday —
    /// so a streak stays lit through the day you are still working on, and only resets once
    /// a whole day has passed below the goal. The alternative (anchoring on today either
    /// way) would show every streak as broken every morning, which is scolding a day for
    /// not being over yet.
    public static func streak(
        summaries: [DailySummary],
        todayStart: Int64,
        todayActiveSeconds: Int,
        goalMinutes: Int
    ) -> Int {
        let goalSeconds = goalMinutes * 60
        guard goalSeconds > 0 else { return 0 }

        var active: [Int64: Int] = [:]
        for summary in summaries { active[summary.dayStart] = summary.activeSeconds }
        // The live figure wins for today: its stored headline is only written on rollup.
        active[todayStart] = todayActiveSeconds

        func met(_ day: Int64) -> Bool { (active[day] ?? 0) >= goalSeconds }

        var day = met(todayStart) ? todayStart : todayStart - dayMillis
        var streak = 0
        while met(day) {
            streak += 1
            day -= dayMillis
        }
        return streak
    }
}
