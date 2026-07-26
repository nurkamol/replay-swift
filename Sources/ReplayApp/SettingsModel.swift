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
    func compact() {
        busy = true
        defer { busy = false }
        do {
            let result = try store.compactSafely()
            status = result.reclaimed > 0
                ? "Reclaimed \(formatBytes(result.reclaimed)); \(result.rows) rows verified"
                : "Nothing to reclaim; \(result.rows) rows verified"
            refreshAfterChange()
        } catch {
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
