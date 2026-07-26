import Foundation
import Observation
import ReplayCore

/// Everything the UI reads, in one place.
///
/// The Glaze app needs React Query and an IPC layer to get the backend's state into its
/// views; natively the store *is* the model, so this is a thin observable wrapper that
/// reloads when the tracker records something and on a slow timer for the clock.
@MainActor
@Observable
final class AppModel {
    private(set) var timeline: [TimelineItem] = []
    private(set) var summary: DaySummary?
    private(set) var current: (applicationName: String, startedAt: Int64)?
    private(set) var isAway = false
    private(set) var isRecording = false
    private(set) var errorMessage: String?
    /// Ticks so views that show a live duration redraw.
    private(set) var now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)

    let store: ActivityStore
    private var tracker: ActivityTracker?
    private var timer: Timer?

    /// The app's own container, so the native app never touches the Glaze database.
    static var defaultDatabaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("app.replay.native/activity.db")
    }

    init(databaseURL: URL = AppModel.defaultDatabaseURL) {
        store = ActivityStore(path: databaseURL.path)
        do {
            try FileManager.default.createDirectory(
                at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try store.open()
            // Fold complete days into headlines on launch, as the reference does.
            try store.rollupCompleteDays(now: now)
        } catch {
            errorMessage = "\(error)"
        }
    }

    func start() {
        let tracker = ActivityTracker(store: store) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        self.tracker = tracker
        tracker.start()
        isRecording = tracker.isRecording

        // One second is enough for a live "23m" to look alive without redrawing constantly.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        reload()
    }

    func shutdown() {
        timer?.invalidate()
        tracker?.shutdown()
        store.close()
    }

    private func tick() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
        current = tracker?.current
        isAway = tracker?.isAway ?? false
    }

    func reload() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
        let dayStart = startOfLocalDay(now)
        do {
            // Only runs that *began* today: the query reaches back on purpose, and a
            // session crossing midnight belongs to the day it started (SPEC §5).
            let events = try store
                .sessions(from: dayStart, to: dayStart + dayMillis)
                .filter { $0.startedAt >= dayStart }
            timeline = buildTimeline(events, now: now)
            summary = computeDaySummary(events: events, timeline: timeline, dayStart: dayStart, now: now)
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
        current = tracker?.current
        isAway = tracker?.isAway ?? false
        isRecording = tracker?.isRecording ?? false
    }

    // ── actions ───────────────────────────────────────────────────────────────

    func setTracking(_ enabled: Bool) {
        guard let tracker else { return }
        if enabled { tracker.start() } else { tracker.stop() }
        isRecording = tracker.isRecording
        reload()
    }

    func deleteSession(_ session: ActivitySession) {
        do {
            _ = try tracker?.deleteSession(eventIDs: session.events.map(\.id))
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    var sessions: [ActivitySession] {
        timeline.compactMap { if case .session(let s) = $0 { return s } else { return nil } }
    }

    /// What the menu bar says: the app in front, how long you have been away, or paused.
    var statusLine: String {
        if !isRecording { return "Paused" }
        if isAway { return "Away" }
        guard let current else { return "Replay" }
        let elapsed = max(0, Int((Double(now - current.startedAt) / 1000).rounded()))
        return "\(current.applicationName) · \(formatDurationShort(elapsed))"
    }
}
