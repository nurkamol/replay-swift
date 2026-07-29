import Foundation

/// Pausing that ends on its own.
///
/// **The problem this exists for is not pausing — it is forgetting.** Pausing was one switch
/// with no other end than remembering to put it back, and the cost of forgetting is silent
/// and total: the rest of the day simply is not recorded, and Replay cannot tell you that
/// later because it has nothing to tell you with. A pause with a stated end is the same
/// feature with the failure removed.
///
/// The rules are here rather than in a timer because they are the part that can be wrong in a
/// way nobody notices for a day: what "until tomorrow" means when it is already tomorrow
/// somewhere in the code, and whether a deadline that passed while the Mac was asleep counts
/// as over. Both are decided by the calendar, once, where they can be tested.
public enum Pause {

    /// How long a pause lasts. Deliberately three, and deliberately not "custom": a pause is
    /// something you set in one gesture on the way to doing something else.
    public enum Span: String, CaseIterable, Sendable, Codable {
        case fifteenMinutes, hour, untilTomorrow

        /// What the menu calls it, as a sentence completing "Pause for…".
        public var label: String {
            switch self {
            case .fifteenMinutes: "15 minutes"
            case .hour: "1 hour"
            case .untilTomorrow: "Until tomorrow"
            }
        }
    }

    /// When a pause started now would end.
    ///
    /// "Until tomorrow" is the next local midnight rather than twenty-four hours: somebody
    /// stepping away from a recorded day means *this* day, and a pause that ended at 3pm
    /// tomorrow would quietly eat half of the next one too. Falling back to a day of seconds
    /// only if the calendar cannot produce a midnight, which it always can.
    public static func ends(_ span: Span, from now: Date, calendar: Calendar = .current) -> Date {
        switch span {
        case .fifteenMinutes: now.addingTimeInterval(15 * 60)
        case .hour: now.addingTimeInterval(60 * 60)
        case .untilTomorrow:
            calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(24 * 60 * 60)
        }
    }

    /// Whether a pause is finished.
    ///
    /// A deadline that passed while the Mac was asleep is over — the interesting case, and the
    /// reason this is a comparison against the clock rather than a timer that has to have been
    /// running. Nil is an indefinite pause, which is never over on its own; that is what makes
    /// it indefinite.
    public static func isOver(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now >= until
    }

    /// Whether a stored pause should still be in force at launch.
    ///
    /// A timed pause survives a quit, and an indefinite one does not — which is not an
    /// inconsistency but the difference between the two. "Pause until tomorrow" is a decision
    /// about a span of time and has to outlive the process to mean anything; "pause" with no
    /// end is a decision about *now*, and having the app come back recording is both the old
    /// behaviour and the safer direction, since the failure it risks is recording rather than
    /// not recording.
    public static func stillPaused(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now < until
    }
}
