import Foundation
import Observation
import ReplayCore

/// What the user has written on their sessions, held for whatever is on screen.
///
/// Keyed by session start, and loaded a range at a time rather than a card at a time: a day
/// of session cards should cost one query, not one per card. Every surface shares one of
/// these, so bookmarking a session in the Timeline is already true when Today next draws it.
@MainActor
@Observable
final class AnnotationsModel {
    private(set) var entries: [Int64: SessionAnnotation] = [:]
    private(set) var errorMessage: String?

    private let store: ActivityStore

    init(store: ActivityStore) {
        self.store = store
    }

    /// What is stored for a session, or an empty annotation when it has nothing.
    func annotation(for sessionStart: Int64) -> SessionAnnotation {
        entries[sessionStart] ?? SessionAnnotation(sessionStart: sessionStart)
    }

    /// Load the annotations for `[from, to)`, replacing what is held for that span.
    ///
    /// The span is cleared first so an annotation deleted elsewhere does not linger in the
    /// cache as a ghost mark on a card.
    func load(from: Int64, to: Int64) {
        do {
            let loaded = try store.annotations(from: from, to: to)
            entries = entries.filter { $0.key < from || $0.key >= to }
            for annotation in loaded { entries[annotation.sessionStart] = annotation }
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    // ── writes ────────────────────────────────────────────────────────────────
    //
    // Each writes through immediately and keeps the returned row, which is the store's
    // truth after normalising and after the empty-row rule — so the UI shows what was
    // actually saved rather than what was typed.

    func setNote(_ sessionStart: Int64, _ note: String) {
        apply(sessionStart) { try store.setNote(sessionStart: sessionStart, note: note, now: $0) }
    }

    func setBookmarked(_ sessionStart: Int64, _ bookmarked: Bool) {
        apply(sessionStart) {
            try store.setBookmarked(sessionStart: sessionStart, bookmarked: bookmarked, now: $0)
        }
    }

    func setTags(_ sessionStart: Int64, _ tags: [String]) {
        apply(sessionStart) { try store.setTags(sessionStart: sessionStart, tags: tags, now: $0) }
    }

    private func apply(_ sessionStart: Int64, _ write: (Int64) throws -> SessionAnnotation) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            let saved = try write(now)
            // An emptied annotation leaves no row, so it leaves no entry either.
            if saved.isEmpty { entries.removeValue(forKey: sessionStart) } else { entries[sessionStart] = saved }
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }
}
