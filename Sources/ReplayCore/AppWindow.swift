import Foundation

/// How far back the surface is looking. Not a `TimeRange` — that one exists for the
/// Timeline and carries a `keepDayOffset` rule about single days that means nothing
/// here, where every window reaches back from today.
public enum AppWindow: String, CaseIterable, Identifiable {
    case today, week, month

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .today: "Today"
        case .week: "This Week"
        case .month: "This Month"
        }
    }

    public var subtitle: String {
        switch self {
        case .today: "Where your time went today."
        case .week: "Where your time went this week."
        case .month: "Where your time went this month."
        }
    }

    public var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }
}
