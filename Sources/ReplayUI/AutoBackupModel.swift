import AppKit
import Observation
import ReplayCore

/// Backups nobody has to remember to take.
///
/// The app already exports a full backup — a panel, a filename, a place to put it — and that
/// is the version somebody does twice and then stops doing. This is the same file, written on
/// a schedule into a folder they chose once, and it exists because of the one thing this app
/// claims: the record is theirs and it is only here. A record that only exists once is one
/// disk away from not existing.
///
/// **It is off until it is asked for.** Writing several megabytes into a folder nobody named
/// would be exactly the sort of thing this app does not do.
///
/// Not sandboxed, so a plain path is enough to write there. If Replay is ever sandboxed this
/// is the one place that changes: the folder would have to be kept as a security-scoped
/// bookmark and resolved with `startAccessingSecurityScopedResource` around each write. The
/// rest of this — when a backup is due, what it is called, which old ones go — is in
/// `AutoBackup` in the core, where it is tested without a disk.
@MainActor
@Observable
final class AutoBackupModel {
    private let model: AppModel
    private let preferences: Preferences

    /// What the last attempt did, for the line in Settings. Never an alert: a backup is a
    /// background courtesy, and interrupting somebody to tell them it worked would undo the
    /// point of it.
    private(set) var status: String?
    private(set) var errorMessage: String?

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
    }

    var folderURL: URL? {
        preferences.autoBackupFolder.isEmpty
            ? nil
            : URL(fileURLWithPath: preferences.autoBackupFolder, isDirectory: true)
    }

    /// The folder, named the way a person named it rather than as a path.
    var folderLabel: String? { folderURL?.lastPathComponent }

    /// Ask for the folder. Nothing is written until one is chosen.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = Loc.t("Choose")
        panel.message = Loc.t("Where should Replay keep its backups?")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.autoBackupFolder = url.path
        errorMessage = nil
        // Chosen a folder and set a schedule: the first copy belongs now rather than
        // tomorrow, so the thing that was just switched on has visibly happened.
        runIfDue()
    }

    /// Write one if one is owed. Called at launch and on the hour.
    func runIfDue(now: Date = Date()) {
        guard preferences.autoBackupCadence != .off, folderURL != nil else { return }
        guard AutoBackup.isDue(
            last: preferences.lastAutoBackup, now: now, cadence: preferences.autoBackupCadence
        ) else { return }
        run(now: now)
    }

    /// Write one because somebody asked, due or not.
    func runNow() { run(now: Date()) }

    /// The whole database, written atomically, and the oldest copies removed.
    ///
    /// Atomically because the failure this guards against is the one that matters: a backup
    /// half-written when the machine sleeps is a file that looks like a backup and restores
    /// nothing. `.atomic` writes a temporary file and renames it, so what is in the folder is
    /// either the previous copy or a complete new one.
    ///
    /// The last-run stamp is written only after the file is, so a failed attempt is retried
    /// on the next tick rather than waiting a day to fail again.
    private func run(now: Date) {
        guard let folder = folderURL else {
            errorMessage = "Choose a folder for Replay to keep backups in."
            return
        }
        do {
            let rows = try model.store.rowsForBackup()
            let version = Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                ?? Replay.version
            let url = folder.appendingPathComponent(AutoBackup.filename(for: now))
            try Backup.encode(rows: rows, appVersion: version, now: now)
                .write(to: url, options: .atomic)
            preferences.lastAutoBackup = now
            prune(in: folder)
            status = String(
                format: Loc.t("Backed up %@ rows to %@"), "\(rows.count)", url.lastPathComponent
            )
            errorMessage = nil
        } catch {
            errorMessage = String(
                format: Loc.t("Couldn't write that backup: %@"), error.localizedDescription
            )
        }
    }

    /// Remove the oldest copies past the keep limit, and only ones this wrote.
    ///
    /// A folder chosen for backups is very likely a folder with other things in it. The names
    /// are matched against this feature's own pattern in `AutoBackup.stale`, and anything
    /// else in there is not this code's business. A failure to delete is deliberately silent:
    /// too many backups is not a problem worth interrupting anybody about, and the copy that
    /// was just written is safe either way.
    private func prune(in folder: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in AutoBackup.stale(names) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// "Yesterday at 3:04 AM", or nothing when it has never run.
    var lastRunLabel: String? {
        preferences.lastAutoBackup.map {
            $0.formatted(.relative(presentation: .named).locale(Loc.locale))
        }
    }
}
