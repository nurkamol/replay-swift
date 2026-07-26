import Foundation
import Observation
import ReplayCore

/// One application's own history.
///
/// Every figure here is about *this* app, so the rows are filtered before anything is
/// summed. `visits` counts rows rather than derived sessions — how many times the app came
/// to the front — which is why the average visit is short and honest rather than a session
/// length dressed up as attention.
@MainActor
@Observable
final class AppHistoryModel {
    struct Figures: Equatable {
        var today = 0
        var yesterday = 0
        var lastWeek = 0
        var averageVisit = 0
        var visits = 0
    }

    private(set) var name = ""
    private(set) var appPath: String?
    private(set) var figures = Figures()
    /// The sessions this application took part in, newest first.
    private(set) var sessions: [ActivitySession] = []
    /// Which collections those sessions fall into — the kinds of work this app is part of.
    private(set) var collections: [SessionCategory] = []
    private(set) var loaded = false

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load(bundleID: String) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let todayStart = startOfLocalDay(now)
        let from = todayStart - Int64(Report.fetchDays - 1) * dayMillis
        let to = todayStart + dayMillis

        let all = ((try? model.store.sessions(from: from, to: to)) ?? [])
            .filter { $0.startedAt >= from }
        let mine = all.filter { $0.bundleIdentifier == bundleID }

        name = mine.first?.applicationName ?? bundleID
        appPath = mine.first { $0.appPath != nil }?.appPath

        func total(_ from: Int64, _ to: Int64) -> Int {
            mine.filter { $0.startedAt >= from && $0.startedAt < to }
                .reduce(0) { $0 + $1.effectiveDuration(now: now) }
        }
        let overall = mine.reduce(0) { $0 + $1.effectiveDuration(now: now) }
        figures = Figures(
            today: total(todayStart, todayStart + dayMillis),
            yesterday: total(todayStart - dayMillis, todayStart),
            lastWeek: total(todayStart - 6 * dayMillis, todayStart + dayMillis),
            averageVisit: mine.isEmpty
                ? 0
                : Int((Double(overall) / Double(mine.count)).rounded()),
            visits: mine.count
        )

        // Idle stretches go before the derivation here, as upstream — this list is about
        // where the app actually showed up, not where a Mac was left open on it.
        let derived = sessionsForWeek(excludeIdleStretches(all, now: now), now: now)
        sessions = derived
            .filter { $0.apps.contains { $0.bundleIdentifier == bundleID } }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(12)
            .map { $0 }

        // Ordered by the collections table rather than by how many sessions landed in each,
        // so the chips read in the same order everywhere in the app.
        let present = Set(sessions.map(\.category))
        collections = Collections.categories.map(\.category).filter(present.contains)

        model.annotations.load(from: from, to: to)
        loaded = true
    }
}
