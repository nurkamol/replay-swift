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
    /// True while a backup is being read and merged, so the button can say so. It could not
    /// before: the whole thing ran on the main actor, so no state it set was ever drawn.
    private(set) var busy = false
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

    /// The sessions a scope covers. Lives on `AppModel` now, because the scheduled report
    /// needs exactly the same selection and two copies of a range query is how two features
    /// come to disagree about what "this week" means.
    private func selection(_ scope: Report.Scope) -> [Report.Entry] {
        model.reportEntries(for: scope)
    }

    /// Save a report of these sessions, pairing each with what was written on it.
    func exportReport(_ format: Report.Format, label: String, sessions: [ActivitySession]) {
        exportReport(format, label: label, entries: entries(for: sessions))
    }

    /// Resolve an app icon to a data URI, so a shared document carries its own images.
    ///
    /// Redrawn into a 64×64 bitmap rather than handed straight to `tiffRepresentation`.
    /// Setting `NSImage.size` changes the *point* size and nothing about the pixels: the
    /// representation handed back is still the largest one in the iconset, a 1024px master.
    /// Sixty-nine sessions across a week of apps produced an **89 MB** HTML file that way —
    /// full-resolution art for tiles drawn eighteen points wide. At 64px the same report is
    /// a few hundred kilobytes and looks identical.
    private func iconDataURI(_ appPath: String?) -> String? {
        guard let appPath, FileManager.default.fileExists(atPath: appPath) else { return nil }
        let source = NSWorkspace.shared.icon(forFile: appPath)

        let side = 64
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        source.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
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

        let written = String(
            format: Loc.t("Exported %1$@ to %2$@"),
            Loc.count(entries.count, "%@ session", "%@ sessions"),
            url.lastPathComponent
        )

        do {
            switch format {
            case .html:
                let document = Report.html(
                    label: label, entries: entries, icon: { [self] in iconDataURI($0) }
                )
                try document.write(to: url, atomically: true, encoding: .utf8)
            case .pdf:
                // Drawn rather than serialised — see `ReportPDF`, and the three dead WebKit
                // routes in the ledger that led there.
                try ReportPDF.write(
                    Report.PDF.page(label: label, entries: entries), to: url
                )
            case .markdown, .csv, .json:
                try Report.build(format, label: label, entries: entries)
                    .write(to: url, atomically: true, encoding: .utf8)
            }
            status = written
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
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Replay.version
            try Backup.encode(rows: rows, appVersion: version).write(to: url, options: .atomic)
            status = "Backed up \(rows.count) rows to \(url.lastPathComponent)"
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't write that backup: \(error.localizedDescription)"
        }
    }

    /// Hand a report to the system's share sheet rather than to a save panel.
    ///
    /// Written to a temporary file first because that is what every sharing service takes —
    /// Mail wants an attachment, Messages wants a file, Notes wants a document. A string
    /// would only reach a subset of them.
    func share(_ format: Report.Format, label: String, sessions: [ActivitySession], from view: NSView?) {
        let entries = entries(for: sessions)
        guard !entries.isEmpty, let view else {
            errorMessage = "There's nothing recorded here to share"
            return
        }
        do {
            let name = Report.defaultName(label: label, format: format)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            let content = format == .html
                ? Report.html(label: label, entries: entries, icon: { [self] in iconDataURI($0) })
                : Report.build(format, label: label, entries: entries)
            try content.write(to: url, atomically: true, encoding: .utf8)

            let picker = NSSharingServicePicker(items: [url])
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
            status = nil
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't prepare that for sharing: \(error.localizedDescription)"
        }
    }

    /// Read a backup back in. Merges rather than replaces — an import never erases.
    /// Read a backup and merge it, without the window going quiet while it happens.
    ///
    /// **Split where the work actually splits.** Reading is pure — parse JSON, validate every
    /// field, produce rows — and for a large export it is the slow half, so it happens off the
    /// main actor. Writing is SQL on the app's own connection inside one transaction, and it
    /// stays here: a second connection would be writing the same file the tracker is writing,
    /// and the in-memory state would be reading a database that had changed underneath it.
    ///
    /// Recording is paused around the merge for the same reason compaction pauses it — an app
    /// switch landing mid-transaction is a write waiting on a lock — and put back exactly as
    /// it was found.
    func importBackup() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }

        let read = await Task.detached(priority: .userInitiated) { () -> Result<Backup.ReadResult, Error> in
            do { return .success(try Backup.read(contentsOf: url)) } catch { return .failure(error) }
        }.value

        let parsed: Backup.ReadResult
        switch read {
        case .success(let value): parsed = value
        case .failure(let error): errorMessage = "\(error)"; return
        }

        let wasRecording = model.isRecording
        if wasRecording { model.setTracking(false) }
        defer { if wasRecording { model.setTracking(true) } }

        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let restored = try model.store.restore(rows: parsed.rows)
            if restored.imported > 0 { try model.store.rebuildSummaries(now: now) }
            model.reload()
            var message = "Imported \(restored.imported) rows"
            if restored.skipped > 0 { message += ", skipped \(restored.skipped) already here" }
            if parsed.skipped > 0 { message += ", \(parsed.skipped) unreadable" }
            status = message
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
    }
}
