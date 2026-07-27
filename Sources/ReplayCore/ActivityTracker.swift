#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation

/// Turns macOS's app-switch signal into durable focus sessions.
///
/// This is the whole recording engine, and natively it is *smaller* than the Glaze
/// version rather than larger: there, the bridge serialises `NSRunningApplication`
/// into a string that has to be parsed for a bundle identifier, and resolving an
/// app's name and path means shelling out to Spotlight. Here both come straight from
/// the notification's own object.
///
/// **It needs no permissions.** `NSWorkspace.didActivateApplicationNotification` is a
/// public signal any app may observe, and `CGEventSource` idle time is a single
/// integer from the window server. No Accessibility, no Automation, no Screen
/// Recording, and nothing is ever read from inside a window. That property is worth
/// protecting: it is the app's central privacy claim and its main advantage over
/// everything else in this category.
///
/// Replaces, in the Glaze version:
///   - `systemPreferences.subscribeWorkspaceNotification` → `NSWorkspace.notificationCenter`
///   - `powerMonitor.getSystemIdleTime`                   → `CGEventSource.secondsSinceLastEventType`
///   - `mdfind` via `child_process`                       → the notification's `NSRunningApplication`
///     (which also removes the one thing that could not survive App Sandbox)
public final class ActivityTracker {
    private let store: ActivityStore
    private let onChange: () -> Void

    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?

    /// The session currently being recorded, if any.
    private var active: (id: Int64, bundleID: String, app: AppInfo, startedAt: Int64)?
    /// When the current away stretch began, or nil while the user is present.
    private var awaySince: Int64?
    /// The session parked when the user stepped away, resumed when they return.
    private var parked: (bundleID: String, app: AppInfo)?
    /// Last time each (type, bundle) point event was recorded, for de-duplication.
    private var lastPointEvent: [String: Int64] = [:]

    public struct AppInfo: Equatable, Sendable {
        public var name: String
        public var bundleID: String?
        public var appPath: String?
    }

    /// Applications the user has asked Replay never to record.
    public var excludedBundleIDs: Set<String> = []

    public init(store: ActivityStore, onChange: @escaping () -> Void = {}) {
        self.store = store
        self.onChange = onChange
    }

