@testable import ReplayCore
import Foundation
import Testing

/// When a backup is owed, and which old ones are removed.
///
/// The pruning is the half that can lose something, so it is tested first and hardest: this
/// is the only code in Replay that deletes a file it did not just write, and the folder it
/// runs in is one the user chose — which means it is a folder with other things in it.
@Suite("Automatic backup")
struct AutoBackupBehaviour {

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return calendar().date(from: parts)!
    }

    // ── when one is due ───────────────────────────────────────────────────────

    @Test("Off is off, however long it has been")
    func offNeverRuns() {
        #expect(!AutoBackup.isDue(
            last: nil, now: Self.at(2026, 7, 29), cadence: .off, calendar: Self.calendar()
        ))
    }

    @Test("Never having run is due, so switching it on writes a copy now")
    func firstRun() {
        #expect(AutoBackup.isDue(
            last: nil, now: Self.at(2026, 7, 29), cadence: .daily, calendar: Self.calendar()
        ))
        #expect(AutoBackup.isDue(
            last: nil, now: Self.at(2026, 7, 29), cadence: .weekly, calendar: Self.calendar()
        ))
    }

    @Test("Daily is a new day, not twenty-four hours")
    func dailyCountsDays() {
        let calendar = Self.calendar()
        // Late last night to early this morning is nine hours and *is* a new day.
        #expect(AutoBackup.isDue(
            last: Self.at(2026, 7, 28, 23), now: Self.at(2026, 7, 29, 8),
            cadence: .daily, calendar: calendar
        ))
        // Morning to evening of the same day is longer and is not.
        #expect(!AutoBackup.isDue(
            last: Self.at(2026, 7, 29, 8), now: Self.at(2026, 7, 29, 23),
            cadence: .daily, calendar: calendar
        ))
    }

    @Test("Weekly waits seven days")
    func weeklyWaits() {
        let calendar = Self.calendar()
        #expect(!AutoBackup.isDue(
            last: Self.at(2026, 7, 23), now: Self.at(2026, 7, 29),
            cadence: .weekly, calendar: calendar
        ))
        #expect(AutoBackup.isDue(
            last: Self.at(2026, 7, 22), now: Self.at(2026, 7, 29),
            cadence: .weekly, calendar: calendar
        ))
    }

    @Test("A stamp from the future is due rather than never")
    func clockWentBackwards() {
        #expect(AutoBackup.isDue(
            last: Self.at(2027, 1, 1), now: Self.at(2026, 7, 29),
            cadence: .daily, calendar: Self.calendar()
        ))
    }

    // ── what it is called ─────────────────────────────────────────────────────

    @Test("The name carries the day, so two runs on one day are one file")
    func nameIsDated() {
        let name = AutoBackup.filename(for: Self.at(2026, 7, 29, 3), calendar: Self.calendar())
        #expect(name == "Replay backup 2026-07-29.json")
        #expect(
            AutoBackup.filename(for: Self.at(2026, 7, 29, 23), calendar: Self.calendar()) == name
        )
    }

    // ── which ones go ─────────────────────────────────────────────────────────

    @Test("Under the limit, nothing is removed")
    func keepsWhatItHas() {
        let names = (1...8).map { "Replay backup 2026-07-0\($0).json" }
        #expect(AutoBackup.stale(names).isEmpty)
    }

    @Test("Past the limit, the oldest go and the newest stay")
    func removesTheOldest() {
        let names = (1...9).map { "Replay backup 2026-07-0\($0).json" }
        #expect(AutoBackup.stale(names) == ["Replay backup 2026-07-01.json"])
    }

    @Test("Nothing else in the folder is ever touched")
    func leavesOtherFilesAlone() {
        let mine = (1...9).map { "Replay backup 2026-07-0\($0).json" }
        let theirs = [
            "taxes.json", "Replay report 2026-07-01.json", "backup.json",
            "Replay backup 2026-07-01.json.bak", ".DS_Store",
        ]
        let stale = AutoBackup.stale(mine + theirs)
        #expect(stale == ["Replay backup 2026-07-01.json"])
        for name in theirs { #expect(!stale.contains(name)) }
    }

    @Test("The oldest is decided by the date in the name, not by the order they arrive")
    func sortsByName() {
        let jumbled = [
            "Replay backup 2026-07-09.json", "Replay backup 2026-06-30.json",
            "Replay backup 2026-07-05.json", "Replay backup 2026-07-01.json",
        ]
        #expect(AutoBackup.stale(jumbled, keeping: 2) == [
            "Replay backup 2026-06-30.json", "Replay backup 2026-07-01.json",
        ])
    }
}
