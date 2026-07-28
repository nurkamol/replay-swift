import Foundation
import SQLite3

/// SQLite storage for macOS application-activity events.
///
/// The schema is `spec/schema.sql`, generated from the Glaze app — a database written
/// by either implementation must be readable by the other, so this file's `CREATE`
/// statements are not a design decision to revisit but a contract to match.
///
/// Raw SQL against the system SQLite on purpose: the queries here have to stay
/// identical to the Glaze app's, and a query builder would hide exactly the details
/// that matter (the `duration < idleStretchSeconds` filter that makes "active" mean
/// something, the `started_at` lower bound that keeps range scans bounded).
/// Where Replay keeps its record.
///
/// In `ReplayCore` rather than in the app because more than one process needs it now: the
/// app opens it to write, and an App Intent opens it to read without the app running. Two
/// copies of a path is how a feature ends up reading an empty database on somebody else's
/// Mac and nobody finding out.
public func defaultDatabaseURL() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("app.replay.native/activity.db")
}

public final class ActivityStore {
    private var db: OpaquePointer?
    // Internal so Maintenance.swift can name the file it is copying and rewriting.
    let path: String

    public init(path: String) {
        self.path = path
    }

    deinit { if db != nil { sqlite3_close(db) } }

    public enum StoreError: Error, CustomStringConvertible {
        case open(String)
        case sql(String, String)

        public var description: String {
            switch self {
            case .open(let message): "could not open the database: \(message)"
            case .sql(let statement, let message): "\(message) — while running: \(statement)"
            }
        }
    }

    // ── lifecycle ─────────────────────────────────────────────────────────────

    /// Open the database and ensure the schema exists. Safe to call more than once.
    public func open() throws {
        guard db == nil else { return }
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw StoreError.open(message)
        }
        db = handle
        try exec(Self.schema)

