import Foundation

/// When an unattended backup is due, what it is called, and which old ones go.
///
/// The whole of this is pure and lives here rather than in the app, for one reason: the part
/// that can lose somebody's history is the *pruning*, and a rule that decides which files to
/// delete should be readable and testable without a disk. Everything else follows from that —
/// if the naming lives beside the pruning, the two cannot drift into a state where a file is
/// written under one pattern and deleted under another.
///
/// Nothing here is the reference's. The Glaze app has a full backup you ask for and no
/// schedule, so this is entirely this port's own — see `docs/PARITY.md`.
public enum AutoBackup {

    /// How often, or not at all.
    ///
    /// Off by default. A background job that writes several megabytes into a folder somebody
    /// did not name is not a feature they asked for, and this app's whole claim is that the
    /// record belongs to its owner.
    public enum Cadence: String, CaseIterable, Sendable {
        case off, daily, weekly

        public var label: String {
            switch self {
            case .off: "Never"
            case .daily: "Every day"
            case .weekly: "Every week"
            }
        }

        var days: Int? {
            switch self {
            case .off: nil
            case .daily: 1
            case .weekly: 7
            }
        }
    }

    /// How many backups are kept in the folder before the oldest is removed.
    ///
    /// Eight, which is two months of weekly copies or a working week and a half of daily
    /// ones — enough that a mistake noticed late is still recoverable, few enough that a
    /// folder does not silently grow to a gigabyte. A year of hard use is 50–60 MB
    /// (SPEC §1), so eight of them is bounded at roughly half a gigabyte in the worst case.
    public static let keep = 8

    /// The file a backup taken on this day is written as.
    ///
    /// The date is in the name, so two backups on the same day are one file rather than two —
    /// a daily schedule that ran twice because the app was relaunched should not leave a
    /// second copy of the same day.
    ///
    /// `en_US_POSIX` and a fixed format on purpose: this name is *parsed* again by `stale`,
    /// and a name written in the user's locale would sort by whatever their calendar does.
    public static func filename(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(namePrefix)\(formatter.string(from: date)).json"
    }

    public static let namePrefix = "Replay backup "

    /// Whether a backup is owed.
    ///
    /// True when one has never been taken, so switching the schedule on writes a copy now
    /// rather than in a week — the moment somebody turns this on is the moment they want a
    /// backup to exist.
    ///
    /// Compared by *day*, not by elapsed seconds: "every day" means a copy from each day,
    /// and 23 hours and 50 minutes after yesterday's run is a new day if the clock says so.
    public static func isDue(
        last: Date?, now: Date, cadence: Cadence, calendar: Calendar = .current
    ) -> Bool {
        guard let days = cadence.days else { return false }
        guard let last else { return true }
        // A last-run stamp in the future means the clock moved backwards or the file was
        // edited; treat it as due rather than never running again.
        if last > now { return true }
        let from = calendar.startOfDay(for: last)
        let to = calendar.startOfDay(for: now)
        let elapsed = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return elapsed >= days
    }

    /// Which of these files are past the keep limit, oldest first.
    ///
    /// Given only the names, and only ones this feature wrote: a folder chosen for backups is
    /// very likely a folder with other things in it, and deleting by "oldest file here" would
    /// be a way to lose somebody's unrelated work. Anything not matching the pattern is left
    /// alone, which is why the pattern is fixed rather than localised.
    ///
    /// The names sort lexicographically because the date in them is ISO-ordered — that is the
    /// whole reason for that format, and the reason this can be a sort rather than a stat of
    /// every file's modification date, which a copy or a restore would have rewritten anyway.
    public static func stale(_ names: [String], keeping: Int = keep) -> [String] {
        let mine = names
            .filter { $0.hasPrefix(namePrefix) && $0.hasSuffix(".json") }
            .sorted()
        guard mine.count > keeping else { return [] }
        return Array(mine.prefix(mine.count - keeping))
    }
}
