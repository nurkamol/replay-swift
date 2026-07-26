import Foundation
import Observation
import ReplayCore

/// Where your time went, by application.
///
/// The widest window is fetched once and each narrower one is a filter over it, as upstream:
/// switching between Today, This Week and This Month should not be a database query, and the
/// thirty days are already the span Search and export cover.
@MainActor
@Observable
final class AppsModel {
    /// How far back the surface is looking. Not a `TimeRange` — that one exists for the
    /// Timeline and carries a `keepDayOffset` rule about single days that means nothing
    /// here, where every window reaches back from today.
    enum Window: String, CaseIterable, Identifiable {
        case today, week, month

        var id: String { rawValue }

        var label: String {
            switch self {
            case .today: "Today"
            case .week: "This Week"
            case .month: "This Month"
            }
        }

        var subtitle: String {
            switch self {
            case .today: "Where your time went today."
            case .week: "Where your time went this week."
            case .month: "Where your time went this month."
            }
        }

        var days: Int {
            switch self {
            case .today: 1
            case .week: 7
            case .month: 30
            }
        }
    }

    var window: Window = .week {
        didSet { if window != oldValue { refilter() } }
    }

    private(set) var stats: [AppStat] = []
    private(set) var loaded = false

    /// Everything in the widest window, filtered down per selection.
    private var all: [ActivityEvent] = []
    private var now: Int64 = 0

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    var totalSeconds: Int { stats.reduce(0) { $0 + $1.totalSeconds } }

    /// The apps kept at the top by choice, in the order they were pinned, and only when they
    /// have activity in the current window — a favourite with nothing in it this week is not
    /// news, it is a blank row.
    func favourites(pinned: [String]) -> [AppStat] {
        let byID = Dictionary(
            stats.compactMap { stat in stat.bundleIdentifier.map { ($0, stat) } },
            uniquingKeysWith: { first, _ in first }
        )
        return pinned.compactMap { byID[$0] }
    }

    func load() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
        let todayStart = startOfLocalDay(now)
        let from = todayStart - Int64(Window.month.days - 1) * dayMillis
        all = ((try? model.store.sessions(from: from, to: todayStart + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        loaded = true
        refilter()
    }

    private func refilter() {
        let from = startOfLocalDay(now) - Int64(window.days - 1) * dayMillis
        let windowed = all.filter { $0.startedAt >= from }
        // Idle stretches go before counting, not after: "how long in this app" means time
        // at the keyboard rather than a Mac left open with the app in front (SPEC §4).
        stats = computeAppStats(excludeIdleStretches(windowed, now: now), now: now)
    }
}
