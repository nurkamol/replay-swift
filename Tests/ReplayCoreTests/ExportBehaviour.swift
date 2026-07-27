@testable import ReplayCore
import Foundation
import Testing

/// What leaves the app, and whether it can come back.
///
/// The report serialisers are already compared as text against the reference's own output.
/// This covers the thing text comparison cannot: whether an export *contains* the history it
/// claims to. That distinction is not academic — this port shipped a backup writer that
/// emitted camelCase keys where the reader expected column names, so every row failed a
/// lenient guard and the file parsed as a **valid, empty backup**. It looked fine. It was
/// caught by a round trip, and only by a round trip.
@Suite("Export behaviour")
struct ExportBehaviour {
    private static func makeStore() throws -> (ActivityStore, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-export-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ActivityStore(path: directory.appendingPathComponent("activity.db").path)
        try store.open()
        return (store, directory)
    }

    private static let day: Int64 = 1_770_076_800_000
    private static let hour: Int64 = 3_600_000

    @discardableResult
    private static func record(
        _ store: ActivityStore, _ name: String, _ bundleID: String, from: Int64, seconds: Int
    ) throws -> Int64 {
        let id = try store.openSession(
            name: name, bundleID: bundleID, appPath: nil, startedAt: from
        )
        try store.closeSession(id: id, endedAt: from + Int64(seconds) * 1000)
        return id
    }

    /// A day with two sessions, a note, a tag, a bookmark and a reflection on it.
    private static func seed(_ store: ActivityStore) throws {
        try record(store, "Code", "com.microsoft.VSCode", from: day + 9 * hour, seconds: 900)
        try record(store, "Terminal", "com.apple.Terminal", from: day + 9 * hour + 900_000, seconds: 300)
        try record(store, "Safari", "com.apple.Safari", from: day + 14 * hour, seconds: 600)
        try record(store, "Mail", "com.apple.mail", from: day + 14 * hour + 600_000, seconds: 300)
        _ = try store.setNote(sessionStart: day + 9 * hour, note: "the migration spike", now: day)
        _ = try store.setTags(sessionStart: day + 9 * hour, tags: ["deep-work"], now: day)
        _ = try store.setBookmarked(sessionStart: day + 14 * hour, bookmarked: true, now: day)
        _ = try store.setReflection(dayStart: day, text: "A day worth keeping.", now: day)
        try store.upsertSummary(dayStart: day, now: day + 20 * hour)
    }

    // ── the backup, which has to come back ────────────────────────────────────

    @Test("A backup carries every row, and reads back as the same history")
    func backupRoundTrips() throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.seed(store)

        let rows = try store.rowsForBackup()
        let encoded = Backup.encode(rows: rows, appVersion: "test")

        // The guard that matters. A backup that parses cleanly and holds nothing is the
        // exact failure this port already shipped once; counting the rows is what tells the
        // two apart, and reading without counting is what missed it.
        let parsed = try Backup.read(encoded)
        #expect(parsed.rows.count == rows.count, "every row is in the file")
        #expect(!parsed.rows.isEmpty, "and the file is not merely well-formed")
        #expect(parsed.skipped == 0, "nothing was rejected as malformed")