        // Any session left open by a previous run (quit or crash mid-session) is
        // closed at its own start, so it never counts time the app was not around
        // to observe.
        try exec("""
            UPDATE events SET ended_at = started_at, duration = 0
            WHERE type = 'activated' AND ended_at IS NULL
            """)
    }

    public func close() {
        if db != nil { sqlite3_close(db) }
        db = nil
    }

    /// Kept in step with `spec/schema.sql`; `swift run replay-parity` fails if it
    /// drifts. Exposed through `schemaForParityCheck` so that check can read it
    /// without making the schema part of the public API.
    static let schema = """
        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          application_name TEXT NOT NULL,
          bundle_identifier TEXT,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          duration INTEGER NOT NULL DEFAULT 0,
          metadata TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_events_started ON events(started_at);
        CREATE INDEX IF NOT EXISTS idx_events_type ON events(type);

        CREATE TABLE IF NOT EXISTS daily_summaries (
          day_start INTEGER PRIMARY KEY,
          active_seconds INTEGER NOT NULL,
          top_bundle_id TEXT,
          top_app_name TEXT,
          top_seconds INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS reflections (
          day_start INTEGER PRIMARY KEY,
          text TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS annotations (
          session_start INTEGER PRIMARY KEY,
          note TEXT,
          bookmarked INTEGER NOT NULL DEFAULT 0,
          tags TEXT,
          updated_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_annotations_bookmarked ON annotations(bookmarked);
        """

    /// The schema text, for `replay-parity` to compare against the generated spec.
    public static var schemaForParityCheck: String { schema }

    // ── plumbing ──────────────────────────────────────────────────────────────

    func handle() throws -> OpaquePointer {
        guard let db else { throw StoreError.open("store used before open()") }
        return db
    }

    private func exec(_ sql: String) throws {
        let db = try handle()
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw StoreError.sql(sql, message)
        }
    }

    /// Bindable SQLite values, so callers pass parameters rather than interpolating.
    public enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null
    }

    private func prepare(_ sql: String, _ params: [Value]) throws -> OpaquePointer {
        let db = try handle()
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = String(cString: sqlite3_errmsg(db))
            sqlite3_finalize(statement)
            throw StoreError.sql(sql, message)
        }
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(statement, position, v)
            case .double(let v): sqlite3_bind_double(statement, position, v)
            case .text(let v): sqlite3_bind_text(statement, position, v, -1, SQLITE_TRANSIENT)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    // Internal rather than private so the extensions in Backup.swift and Annotations.swift
    // can build statements the same way this file does, instead of each growing its own.
    @discardableResult
    func run(_ sql: String, _ params: [Value] = []) throws -> Int {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        guard status == SQLITE_DONE || status == SQLITE_ROW else {
            throw StoreError.sql(sql, String(cString: sqlite3_errmsg(try handle())))
        }
        return Int(sqlite3_changes(try handle()))
    }

    func query<T>(
        _ sql: String,
        _ params: [Value] = [],
        row: (OpaquePointer) -> T
    ) throws -> [T] {
        let statement = try prepare(sql, params)
        defer { sqlite3_finalize(statement) }
        var out: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { out.append(row(statement)) }
        return out
    }

    // ── helpers for extensions in other files (Backup.swift) ──────────────────

    /// Run a statement, ignoring any rows it returns.
    func execute(_ sql: String, _ params: [Value] = []) throws {
        try run(sql, params)
    }

    /// Whether a query matched anything — for existence checks.
    func queryFirst(_ sql: String, _ params: [Value] = []) throws -> Bool {
        try !query(sql, params, row: { _ in true }).isEmpty
    }

    /// Run `body` inside a transaction, rolling back if it throws.
    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN")
        do {
            try body()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    private func optionalInt(_ statement: OpaquePointer, _ column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL
            ? nil : sqlite3_column_int64(statement, column)
    }

    // ── writing activity ──────────────────────────────────────────────────────

    /// Open a focus session; returns the row id.
    @discardableResult
    public func openSession(
        name: String,
        bundleID: String?,
        appPath: String?,
        startedAt: Int64
    ) throws -> Int64 {
        let metadata = "{\"appPath\":\(appPath.map { "\"\($0)\"" } ?? "null")}"
        try run(
            """
            INSERT INTO events (type, application_name, bundle_identifier, started_at, ended_at, duration, metadata)
            VALUES ('activated', ?, ?, ?, NULL, 0, ?)
            """,
            [.text(name), bundleID.map(Value.text) ?? .null, .int(startedAt), .text(metadata)]
        )
        return sqlite3_last_insert_rowid(try handle())
    }

    /// Close a session: stamp `ended_at` and compute the duration in whole seconds.
    public func closeSession(id: Int64, endedAt: Int64) throws {
        try run(
            """
            UPDATE events
            SET ended_at = ?, duration = MAX(0, CAST(ROUND((? - started_at) / 1000.0) AS INTEGER))
            WHERE id = ? AND ended_at IS NULL
            """,
            [.int(endedAt), .int(endedAt), .int(id)]
        )
    }

    /// Record a stretch with no keyboard or mouse input.
    public func recordAway(startedAt: Int64, endedAt: Int64) throws {
        let duration = max(0, Int((Double(endedAt - startedAt) / 1000).rounded()))
        guard duration > 0 else { return }
        try run(
            """
            INSERT INTO events (type, application_name, bundle_identifier, started_at, ended_at, duration, metadata)
            VALUES ('idle', 'Away', NULL, ?, ?, ?, NULL)
            """,
            [.int(startedAt), .int(endedAt), .int(Int64(duration))]
        )
    }

    /// Record a point-in-time event (launch / terminate) with no duration.
    public func recordPointEvent(
        type: EventType,
        name: String,
        bundleID: String?,
        appPath: String?,
        at: Int64
    ) throws {
        let metadata = "{\"appPath\":\(appPath.map { "\"\($0)\"" } ?? "null")}"
        try run(
            """
            INSERT INTO events (type, application_name, bundle_identifier, started_at, ended_at, duration, metadata)
            VALUES (?, ?, ?, ?, ?, 0, ?)
            """,
            [
                .text(type.rawValue), .text(name), bundleID.map(Value.text) ?? .null,
                .int(at), .int(at), .text(metadata),
            ]
        )
    }

    // ── reading ───────────────────────────────────────────────────────────────

    private func event(from statement: OpaquePointer) -> ActivityEvent {
        var appPath: String?
        if let metadata = text(statement, 7),
           let data = metadata.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            appPath = parsed["appPath"] as? String
        }
        return ActivityEvent(
            id: sqlite3_column_int64(statement, 0),
            type: EventType(rawValue: text(statement, 1) ?? "activated") ?? .activated,
            applicationName: text(statement, 2) ?? "",
            bundleIdentifier: text(statement, 3),
            appPath: appPath,
            startedAt: sqlite3_column_int64(statement, 4),
            endedAt: optionalInt(statement, 5),
            duration: Int(sqlite3_column_int64(statement, 6))
        )
    }

    /// Focus sessions and away stretches overlapping `[from, to)`.
    ///
    /// The `started_at` lower bound lets SQLite prune old rows by index rather than
    /// scan the table — the difference between O(total history) and O(window) once
    /// years accumulate. The buffer keeps a long away stretch that began before the
    /// window but reaches into it.
    ///
    /// Note this deliberately returns rows that *started before* `from`. Callers
    /// showing a single day must filter to runs that began that day; the Glaze app's
    /// day view had a bug here once, where a session crossing midnight appeared on
    /// both days.
    public func sessions(from: Int64, to: Int64) throws -> [ActivityEvent] {
        let buffer = Int64(60) * dayMillis
        return try query(
            """
            SELECT * FROM events
            WHERE type IN ('activated', 'idle')
              AND started_at >= ? AND started_at < ?
              AND (ended_at IS NULL OR ended_at > ?)
            ORDER BY started_at ASC
            """,
            [.int(from - buffer), .int(to), .int(from)],
            row: event(from:)
        )
    }

    public func countRows() throws -> Int {
        try query("SELECT COUNT(*) FROM events", row: { Int(sqlite3_column_int64($0, 0)) }).first ?? 0
    }

    /// Active seconds in a window: summed focus time, with the open session counted
    /// up to `now`. Idle rows are excluded, so this is time actually spent in apps.
    public func activeSeconds(from: Int64, to: Int64, now: Int64) throws -> Int {
        try query(
            """
            SELECT COALESCE(SUM(
              CASE WHEN ended_at IS NULL
                   THEN MAX(0, (? - started_at) / 1000.0)
                   ELSE duration END), 0)
            FROM events
            WHERE type = 'activated' AND started_at >= ? AND started_at < ?
            """,
            [.int(now), .int(from), .int(to)],
            row: { Int(sqlite3_column_double($0, 0).rounded()) }
        ).first ?? 0
    }

    // ── daily headlines ───────────────────────────────────────────────────────

    /// Whether any raw focus row is still stored for a day.
    private func hasRawEvents(dayStart: Int64) throws -> Bool {
        try query(
            """
            SELECT 1 FROM events
            WHERE type = 'activated' AND started_at >= ? AND started_at < ? LIMIT 1
            """,
            [.int(dayStart), .int(dayStart + dayMillis)],
            row: { _ in true }
        ).first ?? false
    }

    /// Write (or clear) a day's headline.
    ///
    /// A day with no rows behind it has no headline to write, and its row is removed.
    /// This is what keeps a deleted day deleted: without it, the next rollup walking
    /// over the gap would insert an all-zero summary and the day would reappear as an
    /// empty entry.
    public func upsertSummary(dayStart: Int64, now: Int64) throws {
        guard try hasRawEvents(dayStart: dayStart) else {
            try run("DELETE FROM daily_summaries WHERE day_start = ?", [.int(dayStart)])
            return
        }
        let dayEnd = dayStart + dayMillis
        let limit = Int64(Rules.idleStretchSeconds)

        let active = try query(
            """
            SELECT COALESCE(SUM(duration), 0) FROM events
            WHERE type = 'activated' AND duration < ? AND started_at >= ? AND started_at < ?
            """,
            [.int(limit), .int(dayStart), .int(dayEnd)],
            row: { Int(sqlite3_column_int64($0, 0)) }
        ).first ?? 0

        let top = try query(
            """
            SELECT application_name, bundle_identifier, SUM(duration) AS s FROM events
            WHERE type = 'activated' AND duration < ? AND started_at >= ? AND started_at < ?
            GROUP BY bundle_identifier ORDER BY s DESC LIMIT 1
            """,
            [.int(limit), .int(dayStart), .int(dayEnd)],
            row: { (self.text($0, 0), self.text($0, 1), Int(sqlite3_column_int64($0, 2))) }
        ).first

        try run(
            """
            INSERT INTO daily_summaries (day_start, active_seconds, top_bundle_id, top_app_name, top_seconds, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(day_start) DO UPDATE SET
              active_seconds = excluded.active_seconds,
              top_bundle_id = excluded.top_bundle_id,
              top_app_name = excluded.top_app_name,
              top_seconds = excluded.top_seconds,
              updated_at = excluded.updated_at
            """,
            [
                .int(dayStart), .int(Int64(active)),
                top?.1.map(Value.text) ?? .null,
                top?.0.map(Value.text) ?? .null,
                .int(Int64(top?.2 ?? 0)), .int(now),
            ]
        )
    }

    /// Roll up every complete day that isn't summarised yet.
    ///
    /// Incremental: it walks from the day after the newest summary, so a normal launch
    /// summarises at most the day that just ended. Today is never rolled up — it is
    /// still being written, and live views compute it directly.
    public func rollupCompleteDays(now: Int64) throws {
        let newest = try query(
            "SELECT MAX(day_start) FROM daily_summaries",
            row: { self.optionalInt($0, 0) }
        ).first ?? nil
        guard let firstEvent = try query(
            "SELECT MIN(started_at) FROM events WHERE type = 'activated'",
            row: { self.optionalInt($0, 0) }
        ).first ?? nil else { return }

        let todayStart = startOfLocalDay(now)
        var day = newest.map { $0 + dayMillis } ?? startOfLocalDay(firstEvent)
        while day < todayStart {
            try upsertSummary(dayStart: day, now: now)
            day += dayMillis
        }
    }

    /// Recompute the headlines the raw rows can still account for.
    ///
    /// Bounded to the range the surviving rows cover, rather than emptying the table
    /// and starting over. Anything older was pruned past the retention window, and for
    /// those days the headline is the *only* record left — rebuilding them from rows
    /// that no longer exist erases the day instead of restating it.
    public func rebuildSummaries(now: Int64) throws {
        guard let first = try query(
            "SELECT MIN(started_at) FROM events WHERE type = 'activated'",
            row: { self.optionalInt($0, 0) }
        ).first ?? nil else { return }

        let todayStart = startOfLocalDay(now)
        var day = startOfLocalDay(first)
        while day < todayStart {
            try upsertSummary(dayStart: day, now: now)
            day += dayMillis
        }
    }

    /// Recompute particular days, after rows inside them changed. Today is skipped.
    public func resummarize(days: [Int64], now: Int64) throws {
        let todayStart = startOfLocalDay(now)
        for day in days where day < todayStart {
            try upsertSummary(dayStart: day, now: now)
        }
    }

    public func dailySummaries(from: Int64, to: Int64) throws -> [DailySummary] {
        try query(
            """
            SELECT day_start, active_seconds, top_bundle_id, top_app_name, top_seconds
            FROM daily_summaries WHERE day_start >= ? AND day_start < ? ORDER BY day_start ASC
            """,
            [.int(from), .int(to)],
            row: {
                DailySummary(
                    dayStart: sqlite3_column_int64($0, 0),
                    activeSeconds: Int(sqlite3_column_int64($0, 1)),
                    topBundleID: self.text($0, 2),
                    topAppName: self.text($0, 3),
                    topSeconds: Int(sqlite3_column_int64($0, 4))
                )
            }
        )
    }

    // ── deleting ──────────────────────────────────────────────────────────────

    /// Erase one local day: its rows, its headline, and its reflection.
    ///
    /// Rows are matched on `started_at` — the same bucketing the headlines use — so a
    /// session that began before midnight belongs to the day it started in. Unlike a
    /// retention prune this keeps no headline behind: a day the user deleted should
    /// leave no trace, not a summary of what it used to be.
    @discardableResult
    public func deleteDay(dayStart: Int64) throws -> Int {
        try exec("BEGIN")
        do {
            let removed = try run(
                "DELETE FROM events WHERE started_at >= ? AND started_at < ?",
                [.int(dayStart), .int(dayStart + dayMillis)]
            )
            try run("DELETE FROM daily_summaries WHERE day_start = ?", [.int(dayStart)])
            try run("DELETE FROM reflections WHERE day_start = ?", [.int(dayStart)])
            try exec("COMMIT")
            return removed
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Erase specific rows by id — the events behind one session.
    ///
    /// Chunked because a busy session can be hundreds of switches and SQLite bounds
    /// parameters per statement; the chunks share a transaction, so the session is
    /// still deleted all-or-nothing. Returns the rows removed and the days they fell
    /// on, so their headlines can be restated.
    @discardableResult
    public func deleteEvents(ids: [Int64]) throws -> (removed: Int, dayStarts: [Int64]) {
        guard !ids.isEmpty else { return (0, []) }
        var days = Set<Int64>()
        var removed = 0

        try exec("BEGIN")
        do {
            for chunk in stride(from: 0, to: ids.count, by: Rules.deleteChunk).map({
                Array(ids[$0..<min($0 + Rules.deleteChunk, ids.count)])
            }) {
                let placeholders = chunk.map { _ in "?" }.joined(separator: ", ")
                let params = chunk.map(Value.int)
                for started in try query(
                    "SELECT started_at FROM events WHERE id IN (\(placeholders))",
                    params,
                    row: { sqlite3_column_int64($0, 0) }
                ) {
                    days.insert(startOfLocalDay(started))
                }
                removed += try run("DELETE FROM events WHERE id IN (\(placeholders))", params)
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
        return (removed, days.sorted())
    }

    /// Drop raw events older than `retentionDays`, having first ensured the days being
    /// dropped are summarised. `0` keeps everything and prunes nothing.
    @discardableResult
    public func pruneOldEvents(retentionDays: Int, now: Int64) throws -> Int {
        guard retentionDays > 0 else { return 0 }
        try rollupCompleteDays(now: now)
        let cutoff = startOfLocalDay(now) - Int64(retentionDays) * dayMillis
        return try run("DELETE FROM events WHERE started_at < ?", [.int(cutoff)])
    }

    /// Drop annotations that no longer describe anything.
    ///
    /// An annotation is keyed to its session's first event, so it is live exactly
    /// while some event still starts at that instant. Narrower than deleting by
    /// application on purpose: a session that merely *included* a deleted app keeps
    /// its first event, and therefore its identity and its note.
    @discardableResult
    public func pruneOrphanAnnotations() throws -> Int {
        try run("""
            DELETE FROM annotations
            WHERE NOT EXISTS (
              SELECT 1 FROM events
              WHERE events.type = 'activated' AND events.started_at = annotations.session_start
            )
            """)
    }

    // ── compaction ────────────────────────────────────────────────────────────

    private func pageStats() throws -> (free: Int, total: Int, pageSize: Int) {
        func pragma(_ name: String) throws -> Int {
            try query("PRAGMA \(name)", row: { Int(sqlite3_column_int64($0, 0)) }).first ?? 0
        }
        return (try pragma("freelist_count"), try pragma("page_count"), try pragma("page_size"))
    }

    /// Bytes a compaction would hand back right now.
    ///
    /// A **lower bound**, not the whole story: `VACUUM` also repacks partially-filled
    /// pages, which the freelist does not count — in testing it recovered 2% of a
    /// database whose freelist was zero. So never disable a compact action on this
    /// being zero; report it as "at least".
    public func reclaimableBytes() throws -> Int {
        let stats = try pageStats()
        return stats.free * stats.pageSize
    }

    /// SQLite's own structural check.
    ///
    /// A badly damaged file does not return a row saying so — it raises "database disk
    /// image is malformed" from the query itself. Both outcomes mean the same thing
    /// here, so the throw is caught rather than escaping and skipping a caller's
    /// recovery path.
    public func integrityCheck() -> (ok: Bool, detail: String) {
        do {
            let detail = try query("PRAGMA integrity_check", row: { self.text($0, 0) ?? "unknown" })
                .first ?? "unknown"
            return (detail == "ok", detail)
        } catch {
            return (false, "\(error)")
        }
    }

    /// Rewrite the database so freed pages return to the filesystem.
    ///
    /// Must run outside a transaction, and holds an exclusive lock for its duration —
    /// safe because every caller is a user-initiated bulk delete rather than anything
    /// on the tracking path.
    public func vacuum() throws { try exec("VACUUM") }

    /// Compact only when enough of the file is dead space to be worth rewriting it.
    @discardableResult
    public func compactIfWasteful() throws -> Bool {
        let stats = try pageStats()
        guard stats.total > 0 else { return false }
        guard stats.free >= Rules.compactMinFreePages,
              Double(stats.free) / Double(stats.total) >= Rules.compactMinFreeRatio
        else { return false }
        try vacuum()
        return true
    }
}

// SQLITE_TRANSIENT tells SQLite to copy the bound string, which it must here: the
// Swift string may not outlive the statement.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
