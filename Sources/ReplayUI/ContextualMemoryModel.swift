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
    /// Something you wrote on an earlier day, offered back. One of the four things Today can
    /// lead with, and the only one that is your own words rather than the app's.
    private(set) var pastReflection: Reflection?
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
            pastReflection = nil
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

        // Two years of reflections, which is enough to catch a first-reflection
        // anniversary, and every bookmark ever made.
        let reflections = ((try? model.store.reflections(
            from: today - 366 * 2 * dayMillis, to: today + dayMillis
        )) ?? []).map { DatedText(dayStart: $0.dayStart, text: $0.text) }
        // The newest thing you wrote before today, from the last thirty days. Today's own
        // reflection is excluded — offering back what you have just written is not a memory.
        pastReflection = ((try? model.store.reflections(
            from: today - Int64(todayHeroReflectionLookbackDays) * dayMillis, to: today
        )) ?? [])
            .filter { $0.dayStart < today && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .max { $0.dayStart < $1.dayStart }

        let bookmarks = ((try? model.store.annotations(from: 0, to: now + dayMillis)) ?? [])
            .filter(\.bookmarked)
        let seed = try? model.store.momentSeed()

        var produced = [
            detectRightTime(events: events, projects: candidates, now: now),
            detectThreadUpdate(candidates, now: now),
            detectEcho(events: todayEvents, projects: candidates, now: now),
        ].compactMap { $0 }
        produced += detectAnniversaries(
            seed: seed, projects: candidates, bookmarks: bookmarks,
            reflections: reflections, now: now
        )
        produced += detectForgotten(
            projects: candidates, bookmarks: bookmarks,
            reflections: reflections, now: now
        )

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

    /// Put this memory away for now. Recorded by id, which is why the ids have to be
    /// stable — a dismissed memory that came back tomorrow would be worse than never
    /// showing it at all.
    func dismiss(_ candidate: MemoryCandidate) {
        preferences.dismissedMemories.append(candidate.id)
        load()
    }

    /// Put it away for good.
    ///
    /// A different act from dismissing, and only offered where it makes sense: saying "not
    /// today" about an anniversary is reasonable, but a bookmark you have decided you are
    /// finished with should not come round again in a month.
    func archive(_ candidate: MemoryCandidate) {
        preferences.archivedMemories.append(candidate.id)
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