        // And into a fresh database, which is what a restore actually is.
        let (restored, restoredDirectory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: restoredDirectory) }
        let outcome = try restored.restore(rows: parsed.rows)
        #expect(outcome.imported == rows.count)

        // The sessions come back.
        let events = try restored.sessions(from: Self.day, to: Self.day + dayMillis)
        #expect(events.count == 4)
        #expect(Set(events.map(\.applicationName)) == ["Code", "Terminal", "Safari", "Mail"])

        // And what does *not* come back, asserted deliberately rather than left as a
        // surprise: a backup carries the `events` table and nothing else. Notes, tags,
        // bookmarks and reflections are not in the file, so restoring onto a clean Mac
        // returns the activity and loses everything written about it.
        //
        // Inherited rather than introduced — the reference's export is the same shape, and
        // the two files are meant to be interchangeable. Pinned here so the limitation is a
        // recorded fact rather than something a user discovers after wiping a machine.
        #expect(
            try restored.annotations(from: 0, to: 4_000_000_000_000).isEmpty,
            "a backup does not carry annotations — see the ledger"
        )
        #expect(try restored.reflection(dayStart: Self.day).text.isEmpty)
        #expect(try restored.dailySummaries(from: Self.day, to: Self.day + dayMillis).isEmpty)
    }

    @Test("Importing the same backup twice does not double the history")
    func restoreMerges() throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.seed(store)

        let encoded = Backup.encode(rows: try store.rowsForBackup(), appVersion: "test")
        let parsed = try Backup.read(encoded)
        let before = try store.countRows()

        // Restoring into the database it came from: importing merges rather than
        // overwriting, so the honest outcome is that nothing changes at all.
        let outcome = try store.restore(rows: parsed.rows)
        #expect(try store.countRows() == before, "an import is a merge, not an append")
        #expect(outcome.skipped > 0, "and the rows it already had are skipped, not added")
    }

    // ── the reports, which have to hold the day ───────────────────────────────

    @Test("Every format carries the sessions the scope selected")
    func reportsCarryTheirSessions() throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.seed(store)

        let now = Self.day + 20 * Self.hour
        let events = try store.sessions(from: Self.day, to: Self.day + dayMillis)
        let sessions = Report.sessions(in: events, now: now)
        #expect(sessions.count == 2, "the seeded day derives as two runs")

        let entries = sessions.map { Report.Entry(session: $0, annotation: nil) }
        for format in Report.Format.allCases {
            let text = Report.build(
                format, label: "Today", entries: entries,
                now: Date(timeIntervalSince1970: Double(now) / 1000)
            )
            #expect(!text.isEmpty, "\(format) produced nothing")
            // The point: a serialiser that emits a well-formed but empty document is the
            // same failure shape as the backup bug. Every session's title has to appear.
            for session in sessions {
                #expect(
                    text.contains(session.title),
                    "\(format) lost the session '\(session.title)'"
                )
            }
        }
    }

    @Test("A note and a tag reach the export that carries them")
    func reportsCarryAnnotations() throws {
        let (store, directory) = try Self.makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.seed(store)

        let now = Self.day + 20 * Self.hour
        let events = try store.sessions(from: Self.day, to: Self.day + dayMillis)
        let sessions = Report.sessions(in: events, now: now)
        let annotations = try store.annotations(from: Self.day, to: Self.day + dayMillis)
        let entries = sessions.map { session in
            Report.Entry(
                session: session,
                annotation: annotations.first { $0.sessionStart == session.startedAt }
            )
        }

        // Markdown and JSON both carry them; CSV is a table of sessions and does not
        // pretend to. Asserting per-format rather than in general, so this says what is
        // actually true rather than what would be tidy.
        for format in [Report.Format.markdown, .json] {
            let text = Report.build(
                format, label: "Today", entries: entries,
                now: Date(timeIntervalSince1970: Double(now) / 1000)
            )
            #expect(text.contains("the migration spike"), "\(format) dropped the note")
            #expect(text.contains("deep-work"), "\(format) dropped the tag")
        }
    }

    @Test("An empty scope exports an empty report rather than failing")
    func emptyScopeIsHonest() throws {
        let now = Self.day + 20 * Self.hour
        for format in Report.Format.allCases {
            let text = Report.build(
                format, label: "Today", entries: [],
                now: Date(timeIntervalSince1970: Double(now) / 1000)
            )
            // Something has to come out — a file that says there was nothing is a fact, and
            // an error would be a lie about a day that genuinely held nothing.
            #expect(!text.isEmpty, "\(format) produced nothing at all for an empty day")
        }
    }
}
