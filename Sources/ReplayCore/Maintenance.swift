import Foundation
import SQLite3

/// An application Replay has seen, for the exclusion picker.
public struct KnownApp: Equatable, Sendable {
    public var applicationName: String
    public var bundleIdentifier: String
    public var appPath: String?

    public init(applicationName: String, bundleIdentifier: String, appPath: String? = nil) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
    }
}

/// What a compaction did, or why it did not finish.
public struct CompactionResult: Equatable, Sendable {
    public var before: Int
    public var after: Int
    public var rows: Int
    /// The copy taken first. Removed on success; **left on disk and named** on failure.
    public var backupPath: String?

    public var reclaimed: Int { max(0, before - after) }
}

public enum CompactionError: Error, CustomStringConvertible {
    case verificationFailed(detail: String, backupPath: String)

    public var description: String {
        switch self {
        case .verificationFailed(let detail, let path):
            "The compacted database did not verify (\(detail)). "
                + "Your data has not been touched — a copy from before the attempt is at \(path)"
        }
    }
}

extension ActivityStore {
    /// Every application Replay has recorded, most recently used first.
    ///
    /// Read from the events themselves rather than a table of its own: the apps you have
    /// used *are* the history. An excluded app whose rows are gone will not appear here,
    /// which is why the exclusion list stores each app's name and path too.
    public func listKnownApps() throws -> [KnownApp] {
        try query(
            """
            SELECT application_name, bundle_identifier, metadata, MAX(started_at) AS last_used
            FROM events
            WHERE type = 'activated' AND bundle_identifier IS NOT NULL
            GROUP BY bundle_identifier
            ORDER BY last_used DESC
            """,
            [],
            row: { statement in
                var appPath: String?
                if let raw = sqlite3_column_text(statement, 2).map({ String(cString: $0) }),
                   let data = raw.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    appPath = parsed["appPath"] as? String
                }
                return KnownApp(
                    applicationName: sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "",
                    bundleIdentifier: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "",
                    appPath: appPath
                )
            }
        )
    }

    /// Erase every row belonging to these applications.
    ///
    /// Excluding an app is a privacy action: it stops the app being recorded going forward
    /// *and* erases what was already recorded for it, because an excluded app should leave
    /// no trace, past or future. Un-excluding only resumes tracking; it cannot bring erased
    /// history back.
    @discardableResult
    public func deleteByBundleIDs(_ bundleIDs: [String]) throws -> Int {
        guard !bundleIDs.isEmpty else { return 0 }
        var removed = 0
        for chunk in stride(from: 0, to: bundleIDs.count, by: Rules.deleteChunk).map({
            Array(bundleIDs[$0..<min($0 + Rules.deleteChunk, bundleIDs.count)])
        }) {
            let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
            removed += try run(
                "DELETE FROM events WHERE bundle_identifier IN (\(placeholders))",
                chunk.map(Value.text)
            )
        }
        return removed
    }

    /// Erase everything: rows, headlines, reflections, annotations.
    ///
    /// Unlike a retention prune this keeps no headline behind. "Clear history" has to mean
    /// what it says, or the promise the Privacy tab makes is not true.
    @discardableResult
    public func clearAllHistory() throws -> Int {
        var removed = 0
        try transaction {
            removed = try run("DELETE FROM events", [])
            _ = try run("DELETE FROM daily_summaries", [])
            _ = try run("DELETE FROM reflections", [])
            _ = try run("DELETE FROM annotations", [])
        }
        return removed
    }

    /// Rewrite the database to hand freed pages back to the disk, safely.
    ///
    /// The order is the one SPEC §7 fixes, and every step of it is load-bearing: copy the
    /// file, `VACUUM`, verify with `integrity_check` **and** a row count, and only then
    /// remove the copy. If verification fails the copy is **left on disk and named in the
    /// error**, because a caller that cannot say where the backup went has not made one.
    ///
    /// Deliberately no automatic restore: swapping files underneath live connections is a
    /// more dangerous path than the one it guards, and `VACUUM` is already transactional.
    public func compactSafely() throws -> CompactionResult {
        let before = try fileSize()
        let rowsBefore = try countRows()

        let backupURL = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .appendingPathComponent("activity-before-compaction.db")
        try? FileManager.default.removeItem(at: backupURL)

        // A checkpointed copy through SQLite rather than a file copy, so an open
        // connection's uncommitted pages cannot make the copy a torn one.
        try backup(to: backupURL.path)

        try vacuum()

        let check = integrityCheck()
        let rowsAfter = try countRows()
        guard check.ok, rowsAfter == rowsBefore else {
            let detail = check.ok
                ? "row count went from \(rowsBefore) to \(rowsAfter)"
                : check.detail
            throw CompactionError.verificationFailed(
                detail: detail, backupPath: backupURL.path
            )
        }

        try? FileManager.default.removeItem(at: backupURL)
        return CompactionResult(
            before: before, after: try fileSize(), rows: rowsAfter, backupPath: nil
        )
    }

    /// Bytes the database occupies on disk, including its write-ahead log.
    public func fileSize() throws -> Int {
        let manager = FileManager.default
        return [path, path + "-wal", path + "-shm"].reduce(0) { total, candidate in
            let size = (try? manager.attributesOfItem(atPath: candidate)[.size] as? Int) ?? nil
            return total + (size ?? 0)
        }
    }

    /// Copy the live database to `destination` using SQLite's own backup API.
    private func backup(to destination: String) throws {
        var target: OpaquePointer?
        guard sqlite3_open_v2(
            destination, &target, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil
        ) == SQLITE_OK, let target else {
            if let target { sqlite3_close(target) }
            throw StoreError.sql("open backup", "could not create \(destination)")
        }
        defer { sqlite3_close(target) }

        guard let session = sqlite3_backup_init(target, "main", try handle(), "main") else {
            throw StoreError.sql("backup", String(cString: sqlite3_errmsg(target)))
        }
        sqlite3_backup_step(session, -1)
        let status = sqlite3_backup_finish(session)
        guard status == SQLITE_OK else {
            throw StoreError.sql("backup", String(cString: sqlite3_errmsg(target)))
        }
    }
}
