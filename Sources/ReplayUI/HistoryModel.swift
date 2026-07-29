import Foundation
import Observation
import ReplayCore

/// A day as the Timeline draws it: its key, its name, and the runs that began on it.
struct TimelineDay: Identifiable {
    var dayStart: Int64
    var label: String
    var items: [TimelineItem]

    var id: Int64 { dayStart }

    var sessions: [ActivitySession] {
        items.compactMap { if case .session(let s) = $0 { return s } else { return nil } }
    }

    var activeSeconds: Int {
        sessions.reduce(0) { $0 + $1.activeSeconds }
    }
}

/// History: everything the Timeline and a reopened day read.
///
/// Separate from `AppModel` on purpose — that one owns the tracker and today's live state,
/// and reloads on every recorded event. History is a read-only view over the same store
/// that only needs to reload when the range changes or a day is deleted.
@MainActor
@Observable
final class HistoryModel {
    var range: TimeRange = .week {
        didSet { if range != oldValue { reload() } }
    }

    private(set) var days: [TimelineDay] = []
    private(set) var errorMessage: String?

    /// Deletion goes through the live model so it takes the tracker's path — restating the
    /// affected days' headlines and pruning orphaned annotations (SPEC §6) — rather than a
    /// second, quieter way to remove rows.
    private let model: AppModel
    private var store: ActivityStore { model.store }

    init(model: AppModel) {
        self.model = model
    }

    func reload() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        let from = today - Int64(range.days - 1) * dayMillis
        let to = today + dayMillis

        do {
            let events = try store.sessions(from: from, to: to)
            var built = groupByDay(events).map { group in
                TimelineDay(
                    dayStart: group.dayStart,
                    label: dayLabel(group.dayStart, today: today),
                    // Built per day, so a run never straddles midnight.
                    items: buildTimeline(group.events, now: now)
                )
            }
            // The query reaches back by design; a day older than the range came with it.
            built = built.filter { $0.dayStart >= from }
            if let offset = range.keepDayOffset {
                let wanted = today - Int64(offset) * dayMillis
                built = built.filter { $0.dayStart == wanted }
            }
            days = built
            model.annotations.load(from: from, to: to)
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// One day from the past, reopened — the same derivation, for a single fixed day.
    ///
    /// Keeps only the runs that *began* on the day: the range query deliberately reaches
    /// back, so without this filter a session crossing midnight appears on two days at
    /// once. The Glaze app shipped that bug once (SPEC §5).
    func day(_ dayStart: Int64) -> TimelineDay {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let end = dayStart + dayMillis
        let events = ((try? store.sessions(from: dayStart, to: end)) ?? [])
            .filter { $0.startedAt >= dayStart && $0.startedAt < end }
        model.annotations.load(from: dayStart, to: end)
        return TimelineDay(
            dayStart: dayStart,
            label: dayLabel(dayStart, today: startOfLocalDay(now)),
            items: buildTimeline(events, now: now)
        )
    }

    /// What was written about a day, or an empty reflection.
    func reflection(_ dayStart: Int64) -> Reflection {
        (try? store.reflection(dayStart: dayStart)) ?? Reflection(dayStart: dayStart)
    }

    func setReflection(_ dayStart: Int64, _ text: String) {
        do {
            _ = try store.setReflection(
                dayStart: dayStart, text: text,
                now: Int64(Date().timeIntervalSince1970 * 1000)
            )
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// The durable headline for a day, which outlives the rows behind it.
    ///
    /// What tells "nothing was recorded" apart from "this day is older than the kept
    /// history": the events are gone but the summary is not.
    func headline(_ dayStart: Int64) -> DailySummary? {
        try? store.dailySummaries(from: dayStart, to: dayStart + dayMillis).first
    }

    /// Erase a whole day: its rows, its headline, its reflection, its annotations.
    ///
    /// Unlike a retention prune this leaves no headline behind — a day the user deleted
    /// should leave no trace, not a summary of what it used to be (SPEC §6).
    func deleteDay(_ dayStart: Int64) {
        do {
            _ = try store.deleteDay(dayStart: dayStart)
            // Explicit rather than left to the orphan prune below: notes and bookmarks are
            // memories of the sessions being erased, so they go with them by intent.
            _ = try store.deleteAnnotations(from: dayStart, to: dayStart + dayMillis)
            _ = try store.pruneOrphanAnnotations()
            try store.compactIfWasteful()
            reload()
            // Today's figures are stale if today is what went.
            model.reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func deleteSession(_ session: ActivitySession) {
        model.deleteSession(session)
        reload()
    }
}

/// How a day is named on screen. Relative for the two days people think of by name, and a
/// plain date for the rest — a date is unambiguous, and "3 days ago" makes you count.
func dayLabel(_ dayStart: Int64, today: Int64) -> String {
    if dayStart == today { return "Today" }
    if dayStart == today - dayMillis { return "Yesterday" }
    return Date(timeIntervalSince1970: Double(dayStart) / 1000)
        .formatted(.dateTime.weekday(.wide).month(.wide).day().locale(Loc.locale))
}


