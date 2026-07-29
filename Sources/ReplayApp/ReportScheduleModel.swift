import AppKit
import Observation
import ReplayCore

/// A report in a folder, every day or every week, without being asked.
///
/// **The one file in this app you are meant to open.** The scheduled *backup* beside it is
/// insurance — its value is that it restores, and the best outcome is never reading it. This
/// is the opposite: a week's report landing in a folder on a Monday is, for most people, the
/// only way they ever look back at a week deliberately rather than by accident.
///
/// Deliberately the same shape as ``AutoBackupModel``: same cadence, same chosen folder, same
/// eight kept, same rule that it prunes only files matching its own pattern. Two features that
/// do the same *kind* of thing should read the same, and a reader who has understood one
/// should not have to work the other out.
///
/// Markdown or HTML, and not PDF: a PDF is one page with a pointer to HTML for anything
/// longer, which is right for a document somebody asked for and wrong for a file that arrives
/// on its own and might cover a busy week.
@MainActor
@Observable
final class ReportScheduleModel {
    private let model: AppModel
    private let preferences: Preferences

    private(set) var status: String?
    private(set) var errorMessage: String?

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
    }

    var folderURL: URL? {
        preferences.reportFolder.isEmpty
            ? nil
            : URL(fileURLWithPath: preferences.reportFolder, isDirectory: true)
    }

    var folderLabel: String? { folderURL?.lastPathComponent }

    /// The formats a schedule may write. See the note above about PDF.
    static let formats: [Report.Format] = [.markdown, .html]

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = Loc.t("Choose")
        panel.message = Loc.t("Where should Replay write its reports?")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        preferences.reportFolder = url.path
        errorMessage = nil
        runIfDue()
    }

    /// Write one if one is owed. Called at launch and on the hour, beside the backup.
    func runIfDue(now: Date = Date()) {
        guard preferences.reportCadence != .off, folderURL != nil else { return }
        guard AutoBackup.isDue(
            last: preferences.lastReport, now: now, cadence: preferences.reportCadence
        ) else { return }
        run(now: now)
    }

    func runNow() { run(now: Date()) }

    /// Build the period that has finished and write it.
    ///
    /// The stamp is written only after the file is, so a failure is retried on the next tick
    /// rather than counting as the day's report — the same rule the update check had to learn.
    private func run(now: Date) {
        guard let folder = folderURL else {
            errorMessage = Loc.t("Choose a folder for Replay to write reports into.")
            return
        }
        guard let scope = ScheduledReport.scope(for: preferences.reportCadence) else { return }
        let format = preferences.reportFormat
        let entries = model.reportEntries(for: scope)
        guard !entries.isEmpty else {
            // Nothing happened in the period. A file saying so is a file that trains somebody
            // to ignore the folder, so the schedule simply waits for a period with something
            // in it — and says so here rather than silently doing nothing.
            preferences.lastReport = now
            status = Loc.t("Nothing recorded in that period — no report written.")
            return
        }

        do {
            let url = folder.appendingPathComponent(
                ScheduledReport.filename(for: now, format: format)
            )
            let content = format == .html
                ? Report.html(label: scope.label, entries: entries)
                : Report.build(format, label: scope.label, entries: entries)
            try content.write(to: url, atomically: true, encoding: .utf8)
            preferences.lastReport = now
            prune(in: folder)
            status = String(
                format: Loc.t("Wrote %@ to %@"), scope.label, url.lastPathComponent
            )
            errorMessage = nil
        } catch {
            errorMessage = String(
                format: Loc.t("Couldn't write that report: %@"), error.localizedDescription
            )
        }
    }

    private func prune(in folder: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in ScheduledReport.stale(names) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    var lastRunLabel: String? {
        preferences.lastReport.map {
            $0.formatted(.relative(presentation: .named).locale(Loc.locale))
        }
    }
}
