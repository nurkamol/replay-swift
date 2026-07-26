import Foundation
import Observation
import ReplayCore

/// A curated walk through the best of a history.
///
/// Gathered rather than generated: every section is a filter over records that already
/// exist — the moments, the deepest stretches, the sessions marked, the lines written, the
/// projects that took the most time. Nothing here is scored and nothing is ranked against
/// anyone (SPEC §8).
@MainActor
@Observable
final class MuseumModel {
    private(set) var moments: [Moment] = []
    private(set) var deepestFocus: [ActivitySession] = []
    private(set) var bookmarked: [ActivitySession] = []
    private(set) var reflections: [Reflection] = []
    private(set) var loaded = false

    private let model: AppModel
    private let projects: ProjectsModel

    init(model: AppModel, projects: ProjectsModel) {
        self.model = model
        self.projects = projects
    }

    /// The projects that took the most time, borrowed rather than recomputed — the same
    /// detection, and a second copy could disagree with the Projects surface.
    var topProjects: [ProjectsModel.Named] {
        Array(projects.projects.sorted { $0.project.totalSeconds > $1.project.totalSeconds }.prefix(4))
    }

    var isEmpty: Bool {
        moments.isEmpty && deepestFocus.isEmpty && bookmarked.isEmpty
            && reflections.isEmpty && topProjects.isEmpty
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        let from = today - Int64(projectDays - 1) * dayMillis

        let events = ((try? model.store.sessions(from: from, to: today + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        let sessions = sessionsForWeek(events, now: now)

        // Moments reach further back than the sessions do: they read the durable headlines,
        // which outlive the rows.
        let summaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        moments = detectMoments(
            seed: try? model.store.momentSeed(),
            summaries: summaries, events: events, now: now
        )

        deepestFocus = sessions
            .filter { $0.activeSeconds >= 20 * 60 }
            .sorted { $0.activeSeconds > $1.activeSeconds }
            .prefix(3)
            .map { $0 }

        model.annotations.load(from: from, to: today + dayMillis)
        bookmarked = sessions
            .filter { model.annotations.annotation(for: $0.startedAt).bookmarked }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(4)
            .map { $0 }

        // A year of reflections rather than thirty days: a line someone wrote is worth
        // keeping in view long after the activity behind it has been pruned.
        reflections = ((try? model.store.reflections(
            from: today - 365 * dayMillis, to: today + dayMillis
        )) ?? [])
            .sorted { $0.dayStart > $1.dayStart }
            .prefix(5)
            .map { $0 }

        if !projects.loaded { projects.load() }
        loaded = true
    }

    /// The moment to feature today, stable through the day.
    var quote: Moment? {
        pickDailyQuote(moments, now: Int64(Date().timeIntervalSince1970 * 1000))
    }
}
