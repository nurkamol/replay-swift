@testable import ReplayApp
import Foundation
import ReplayCore
import Testing

/// The three models that had no tests: Settings, Collections and Export.
///
/// Settings is the one that matters most, and it is the reason this file exists. Every other
/// model *reads*; Settings is the only one that erases, and it erases on a promise — exclude
/// an application and Replay does not merely stop recording it, it removes what it already
/// recorded. A regression there is silent and permanent, which is the worst pair.
///
/// Preferences are given their own `UserDefaults` suite per case. Without that these would
/// write into the real defaults of whoever ran them, which is a test that changes the
/// machine it runs on.
@MainActor
@Suite("Settings, collections and export")
struct SettingsBehaviour {

    // ── the harness ───────────────────────────────────────────────────────────

    private static let hour: Int64 = 3_600_000

    private struct Fixture {
        var model: AppModel
        var preferences: Preferences
        var directory: URL
        var suite: String
    }

    private static func makeFixture() throws -> Fixture {
        sweepAbandonedSuites()
        let id = UUID().uuidString
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-settings-tests-\(id)")
        let model = AppModel(databaseURL: directory.appendingPathComponent("activity.db"))
        try #require(model.errorMessage == nil)
        let suite = "replay.tests.\(id)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return Fixture(
            model: model, preferences: Preferences(defaults: defaults),
            directory: directory, suite: suite
        )
    }

    private static func discard(_ fixture: Fixture) {
        try? FileManager.default.removeItem(at: fixture.directory)
        // Two steps, and both are needed.
        //
        // `.standard.removePersistentDomain(forName:)` was the whole of it, and asking
        // standard to drop a domain it does not own silently does nothing — so every run
        // since these tests were written left its suite behind in the user's real
        // preferences. 531 of them by the time one was noticed, and only because a stray
        // click sent me reading `defaults domains`. A leak with no symptom is still a leak.
        //
        // Removing the domain through the suite's *own* instance is the documented way, and
        // it still leaves the plist on disk, because `cfprefsd` writes the file back when
        // the instance is released. So the file goes too.
        removeSuite(fixture.suite)
    }

    private static func removeSuite(_ suite: String) {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        guard let preferences = preferencesDirectory() else { return }
        try? FileManager.default.removeItem(
            at: preferences.appendingPathComponent("\(suite).plist")
        )
    }

    private static func preferencesDirectory() -> URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Preferences")
    }

    /// Anything an earlier run left behind, swept on the way past.
    ///
    /// The fix above stops new ones; this clears the old, and costs a directory listing per
    /// run. Scoped to this suite's own prefix so it can never touch anything else.
    static func sweepAbandonedSuites() {
        guard let preferences = preferencesDirectory() else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path)) ?? []
        for file in names where file.hasPrefix("replay.tests.") && file.hasSuffix(".plist") {
            removeSuite(String(file.dropLast(".plist".count)))
        }
    }

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

    private static func midnight(daysAgo: Int) -> Int64 {
        let today = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        return startOfLocalDay(today - Int64(daysAgo) * dayMillis + 12 * hour)
    }

    /// A day of work in two applications, on the day given.
    private static func aDay(_ store: ActivityStore, daysAgo: Int) throws {
        let start = midnight(daysAgo: daysAgo) + 9 * hour
        try record(store, "Code", "com.microsoft.VSCode", from: start, seconds: 600)
        try record(store, "Safari", "com.apple.Safari", from: start + 600_000, seconds: 300)
        try record(store, "Code", "com.microsoft.VSCode", from: start + 900_000, seconds: 600)
    }

    // ── excluding an application ──────────────────────────────────────────────

    /// The promise the Privacy pane makes, in full: stop recording it, *and* erase what was
    /// recorded. Half of that — stopping without erasing — would leave the app's history in
    /// the database while the screen said it was excluded.
    @Test("Excluding an application erases the rows it already had")
    func excludingErases() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 1)

        let settings = SettingsModel(
            model: fixture.model,
            history: HistoryModel(model: fixture.model),
            preferences: fixture.preferences
        )
        settings.reload()
        let before = try #require(settings.info).eventCount
        #expect(before == 3)

        let safari = try #require(
            settings.knownApps.first { $0.bundleIdentifier == "com.apple.Safari" }
        )
        settings.setExcluded(safari, true)

        #expect(settings.errorMessage == nil)
        #expect(fixture.preferences.excludedBundleIDs.contains("com.apple.Safari"))
        // Its two rows are gone; the other application's are untouched.
        let rows = try fixture.model.store.sessions(from: 0, to: .max)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.bundleIdentifier == "com.microsoft.VSCode" })
    }

    /// The subtle half. Erasing rows moves the boundaries of the sessions around them, and a
    /// note is keyed to the first event of the session it was written on — so a purge can
    /// orphan an annotation that still has a row in the database and no session to belong
    /// to. `setExcluded` prunes them; without that the note survives as a ghost.
    @Test("Excluding an application takes any annotation it orphaned with it")
    func excludingPrunesOrphans() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }

        // A day that is nothing but Safari, so excluding it leaves no session at all.
        let start = Self.midnight(daysAgo: 1) + 9 * Self.hour
        try Self.record(fixture.model.store, "Safari", "com.apple.Safari", from: start, seconds: 600)
        _ = try fixture.model.store.setNote(sessionStart: start, note: "worth keeping", now: start)
        #expect(try fixture.model.store.annotations(from: 0, to: .max).count == 1)

        let settings = SettingsModel(
            model: fixture.model,
            history: HistoryModel(model: fixture.model),
            preferences: fixture.preferences
        )
        settings.reload()
        let safari = try #require(
            settings.knownApps.first { $0.bundleIdentifier == "com.apple.Safari" }
        )
        settings.setExcluded(safari, true)

        #expect(settings.errorMessage == nil)
        #expect(try fixture.model.store.annotations(from: 0, to: .max).isEmpty)
    }

    /// An excluded application whose history has been erased is no longer a *known* app —
    /// the store has never heard of it. If the list were only the known ones, excluding an
    /// app would make it disappear from the very screen you would un-exclude it on.
    @Test("An excluded application stays on the list after its history is gone")
    func excludedAppRemainsFindable() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 1)

        let settings = SettingsModel(
            model: fixture.model,
            history: HistoryModel(model: fixture.model),
            preferences: fixture.preferences
        )
        settings.reload()
        let safari = try #require(
            settings.knownApps.first { $0.bundleIdentifier == "com.apple.Safari" }
        )
        settings.setExcluded(safari, true)

        #expect(settings.knownApps.contains { $0.bundleIdentifier == "com.apple.Safari" } == false)
        #expect(
            settings.exclusionCandidates.contains { $0.bundleIdentifier == "com.apple.Safari" }
        )

        // And un-excluding resumes tracking without pretending the history came back.
        settings.setExcluded(safari, false)
        #expect(fixture.preferences.excludedBundleIDs.contains("com.apple.Safari") == false)
        #expect(try fixture.model.store.sessions(from: 0, to: .max).count == 2)
    }

    // ── retention and clearing ────────────────────────────────────────────────

    @Test("Retention prunes past the window and keeps everything inside it")
    func retentionPrunes() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 1)
        try Self.aDay(fixture.model.store, daysAgo: 40)

        let settings = SettingsModel(
            model: fixture.model,
            history: HistoryModel(model: fixture.model),
            preferences: fixture.preferences
        )
        fixture.preferences.retentionDays = 30
        settings.applyRetention()

        #expect(settings.errorMessage == nil)
        let rows = try fixture.model.store.sessions(from: 0, to: .max)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.startedAt >= Self.midnight(daysAgo: 30) })

        // The day is pruned, but its headline is what Memories reads — and it survives.
        let summaries = try fixture.model.store.dailySummaries(from: 0, to: .max)
        #expect(summaries.contains { $0.dayStart == Self.midnight(daysAgo: 40) })
    }

    @Test("Keeping everything prunes nothing")
    func retentionOffKeepsEverything() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 400)

        let settings = SettingsModel(
            model: fixture.model,
            history: HistoryModel(model: fixture.model),
            preferences: fixture.preferences
        )
        // Zero is the default and means "never delete history the user did not ask to lose".
        #expect(fixture.preferences.retentionDays == 0)
        settings.applyRetention()
        #expect(try fixture.model.store.sessions(from: 0, to: .max).count == 3)
    }

    @Test("Clearing history leaves the summaries behind too")
    func clearingRemovesEverything() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 1)

        let settings = SettingsModel(
            model: fixture.model,
            history: HistoryModel(model: fixture.model),
            preferences: fixture.preferences
        )
        settings.clearHistory()

        #expect(settings.errorMessage == nil)
        #expect(try fixture.model.store.sessions(from: 0, to: .max).isEmpty)
        // Unlike retention, this is "forget all of it" — the headlines go as well, or the
        // app would still be able to tell you about days you asked it to forget.
        #expect(try fixture.model.store.dailySummaries(from: 0, to: .max).isEmpty)
    }

    // ── collections ───────────────────────────────────────────────────────────

    @Test("A collection's count and its sessions are the same set")
    func collectionsAgreeWithTheirSessions() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 1)
        try Self.aDay(fixture.model.store, daysAgo: 2)

        let collections = CollectionsModel(model: fixture.model)
        collections.load()
        #expect(collections.loaded)
        #expect(!collections.collections.isEmpty)

        // The list is a fold of the same sessions, so the two must never disagree — a count
        // in a header that does not match the rows under it is the classic derived-view bug.
        for collection in collections.collections {
            #expect(collections.sessions(in: collection.category).count == collection.sessionCount)
        }

        // "Other" is deliberately not a collection: gathering the sessions Replay could not
        // name into a set called Other implies they have something in common.
        #expect(collections.collections.contains { $0.category == .other } == false)
    }

    // ── export ────────────────────────────────────────────────────────────────

    @Test("An export carries what was written on a session")
    func exportEntriesCarryAnnotations() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        let start = Self.midnight(daysAgo: 1) + 9 * Self.hour
        try Self.aDay(fixture.model.store, daysAgo: 1)

        let history = HistoryModel(model: fixture.model)
        let day = try #require(history.day(Self.midnight(daysAgo: 1)))
        let first = try #require(day.sessions.first)
        _ = try fixture.model.store.setNote(
            sessionStart: first.startedAt, note: "the morning", now: start
        )
        _ = try fixture.model.store.setTags(
            sessionStart: first.startedAt, tags: ["deep work"], now: start
        )
        fixture.model.annotations.load(from: 0, to: .max)

        let export = ExportModel(model: fixture.model)
        let entries = export.entries(for: day.sessions)
        #expect(entries.count == day.sessions.count)
        let annotated = try #require(entries.first { $0.session.startedAt == first.startedAt })
        #expect(annotated.annotation?.note == "the morning")
        #expect(annotated.annotation?.tags == ["deep work"])
        // An unannotated session carries nothing rather than an empty annotation, so a
        // report can tell "nothing written" from "written and then cleared".
        #expect(entries.filter { $0.annotation == nil }.count == entries.count - 1)
    }

    /// The count shown beside a scope before the save panel opens is the only thing anyone
    /// can check an export against without opening it, so it has to be right.
    ///
    /// Checked against the day the Timeline derives independently, rather than against
    /// `selection` — `count` *is* `selection(...).count`, so comparing the two would assert
    /// nothing at all. Two paths to the same number is the only version of this worth having.
    @Test("A scope's count agrees with the days it covers")
    func scopeCountsCoverTheRightDays() throws {
        let fixture = try Self.makeFixture()
        defer { Self.discard(fixture) }
        try Self.aDay(fixture.model.store, daysAgo: 0)
        try Self.aDay(fixture.model.store, daysAgo: 2)
        try Self.aDay(fixture.model.store, daysAgo: 10)
        fixture.model.annotations.load(from: 0, to: .max)

        let history = HistoryModel(model: fixture.model)
        let export = ExportModel(model: fixture.model)

        let today = try #require(history.day(Self.midnight(daysAgo: 0)))
        #expect(export.count(.today) == today.sessions.count)
        #expect(export.count(.today) > 0)

        // Seven days including today, so the day two back is in and the one ten back is not.
        let week = (0..<7).compactMap { history.day(Self.midnight(daysAgo: $0)) }
        #expect(export.count(.week) == week.reduce(0) { $0 + $1.sessions.count })
        #expect(export.count(.week) > export.count(.today))

        // A month reaches the ten-day-old day the week does not.
        #expect(export.count(.month) > export.count(.week))

        // Nothing was bookmarked or annotated, so those two scopes are empty rather than
        // falling back to everything — the failure mode that would silently export a month.
        #expect(export.count(.bookmarks) == 0)
        #expect(export.count(.notes) == 0)
    }
}
