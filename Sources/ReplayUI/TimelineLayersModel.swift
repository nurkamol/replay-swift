import Foundation
import Observation
import ReplayCore

/// What the Timeline's layers need beyond the days themselves.
///
/// Two different jobs. **Projects** narrows: it knows which sessions belong to a detected
/// project. The other three *add* — a reflection, a moment, an earlier year — and each keeps
/// a day on screen even when every session in it has been filtered away, because a day you
/// only wrote about is still a day worth seeing.
@MainActor
@Observable
final class TimelineLayersModel {
    /// The session starts that belong to some project.
    private(set) var projectSessions: Set<Int64> = []
    private(set) var reflections: [Int64: String] = [:]
    private(set) var moments: [Int64: [Moment]] = [:]
    /// For a day, what the same calendar date held in an earlier year.
    private(set) var earlierYears: [Int64: (dayStart: Int64, topApp: String?)] = [:]
    private(set) var loaded = false

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        let from = today - Int64(projectDays - 1) * dayMillis
        let events = ((try? model.store.sessions(from: from, to: today + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }

        projectSessions = Set(
            detectProjects(sessionsForWeek(events, now: now))
                .flatMap { $0.sessions.map(\.startedAt) }
        )

        reflections = Dictionary(
            ((try? model.store.reflections(from: from, to: today + dayMillis)) ?? [])
                .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.dayStart, $0.text) },
            uniquingKeysWith: { first, _ in first }
        )

        let summaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        moments = Dictionary(
            grouping: detectMoments(
                seed: try? model.store.momentSeed(),
                summaries: summaries, events: events, now: now
            ).compactMap { moment in moment.dayStart.map { ($0, moment) } },
            by: \.0
        ).mapValues { $0.map(\.1) }

        // The same calendar date in an earlier year. Built once as a lookup rather than
        // searched per day: a thirty-day range would otherwise scan the whole history
        // thirty times over.
        var byMonthDay: [String: [(year: Int, dayStart: Int64, topApp: String?)]] = [:]
        let calendar = Calendar.current
        for summary in summaries where summary.activeSeconds > 0 {
            let parts = calendar.dateComponents(
                [.year, .month, .day],
                from: Date(timeIntervalSince1970: Double(summary.dayStart) / 1000)
            )
            let key = "\(parts.month ?? 0)-\(parts.day ?? 0)"
            byMonthDay[key, default: []].append(
                (parts.year ?? 0, summary.dayStart, summary.topAppName)
            )
        }
        var found: [Int64: (dayStart: Int64, topApp: String?)] = [:]
        for offset in 0..<Int(TimeRange.month.days) {
            let day = today - Int64(offset) * dayMillis
            let parts = calendar.dateComponents(
                [.year, .month, .day], from: Date(timeIntervalSince1970: Double(day) / 1000)
            )
            let key = "\(parts.month ?? 0)-\(parts.day ?? 0)"
            let earlier = (byMonthDay[key] ?? []).filter { $0.year < (parts.year ?? 0) }
            if let best = earlier.max(by: { $0.year < $1.year }) {
                found[day] = (best.dayStart, best.topApp)
            }
        }
        earlierYears = found
        loaded = true
    }
}
