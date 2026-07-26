import Foundation
import Observation
import ReplayCore

/// One pair of applications, and how they are used together.
@MainActor
@Observable
final class RelationshipsModel {
    private(set) var pair: Relationship?
    private(set) var loaded = false

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func load(keyA: String, keyB: String) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let from = startOfLocalDay(now) - Int64(Report.fetchDays - 1) * dayMillis
        let events = ((try? model.store.sessions(from: from, to: now + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        // Idle stretches go before the derivation, as upstream: a bond between two apps
        // means switching between them, not a Mac left open with one in front.
        let sessions = sessionsForWeek(excludeIdleStretches(events, now: now), now: now)
        pair = computeRelationship(sessions, keyA: keyA, keyB: keyB)
        model.annotations.load(from: from, to: now + dayMillis)
        loaded = true
    }
}
