import Foundation
import ReplayCore

/// The parity checks, as data — so the same suite can run two ways.
///
/// `swift test` runs it through swift-testing, which needs Xcode. `swift run
/// replay-parity` runs it as a plain executable, which does not. Both call
/// ``ParityKit/runAllChecks(specRoot:)`` and get identical results, so there is no
/// second implementation to keep in step.
///
/// Everything is measured against `spec/`, generated from the Glaze app by
/// `tools/sync-spec.mjs`. See docs/SYNC.md.
public enum ParityKit {

    // ── the generated contract ────────────────────────────────────────────────

    public struct Fixture: Decodable, Sendable {
        public struct Event: Decodable, Sendable {
            public let id: Int64
            public let type: String
            public let applicationName: String
            public let bundleIdentifier: String?
            public let appPath: String?
            public let startedAt: Int64
            public let endedAt: Int64?
            public let duration: Int
        }
        public struct App: Decodable, Sendable {
            public let applicationName: String
            public let bundleIdentifier: String?
            public let seconds: Int
            public let switches: Int
            public let share: Double
        }
        public struct Item: Decodable, Sendable {
            public let kind: String
            public let title: String?
            public let category: String?
            public let spanSeconds: Int?
            public let activeSeconds: Int?
            public let switches: Int?
            public let eventIds: [Int64]?
            public let apps: [App]?
            public let reason: String?
            public let applicationName: String?
            public let startedAt: Int64
            public let endedAt: Int64
            public let seconds: Int?
        }
        /// What `computeDaySummary` produced for the same input — the figures Today
        /// leads with, so a drift here is visible on the first screen of the app.
        public struct Summary: Decodable, Sendable {
            public struct Focus: Decodable, Sendable {
                public let averageStretchSeconds: Int
                public let quality: String
            }
            public struct TopApp: Decodable, Sendable {
                public let applicationName: String
                public let seconds: Int
            }
            public let activeSeconds: Int
            public let activeLabel: String
            public let appsUsed: Int
            public let sessionCount: Int
            public let switches: Int
            public let focus: Focus?
            public let mostUsed: TopApp?
            public let longestSessionSeconds: Int?
        }
        public let name: String
        public let description: String
        public let now: Int64
        public let events: [Event]
        public let expected: [Item]
        public let summary: Summary
    }

    public struct Constants: Decodable, Sendable {
        public struct Tracker: Decodable, Sendable {
            public let awayAfterSeconds: Int
            public let idlePollMs: Int
            public let pointEventDedupeMs: Int
            public let ignoredBundleIds: [String]
        }
        public struct Store: Decodable, Sendable {
            public let idleStretchSeconds: Int
            public let compactMinFreeRatio: Double
            public let compactMinFreePages: Int
            public let deleteChunk: Int
        }
        public struct CategoryPattern: Decodable, Sendable {
            public let category: String
            public let pattern: String
        }
        public struct Derivation: Decodable, Sendable {
            public let idleBreakSeconds: Int
            public let recordingGapSeconds: Int
            public let minSessionSeconds: Int
            public let categoryPatterns: [CategoryPattern]
        }
        public struct BackupInfo: Decodable, Sendable {
            public let format: String
            public let version: Int
            public let acceptedEventTypes: [String]
        }
        public let glazeVersion: String
        public let glazeCommit: String
        public let tracker: Tracker
        public let store: Store
        public let derivation: Derivation
        public let backup: BackupInfo
    }

    // ── results ───────────────────────────────────────────────────────────────

    /// One assertion, with enough context to be actionable on its own — these are read
    /// in a terminal as often as in a test report.
    public struct Check: Sendable {
        public let group: String
        public let what: String
        public let passed: Bool
        public let detail: String?
    }

    public struct Report: Sendable {
        public let glazeVersion: String
        public let glazeCommit: String
        public let specRoot: String
        public let checks: [Check]
        /// Fixture name → whether every check for it passed, in spec order.
        public let fixtureResults: [(name: String, description: String, passed: Bool)]

        public var failures: [Check] { checks.filter { !$0.passed } }
        public var passed: Bool { failures.isEmpty }
    }

    // ── locating spec/ ────────────────────────────────────────────────────────

    /// `spec/` sits beside the package rather than in the build products, so it is found
    /// relative to this source file unless a path is given (for CI).
    public static func defaultSpecRoot(file: String = #filePath) -> URL {
        var root = URL(fileURLWithPath: file)
        for _ in 0..<3 { root.deleteLastPathComponent() }   // Sources/ParityKit/ParityKit.swift
        return root.appendingPathComponent("spec")
    }

