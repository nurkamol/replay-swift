import AppKit
import Foundation
import Observation
import ReplayCore

/// The long view: rituals, eras, and the history told back.
///
/// All three read the durable daily headlines rather than the raw rows, which is why they
/// reach across the whole kept history and survive a retention prune. Rituals are the one
/// exception — they need sessions, so they look only at the recent window.
@MainActor
@Observable
final class StoryModel {
    private(set) var rituals = Rituals(slots: [], firstApp: nil)

    struct NamedChapter: Identifiable {
        var chapter: Chapter
        var name: String
        var named: Bool
        var id: String { chapter.id }
    }

    private(set) var chapters: [NamedChapter] = []
    private(set) var periods: [Period] = []
    private(set) var loaded = false

    private let model: AppModel
    private let preferences: Preferences

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)

        // Rituals need sessions, so they read the recent window rather than all history.
        let recentFrom = today - Int64(projectDays - 1) * dayMillis
        let recent = ((try? model.store.sessions(from: recentFrom, to: today + dayMillis)) ?? [])
            .filter { $0.startedAt >= recentFrom }
        rituals = detectRituals(
            sessions: sessionsForWeek(recent, now: now), events: recent
        )

        // Everything else reads the headlines, from the beginning of time.
        let summaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        chapters = detectChapters(summaries, appPaths: appPaths(summaries)).map(named)
        periods = listPeriods(summaries)
        loaded = true
    }

    func chapter(_ id: String) -> NamedChapter? { chapters.first { $0.id == id } }

    /// The whole archive. Computed on demand rather than held: it is a handful of
    /// aggregates over headlines already in the database, and caching it would only make
    /// it possible for it to be stale.
    func legacy() -> Legacy? {
        let today = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        let summaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        return computeLegacy(summaries, appPaths: appPaths(summaries))
    }

    /// The story of one period, told now rather than cached — it is a paragraph of text
    /// assembled from numbers already in hand, and holding it would only risk it going stale.
    func autobiography(for period: Period) -> Autobiography {
        let today = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        let summaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        // Reflections live in their own table, so they are counted separately.
        let reflections = (try? model.store.reflections(
            from: period.start, to: period.end + dayMillis
        )) ?? []
        return summarizePeriod(
            period, summaries: summaries,
            appPaths: appPaths(summaries),
            reflectionCount: reflections.count
        )
    }

    func rename(chapter id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = preferences.chapterNames
        if trimmed.isEmpty { names.removeValue(forKey: id) } else { names[id] = trimmed }
        preferences.chapterNames = names
        chapters = chapters.map { named($0.chapter) }
    }

    private func named(_ chapter: Chapter) -> NamedChapter {
        let names = preferences.chapterNames
        let custom = names[chapter.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NamedChapter(
            chapter: chapter,
            name: resolveChapterName(chapter, names: names),
            named: !custom.isEmpty
        )
    }

    /// Icons for the apps that led each day.
    ///
    /// A headline stores a bundle identifier but no path, because the app that led a day two
    /// years ago may not be installed any more — so the path is looked up now, and simply
    /// absent when it is gone.
    private func appPaths(_ summaries: [DailySummary]) -> [String: String] {
        var paths: [String: String] = [:]
        for id in Set(summaries.compactMap(\.topBundleID)) {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                paths[id] = url.path
            }
        }
        return paths
    }
}
