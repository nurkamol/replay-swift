import AppKit
import Foundation
import Observation
import ReplayCore

/// Writing what is on screen to a file the user picks.
///
/// The save panel and the write live here; the *shape* of a report is `ReplayCore.Report`,
/// which has no idea a window exists. Same split as the reference, for the same reason:
/// the format is behaviour worth checking, the file dialog is not.
@MainActor
@Observable
final class ExportModel {
    private(set) var status: String?
    private(set) var errorMessage: String?

    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Pair each session with whatever was written on it, so an export carries the notes.
    func entries(for sessions: [ActivitySession]) -> [Report.Entry] {
        sessions.map {
            let annotation = model.annotations.annotation(for: $0.startedAt)
            return Report.Entry(session: $0, annotation: annotation.isEmpty ? nil : annotation)
        }
    }

    /// How many sessions a scope would export right now, for the dialog to say so before
    /// anyone picks a file. An export that turns out to be empty after the save panel is a
    /// wasted trip.
    func count(_ scope: Report.Scope) -> Int {
        selection(scope).count
    }

    /// Export a named slice of history rather than one day.
    func exportScope(_ format: Report.Format, scope: Report.Scope) {
        exportReport(format, label: scope.label, entries: selection(scope))
    }

    /// The sessions a scope covers, derived from one fetch wide enough for any of them.
    private func selection(_ scope: Report.Scope) -> [Report.Entry] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let todayStart = startOfLocalDay(now)
        let from = todayStart - Int64(Report.fetchDays - 1) * dayMillis
        let to = todayStart + dayMillis

        do {
            // The store's range query reaches back on purpose, so runs that began before the
            // window are dropped here — the same rule every day-scoped view follows (SPEC §5).
            let events = try model.store.sessions(from: from, to: to)
                .filter { $0.startedAt >= from }
            let sessions = Report.sessions(in: events, now: now)
            let annotations = Dictionary(
                uniqueKeysWithValues: try model.store.annotations(from: from, to: to)
                    .map { ($0.sessionStart, $0) }
            )
            return Report.select(
                scope, sessions: sessions, annotations: annotations, todayStart: todayStart
            )
        } catch {
            errorMessage = "\(error)"
            return []
        }
    }

    /// Save a report of these sessions, pairing each with what was written on it.
    func exportReport(_ format: Report.Format, label: String, sessions: [ActivitySession]) {
        exportReport(format, label: label, entries: entries(for: sessions))
    }

    /// Save a report of entries that are already paired.
    ///
    /// Refuses an empty selection rather than writing an empty file: a report of nothing is
    /// a file you find later and cannot explain.
    func exportReport(_ format: Report.Format, label: String, entries: [Report.Entry]) {
        guard !entries.isEmpty else {
            errorMessage = "There's nothing recorded here to export"
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = Report.defaultName(label: label, format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = Report.build(format, label: label, entries: entries)
            try content.write(to: url, atomically: true, encoding: .utf8)
            status = "Exported \(entries.count) \(entries.count == 1 ? "session" : "sessions") "
                + "to \(url.lastPathComponent)"
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't write that file: \(error.localizedDescription)"
        }
    }

    /// Write the whole database as the backup format both implementations read.
    ///
    /// Deliberately not one of the report formats: a report is shaped for reading and drops
    /// what a restore needs. Calling a report a backup is how people lose history.
    func exportBackup() {
        let panel = NSSavePanel()
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "Replay backup \(stamp).json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let rows = try model.store.rowsForBackup()
            let version = Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
            try Backup.encode(rows: rows, appVersion: version).write(to: url, options: .atomic)
            status = "Backed up \(rows.count) rows to \(url.lastPathComponent)"
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't write that backup: \(error.localizedDescription)"
        }
    }

    /// Read a backup back in. Merges rather than replaces — an import never erases.
    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let result = try model.store.importBackup(from: url, now: now)
            model.reload()
            var message = "Imported \(result.imported) rows"
            if result.skipped > 0 { message += ", skipped \(result.skipped) already here" }
            if result.malformed > 0 { message += ", \(result.malformed) unreadable" }
            status = message
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }
}
