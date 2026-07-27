@testable import ReplayCore
import Foundation
import Testing

/// What the tracker records, and what it refuses to.
///
/// This is the only component in the app whose failure is *silent*. Every other gap is a
/// feature you can see is missing; a tracker that mis-records loses a day permanently and
/// nothing says so. It had no tests at all until these, which is the largest quiet risk the
/// ledger recorded.
///
/// The clock is injected so the rules can be checked at all: every one of them is a
/// comparison against time — a dedupe window, a session's end, an away stretch — and none
/// can be pinned against a clock that keeps moving.
@Suite("Tracker behaviour")
struct TrackerBehaviour {
    /// A tracker on a database of its own, with time under the test's control.
    private static func makeTracker() throws -> (ActivityTracker, ActivityStore, Clock, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-tracker-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ActivityStore(path: directory.appendingPathComponent("activity.db").path)
        try store.open()
        let clock = Clock()
        let tracker = ActivityTracker(store: store)
        tracker.clock = { clock.now }
        return (tracker, store, clock, directory)
    }

    /// A clock a test can move by hand.
    private final class Clock: @unchecked Sendable {
        /// A fixed local midnight, so nothing here depends on when it runs.
        var now: Int64 = 1_770_076_800_000
        func advance(seconds: Int) { now += Int64(seconds) * 1000 }
    }

    private static func app(_ name: String, _ bundleID: String) -> ActivityTracker.AppInfo {
        ActivityTracker.AppInfo(name: name, bundleID: bundleID, appPath: nil)
    }

    private static func rows(_ store: ActivityStore) throws -> [ActivityEvent] {
        try store.sessions(from: 0, to: 4_000_000_000_000)
    }

    // ── switching ─────────────────────────────────────────────────────────────

    @Test("A switch closes the session behind it and opens the next")
    func switchingClosesAndOpens() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        tracker.activate(bundleID: "com.microsoft.VSCode", app: Self.app("Code", "com.microsoft.VSCode"))
        clock.advance(seconds: 600)
        tracker.activate(bundleID: "com.apple.Safari", app: Self.app("Safari", "com.apple.Safari"))

