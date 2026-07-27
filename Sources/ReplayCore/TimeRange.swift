import Foundation

/// The spans the Timeline can jump between.
///
/// The single-day ranges deliberately fetch more than their day and then keep only it: the
/// range query reaches back so a long away stretch that began before midnight is not lost,
/// and the day filter is applied afterwards (SPEC §5).
public enum TimeRange: String, CaseIterable, Identifiable, Sendable {
    case today, yesterday, week, month

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .week: "Last 7 Days"
        case .month: "Last 30 Days"
        }
    }

    public var subtitle: String {
        switch self {
        case .today: "Everything you did today."
        case .yesterday: "A look back at yesterday."
        case .week: "Your last seven days, newest first."
        case .month: "The last month, newest first."
        }
    }

    /// Days of events to fetch back from today, inclusive.
    public var days: Int {
        switch self {
        case .today: 1
        case .yesterday: 2
        case .week: 7
        case .month: 30
        }
    }

    /// Which single day to keep, as an offset back from today. `nil` keeps them all.
    public var keepDayOffset: Int? {
        switch self {
        case .today: 0
        case .yesterday: 1
        case .week, .month: nil
        }
    }
}

/// What the Timeline opens on. The reference's own default, and checked.
public let defaultTimeRange = TimeRange.week