    static func load<T: Decodable>(_ type: T.Type, _ relative: String, from root: URL) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent(relative)))
    }

    static func event(_ raw: Fixture.Event) -> ActivityEvent {
        ActivityEvent(
            id: raw.id,
            type: EventType(rawValue: raw.type) ?? .activated,
            applicationName: raw.applicationName,
            bundleIdentifier: raw.bundleIdentifier,
            appPath: raw.appPath,
            startedAt: raw.startedAt,
            endedAt: raw.endedAt,
            duration: raw.duration
        )
    }

    // ── the suite ─────────────────────────────────────────────────────────────

    public static func runAllChecks(specRoot: URL? = nil) throws -> Report {
        let root = specRoot ?? defaultSpecRoot()
        let constants = try load(Constants.self, "constants.json", from: root)

        var checks: [Check] = []
        func check(_ group: String, _ what: String, _ passed: Bool, _ detail: String? = nil) {
            checks.append(Check(group: group, what: what, passed: passed, detail: detail))
        }
        func equal<T: Equatable>(_ group: String, _ what: String, _ actual: T, _ expected: T) {
            checks.append(Check(
                group: group,
                what: what,
                passed: actual == expected,
                detail: actual == expected ? nil : "got \(actual), want \(expected)"
            ))
        }

        // constants — Rules in Model.swift is a second copy of these on purpose (the
        // shipping app should not parse JSON), so this is what keeps the copies equal.
        let g1 = "constants"
        equal(g1, "awayAfterSeconds", Rules.awayAfterSeconds, constants.tracker.awayAfterSeconds)
        equal(g1, "idlePollMs", Int(Rules.idlePollSeconds * 1000), constants.tracker.idlePollMs)
        equal(g1, "pointEventDedupeMs",
              Int(Rules.pointEventDedupeSeconds * 1000), constants.tracker.pointEventDedupeMs)
        equal(g1, "ignoredBundleIDs",
              Rules.ignoredBundleIDs.sorted(), constants.tracker.ignoredBundleIds.sorted())
        equal(g1, "idleStretchSeconds", Rules.idleStretchSeconds, constants.store.idleStretchSeconds)
        equal(g1, "compactMinFreeRatio", Rules.compactMinFreeRatio, constants.store.compactMinFreeRatio)
        equal(g1, "compactMinFreePages", Rules.compactMinFreePages, constants.store.compactMinFreePages)
        equal(g1, "deleteChunk", Rules.deleteChunk, constants.store.deleteChunk)
        equal(g1, "idleBreakSeconds", Rules.idleBreakSeconds, constants.derivation.idleBreakSeconds)
        equal(g1, "recordingGapSeconds",
              Rules.recordingGapSeconds, constants.derivation.recordingGapSeconds)
        equal(g1, "minSessionSeconds", Rules.minSessionSeconds, constants.derivation.minSessionSeconds)

        // the category table — order-sensitive, because first match wins and it names
        // the session.
        let g2 = "category table"
        for entry in constants.derivation.categoryPatterns {
            let probe = entry.pattern
                .split(separator: "|").first
                .map {
                    String($0)
                        .replacingOccurrences(of: "^", with: "")
                        .replacingOccurrences(of: "$", with: "")
                } ?? ""
            guard !probe.isEmpty else { continue }
            equal(g2, "categorizeApp(\"\(probe)\")", categorizeApp(probe).rawValue, entry.category)
        }

        // schema — a database written by either implementation must be readable by the
        // other, so this is compared statement for statement.
        let generatedSchema = try String(
            contentsOf: root.appendingPathComponent("schema.sql"),
            encoding: .utf8
        )
        func normalise(_ sql: String) -> String {
            sql.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("--") }
                .joined(separator: " ")
        }
        equal("schema", "ActivityStore.schema matches spec/schema.sql",
              normalise(ActivityStore.schemaForParityCheck), normalise(generatedSchema))

        // session derivation — against the output the Glaze code actually produced.
        struct Index: Decodable { let fixtures: [String] }
        let index = try load(Index.self, "fixtures/index.json", from: root)
        var fixtureResults: [(name: String, description: String, passed: Bool)] = []

        for name in index.fixtures {
            let fixture = try load(Fixture.self, "fixtures/\(name).json", from: root)
            let before = checks.count
            let produced = buildTimeline(fixture.events.map(event), now: fixture.now)
            let group = "derivation/\(name)"

            equal(group, "number of items", produced.count, fixture.expected.count)
            if produced.count == fixture.expected.count {
                for (offset, expected) in fixture.expected.enumerated() {
                    switch produced[offset] {
                    case .session(let session):
                        equal(group, "[\(offset)] kind", "session", expected.kind)
                        equal(group, "[\(offset)] title", session.title, expected.title ?? "")
                        equal(group, "[\(offset)] category",
                              session.category.rawValue, expected.category ?? "")
                        equal(group, "[\(offset)] startedAt", session.startedAt, expected.startedAt)
                        equal(group, "[\(offset)] endedAt", session.endedAt, expected.endedAt)
                        equal(group, "[\(offset)] spanSeconds",
                              session.spanSeconds, expected.spanSeconds ?? -1)
                        equal(group, "[\(offset)] activeSeconds",
                              session.activeSeconds, expected.activeSeconds ?? -1)
                        equal(group, "[\(offset)] switches", session.switches, expected.switches ?? -1)
                        equal(group, "[\(offset)] rows the session is made of",
                              session.events.map(\.id), expected.eventIds ?? [])
                        equal(group, "[\(offset)] app order",
                              session.apps.map(\.applicationName),
                              (expected.apps ?? []).map(\.applicationName))
                        for (app, expectedApp) in zip(session.apps, expected.apps ?? []) {
                            equal(group, "\(app.applicationName) seconds",
                                  app.seconds, expectedApp.seconds)
                            equal(group, "\(app.applicationName) switches",
                                  app.switches, expectedApp.switches)
                            check(group, "\(app.applicationName) share",
                                  abs(app.share - expectedApp.share) < 0.000_01,
                                  "got \(app.share), want \(expectedApp.share)")
                        }

                    case .breakItem(let gap):
                        equal(group, "[\(offset)] kind", "break", expected.kind)
                        equal(group, "[\(offset)] reason", gap.reason.rawValue, expected.reason ?? "")
                        equal(group, "[\(offset)] startedAt", gap.startedAt, expected.startedAt)
                        equal(group, "[\(offset)] endedAt", gap.endedAt, expected.endedAt)
                        equal(group, "[\(offset)] seconds", gap.seconds, expected.seconds ?? -1)
                        equal(group, "[\(offset)] applicationName",
                              gap.applicationName, expected.applicationName)
                    }
                }
            }
            // The day's headline, from the same rows.
            let events = fixture.events.map(event)
            let summary = computeDaySummary(
                events: events, timeline: produced,
                dayStart: startOfLocalDay(fixture.events.first?.startedAt ?? fixture.now),
                now: fixture.now
            )
            let sg = "summary/\(name)"
            equal(sg, "activeSeconds", summary.activeSeconds, fixture.summary.activeSeconds)
            equal(sg, "activeLabel", formatDurationShort(summary.activeSeconds), fixture.summary.activeLabel)
            equal(sg, "appsUsed", summary.appsUsed, fixture.summary.appsUsed)
            equal(sg, "sessionCount", summary.sessionCount, fixture.summary.sessionCount)
            equal(sg, "switches", summary.switches, fixture.summary.switches)
            equal(sg, "focus stretch", summary.focus?.averageStretchSeconds,
                  fixture.summary.focus?.averageStretchSeconds)
            equal(sg, "focus quality", summary.focus?.quality.rawValue, fixture.summary.focus?.quality)
            equal(sg, "top app", summary.mostUsed?.applicationName, fixture.summary.mostUsed?.applicationName)
            equal(sg, "top app seconds", summary.mostUsed?.seconds, fixture.summary.mostUsed?.seconds)
            equal(sg, "longest session", summary.longestSession?.activeSeconds,
                  fixture.summary.longestSessionSeconds)

            let stillPassing = checks[before...].allSatisfy(\.passed)
            fixtureResults.append((name, fixture.description, stillPassing))
        }

        // the store, end to end against a real SQLite file.
        let group = "store round-trip"
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-parity-\(UUID().uuidString).db")
        let store = ActivityStore(path: tmp.path)
        try store.open()
        let t0 = Int64(1_770_000_000_000)
        let id = try store.openSession(
            name: "Code", bundleID: "com.microsoft.VSCode", appPath: nil, startedAt: t0
        )
        try store.closeSession(id: id, endedAt: t0 + 600_000)
        try store.recordAway(startedAt: t0 + 600_000, endedAt: t0 + 1_200_000)
        equal(group, "two rows written", try store.countRows(), 2)
        let read = try store.sessions(
            from: startOfLocalDay(t0), to: startOfLocalDay(t0) + dayMillis
        )
        equal(group, "both rows read back", read.count, 2)
        equal(group, "duration computed by SQL, in seconds", read.first?.duration, 600)
        equal(group, "a fresh database has nothing to reclaim", try store.reclaimableBytes(), 0)
        check(group, "integrity check passes", store.integrityCheck().ok)
        let deleted = try store.deleteEvents(ids: [id])
        equal(group, "delete by id removes one row", deleted.removed, 1)
        equal(group, "and reports the day it fell on", deleted.dayStarts, [startOfLocalDay(t0)])
        store.close()
        try? FileManager.default.removeItem(at: tmp)

        // backup format — the migration path off the Glaze app, so a mismatch here means
        // a user's exported history cannot be read.
        let g4 = "backup"
        equal(g4, "format string", Backup.format, constants.backup.format)
        equal(g4, "format version", Backup.version, constants.backup.version)
        equal(g4, "accepted row types",
              Backup.acceptedTypes.map(\.rawValue).sorted(),
              constants.backup.acceptedEventTypes.sorted())
        check(g4, "accepts idle rows — dropping them relabels away time as not-recorded",
              Backup.acceptedTypes.contains(.idle))

        // A backup written in the documented shape, read back, and imported twice: the
        // second import must be a no-op, which is what makes the operation safe to repeat.
        let backupURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-parity-backup-\(UUID().uuidString).json")
        let t1 = Int64(1_770_000_000_000)
        let backupJSON = """
            {
              "format": "\(Backup.format)",
              "version": \(Backup.version),
              "exportedAt": "2026-07-26T12:00:00.000Z",
              "appVersion": "\(constants.glazeVersion)",
              "eventCount": 4,
              "events": [
                {"type":"activated","application_name":"Code","bundle_identifier":"com.microsoft.VSCode",
                 "started_at":\(t1),"ended_at":\(t1 + 600_000),"duration":600,"metadata":null},
                {"type":"idle","application_name":"Away","bundle_identifier":null,
                 "started_at":\(t1 + 600_000),"ended_at":\(t1 + 1_200_000),"duration":600,"metadata":null},
                {"type":"activated","application_name":"Safari","bundle_identifier":"com.apple.Safari",
                 "started_at":\(t1 + 1_200_000),"ended_at":\(t1 + 1_500_000),"duration":300,"metadata":null},
                {"type":"nonsense","application_name":"","started_at":"not a number"}
              ]
            }
            """
        try backupJSON.write(to: backupURL, atomically: true, encoding: .utf8)

        let restoreDB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-parity-restore-\(UUID().uuidString).db")
        let restoreStore = ActivityStore(path: restoreDB.path)
        try restoreStore.open()

        let parsed = try Backup.read(contentsOf: backupURL)
        equal(g4, "reads the valid rows", parsed.rows.count, 3)
        equal(g4, "drops the malformed row", parsed.skipped, 1)
        check(g4, "keeps the away row", parsed.rows.contains { $0.type == .idle })

        let first = try restoreStore.importBackup(from: backupURL, now: t1 + 2_000_000)
        equal(g4, "first import restores every valid row", first.imported, 3)
        equal(g4, "and stores them", try restoreStore.countRows(), 3)
        let second = try restoreStore.importBackup(from: backupURL, now: t1 + 2_000_000)
        equal(g4, "importing the same file again imports nothing", second.imported, 0)
        equal(g4, "skipping them instead", second.skipped, 3)
        equal(g4, "so the row count is unchanged", try restoreStore.countRows(), 3)

        do {
            _ = try Backup.read(Data(#"{"format":"something.else","events":[]}"#.utf8))
            check(g4, "a foreign format is refused", false, "it was accepted")
        } catch {
            check(g4, "a foreign format is refused", true)
        }

        restoreStore.close()
        try? FileManager.default.removeItem(at: restoreDB)
        try? FileManager.default.removeItem(at: backupURL)

        return Report(
            glazeVersion: constants.glazeVersion,
            glazeCommit: constants.glazeCommit,
            specRoot: root.path,
            checks: checks,
            fixtureResults: fixtureResults
        )
    }
}
