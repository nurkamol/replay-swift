@testable import ReplayCore
import Foundation
import Testing

/// A report written on a schedule, and the half of it that can delete something.
///
/// The naming and the pruning, for the same reason `AutoBackup` tests them: this is the second
/// piece of code in the app that removes a file it did not just write, in a folder somebody
/// chose for their own reasons. The rest of the schedule — whether one is due — is
/// `AutoBackup.isDue`, tested there and shared rather than reimplemented.
@Suite("Scheduled report")
struct ScheduledReportBehaviour {

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return calendar().date(from: parts)!
    }

    @Test("A cadence covers the period that has finished, never the one being lived")
    func scopes() {
        // Daily is the day just gone and weekly the week behind it — `Report.select` reads
        // both as past tense. Off covers nothing, which is what makes it off.
        #expect(ScheduledReport.scope(for: .daily) == .today)
        #expect(ScheduledReport.scope(for: .weekly) == .week)
        #expect(ScheduledReport.scope(for: .off) == nil)
    }

    @Test("The name carries the day and the format")
    func naming() {
        #expect(
            ScheduledReport.filename(
                for: Self.at(2026, 7, 29), format: .markdown, calendar: Self.calendar()
            ) == "Replay report 2026-07-29.md"
        )
        #expect(
            ScheduledReport.filename(
                for: Self.at(2026, 7, 29, 23), format: .html, calendar: Self.calendar()
            ) == "Replay report 2026-07-29.html"
        )
    }

    @Test("Past the limit, the oldest go")
    func prunes() {
        let names = (1...9).map { "Replay report 2026-07-0\($0).md" }
        #expect(ScheduledReport.stale(names) == ["Replay report 2026-07-01.md"])
        #expect(ScheduledReport.stale(Array(names.prefix(8))).isEmpty)
    }

    @Test("Nothing else in the folder is ever touched")
    func leavesOtherFilesAlone() {
        let mine = (1...9).map { "Replay report 2026-07-0\($0).md" }
        let theirs = [
            "Replay backup 2026-07-01.json",   // the *other* schedule's files
            "Replay report 2026-07-01.txt",    // a format this never writes
            "report.md", "Replay report.md", "notes 2026-07-01.md",
        ]
        let stale = ScheduledReport.stale(mine + theirs)
        #expect(stale == ["Replay report 2026-07-01.md"])
        for name in theirs { #expect(!stale.contains(name)) }
    }

    @Test("Both formats are recognised as its own, and only those")
    func formatsItWrites() {
        let names = (1...9).flatMap { day in
            ["Replay report 2026-07-0\(day).md", "Replay report 2026-06-0\(day).html"]
        }
        // Eighteen files, eight kept: the ten oldest go, and every one of them is one of ours.
        let stale = ScheduledReport.stale(names)
        #expect(stale.count == 10)
        #expect(stale.allSatisfy { $0.hasPrefix(ScheduledReport.namePrefix) })
    }
}
