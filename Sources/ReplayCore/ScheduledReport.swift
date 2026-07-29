import Foundation

/// Reports nobody has to remember to export.
///
/// The sibling of ``AutoBackup``, deliberately: same cadence, same folder-and-prune shape,
/// same rule that a schedule writes into a place its owner named. What differs is what the
/// file is *for*. A backup is insurance — you hope never to open it, and its value is that it
/// restores. A report is the opposite: it exists to be read, and a weekly one landing in a
/// folder on a Monday is the only way most people ever look back at a week deliberately.
///
/// That difference decides the scope. A schedule writes the period that has **finished** —
/// yesterday, or the week just gone — never the one still being lived. A report of a day at
/// two in the afternoon is a report that is wrong by six.
///
/// Nothing here is the reference's: the Glaze app exports when you ask it to and has no
/// schedule. See `docs/PARITY.md`.
public enum ScheduledReport {

    public static let namePrefix = "Replay report "

    /// How many are kept before the oldest goes. Eight, matching ``AutoBackup/keep`` — two
    /// months of weekly reports, or a working week and a half of daily ones.
    public static let keep = 8

    /// What a cadence covers.
    ///
    /// Daily writes the day that has just ended, weekly the seven days behind it. Both are
    /// past tense, which is the whole point: a finished period is a thing you can read, and an
    /// unfinished one is a thing that keeps changing while you read it.
    public static func scope(for cadence: AutoBackup.Cadence) -> Report.Scope? {
        switch cadence {
        case .off: nil
        case .daily: .today
        case .weekly: .week
        }
    }

    /// The file a report written on this day is called.
    ///
    /// Dated like a backup and for the same two reasons: two runs on one day are one file
    /// rather than two, and an ISO date sorts lexicographically, which is what lets ``stale``
    /// be a sort rather than a stat of every file's modification date.
    public static func filename(
        for date: Date, format: Report.Format, calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(namePrefix)\(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// Which of these files are past the keep limit, oldest first.
    ///
    /// Only ones this wrote, and only ones in a format it writes — a folder somebody chose is
    /// a folder with other things in it, and the one piece of code here that deletes should be
    /// the fussiest about what it is looking at.
    public static func stale(_ names: [String], keeping: Int = keep) -> [String] {
        let extensions = Set(Report.Format.allCases.map(\.fileExtension))
        let mine = names
            .filter { name in
                guard name.hasPrefix(namePrefix) else { return false }
                let suffix = name.split(separator: ".").last.map(String.init) ?? ""
                return extensions.contains(suffix)
            }
            .sorted()
        guard mine.count > keeping else { return [] }
        return Array(mine.prefix(mine.count - keeping))
    }
}
