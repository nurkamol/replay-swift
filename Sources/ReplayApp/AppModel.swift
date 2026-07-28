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
    /// Today's reflection, and the headlines behind a focus streak.
    private(set) var reflection = Reflection(dayStart: 0)
    private(set) var recentSummaries: [DailySummary] = []

    let store: ActivityStore
    /// Shared with every surface, so a bookmark set in the Timeline is already true here.
    let annotations: AnnotationsModel
    private var tracker: ActivityTracker?
    private var timer: Timer?
    /// When the derivation last ran, so the clock can tick faster than the figures.
    private var lastDerivedAt: Int64 = 0

    /// How often the day is re-derived against a fresh `now`.
    ///
    /// The reference re-derives on a 30s timer (`useNow`, and a matching `refetchInterval`).
    /// Without it the headline only moves when the tracker records a switch, so leaving
    /// Replay in front freezes Today at whatever it read on the last one — while a day
    /// opened from the Timeline, which derives on demand, reads higher.
    private static let deriveIntervalMillis: Int64 = 30_000

    /// The app's own container, so the native app never touches the Glaze database.
    /// Defined in `ReplayCore` because App Intents open the same file without the app.
    static var defaultDatabaseURL: URL { ReplayCore.defaultDatabaseURL() }

    init(databaseURL: URL = AppModel.defaultDatabaseURL) {
        store = ActivityStore(path: databaseURL.path)
        annotations = AnnotationsModel(store: store)
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

    /// One second is enough for a live "23m" to look alive; the day itself is re-derived on
    /// the slower interval, because a headline measured in minutes does not need a query a
    /// second to stay true.
    private func tick() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
        current = tracker?.current
        isAway = tracker?.isAway ?? false
        if now - lastDerivedAt >= Self.deriveIntervalMillis { reload() }
    }

    func reload() {
        now = Int64(Date().timeIntervalSince1970 * 1000)
        lastDerivedAt = now
        let dayStart = startOfLocalDay(now)
        do {
            // Only runs that *began* today: the query reaches back on purpose, and a
            // session crossing midnight belongs to the day it started (SPEC §5).
            let events = try store
                .sessions(from: dayStart, to: dayStart + dayMillis)
                .filter { $0.startedAt >= dayStart }
            timeline = buildTimeline(events, now: now)
            summary = computeDaySummary(events: events, timeline: timeline, dayStart: dayStart, now: now)
            annotations.load(from: dayStart, to: dayStart + dayMillis)
            reflection = try store.reflection(dayStart: dayStart)
            // A year is enough to draw any streak anyone will have, and stays one indexed
            // range scan rather than a walk back through all of history.
            recentSummaries = try store.dailySummaries(from: dayStart - 366 * dayMillis, to: dayStart)
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
        current = tracker?.current
        isAway = tracker?.isAway ?? false
        isRecording = tracker?.isRecording ?? false
    }

    // ── actions ───────────────────────────────────────────────────────────────

    /// Hand the tracker the set it should never record.
    ///
    /// Applied live rather than at the next launch: excluding an app is a privacy action,
    /// and one that only takes effect after a restart is not one.
    /// Active seconds per day for a heatmap, headlines plus today from the sessions.
    ///
    /// One definition because there are two grids — Memories' "Browse by date" and My
    /// Story's "Growth" — and they were about to disagree: headlines are written for days
    /// that have finished, so a grid reading only headlines shows today as an idle day.
    /// Memories had a fix for that inline and My Story would have shipped without one.
    ///
    /// Today goes through `computeDaySummary` over the same events Today counts, with the
    /// same "began today" filter, so no grid can disagree with the headline at the top of
    /// Today either.
    func activityByDay() -> [Int64: Int] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let todayStart = startOfLocalDay(now)
        let summaries = (try? store.dailySummaries(from: 0, to: todayStart + dayMillis)) ?? []
        var byDay = Dictionary(
            summaries.map { ($0.dayStart, $0.activeSeconds) },
            uniquingKeysWith: { first, _ in first }
        )
        let events = ((try? store.sessions(from: todayStart, to: todayStart + dayMillis)) ?? [])
            .filter { $0.startedAt >= todayStart }
        let live = computeDaySummary(
            events: events, timeline: buildTimeline(events, now: now),
            dayStart: todayStart, now: now
        ).activeSeconds
        if live > 0 { byDay[todayStart] = live }
        return byDay
    }

    func applyExclusions(_ bundleIDs: Set<String>) {
        tracker?.excludedBundleIDs = bundleIDs
    }

    func setTracking(_ enabled: Bool) {
        guard let tracker else { return }
        if enabled { tracker.start() } else { tracker.stop() }
        isRecording = tracker.isRecording
        reload()
    }

    func setReflection(_ text: String) {
        do {
            reflection = try store.setReflection(
                dayStart: startOfLocalDay(now), text: text, now: now
            )
        } catch {
            errorMessage = "\(error)"
        }
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

    /// The application in front, with the fields an icon needs.
    ///
    /// The tracker knows a name and a start; the bundle identifier and path live on the
    /// `SessionApp` rows the timeline built. Searching backwards finds the most recent
    /// session that mentions this application, which is the one it is currently in.
    ///
    /// Here rather than in a view because two surfaces want it — ambient mode and the menu
    /// bar popover — and the second one was about to be a copy of the first.
    var currentApp: (name: String, bundleID: String?, appPath: String?)? {
        guard let current else { return nil }
        for item in timeline.reversed() {
            guard case .session(let session) = item else { continue }
            if let app = session.apps.first(where: { $0.applicationName == current.applicationName }) {
                return (current.applicationName, app.bundleIdentifier, app.appPath)
            }
        }
        return (current.applicationName, nil, nil)
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