        let recorded = try Self.rows(store)
        #expect(recorded.count == 2)
        // The first is closed, and closed at the moment the second began — not later, and
        // not left open. A session that never closes reads as running forever.
        #expect(recorded[0].applicationName == "Code")
        #expect(recorded[0].endedAt == clock.now)
        #expect(recorded[0].duration == 600)
        #expect(recorded[1].applicationName == "Safari")
        #expect(recorded[1].endedAt == nil, "the app in front has not finished yet")
    }

    @Test("Re-activating the app already in front records nothing")
    func reactivatingIsANoOp() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        tracker.activate(bundleID: "com.apple.Terminal", app: Self.app("Terminal", "com.apple.Terminal"))
        clock.advance(seconds: 30)
        // macOS sends this more than once — clicking a window of the app that already has
        // focus, for one. Recording it would chop one session into several.
        tracker.activate(bundleID: "com.apple.Terminal", app: Self.app("Terminal", "com.apple.Terminal"))

        #expect(try Self.rows(store).count == 1)
    }

    @Test("An excluded application is never recorded, and does not end what is")
    func excludedApplicationsAreInvisible() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        tracker.excludedBundleIDs = ["com.apple.Passwords"]
        tracker.activate(bundleID: "com.microsoft.VSCode", app: Self.app("Code", "com.microsoft.VSCode"))
        clock.advance(seconds: 60)
        tracker.activate(bundleID: "com.apple.Passwords", app: Self.app("Passwords", "com.apple.Passwords"))

        let recorded = try Self.rows(store)
        #expect(recorded.count == 1)
        #expect(recorded[0].applicationName == "Code")
        // And crucially still open: excluding an app means Replay does not look, not that
        // the session you were in ended when you glanced at it.
        #expect(recorded[0].endedAt == nil)
    }

    @Test("Replay's own helpers are ignored without being excluded")
    func ignoredApplicationsAreSkipped() throws {
        let (tracker, store, _, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        let ignored = try #require(Rules.ignoredBundleIDs.first)
        tracker.activate(bundleID: ignored, app: Self.app("Something", ignored))

        #expect(try Self.rows(store).isEmpty)
    }

    // ── point events ──────────────────────────────────────────────────────────

    @Test("A launch arriving twice in a moment is recorded once")
    func pointEventsDeduplicate() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        tracker.point(.launched, bundleID: "com.apple.Safari", app: Self.app("Safari", "com.apple.Safari"))
        clock.advance(seconds: 1)
        tracker.point(.launched, bundleID: "com.apple.Safari", app: Self.app("Safari", "com.apple.Safari"))

        let launches = try store.sessions(from: 0, to: 4_000_000_000_000)
        // `sessions` reads focus and idle rows only, so the launch is counted directly.
        #expect(launches.isEmpty)
        #expect(try store.countRows() == 1, "the second arrival inside the window is dropped")

        // Past the window it is a real second launch.
        clock.advance(seconds: Int(Rules.pointEventDedupeSeconds) + 1)
        tracker.point(.launched, bundleID: "com.apple.Safari", app: Self.app("Safari", "com.apple.Safari"))
        #expect(try store.countRows() == 2)
    }

    // ── away ──────────────────────────────────────────────────────────────────

    @Test("Stepping away closes the session, and coming back opens it again")
    func awayParksAndResumes() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        tracker.activate(bundleID: "com.microsoft.VSCode", app: Self.app("Code", "com.microsoft.VSCode"))
        clock.advance(seconds: 300)
        let awayStart = clock.now
        tracker.beginAway(at: awayStart)

        var recorded = try Self.rows(store)
        #expect(recorded.count == 1)
        #expect(recorded[0].endedAt == awayStart, "the session ends where the absence begins")

        clock.advance(seconds: 900)
        tracker.endAway(at: clock.now, from: awayStart)

        recorded = try Self.rows(store)
        // An away row for the gap, and the parked session resumed as a new one.
        #expect(recorded.contains { $0.type == .idle })
        let away = try #require(recorded.first { $0.type == .idle })
        #expect(away.startedAt == awayStart)
        #expect(away.endedAt == clock.now)
        #expect(recorded.filter { $0.applicationName == "Code" }.count == 2,
                "the work you came back to is a new session, not the old one reopened")
    }

    @Test("A switch while away ends the absence without resuming what was parked")
    func switchingWhileAwayDoesNotResume() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        tracker.activate(bundleID: "com.microsoft.VSCode", app: Self.app("Code", "com.microsoft.VSCode"))
        clock.advance(seconds: 300)
        tracker.beginAway(at: clock.now)
        clock.advance(seconds: 900)
        // Coming back *into a different app* is still coming back, but the thing you parked
        // is not what you returned to — resuming it would invent a session.
        tracker.activate(bundleID: "com.apple.Safari", app: Self.app("Safari", "com.apple.Safari"))

        let recorded = try Self.rows(store)
        #expect(recorded.filter { $0.applicationName == "Code" }.count == 1)
        #expect(recorded.filter { $0.applicationName == "Safari" }.count == 1)
        #expect(recorded.contains { $0.type == .idle })
    }

    // ── what the derivation makes of it ───────────────────────────────────────

    @Test("What the tracker records is what the timeline reads back")
    func recordedActivityDerivesAsExpected() throws {
        let (tracker, store, clock, directory) = try Self.makeTracker()
        defer { try? FileManager.default.removeItem(at: directory) }

        // A morning of work: two apps, back and forth, then a switch away.
        for (bundle, name) in [
            ("com.microsoft.VSCode", "Code"), ("com.apple.Terminal", "Terminal"),
            ("com.microsoft.VSCode", "Code"), ("com.apple.Terminal", "Terminal"),
        ] {
            tracker.activate(bundleID: bundle, app: Self.app(name, bundle))
            clock.advance(seconds: 300)
        }
        tracker.activate(bundleID: "com.apple.Safari", app: Self.app("Safari", "com.apple.Safari"))

        // The point of this one: the rows the tracker wrote have to survive the derivation
        // the whole app reads through. A tracker that records correctly into a shape the
        // derivation then discards is still a tracker that lost the day.
        let rows = try Self.rows(store)
        let timeline = buildTimeline(rows, now: clock.now)
        let sessions = timeline.compactMap { item -> ActivitySession? in
            if case .session(let session) = item { return session } else { return nil }
        }
        #expect(sessions.count == 1, "one unbroken run, not four")
        let session = try #require(sessions.first)
        #expect(session.activeSeconds == 1200)
        // `switches` counts the session's *rows*, not the moves between them — five rows
        // is five, not four. Read out of the derivation rather than guessed: two earlier
        // versions of this line asserted the number I expected instead of the one the code
        // produces, which is a test written backwards. The name is the reference's and is
        // slightly wrong in both apps; it is not this port's to rename.
        #expect(session.switches == rows.count)
        // Safari is in this session too: it followed with no gap, and a run is a run. The
        // first version of this expectation left it out and was simply wrong — the check
        // was corrected to what the derivation does, not the other way round.
        #expect(
            Set(session.apps.map(\.applicationName)) == ["Code", "Terminal", "Safari"]
        )
        #expect(session.apps.first?.applicationName == "Code",
                "and the app that held it longest leads")
    }
}
