import Foundation
import ReplayCore
import Testing

/// The sentences an App Intent gives back.
///
/// Tested here rather than beside the intents because `AppIntents` conformances are almost
/// impossible to exercise — they are discovered by the system at runtime out of generated
/// metadata, and `perform()` wants a live intent graph around it. So the intents hold no
/// logic worth testing: every one of them opens the store, calls ``Answers``, and hands back
/// what it got. This is the part that can be wrong.
///
/// And it is worth pinning, because a Shortcut's result has no interface around it. The
/// sentence is read aloud, or dropped into a note, or piped into another app — with none of
/// the context a screen would give it. "0m" and "nothing recorded" look similar in a summary
/// row and mean entirely different things in a spoken answer.
@Suite("Answers")
struct AnswerBehaviour {

    private struct Fixture {
        var store: ActivityStore
        var directory: URL
    }

    private static func makeFixture() throws -> Fixture {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-answers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = ActivityStore(path: directory.appendingPathComponent("activity.db").path)
        try store.open()
        return Fixture(store: store, directory: directory)
    }

    private static func discard(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.directory)
    }

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

    /// A fixed instant, so "today" and "yesterday" mean the same thing on every run.
    private static let now: Int64 = 1_785_178_800_000

    /// **Every stretch below is under thirty minutes, on purpose.**
    ///
    /// `excludeIdleStretches` drops any single unbroken row that reaches
    /// `Rules.idleBreakSeconds`, because a half-hour with no switch in it is a Mac left
    /// open rather than somebody working — SPEC §4, "active means what a person would
    /// mean". The first version of these fixtures used a 30-minute row and a 60-minute
    /// one and both vanished, which looked like a bug in `Answers` and was the derivation
    /// doing exactly its job. Anyone adding a case here will hit the same wall.
    ///
    /// The threshold is exclusive: 1800 seconds is dropped, 1799 is kept.

    @Test("A day with nothing in it says so, rather than saying zero")
    func emptyDayIsNotZero() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }

        let day = try Answers.day(Self.now, store: fixture.store, now: Self.now)
        #expect(day.activeSeconds == 0)
        #expect(day.sentence.contains("nothing recorded"))
        // The distinction this test exists for: zero minutes and no record are different
        // claims, and only one of them is true when Replay was not running.
        #expect(!day.sentence.contains("0m"))
    }

    @Test("Today's sentence names the total and what most of it was")
    func todayReadsWell() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        let start = startOfLocalDay(Self.now)

        try Self.record(fixture.store, "Terminal", "com.apple.Terminal", from: start + 60_000, seconds: 1200)
        try Self.record(fixture.store, "Firefox", "org.mozilla.firefox", from: start + 1_400_000, seconds: 600)

        let day = try Answers.day(start, store: fixture.store, now: Self.now)
        #expect(day.sentence.hasPrefix("Today: "))
        #expect(day.sentence.contains("mostly in Terminal"))
        #expect(day.sentence.hasSuffix("."))
        #expect(day.topApp == "Terminal")
        #expect(day.activeSeconds > 0)
    }

    @Test("Yesterday is called Yesterday, not given its date")
    func yesterdayIsNamed() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        let yesterday = startOfLocalDay(startOfLocalDay(Self.now) - dayMillis)

        try Self.record(fixture.store, "Xcode", "com.apple.dt.Xcode", from: yesterday + 60_000, seconds: 900)

        let day = try Answers.day(yesterday, store: fixture.store, now: Self.now)
        #expect(day.sentence.hasPrefix("Yesterday: "))
    }

    @Test("A session that began the day before is not counted into this day")
    func respectsTheDayBoundary() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        let today = startOfLocalDay(Self.now)

        // Begins before midnight and runs past it. SPEC §5: it belongs to the day it began,
        // and an intent that disagreed with the app's own headline would be worse than an
        // intent that did not exist.
        try Self.record(fixture.store, "Terminal", "com.apple.Terminal", from: today - 600_000, seconds: 900)

        let day = try Answers.day(today, store: fixture.store, now: Self.now)
        #expect(day.sentence.contains("nothing recorded"))
    }

    @Test("An application is found however it is typed")
    func applicationMatchIsForgiving() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        let start = startOfLocalDay(Self.now)

        try Self.record(fixture.store, "Xcode", "com.apple.dt.Xcode", from: start + 60_000, seconds: 1500)

        // Spoken into a Shortcut, or typed in a hurry. Matching only the exact string would
        // make this a quiz rather than a question.
        for typed in ["Xcode", "xcode", "XCODE"] {
            let found = try Answers.application(
                named: typed, on: start, store: fixture.store, now: Self.now
            )
            #expect(found?.name == "Xcode", "\(typed) should find Xcode")
            #expect(found?.seconds ?? 0 > 0)
        }
    }

    @Test("An application that was never used returns nothing, not zero")
    func unknownApplicationIsNil() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        let start = startOfLocalDay(Self.now)

        try Self.record(fixture.store, "Terminal", "com.apple.Terminal", from: start + 60_000, seconds: 600)

        let found = try Answers.application(
            named: "Photoshop", on: start, store: fixture.store, now: Self.now
        )
        #expect(found == nil)
    }
}

