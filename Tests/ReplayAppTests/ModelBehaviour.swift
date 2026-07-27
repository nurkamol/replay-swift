@testable import ReplayApp
import Foundation
import ReplayCore
import Testing

/// What the models do, as opposed to what `ReplayCore` computes.
///
/// The parity suite checks the derivation against the reference. Nothing checked the layer
/// above it — loading, range filtering, caching, deleting, reloading — which is where this
/// port's own decisions live and where a regression would be invisible. The ledger recorded
/// these as untestable "because they live in an executable target that no test can import".
/// That was wrong: `@testable import` reaches an executable target fine, and the only thing
/// standing between these models and a test was someone writing one.
///
/// Every case runs against a real SQLite file in a temporary directory, because the point is
/// the round trip through the store rather than a mock of it.
@MainActor
@Suite("Model behaviour")
struct ModelBehaviour {
    // ── the harness ───────────────────────────────────────────────────────────

    /// A model on a database of its own, deleted when the case ends.
    private static func makeModel() throws -> (AppModel, URL) {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-model-tests-\(UUID().uuidString)")
        let model = AppModel(databaseURL: directory.appendingPathComponent("activity.db"))
        try #require(model.errorMessage == nil)
        return (model, directory)
    }

    private static func discard(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A closed focus row, written straight to the store.
    @discardableResult
    private static func record(
        _ store: ActivityStore, _ name: String, _ bundleID: String,
        from: Int64, seconds: Int
    ) throws -> Int64 {
        let id = try store.openSession(
            name: name, bundleID: bundleID, appPath: nil, startedAt: from
        )
        try store.closeSession(id: id, endedAt: from + Int64(seconds) * 1000)
        return id
    }

    private static let hour: Int64 = 3_600_000

    /// Local midnight some days back, so cases sit on real calendar days rather than on
    /// arithmetic that drifts across a daylight-saving boundary.
    private static func midnight(daysAgo: Int) -> Int64 {
        let today = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        return startOfLocalDay(today - Int64(daysAgo) * dayMillis + 12 * hour)
    }

    // ── range filtering ───────────────────────────────────────────────────────

    @Test("The Timeline's range keeps only the days it names")
    func rangeFiltering() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let history = HistoryModel(model: model)

        // One session a day for the last five days, each mid-morning so nothing straddles
        // midnight and every row is short enough to be focus rather than absence.
        for daysAgo in 0..<5 {
            try Self.record(
                model.store, "Code", "com.microsoft.VSCode",
                from: Self.midnight(daysAgo: daysAgo) + 9 * Self.hour, seconds: 600
            )
            try Self.record(
                model.store, "Safari", "com.apple.Safari",
                from: Self.midnight(daysAgo: daysAgo) + 9 * Self.hour + 600_000, seconds: 300
            )
        }

        // Explicit, because `range` only reloads when it *changes* and `.week` is already
        // the default — a model just constructed holds nothing until something asks it to.
        #expect(history.days.isEmpty, "nothing is loaded until it is asked for")
        history.reload()
        #expect(history.days.count == 5, "a week shows every day that has something on it")

        history.range = .today
        #expect(history.days.map(\.dayStart) == [Self.midnight(daysAgo: 0)])

        // The one that matters. The range query deliberately reaches back a day so a long
        // away stretch beginning before midnight is not lost; without the filter that
        // reach-back day would appear as a second day in the list.
        history.range = .yesterday
        #expect(history.days.map(\.dayStart) == [Self.midnight(daysAgo: 1)],
                "yesterday means yesterday, not yesterday and the day the query reached back to")
    }

    @Test("A reopened day keeps only the runs that began on it")
    func reopenedDayExcludesRunsFromTheDayBefore() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let history = HistoryModel(model: model)

        let today = Self.midnight(daysAgo: 0)
        // A run that starts at 23:50 yesterday and ends after midnight. It belongs to
        // yesterday, because a day is bucketed by where a run *began* (SPEC §5) — the
        // reference shipped this appearing on both days once.
        try Self.record(
            model.store, "Code", "com.microsoft.VSCode",
            from: today - 10 * 60_000, seconds: 600
        )
        try Self.record(
            model.store, "Terminal", "com.apple.Terminal",
            from: today - 4 * 60_000, seconds: 300
        )
        // And something unambiguously today.
        try Self.record(
            model.store, "Safari", "com.apple.Safari", from: today + 9 * Self.hour, seconds: 600
        )
        try Self.record(
            model.store, "Mail", "com.apple.mail",
            from: today + 9 * Self.hour + 600_000, seconds: 300
        )

        let day = history.day(today)
        #expect(day.sessions.allSatisfy { $0.startedAt >= today },
                "nothing that began yesterday is on today")
        #expect(day.sessions.count == 1)

        let yesterday = history.day(today - dayMillis)
        #expect(yesterday.sessions.count == 1, "and it is on yesterday, where it began")
    }

    // ── annotations ───────────────────────────────────────────────────────────

    @Test("Loading a span forgets what that span no longer holds")
    func loadingASpanClearsStaleEntries() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let annotations = model.annotations

        let today = Self.midnight(daysAgo: 0)
        let start = today + 9 * Self.hour
        annotations.setNote(start, "worth remembering")
        #expect(annotations.annotation(for: start).note == "worth remembering")

        // Deleted by something else — a day erased in another surface, say — and then the
        // span is reloaded. A cached entry surviving that would draw a mark on a card whose
        // note no longer exists.
        _ = try model.store.deleteAnnotations(from: today, to: today + dayMillis)
        annotations.load(from: today, to: today + dayMillis)
        #expect(annotations.annotation(for: start).note.isEmpty)
        #expect(annotations.annotation(for: start).isEmpty)
    }

    @Test("An emptied annotation leaves no entry behind")
    func emptyingAnAnnotationRemovesIt() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let annotations = model.annotations
        let start = Self.midnight(daysAgo: 0) + 9 * Self.hour

        annotations.setNote(start, "a thought")
        annotations.setTags(start, ["deep-work"])
        #expect(!annotations.annotation(for: start).isEmpty)

        annotations.setNote(start, "")
        #expect(annotations.annotation(for: start).tags == ["deep-work"],
                "clearing the note does not clear the tags")

        annotations.setTags(start, [])
        #expect(annotations.annotation(for: start).isEmpty,
                "the last thing removed takes the row with it")
    }

    @Test("A bookmark set on one surface is already true on the next")
    func annotationsAreShared() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let history = HistoryModel(model: model)
        let start = Self.midnight(daysAgo: 0) + 9 * Self.hour

        model.annotations.setBookmarked(start, true)
        // `HistoryModel` reloads annotations as part of loading a day; the model is shared,
        // so the mark has to survive that rather than be overwritten by the reload.
        _ = history.day(Self.midnight(daysAgo: 0))
        #expect(model.annotations.annotation(for: start).bookmarked)
    }

    // ── deletion ──────────────────────────────────────────────────────────────

    @Test("Deleting a day leaves no headline and no annotations")
    func deletingADayLeavesNothing() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let history = HistoryModel(model: model)

        let day = Self.midnight(daysAgo: 2)
        let start = day + 9 * Self.hour
        try Self.record(model.store, "Code", "com.microsoft.VSCode", from: start, seconds: 600)
        try Self.record(
            model.store, "Safari", "com.apple.Safari", from: start + 600_000, seconds: 300
        )
        try model.store.upsertSummary(dayStart: day, now: Int64(Date().timeIntervalSince1970 * 1000))
        #expect(history.headline(day) != nil, "the day has a headline to begin with")

        let sessions = history.day(day).sessions
        try #require(!sessions.isEmpty)
        model.annotations.setNote(sessions[0].startedAt, "a note on a doomed day")

        history.deleteDay(day)

        // A retention prune keeps the headline; an explicit deletion must not. The
        // difference is the whole point of SPEC §6 — a day the user erased should leave no
        // trace, not a summary of what it used to be.
        #expect(history.headline(day) == nil)
        #expect(history.day(day).sessions.isEmpty)
        #expect(model.annotations.annotation(for: sessions[0].startedAt).isEmpty)
        #expect(!history.days.contains { $0.dayStart == day })
    }

    // ── the week ──────────────────────────────────────────────────────────────

    @Test("The week is seven days ending today, including the empty ones")
    func weekCoversSevenDays() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let week = WeekModel(model: model)

        // Two days with something on them, five without.
        for daysAgo in [1, 4] {
            let start = Self.midnight(daysAgo: daysAgo) + 9 * Self.hour
            try Self.record(model.store, "Code", "com.microsoft.VSCode", from: start, seconds: 900)
            try Self.record(
                model.store, "Terminal", "com.apple.Terminal", from: start + 900_000, seconds: 300
            )
        }
        week.load()

        let summary = try #require(week.summary)
        #expect(summary.days.count == 7)
        #expect(summary.days.map(\.dayStart) == (0..<7).map { Self.midnight(daysAgo: 6 - $0) },
                "oldest first, so the row reads left to right like a calendar")
        #expect(summary.days.filter { !$0.isEmpty }.count == 2)
        #expect(summary.days.last?.isToday == true)
        #expect(!week.rangeLabel.isEmpty)
    }

    @Test("A quiet week has figures but nothing to point at")
    func emptyWeekHasNoPeak() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let week = WeekModel(model: model)
        week.load()

        let summary = try #require(week.summary)
        #expect(summary.activeSeconds == 0)
        #expect(summary.peak == nil, "nothing recorded is not a busiest hour of zero")
        #expect(summary.days.allSatisfy { $0.isEmpty })
        #expect(week.workflows.isEmpty)
    }

    // ── search ────────────────────────────────────────────────────────────────

    @Test("Search finds a session by its note, and stops finding it when the note goes")
    func searchReadsAnnotations() throws {
        let (model, directory) = try Self.makeModel()
        defer { Self.discard(directory) }
        let search = SearchModel(model: model, preferences: Preferences())

        let start = Self.midnight(daysAgo: 1) + 9 * Self.hour
        try Self.record(model.store, "Code", "com.microsoft.VSCode", from: start, seconds: 900)
        try Self.record(
            model.store, "Terminal", "com.apple.Terminal", from: start + 900_000, seconds: 300
        )
        // Search reads a snapshot rather than following the annotations model, so a note
        // written now is findable after the next load and not before. That is the actual
        // contract, and worth pinning: a surface that quietly went stale instead would look
        // identical until someone wondered why their note could not be found.
        search.query = "migration"
        #expect(search.sessions.isEmpty, "nothing is loaded yet, so nothing matches")

        search.load()
        let derived = Report.sessions(
            in: try model.store.sessions(from: start, to: start + dayMillis),
            now: start + dayMillis
        )
        let session = try #require(derived.first)
        model.annotations.setNote(session.startedAt, "the migration spike")
        search.load()
        #expect(search.sessions.contains { $0.startedAt == session.startedAt })

        model.annotations.setNote(session.startedAt, "")
        search.load()
        #expect(!search.sessions.contains { $0.startedAt == session.startedAt },
                "a note that no longer exists cannot still be a way to find the session")
    }
}
