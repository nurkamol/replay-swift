import Foundation

/// A year of days, as squares — and how dark each one gets.
///
/// The rule that matters here is that a square's shade means a *quantity*, not a rank. Five
/// fixed steps at half an hour, an hour and a half and three hours, so the same amount of
/// work looks the same in June as in December, and a quiet month reads as quiet rather than
/// being stretched to fill the scale.
///
/// This port originally shaded each day against the busiest day in the window, which looks
/// reasonable in isolation and is wrong for the thing the grid is for: it made every year
/// look equally busy, and made a square uncomparable with the square beside it. The
/// thresholds are the reference's and are contract-checked.
public enum Heatmap {

    /// How much a square has to hold to reach each step, in seconds.
    public static let lowSeconds = 30 * 60
    public static let midSeconds = 90 * 60
    public static let highSeconds = 3 * 3600

    /// How much of the accent each level mixes into the empty-square colour, as a percentage.
    /// Level 0 is the well itself, which is why it is zero rather than absent.
    public static let levelMix: [Int] = [0, 26, 46, 70, 100]

    /// Nothing, through to a full day's work.
    public enum Level: Int, Sendable, CaseIterable {
        case none = 0, light = 1, some = 2, most = 3, full = 4
    }

    /// Which step a day falls on.
    public static func level(_ seconds: Int) -> Level {
        if seconds <= 0 { return .none }
        if seconds < lowSeconds { return .light }
        if seconds < midSeconds { return .some }
        if seconds < highSeconds { return .most }
        return .full
    }

    /// How much accent a level carries, as a fraction — what the view actually blends with.
    public static func mix(_ level: Level) -> Double {
        Double(levelMix[level.rawValue]) / 100
    }

    /// A week, a month, or a year. The three the reference offers, and no more: a range
    /// picker with six entries is a settings screen, not a way of looking at a year.
    public enum Range: String, Sendable, CaseIterable, Identifiable {
        case week, month, year
        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .week: "Week"
            case .month: "Month"
            case .year: "Year"
            }
        }

        /// How far back this range reaches, in days.
        public var backDays: Int {
            switch self {
            case .week: 6
            case .month: 34
            case .year: 370
            }
        }
    }

    /// How many week-columns the year grid draws, and how many cells a month grid fills.
    /// Both are fixed rather than derived: a grid whose width changed with the month would
    /// reflow the page every time you paged through one.
    public static let yearWeeks = 53
    public static let monthCells = 42

    /// How early in a week a month has to begin before that column is labelled with it.
    /// Without this a month starting on a Saturday would label the column that is almost
    /// entirely the month before.
    public static let monthLabelMaxDate = 7
}
