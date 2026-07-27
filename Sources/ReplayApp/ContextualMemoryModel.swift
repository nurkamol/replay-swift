import Foundation
import Observation
import ReplayCore

/// The one memory worth surfacing right now, or none.
///
/// Every producer is asked, each scores what it found, and the selector picks the most
/// confident thing above the threshold. Most of the time the honest answer is nothing, and
/// nothing is what gets shown — a card that always has something to say stops being a memory
/// and becomes a feed.
@MainActor
@Observable
final class ContextualMemoryModel {
    private(set) var memory: MemoryCandidate?
    /// A look back at yesterday, in the morning, when there is one.
    private(set) var briefing: MorningBriefing?
    /// The moment to quote today — one line, under the briefing.
    private(set) var quote: Moment?
    private(set) var loaded = false

    private let model: AppModel
    private let projects: ProjectsModel
    private let preferences: Preferences

    init(model: AppModel, projects: ProjectsModel, preferences: Preferences) {
        self.model = model
        self.projects = projects
        self.preferences = preferences
    }

    func load() {
        loaded = true
        guard preferences.contextualMemories else {
            memory = nil
            return
        }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        // Ninety days, because right-time needs to see the previous use to have a gap to
        // name. The other producers read less and simply ignore the rest.
        let from = today - 89 * dayMillis
        let events = ((try? model.store.sessions(from: from, to: today + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        let todayEvents = events.filter { $0.startedAt >= today }

        if !projects.loaded { projects.load() }
        let candidates = projects.projects.map { named in
            MemoryProject(
                id: named.id, name: named.name, apps: named.project.apps,
                totalSeconds: named.project.totalSeconds,
                sessionCount: named.project.sessionCount,
                firstSeen: named.project.firstSeen, lastActive: named.project.lastActive,
                sessionStarts: named.project.sessions.map(\.startedAt)
            )
        }

        let produced = [
            detectRightTime(events: events, projects: candidates, now: now),
            detectThreadUpdate(candidates, now: now),
            detectEcho(events: todayEvents, projects: candidates, now: now),
        ].compactMap { $0 }

        // The briefing reads yesterday's rows and the durable headlines either side of it.
        if preferences.morningBriefing,
           !preferences.dismissedBriefings.contains(String(today)) {
            let yesterday = events.filter {
                $0.startedAt >= today - dayMillis && $0.startedAt < today
            }
            let summaries = (try? model.store.dailySummaries(
                from: today - 3 * dayMillis, to: today + dayMillis
            )) ?? []
            let bookmarks = ((try? model.store.annotations(from: 0, to: now + dayMillis)) ?? [])
                .filter(\.bookmarked)
                .map(\.sessionStart)
            let monthAgo = Memories.find(
                in: (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? [],
                now: now
            )
            .first { $0.range.key == "1mo" }
            briefing = buildMorningBriefing(
                now: now,
                yesterdayEvents: yesterday,
                summaries: summaries,
                projects: candidates,
                monthAgo: monthAgo.map { ($0.range.dayStart, $0.summary.topAppName) },
                bookmarkStarts: bookmarks
            )
        } else {
            briefing = nil
        }

        // One line under it, chosen from the day so it is the same all day.
        let allSummaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        quote = pickDailyQuote(
            detectMoments(
                seed: try? model.store.momentSeed(),
                summaries: allSummaries, events: events, now: now
            ),
            now: now
        )

        memory = selectLivingMemory(produced, MemorySelection(
            threshold: preferences.memoryThreshold,
            dismissed: Set(preferences.dismissedMemories),
            archived: Set(preferences.archivedMemories)
        ))
    }

    /// Put this memory away. Recorded by id, which is why the ids have to be stable — a
    /// dismissed memory that came back tomorrow would be worse than never showing it.
    func dismiss(_ candidate: MemoryCandidate) {
        preferences.dismissedMemories.append(candidate.id)
        load()
    }

    /// Put today's briefing away. Keyed by day, so tomorrow's is a fresh one — a briefing
    /// you dismissed once should not be gone for good.
    func dismissBriefing() {
        guard let briefing else { return }
        preferences.dismissedBriefings.append(String(briefing.dayStart))
        load()
    }
}
