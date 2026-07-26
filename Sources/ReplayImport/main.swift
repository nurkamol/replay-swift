import Foundation
import ReplayCore

// Import a Glaze backup into the native app's database.
//
//     swift run replay-import <backup.json> [database.db]
//
// The two apps have separate containers and will never share a live database, so this is
// how a Glaze user's history moves across — and, right now, how this port gets real data
// to develop the UI against instead of fixtures.
//
// Safe to run twice: the import merges on (type, started_at, bundle_identifier) and skips
// what is already there.

let arguments = CommandLine.arguments.dropFirst()
guard let backupPath = arguments.first else {
    print("""
        usage: swift run replay-import <backup.json> [database.db]

        Export a backup from the Glaze app first:
          Settings ▸ Data ▸ Full backup ▸ Export…
        """)
    exit(64)
}

let defaultDB = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/app.replay.native/activity.db")
let dbPath = arguments.dropFirst().first.map { URL(fileURLWithPath: $0) } ?? defaultDB

do {
    try FileManager.default.createDirectory(
        at: dbPath.deletingLastPathComponent(), withIntermediateDirectories: true
    )

    let store = ActivityStore(path: dbPath.path)
    try store.open()
    let before = try store.countRows()

    let parsed = try Backup.read(contentsOf: URL(fileURLWithPath: backupPath))
    print("Backup: \(parsed.rows.count) readable rows"
          + (parsed.skipped > 0 ? ", \(parsed.skipped) malformed and skipped" : "")
          + (parsed.appVersion.map { " · written by Replay \($0)" } ?? "")
          + (parsed.exportedAt.map { " on \($0)" } ?? ""))
    if let declared = parsed.declaredCount, declared != parsed.rows.count + parsed.skipped {
        print("  note: the file claims \(declared) events but contains "
              + "\(parsed.rows.count + parsed.skipped)")
    }

    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let result = try store.importBackup(from: URL(fileURLWithPath: backupPath), now: now)

    let after = try store.countRows()
    let idle = parsed.rows.filter { $0.type == .idle }.count
    print("""

        Imported  \(result.imported)
        Skipped   \(result.skipped) (already present)
        Rows      \(before) → \(after)
        Away rows \(idle) in the backup — kept, not dropped
        Database  \(dbPath.path)
        """)

    // Show something recognisable, as a sanity check that the data is usable.
    if let first = try store.sessions(from: 0, to: now).first {
        let days = try store.dailySummaries(from: 0, to: now)
        print("Earliest row \(Date(timeIntervalSince1970: Double(first.startedAt) / 1000))")
        print("Day headlines \(days.count)")
    }
    store.close()
    exit(0)
} catch {
    print("Import failed: \(error)")
    exit(1)
}
