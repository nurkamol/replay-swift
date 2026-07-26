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
        /// The timezone the fixture was generated under. Session titles are named after
        /// the *local* day part, so deriving in any other zone renames them.
        public let timeZone: String
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
        public struct Annotations: Decodable, Sendable {
            public let maxTagLength: Int
            public let maxTags: Int
        }
        public struct FocusGoal: Decodable, Sendable {
            public let presetMinutes: [Int]
            public let minCustomMinutes: Int
            public let maxCustomMinutes: Int
        }
        public let glazeVersion: String
        public let glazeCommit: String
        public let tracker: Tracker
        public let store: Store
        public let derivation: Derivation
        public let backup: BackupInfo
        public let annotations: Annotations
        public let focusGoal: FocusGoal
    }

    /// Day grouping and report text, run against the real Glaze code under a pinned clock,
    /// timezone and locale. See `spec/grouping-and-export.json`.
    public struct GroupingAndExport: Decodable, Sendable {
        public struct Group: Decodable, Sendable {
            public let dayStart: Int64
            public let eventIds: [Int64]
        }
        public struct Grouping: Decodable, Sendable {
            public let events: [Fixture.Event]
            public let expected: [Group]
        }
        public struct Annotation: Decodable, Sendable {
            public let sessionStart: Int64
            public let note: String
            public let bookmarked: Bool
            public let tags: [String]
        }
        public struct Reports: Decodable, Sendable {
            public let markdown: String
            public let csv: String
            public let json: String
        }
        public struct ReportCase: Decodable, Sendable {
            public let label: String
            public let now: Int64
            public let events: [Fixture.Event]
            public let annotations: [Annotation]
            public let expected: Reports
        }
        public struct Stories: Decodable, Sendable {
            public struct Case: Decodable, Sendable {
                public let name: String
                public let now: Int64
                public let events: [Fixture.Event]
            }
            public struct Expected: Decodable, Sendable {
                public let name: String
                public let sessionCount: Int
                public let sentences: [String]
            }
            public let cases: [Case]
            public let expected: [Expected]
        }
        public struct CollectionsCase: Decodable, Sendable {
            public struct Definition: Decodable, Sendable {
                public let category: String
                public let label: String
            }
            public struct App: Decodable, Sendable {
                public let applicationName: String
                public let seconds: Int
            }
            public struct Expected: Decodable, Sendable {
                public let category: String
                public let label: String
                public let sessionCount: Int
                public let totalSeconds: Int
                public let apps: [App]
            }
            public let events: [Fixture.Event]
            public let now: Int64
            public let definitions: [Definition]
            public let sessionCount: Int
            public let expected: [Expected]
        }
        public struct HistoryCase: Decodable, Sendable {
            public struct Target: Decodable, Sendable {
                public let key: String
                public let label: String
                public let dayStart: Int64
            }
            public struct Found: Decodable, Sendable {
                public let key: String
                public let dayStart: Int64
                public let activeSeconds: Int
            }
            public let now: Int64
            public let targets: [Target]
            public let found: [Found]
        }
        public struct History: Decodable, Sendable {
            public struct Summary: Decodable, Sendable {
                public let dayStart: Int64
                public let activeSeconds: Int
                public let topAppName: String?
            }
            public let summaries: [Summary]
            public let cases: [HistoryCase]
        }
        public struct SearchCase: Decodable, Sendable {
            public struct Result: Decodable, Sendable {
                public let matches: [Int64]
                public let usesApp: [Int64]
            }
            public let queries: [String]
            public let expected: [String: Result]
        }
        public struct Scopes: Decodable, Sendable {
            public let events: [Fixture.Event]
            public let now: Int64
            public let todayStart: Int64
            public let annotations: [Annotation]
            /// Every scope the reference offers, so one added upstream shows up as a key
            /// this port does not handle rather than as silence.
            public let offered: [String]
            public let allSessionStarts: [Int64]
            public let expected: [String: [Int64]]
        }
        public let timeZone: String
        public let locale: String
        public let exportedAtMillis: Int64
        public let grouping: Grouping
        public let report: ReportCase
        public let search: SearchCase
        public let history: History
        public let collections: CollectionsCase
        public let stories: Stories
        public let scopes: Scopes
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
        equal(g1, "maxTagLength", Rules.maxTagLength, constants.annotations.maxTagLength)
        equal(g1, "maxTags", Rules.maxTags, constants.annotations.maxTags)
        equal(g1, "focus goal presets", Goals.presetMinutes, constants.focusGoal.presetMinutes)
        equal(g1, "minCustomGoalMinutes", Goals.minCustomMinutes, constants.focusGoal.minCustomMinutes)
        equal(g1, "maxCustomGoalMinutes", Goals.maxCustomMinutes, constants.focusGoal.maxCustomMinutes)

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
            // Derived in the timezone the fixture was generated under, not the machine's.
            // Session titles are named after the local day part, so without this the suite
            // passes here and fails in CI — the fixture would be recording where it was made.
            var fixtureCalendar = Calendar(identifier: .gregorian)
            fixtureCalendar.timeZone = TimeZone(identifier: fixture.timeZone) ?? .gmt
            let produced = buildTimeline(
                fixture.events.map(event), now: fixture.now, calendar: fixtureCalendar
            )
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
        // annotations, against the same file. These have no generated fixture — the sync
        // tool emits the two caps and the schema, not scenarios — so what is checked is the
        // behaviour the reference's `AnnotationsStore` documents in prose: keyed by session
        // start, merged on write, and deleted rather than kept blank.
        let ag = "annotations"
        let sessionStart = t0
        equal(ag, "an unannotated session reads back empty",
              try store.annotation(sessionStart: sessionStart), SessionAnnotation(sessionStart: sessionStart))

        _ = try store.setNote(sessionStart: sessionStart, note: "shipped the timeline", now: t0)
        _ = try store.setBookmarked(sessionStart: sessionStart, bookmarked: true, now: t0)
        // Normalisation is the part a port gets wrong: case, a leading #, blanks, and
        // duplicates all have to collapse, or one tag becomes two.
        _ = try store.setTags(
            sessionStart: sessionStart,
            tags: ["#Deep Work", "deep work", "  ", "Shipping", String(repeating: "x", count: 40)],
            now: t0
        )
        let stored = try store.annotation(sessionStart: sessionStart)
        equal(ag, "the note survives", stored.note, "shipped the timeline")
        equal(ag, "the bookmark survives a later write", stored.bookmarked, true)
        equal(ag, "tags normalise, dedupe and drop blanks",
              stored.tags, ["deep work", "shipping", String(repeating: "x", count: Rules.maxTagLength)])
        equal(ag, "a tag is capped at maxTagLength", stored.tags.last?.count, Rules.maxTagLength)
        equal(ag, "tags are capped at maxTags",
              try store.setTags(
                  sessionStart: sessionStart,
                  tags: (0..<(Rules.maxTags + 5)).map { "tag\($0)" },
                  now: t0
              ).tags.count,
              Rules.maxTags)

        equal(ag, "a range query finds it",
              try store.annotations(from: sessionStart, to: sessionStart + 1).count, 1)
        equal(ag, "a range that excludes its start does not",
              try store.annotations(from: sessionStart + 1, to: sessionStart + 2).count, 0)
        equal(ag, "bookmarks are listed", try store.bookmarkedAnnotations().count, 1)
        equal(ag, "allTags reports what is in use", try store.allTags().count, Rules.maxTags)

        // Cleared back to empty, the row goes rather than lingering as a blank.
        _ = try store.setBookmarked(sessionStart: sessionStart, bookmarked: false, now: t0)
        _ = try store.setTags(sessionStart: sessionStart, tags: [], now: t0)
        let emptied = try store.setNote(sessionStart: sessionStart, note: "   ", now: t0)
        equal(ag, "an emptied annotation reports no updatedAt", emptied.updatedAt, 0)
        equal(ag, "and leaves no row behind",
              try store.annotations(from: sessionStart, to: sessionStart + 1).count, 0)

        // Orphan pruning is by reachability: an annotation is live exactly while some
        // event still starts at that instant.
        _ = try store.setBookmarked(sessionStart: sessionStart, bookmarked: true, now: t0)
        equal(ag, "an annotation on a live session is kept", try store.pruneOrphanAnnotations(), 0)
        _ = try store.setBookmarked(sessionStart: t0 - 1, bookmarked: true, now: t0)
        equal(ag, "one pointing at no event is pruned", try store.pruneOrphanAnnotations(), 1)

        let deleted = try store.deleteEvents(ids: [id])
        equal(group, "delete by id removes one row", deleted.removed, 1)
        equal(group, "and reports the day it fell on", deleted.dayStarts, [startOfLocalDay(t0)])
        equal(ag, "deleting the session orphans its annotation",
              try store.pruneOrphanAnnotations(), 1)

        // maintenance — the operations Settings runs. The compaction sequence is SPEC §7,
        // where the order *is* the safety: copy, vacuum, verify by integrity check **and**
        // row count, and only then remove the copy.
        let mg = "maintenance"
        let excludable = try store.openSession(
            name: "Sublime Text", bundleID: "com.sublimetext.4", appPath: nil, startedAt: t0
        )
        try store.closeSession(id: excludable, endedAt: t0 + 60_000)
        equal(mg, "known apps are read from the events themselves",
              try store.listKnownApps().map(\.bundleIdentifier), ["com.sublimetext.4"])

        let rowsBefore = try store.countRows()
        let copyPath = URL(fileURLWithPath: tmp.path).deletingLastPathComponent()
            .appendingPathComponent("activity-before-compaction.db").path
        let compaction = try store.compactSafely()
        equal(mg, "compaction verifies the row count survived", compaction.rows, rowsBefore)
        check(mg, "it reports no surviving copy when it verified", compaction.backupPath == nil)
        check(mg, "and the copy it took is gone from disk",
              !FileManager.default.fileExists(atPath: copyPath))
        check(mg, "the database still passes its integrity check", store.integrityCheck().ok)
        equal(mg, "and still holds every row", try store.countRows(), rowsBefore)

        // Excluding an app erases what it recorded — past as well as future.
        equal(mg, "excluding nothing deletes nothing", try store.deleteByBundleIDs([]), 0)
        equal(mg, "excluding an app deletes its rows",
              try store.deleteByBundleIDs(["com.sublimetext.4"]), 1)
        equal(mg, "and leaves the rest alone", try store.countRows(), rowsBefore - 1)

        // reflections — the same empty-row rule annotations follow.
        let rg = "reflections"
        let day = startOfLocalDay(t0)
        equal(rg, "a day with nothing written reads back empty",
              try store.reflection(dayStart: day), Reflection(dayStart: day))
        _ = try store.setReflection(dayStart: day, text: "  a good day  ", now: t0)
        let written = try store.reflection(dayStart: day)
        equal(rg, "the text is stored as written, not trimmed", written.text, "  a good day  ")
        equal(rg, "and carries when it was written", written.updatedAt, t0)
        equal(rg, "a range finds it", try store.reflections(from: day, to: day + dayMillis).count, 1)
        _ = try store.setReflection(dayStart: day, text: "   ", now: t0)
        equal(rg, "cleared back to blank, it leaves no row",
              try store.reflections(from: day, to: day + dayMillis).count, 0)

        /// Compare multi-line text and, on a mismatch, name the first line that differs.
        ///
        /// A whole report echoed into a terminal is not a diagnosis; the line number and the
        /// two versions of that one line are.
        func equalText(_ group: String, _ what: String, _ actual: String, _ expected: String) {
            if actual == expected {
                checks.append(Check(group: group, what: what, passed: true, detail: nil))
                return
            }
            let ours = actual.components(separatedBy: "\n")
            let theirs = expected.components(separatedBy: "\n")
            var detail = "differs in length only (\(ours.count) lines vs \(theirs.count))"
            for index in 0..<max(ours.count, theirs.count) {
                let a = index < ours.count ? ours[index] : "<no line>"
                let b = index < theirs.count ? theirs[index] : "<no line>"
                if a != b {
                    detail = "line \(index + 1):\n        ours: \(a)\n        spec: \(b)"
                    break
                }
            }
            checks.append(Check(group: group, what: what, passed: false, detail: detail))
        }

        /// Fold the non-breaking space variants onto a plain space.
        ///
        /// Foundation and Node bundle different ICU versions, and the newer one separates a
        /// time from its meridiem with a narrow no-break space (U+202F) where the older uses
        /// U+0020 — so "2:40:00 AM" and "2:40:00 AM" differ by a byte neither implementation
        /// chose. Pinning that byte would make the suite fail on an OS or Node upgrade for a
        /// reason no reader of the file could see. Only the space class is folded; every
        /// other character still has to match exactly.
        func withPlainSpaces(_ text: String) -> String {
            text
                .replacingOccurrences(of: "\u{202F}", with: " ")
                .replacingOccurrences(of: "\u{00A0}", with: " ")
        }

        // Day grouping and report text, against output the reference actually produced.
        // Both used to be "verified by reading the reference", which is the weakest kind of
        // verification here — these replace it.
        let fixture = try load(GroupingAndExport.self, "grouping-and-export.json", from: root)
        let environment = ReplayCore.Report.Environment(
            locale: Locale(identifier: fixture.locale),
            timeZone: TimeZone(identifier: fixture.timeZone) ?? .gmt
        )
        // Grouping buckets by *local* midnight, so it is checked in the timezone the
        // fixture was generated under — otherwise this measures the machine, not the code.
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = environment.timeZone
            return calendar
        }()

        let dg = "day grouping"
        let grouped = groupByDay(fixture.grouping.events.map(event), calendar: calendar)
        equal(dg, "the same days, newest first",
              grouped.map(\.dayStart), fixture.grouping.expected.map(\.dayStart))
        equal(dg, "with the same rows in each, oldest first within a day",
              grouped.map { $0.events.map(\.id) }, fixture.grouping.expected.map(\.eventIds))
        check(dg, "a run before midnight lands on the day it began, not the day it reached",
              grouped.last?.events.map(\.id) == [1])

        let rg2 = "report text"
        let reportSessions = buildTimeline(
            fixture.report.events.map(event), now: fixture.report.now, calendar: calendar
        )
            .compactMap { if case .session(let s) = $0 { return s } else { return nil } }
        equal(rg2, "the fixture's sessions derive the same here",
              reportSessions.count, fixture.report.annotations.isEmpty ? 0 : 2)
        let reportEntries = reportSessions.enumerated().map { index, session in
            ReplayCore.Report.Entry(
                session: session,
                annotation: index < fixture.report.annotations.count
                    ? SessionAnnotation(
                        sessionStart: fixture.report.annotations[index].sessionStart,
                        note: fixture.report.annotations[index].note,
                        bookmarked: fixture.report.annotations[index].bookmarked,
                        tags: fixture.report.annotations[index].tags
                    )
                    : nil
            )
        }
        let exportedAt = Date(timeIntervalSince1970: Double(fixture.exportedAtMillis) / 1000)

        // Markdown and CSV are compared as text, because the text *is* the artefact: a
        // report is a file someone keeps, and a stray meridiem or a missing quote is a
        // difference they would see.
        equalText(rg2, "markdown matches the reference, character for character",
              withPlainSpaces(ReplayCore.Report.build(
                  .markdown, label: fixture.report.label, entries: reportEntries,
                  now: exportedAt, environment: environment
              )),
              withPlainSpaces(fixture.report.expected.markdown))
        equalText(rg2, "csv matches the reference, character for character",
              withPlainSpaces(ReplayCore.Report.build(
                  .csv, label: fixture.report.label, entries: reportEntries,
                  now: exportedAt, environment: environment
              )),
              withPlainSpaces(fixture.report.expected.csv))

        // JSON is compared as structure: both sides pretty-print, but key order is not part
        // of the format and pinning it would fail for a reason no consumer would care about.
        let ours = try? JSONSerialization.jsonObject(
            with: Data(ReplayCore.Report.build(
                .json, label: fixture.report.label, entries: reportEntries,
                now: exportedAt, environment: environment
            ).utf8)
        ) as? [String: Any]
        let theirs = try? JSONSerialization.jsonObject(
            with: Data(fixture.report.expected.json.utf8)
        ) as? [String: Any]
        check(rg2, "json parses on both sides", ours != nil && theirs != nil)
        if let ours, let theirs {
            equal(rg2, "the same keys", ours.keys.sorted(), theirs.keys.sorted())
            equal(rg2, "the same exported-at, milliseconds included",
                  ours["exportedAt"] as? String, theirs["exportedAt"] as? String)
            equal(rg2, "the same scope", ours["scope"] as? String, theirs["scope"] as? String)
            equal(rg2, "the same session count",
                  ours["sessionCount"] as? Int, theirs["sessionCount"] as? Int)
            let oursSessions = (ours["sessions"] as? [[String: Any]]) ?? []
            let theirsSessions = (theirs["sessions"] as? [[String: Any]]) ?? []
            equal(rg2, "the same number of sessions serialised",
                  oursSessions.count, theirsSessions.count)
            for (index, theirSession) in theirsSessions.enumerated() {
                guard index < oursSessions.count else { break }
                let ourSession = oursSessions[index]
                equal(rg2, "session \(index) keys",
                      ourSession.keys.sorted(), theirSession.keys.sorted())
                for key in ["title", "startedAt", "endedAt", "category", "note"] {
                    equal(rg2, "session \(index) \(key)",
                          ourSession[key] as? String, theirSession[key] as? String)
                }
                equal(rg2, "session \(index) activeSeconds",
                      ourSession["activeSeconds"] as? Int, theirSession["activeSeconds"] as? Int)
                equal(rg2, "session \(index) bookmarked",
                      ourSession["bookmarked"] as? Bool, theirSession["bookmarked"] as? Bool)
                equal(rg2, "session \(index) tags",
                      ourSession["tags"] as? [String], theirSession["tags"] as? [String])
            }
        }

        // Export scopes — which sessions a report covers.
        let sg = "export scopes"
        equal(sg, "the port offers every scope the reference does",
              ReplayCore.Report.Scope.allCases.map(\.rawValue).sorted(),
              fixture.scopes.offered.sorted())

        let scopeSessions = ReplayCore.Report.sessions(
            in: fixture.scopes.events.map(event), now: fixture.scopes.now, calendar: calendar
        )
        equal(sg, "the same sessions derive from a month of events",
              scopeSessions.map(\.startedAt), fixture.scopes.allSessionStarts)

        var scopeAnnotations: [Int64: SessionAnnotation] = [:]
        for annotation in fixture.scopes.annotations {
            scopeAnnotations[annotation.sessionStart] = SessionAnnotation(
                sessionStart: annotation.sessionStart,
                note: annotation.note,
                bookmarked: annotation.bookmarked,
                tags: annotation.tags
            )
        }

        for scope in ReplayCore.Report.Scope.allCases {
            guard let expected = fixture.scopes.expected[scope.rawValue] else {
                check(sg, "\(scope.rawValue) is covered by the fixture", false, "no expectation recorded")
                continue
            }
            let selected = ReplayCore.Report.select(
                scope,
                sessions: scopeSessions,
                annotations: scopeAnnotations,
                todayStart: fixture.scopes.todayStart
            )
            equal(sg, "\(scope.rawValue) selects the same sessions",
                  selected.map(\.session.startedAt), expected)
        }
        // Stated separately because it is the rule most easily lost: a note of only
        // whitespace is not a note, and must not put a session in that scope.
        check(sg, "a whitespace-only note does not count as a note",
              (fixture.scopes.expected["notes"] ?? []).count
                  < fixture.scopes.annotations.filter { !$0.note.isEmpty }.count)

        // Search — the predicates that decide whether a session is findable.
        let hg = "search"
        for query in fixture.search.queries {
            guard let expected = fixture.search.expected[query] else {
                check(hg, "\(query) is covered by the fixture", false, "no expectation recorded")
                continue
            }
            equal(hg, "\"\(query)\" matches the same sessions",
                  scopeSessions.filter {
                      ReplayCore.Search.matches(
                          session: $0, annotation: scopeAnnotations[$0.startedAt], query: query
                      )
                  }.map(\.startedAt),
                  expected.matches)
            equal(hg, "\"\(query)\" finds the same sessions by application",
                  scopeSessions.filter {
                      ReplayCore.Search.usesApp(session: $0, applicationName: query)
                  }.map(\.startedAt),
                  expected.usesApp)
        }
        // Stated on its own because it is the distinction most easily collapsed: the
        // application predicate is exact, so a lowercase name finds nothing while the
        // exact one finds everything. Substring discovery is a different function.
        check(hg, "the application predicate is exact, not a substring",
              (fixture.search.expected["safari"]?.usesApp ?? []).isEmpty
                  && !(fixture.search.expected["Safari"]?.usesApp ?? []).isEmpty)
        equal(hg, "substring discovery is what finds an app by a lowercase name",
              ReplayCore.Search.apps(matching: "safari", in: scopeSessions).map(\.applicationName),
              ["Safari"])

        // Story Mode — a day told back in sentences.
        //
        // Compared as text, because the text *is* the feature: every clause is a claim
        // about the day, and a wrong word is a wrong claim. The cases are chosen so each
        // rule fires or is suppressed, including a day whose two longest stretches tie —
        // the reference keeps the first, Swift's `max(by:)` would keep the last and
        // narrate a different application.
        let stg = "story mode"
        for (index, storyCase) in fixture.stories.cases.enumerated() {
            guard index < fixture.stories.expected.count else { break }
            let expected = fixture.stories.expected[index]
            let sessions = buildTimeline(
                storyCase.events.map(event), now: storyCase.now, calendar: calendar
            ).compactMap { if case .session(let s) = $0 { return s } else { return nil } }
            equal(stg, "\(storyCase.name): the same sessions derive",
                  sessions.count, expected.sessionCount)
            equal(stg, "\(storyCase.name): the same story",
                  DayStory.build(sessions, calendar: calendar), expected.sentences)
        }
        check(stg, "a day with nothing on it gets no story",
              DayStory.build([], calendar: calendar).isEmpty)

        // Collections — sessions gathered by the kind of work they were.
        //
        // Both orderings are tie-broken explicitly here, and the fixture is built so both
        // ties actually occur: two categories on equal totals, and two apps on equal time
        // inside one. JavaScript's sort is stable and falls back on insertion order without
        // saying so; Swift's is not, so an untie-broken port would reorder between launches
        // and pass a fixture that happened not to tie.
        let cg = "collections"
        equal(cg, "the same categories are collectable, in the same order",
              Collections.categories.map(\.category.rawValue),
              fixture.collections.definitions.map(\.category))
        equal(cg, "and carry the same labels — Admin is shown as Utilities",
              Collections.categories.map(\.label),
              fixture.collections.definitions.map(\.label))

        let collectionSessions = buildTimeline(
            fixture.collections.events.map(event),
            now: fixture.collections.now,
            calendar: calendar
        ).compactMap { if case .session(let s) = $0 { return s } else { return nil } }
        equal(cg, "the fixture's sessions derive the same here",
              collectionSessions.count, fixture.collections.sessionCount)

        let computed = Collections.compute(collectionSessions)
        equal(cg, "the same collections, fullest first",
              computed.map(\.category.rawValue), fixture.collections.expected.map(\.category))
        equal(cg, "with the same totals",
              computed.map(\.totalSeconds), fixture.collections.expected.map(\.totalSeconds))
        equal(cg, "and the same session counts",
              computed.map(\.sessionCount), fixture.collections.expected.map(\.sessionCount))
        for (index, expected) in fixture.collections.expected.enumerated() {
            guard index < computed.count else { break }
            equal(cg, "\(expected.category): the same apps, most time first",
                  computed[index].apps.map(\.applicationName),
                  expected.apps.map(\.applicationName))
            equal(cg, "\(expected.category): with the same times",
                  computed[index].apps.map(\.seconds), expected.apps.map(\.seconds))
        }
        check(cg, "a session the category table could not name is not collected",
              !computed.contains { $0.category == .other })
        check(cg, "an app list is capped",
              computed.allSatisfy { $0.apps.count <= Collections.appLimit })

        // Memories — which calendar day each offset lands on.
        //
        // The month-end cases are the point. JavaScript's Date normalises an overflowing
        // day (31 March minus a month is 3 March); Swift's `date(byAdding:)` clamps it to
        // 28 February. A memory labelled "one month ago" has to mean the same day in both
        // apps, so this pins the arithmetic rather than trusting either default.
        let memg = "memories"
        let historySummaries = fixture.history.summaries.map {
            DailySummary(
                dayStart: $0.dayStart, activeSeconds: $0.activeSeconds, topAppName: $0.topAppName
            )
        }
        for historyCase in fixture.history.cases {
            let when = ISO8601DateFormatter().string(from:
                Date(timeIntervalSince1970: Double(historyCase.now) / 1000)).prefix(10)
            equal(memg, "\(when): the offsets land on the same days",
                  Memories.targets(now: historyCase.now, calendar: calendar).map(\.dayStart),
                  historyCase.targets.map(\.dayStart))
            equal(memg, "\(when): and are labelled the same",
                  Memories.targets(now: historyCase.now, calendar: calendar).map(\.label),
                  historyCase.targets.map(\.label))
            equal(memg, "\(when): the same offsets have something to show",
                  Memories.find(
                      in: historySummaries, now: historyCase.now, calendar: calendar
                  ).map(\.range.key),
                  historyCase.found.map(\.key))
        }
        check(memg, "a day with a headline of zero is not a memory",
              Memories.find(
                  in: [DailySummary(dayStart: startOfLocalDay(t0, calendar: calendar) - dayMillis,
                                    activeSeconds: 0)],
                  now: t0, calendar: calendar
              ).isEmpty)

        // focus goals — the app's one evaluative surface, so its rules are checked rather
        // than trusted. The streak rule is the subtle one: an unfinished today must not
        // break a run, or every streak reads as broken every morning.
        let gg = "focus goal"
        equal(gg, "a goal under an hour reads as minutes", Goals.format(45), "45m")
        equal(gg, "a round hour reads in words", Goals.format(60), "1 hour")
        equal(gg, "more than one hour pluralises", Goals.format(120), "2 hours")
        equal(gg, "a mixed goal keeps both parts", Goals.format(330), "5h 30m")
        check(gg, "a preset is not custom", !Goals.isCustom(240))
        check(gg, "an off-grid target is", Goals.isCustom(45))

        let halfway = Goals.progress(activeSeconds: 1800, goalMinutes: 60)
        equal(gg, "progress is a fraction of the goal", halfway.fraction, 0.5)
        equal(gg, "and reports what is left", halfway.remainingSeconds, 1800)
        check(gg, "an unmet goal is not met", !halfway.met)
        let overshot = Goals.progress(activeSeconds: 7200, goalMinutes: 60)
        equal(gg, "overshooting clamps the ring rather than exceeding it", overshot.fraction, 1)
        equal(gg, "and leaves nothing to go", overshot.remainingSeconds, 0)
        check(gg, "a met goal is met", overshot.met)

        let yesterday = startOfLocalDay(t0) - dayMillis
        let dayBefore = yesterday - dayMillis
        let history = [
            DailySummary(dayStart: yesterday, activeSeconds: 7200, topBundleID: nil,
                         topAppName: nil, topSeconds: 0),
            DailySummary(dayStart: dayBefore, activeSeconds: 7200, topBundleID: nil,
                         topAppName: nil, topSeconds: 0),
        ]
        equal(gg, "an unfinished today keeps the run that ended yesterday",
              Goals.streak(summaries: history, todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 60, goalMinutes: 60), 2)
        equal(gg, "and today joins the run once it is met",
              Goals.streak(summaries: history, todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 7200, goalMinutes: 60), 3)
        equal(gg, "a missed day ends the run",
              Goals.streak(summaries: [history[0]], todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 60, goalMinutes: 60), 1)
        equal(gg, "no goal is no streak",
              Goals.streak(summaries: history, todayStart: startOfLocalDay(t0),
                           todayActiveSeconds: 7200, goalMinutes: 0), 0)

        // reports — what an export writes. Serialising is the whole feature, so the shapes
        // are checked rather than just the call not throwing.
        let xg = "report export"
        // Derived rather than hand-built, so what is serialised is what the app would
        // actually show — the same `buildTimeline` every surface reads.
        let reportEvents = [
            ActivityEvent(
                id: 1, type: .activated, applicationName: "Code",
                bundleIdentifier: "com.microsoft.VSCode", appPath: nil,
                startedAt: t0, endedAt: t0 + 600_000, duration: 600
            ),
            ActivityEvent(
                id: 2, type: .activated, applicationName: "Safari",
                bundleIdentifier: "com.apple.Safari", appPath: nil,
                startedAt: t0 + 600_000, endedAt: t0 + 900_000, duration: 300
            ),
        ]
        guard case .session(let reportSession)? = buildTimeline(reportEvents, now: t0 + 900_000).first
        else {
            check(xg, "a sample session could be derived", false, "buildTimeline produced no session")
            return Report(
                glazeVersion: constants.glazeVersion, glazeCommit: constants.glazeCommit,
                specRoot: root.path, checks: checks, fixtureResults: fixtureResults
            )
        }
        let sample = ReplayCore.Report.Entry(
            session: reportSession,
            annotation: SessionAnnotation(
                sessionStart: t0, note: "shipped it", bookmarked: true, tags: ["deep work"],
                updatedAt: t0
            )
        )

        let markdown = ReplayCore.Report.build(.markdown, label: "Today", entries: [sample])
        check(xg, "markdown leads with the scope it covers", markdown.hasPrefix("# Replay — Today"))
        check(xg, "a bookmarked session is starred", markdown.contains("\(reportSession.title) ⭐"))
        check(xg, "the note is quoted", markdown.contains("> shipped it"))
        check(xg, "tags carry their hash", markdown.contains("Tags: #deep work"))
        check(xg, "an empty export says so rather than being blank",
              ReplayCore.Report.build(.markdown, label: "Today", entries: []).contains("Nothing to export"))

        let csvText = ReplayCore.Report.build(.csv, label: "Today", entries: [sample])
        equal(xg, "csv has a header and a row per session", csvText.split(separator: "\n").count, 2)
        check(xg, "csv marks a bookmark", csvText.contains(",yes,"))
        equal(xg, "a cell with a comma is quoted", ReplayCore.Report.csvCell("a, b"), "\"a, b\"")
        equal(xg, "a quote inside a cell is doubled", ReplayCore.Report.csvCell("say \"hi\""), "\"say \"\"hi\"\"\"")
        equal(xg, "a plain cell is left alone", ReplayCore.Report.csvCell("plain"), "plain")

        let jsonText = ReplayCore.Report.build(.json, label: "Today", entries: [sample])
        let parsedReport = try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any]
        equal(xg, "json reports how many sessions it holds",
              (parsedReport?["sessionCount"] as? Int), 1)
        check(xg, "json carries the annotation",
              ((parsedReport?["sessions"] as? [[String: Any]])?.first?["note"] as? String) == "shipped it")

        // A backup round-trips through its own reader — the check that matters, because a
        // backup nobody can restore is not a backup.
        let backupRows = try store.rowsForBackup()
        let encoded = Backup.encode(rows: backupRows, appVersion: "test")
        let reread = try Backup.read(encoded)
        equal(xg, "a written backup reads back with every row", reread.rows.count, backupRows.count)
        equal(xg, "and its rows survive intact", reread.rows, backupRows)
        equal(xg, "the count it declares matches what it holds",
              reread.declaredCount, backupRows.count)

        // Clearing history means what it says: no rows, and no headline left behind.
        try store.upsertSummary(dayStart: startOfLocalDay(t0), now: t0)
        _ = try store.setBookmarked(sessionStart: t0, bookmarked: true, now: t0)
        _ = try store.clearAllHistory()
        equal(mg, "clearing history removes every row", try store.countRows(), 0)
        equal(mg, "and every headline",
              try store.dailySummaries(from: 0, to: t0 + dayMillis).count, 0)
        equal(mg, "and every annotation", try store.annotations(from: 0, to: t0 + dayMillis).count, 0)

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
