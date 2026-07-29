import Foundation
import Observation
import ReplayCore

/// What Settings reads about the database, and the actions it can take on it.
///
/// Kept apart from `Preferences` — that is what the user chose, this is what is true of the
/// data. The figures are read on demand rather than observed: Settings is a window you
/// open, not a surface that has to keep up.
@MainActor
@Observable
final class SettingsModel {
    struct DatabaseInfo: Equatable {
        var path: String
        var sizeBytes: Int
        var reclaimableBytes: Int
        var eventCount: Int
        var trackedApps: Int
        var excludedApps: Int
    }

    private(set) var info: DatabaseInfo?
    private(set) var knownApps: [KnownApp] = []
    /// The last thing an action reported, shown next to the control that ran it.
    private(set) var status: String?
    private(set) var errorMessage: String?
    private(set) var busy = false

    private let model: AppModel
    private let history: HistoryModel
    private let preferences: Preferences
    private var store: ActivityStore { model.store }

    init(model: AppModel, history: HistoryModel, preferences: Preferences) {
        self.model = model
        self.history = history
        self.preferences = preferences
    }

    func reload() {
        do {
            info = DatabaseInfo(
                path: AppModel.defaultDatabaseURL.path,
                sizeBytes: try store.fileSize(),
                reclaimableBytes: try store.reclaimableBytes(),
                eventCount: try store.countRows(),
                trackedApps: try store.listKnownApps().count,
                excludedApps: preferences.excludedApps.count
            )
            knownApps = try store.listKnownApps()
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Every app that can be excluded: those Replay has seen, plus already-excluded ones
    /// whose history is gone — so an excluded app can always be found again to un-exclude.
    var exclusionCandidates: [KnownApp] {
        var seen = Set(knownApps.map(\.bundleIdentifier))
        var all = knownApps
        for excluded in preferences.excludedApps where !seen.contains(excluded.bundleID) {
            seen.insert(excluded.bundleID)
            all.append(KnownApp(
                applicationName: excluded.name,
                bundleIdentifier: excluded.bundleID,
                appPath: excluded.appPath
            ))
        }
        return all
    }

    // ── actions ───────────────────────────────────────────────────────────────

    /// Exclude or un-exclude an application.
    ///
    /// Excluding is a privacy action, so it does two things: stops the app being recorded,
    /// and erases what was already recorded for it. Un-excluding only resumes tracking — it
    /// cannot bring erased history back, and the UI says so before you confirm.
    func setExcluded(_ app: KnownApp, _ excluded: Bool) {
        do {
            if excluded {
                guard !preferences.excludedBundleIDs.contains(app.bundleIdentifier) else { return }
                preferences.excludedApps.append(ExcludedApp(
                    bundleID: app.bundleIdentifier, name: app.applicationName, appPath: app.appPath
                ))
                let removed = try store.deleteByBundleIDs([app.bundleIdentifier])
                // Purging rows changes past days behind their stored headlines, and can take
                // the first event of a session with it — which is what a note is keyed to.
                try store.rebuildSummaries(now: now())
                _ = try store.pruneOrphanAnnotations()
                try store.compactIfWasteful()
                status = removed > 0
                    ? "Excluded \(app.applicationName), and erased \(removed) recorded rows"
                    : "Excluded \(app.applicationName)"
            } else {
                preferences.excludedApps.removeAll { $0.bundleID == app.bundleIdentifier }
                status = "\(app.applicationName) will be recorded again"
            }
            model.applyExclusions(preferences.excludedBundleIDs)
            refreshAfterChange()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Apply the retention window now, rather than only at the next launch.
    func applyRetention() {
        guard preferences.retentionDays > 0 else {
            status = "Keeping everything"
            return
        }
        do {
            let removed = try store.pruneOldEvents(
                retentionDays: preferences.retentionDays, now: now()
            )
            _ = try store.pruneOrphanAnnotations()
            status = removed > 0
                ? "Removed \(removed) rows older than \(preferences.retentionDays) days — their headlines are kept"
                : "Nothing older than \(preferences.retentionDays) days"
            refreshAfterChange()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Rewrite the file to hand freed pages back (SPEC §7).
    ///
    /// **On its own connection, off the main actor, with recording paused — and each of those
    /// three is load-bearing.**
    ///
    /// It used to run `VACUUM` on the app's own connection, on the main actor, with
    /// `defer { busy = false }` around it. So `busy` was never true for a drawn frame:
    /// "Compacting…" could not appear, the window simply stopped answering for the length of
    /// a whole-file rewrite, and the button that said it was working was unreachable code.
    ///
    /// A second connection to the same file is what lets the rewrite happen somewhere the
    /// window is not. Recording is paused around it because the alternative is a tracker
    /// writing an app switch into a file another connection holds an exclusive lock on —
    /// `SQLITE_BUSY`, and a dropped event. Pausing is honest and reversible; a dropped event
    /// is neither. The pause is put back exactly as it was found, including *not* resuming a
    /// tracker somebody had already paused themselves.
    func compact() async {
        guard !busy else { return }
        busy = true
        let wasRecording = model.isRecording
        if wasRecording { model.setTracking(false) }
        defer {
            if wasRecording { model.setTracking(true) }
            busy = false
        }

        let path = AppModel.defaultDatabaseURL.path
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<CompactionResult, Error> in
            // Opened, used and closed inside this task: nothing about it crosses back, so
            // there is no connection shared between two threads at any point.
            let scratch = ActivityStore(path: path)
            do {
                try scratch.open()
                return .success(try scratch.compactSafely())
            } catch {
                return .failure(error)
            }
        }.value

        switch outcome {
        case .success(let result):
            status = result.reclaimed > 0
                ? "Reclaimed \(formatBytes(result.reclaimed)); \(result.rows) rows verified"
                : "Nothing to reclaim; \(result.rows) rows verified"
            refreshAfterChange()
        case .failure(let error):
            // A failed verification names where the copy was left, so the message is the
            // recovery instruction rather than just bad news.
            errorMessage = "\(error)"
        }
    }

    func clearHistory() {
        do {
            let removed = try store.clearAllHistory()
            try store.compactIfWasteful()
            status = "Deleted \(removed) recorded rows"
            refreshAfterChange()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// The days Settings will offer to delete, newest first.
    ///
    /// Read from the durable per-day headlines rather than from the events, so only days
    /// Replay actually holds a record of are listed. Today is added from the front because it
    /// is never summarised while it is still being written — a day in progress has no
    /// headline yet, and leaving it out would mean the one day you might most want to drop is
    /// the one day missing from the list.
    var deletableDays: [(dayStart: Int64, label: String)] {
        let today = startOfLocalDay(now())
        let from = today - Int64(deletableDaysWindow - 1) * dayMillis
        let summaries = (try? store.dailySummaries(from: from, to: today)) ?? []
        let days = ([today] + summaries.map(\.dayStart).filter { $0 < today })
            .reduce(into: [Int64]()) { seen, day in if !seen.contains(day) { seen.append(day) } }
            .sorted(by: >)
        return days.map { ($0, relativeDayLabel($0, now: now())) }
    }

    /// Delete one day and everything written about it.
    func deleteDay(_ dayStart: Int64) {
        do {
            let removed = try store.deleteDay(dayStart: dayStart)
            status = "Deleted \(removed) recorded rows"
            refreshAfterChange()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Back to a first run: the history, every setting, and the welcome screen.
    ///
    /// The reference resets its own settings file; this port keeps preferences in
    /// `UserDefaults`, so `Preferences.reset()` is what corresponds. Deliberately not a
    /// wipe of the whole domain — that would take things `UserDefaults` holds on the app's
    /// behalf, like window frames, which nobody asked to lose.
    func resetEverything(preferences: Preferences) {
        do {
            _ = try store.clearAllHistory()
            try store.compactIfWasteful()
            preferences.reset()
            status = "Replay is back to a first run"
            refreshAfterChange()
        } catch {
            errorMessage = "\(error)"
        }
    }

    private func refreshAfterChange() {
        model.reload()
        history.reload()
        reload()
    }

    private func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

/// "482 KB", "1.2 MB" — sizes on disk, where a person is judging orders of magnitude.
func formatBytes(_ bytes: Int) -> String {
    let units = ["bytes", "KB", "MB", "GB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024, unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    if unit == 0 { return "\(bytes) bytes" }
    return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unit])
}