    /// The clock, injectable so the recording rules can be tested against a controlled one.
    ///
    /// The tracker's whole job is *when* things happened, and every rule in it is a
    /// comparison against the clock — a dedupe window, an idle threshold, a session's end.
    /// None of that can be checked against a clock that keeps moving.
    var clock: () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }

    private func now() -> Int64 { clock() }

    // ── lifecycle ─────────────────────────────────────────────────────────────

    public var isRecording: Bool { !observers.isEmpty }

    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            self?.onActivate(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            self?.onPointEvent(.launched, note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            self?.onPointEvent(.terminated, note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        })

        idleTimer = Timer.scheduledTimer(withTimeInterval: Rules.idlePollSeconds, repeats: true) {
            [weak self] _ in self?.checkIdle()
        }

        // The app already in front when tracking starts never sends an activation, so
        // open its session now or nothing is recorded until the next switch.
        if let front = NSWorkspace.shared.frontmostApplication { onActivate(front) }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
        idleTimer?.invalidate()
        idleTimer = nil
        closeActive()
    }

    /// Flush any open session on shutdown so its duration is recorded.
    public func shutdown() {
        if let awaySince { endAway(at: now(), from: awaySince) }
        closeActive()
        stop()
    }

    // ── focus ─────────────────────────────────────────────────────────────────

    private func info(for app: NSRunningApplication) -> AppInfo {
        AppInfo(
            name: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
            bundleID: app.bundleIdentifier,
            appPath: app.bundleURL?.path
        )
    }

    private func onActivate(_ app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier else { return }
        activate(bundleID: bundleID, app: info(for: app))
    }

    /// An application came to the front.
    ///
    /// Split from the notification handler so the rules can be exercised without an
    /// `NSRunningApplication`, which a test cannot conjure. The handler's only remaining job
    /// is turning the notification into these two values.
    func activate(bundleID: String, app appInfo: AppInfo) {
        guard !Rules.ignoredBundleIDs.contains(bundleID) else { return }
        guard !excludedBundleIDs.contains(bundleID) else { return }

        // Re-activating the app that already holds focus is a no-op.
        if active?.bundleID == bundleID { return }

        // An app switch is input, so it also ends any open away stretch.
        if let awaySince { endAway(at: now(), from: awaySince, resume: false) }

        let at = now()
        do {
            if let active { try store.closeSession(id: active.id, endedAt: at) }
            let id = try store.openSession(
                name: appInfo.name, bundleID: appInfo.bundleID, appPath: appInfo.appPath, startedAt: at
            )
            active = (id, bundleID, appInfo, at)
            onChange()
        } catch {
            NSLog("[replay] could not record an app switch: \(error)")
        }
    }

    private func onPointEvent(_ type: EventType, _ app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier else { return }
        point(type, bundleID: bundleID, app: info(for: app))
    }

    /// An application launched or quit.
    func point(_ type: EventType, bundleID: String, app appInfo: AppInfo) {
        guard !Rules.ignoredBundleIDs.contains(bundleID) else { return }
        guard !excludedBundleIDs.contains(bundleID) else { return }

        // These notifications can arrive more than once for one real event.
        let at = now()
        let key = "\(type.rawValue):\(bundleID)"
        if let last = lastPointEvent[key],
           Double(at - last) < Rules.pointEventDedupeSeconds * 1000 { return }
        lastPointEvent[key] = at
        if lastPointEvent.count > 500 { lastPointEvent.removeAll() }

        try? store.recordPointEvent(
            type: type, name: appInfo.name, bundleID: appInfo.bundleID,
            appPath: appInfo.appPath, at: at
        )
    }

    private func closeActive(at: Int64? = nil) {
        guard let active else { return }
        try? store.closeSession(id: active.id, endedAt: at ?? now())
        self.active = nil
    }

    // ── away ──────────────────────────────────────────────────────────────────

    /// Seconds since the last keyboard or mouse input.
    ///
    /// `.anyInputEventType` covers key and mouse events without inspecting any of
    /// them — Replay learns only *that* input happened, never what it was.
    private func systemIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .init(rawValue: ~0)!)
    }

    /// Sample input idleness and park or resume the current session around it.
    ///
    /// Idle time is read as "seconds since the last input", so the moment the user
    /// stepped away is reconstructed exactly rather than rounded to the poll
    /// interval: away began `idleSeconds` ago, not now.
    private func checkIdle() {
        let idleSeconds = systemIdleSeconds()
        let at = now()

        guard let awaySince else {
            guard Int(idleSeconds) >= Rules.awayAfterSeconds else { return }
            let awayStart = at - Int64(idleSeconds * 1000)
            if let active {
                parked = (active.bundleID, active.app)
                try? store.closeSession(id: active.id, endedAt: awayStart)
                self.active = nil
            }
            self.awaySince = awayStart
            onChange()
            return
        }

        guard Int(idleSeconds) < Rules.awayAfterSeconds else { return }
        // Input resumed: the away stretch ended when that input happened.
        endAway(at: at - Int64(idleSeconds * 1000), from: awaySince)
    }

    /// Close the open away stretch and, unless an activation is about to do it,
    /// pick the parked session back up.
    ///
    /// Resuming matters: if the user comes back to the app they left in front, no
    /// activation notification fires, so without this nothing would be recorded until
    /// they next switched apps.
    /// Mark the user as away from a given instant. Reachable for tests; the idle timer is
    /// what calls it in the app.
    func beginAway(at: Int64) {
        guard awaySince == nil else { return }
        if let active {
            parked = (active.bundleID, active.app)
            closeActive(at: at)
        }
        awaySince = at
    }

    func endAway(at returnedAt: Int64, from awayStart: Int64, resume: Bool = true) {
        awaySince = nil
        try? store.recordAway(startedAt: awayStart, endedAt: returnedAt)

        guard resume, let parked else { self.parked = nil; return }
        self.parked = nil
        if let id = try? store.openSession(
            name: parked.app.name, bundleID: parked.app.bundleID,
            appPath: parked.app.appPath, startedAt: returnedAt
        ) {
            active = (id, parked.bundleID, parked.app, returnedAt)
        }
        onChange()
    }

    public var isAway: Bool { awaySince != nil }

    /// What is in front right now, for a menu bar item. Nil while away or paused.
    public var current: (applicationName: String, startedAt: Int64)? {
        active.map { ($0.app.name, $0.startedAt) }
    }

    // ── deletion that the tracker has to know about ───────────────────────────

    /// Erase a day, keeping in-memory state honest.
    ///
    /// Deleting *today* is the interesting case: the rows this tracker is holding onto
    /// are about to disappear underneath it, so its state is rebuilt rather than left
    /// pointing at ids that no longer exist. Recording then resumes from this moment
    /// for whatever is in front — the same reasoning as resuming from away: no
    /// activation is coming for an app that never lost focus.
    @discardableResult
    public func deleteDay(dayStart: Int64) throws -> Int {
        let at = now()
        let isToday = dayStart == startOfLocalDay(at)
        let inFront: (bundleID: String, app: AppInfo)? = isToday
            ? active.map { ($0.bundleID, $0.app) } ?? parked
            : nil

        let removed = try store.deleteDay(dayStart: dayStart)
        _ = try store.pruneOrphanAnnotations()
        try store.compactIfWasteful()

        if isToday {
            active = nil
            awaySince = nil
            parked = nil
            if let inFront, isRecording,
               let id = try? store.openSession(
                   name: inFront.app.name, bundleID: inFront.app.bundleID,
                   appPath: inFront.app.appPath, startedAt: at
               ) {
                active = (id, inFront.bundleID, inFront.app, at)
            }
        }
        onChange()
        return removed
    }

    /// Erase one session — the rows behind a single card — and settle what follows:
    /// the affected days' headlines, orphaned annotations, and freed pages.
    @discardableResult
    public func deleteSession(eventIDs: [Int64]) throws -> Int {
        let result = try store.deleteEvents(ids: eventIDs)
        try store.resummarize(days: result.dayStarts, now: now())
        _ = try store.pruneOrphanAnnotations()
        try store.compactIfWasteful()
        onChange()
        return result.removed
    }
}
#endif
