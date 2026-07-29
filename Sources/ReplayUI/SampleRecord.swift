#if DEBUG
import Foundation
import ReplayCore

/// A believable day, for the canvas and for `⌘R`.
///
/// Previews need something to draw. `FocusGoalCard` takes plain numbers and previews without
/// help, but every surface worth looking at — Today, the Timeline, Memories — reads an
/// `AppModel`, which reads a database. Without a record there is nothing to lay out, and a
/// preview of an empty state is the one layout nobody needs help seeing.
///
/// **Debug builds only, and never the real record.** The whole file is inside `#if DEBUG`, so
/// it is not in the shipped binary at all. Everything here is written to a scratch database:
/// previews use a temporary directory, and `⌘R` uses whatever `REPLAY_DB` names. The app's
/// rule that it never invents applies to *your* history; this invents a stranger's, somewhere
/// else, and says so.
///
/// The day is deliberately ordinary rather than impressive: a couple of long stretches, some
/// short ones, one context-switching patch in the afternoon. Layout bugs hide in the ordinary
/// case — a headline that wraps at a plausible number of sessions, a row that clips at a
/// realistic app name — and a day of twelve-hour focus blocks would show none of them.
enum SampleRecord {

    /// One entry in the sample day: an app, when it began, and how long it lasted.
    private struct Stretch {
        let name: String
        let bundleID: String
        /// Minutes after local midnight.
        let startMinute: Int
        let minutes: Int
    }

    /// A working Wednesday: about six hours active across twenty-two stretches.
    ///
    /// **Every stretch is under `Rules.idleStretchSeconds`, and that is not a detail.** A run
    /// of thirty minutes or more in one app is read as having walked away and left it open, so
    /// it is excluded from "active" (SPEC, and `ActivityStore.swift:408`). The first version of
    /// this day had a 68-minute Xcode block and a 47-minute Firefox one, which looked like a
    /// productive morning and rendered as *46m active* — the app correctly threw most of it
    /// away. Real records do not contain hour-long single stretches, because people switch
    /// away and back; a fixture that does is a fixture that previews a day nobody had.
    private static let day: [Stretch] = [
        .init(name: "Mail", bundleID: "com.apple.mail", startMinute: 9 * 60 + 12, minutes: 14),
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", startMinute: 9 * 60 + 28, minutes: 26),
        .init(name: "Terminal", bundleID: "com.apple.Terminal", startMinute: 9 * 60 + 56, minutes: 8),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 10 * 60 + 6, minutes: 28),
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", startMinute: 10 * 60 + 36, minutes: 11),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 10 * 60 + 49, minutes: 24),
        .init(name: "Terminal", bundleID: "com.apple.Terminal", startMinute: 11 * 60 + 15, minutes: 6),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 11 * 60 + 23, minutes: 27),
        .init(name: "Notes", bundleID: "com.apple.Notes", startMinute: 11 * 60 + 52, minutes: 9),
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", startMinute: 12 * 60 + 3, minutes: 12),
        // Lunch — a real gap, so the timeline has a break to draw rather than one solid band.
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", startMinute: 13 * 60 + 20, minutes: 18),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 13 * 60 + 40, minutes: 29),
        .init(name: "Terminal", bundleID: "com.apple.Terminal", startMinute: 14 * 60 + 11, minutes: 7),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 14 * 60 + 20, minutes: 22),
        // The patch where nothing holds for long: this is what makes a switch count look like
        // a switch count instead of a rounding error.
        .init(name: "Messages", bundleID: "com.apple.MobileSMS", startMinute: 14 * 60 + 44, minutes: 5),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 14 * 60 + 51, minutes: 26),
        .init(name: "Terminal", bundleID: "com.apple.Terminal", startMinute: 15 * 60 + 19, minutes: 9),
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", startMinute: 15 * 60 + 30, minutes: 14),
        .init(name: "Xcode", bundleID: "com.apple.dt.Xcode", startMinute: 15 * 60 + 46, minutes: 28),
        .init(name: "Preview", bundleID: "com.apple.Preview", startMinute: 16 * 60 + 16, minutes: 6),
        .init(name: "Mail", bundleID: "com.apple.mail", startMinute: 16 * 60 + 24, minutes: 13),
        .init(name: "Firefox", bundleID: "org.mozilla.firefox", startMinute: 16 * 60 + 39, minutes: 21),
    ]

    /// The longest single stretch in the day, in minutes.
    ///
    /// Exposed only so a test can hold it below `Rules.idleStretchSeconds`. That threshold is
    /// the difference between this fixture describing a day and describing a Mac left on, and
    /// nothing about the canvas would reveal which one you were looking at.
    static var longestStretchMinutes: Int { day.map(\.minutes).max() ?? 0 }

    /// Every distinct app the day touches, for a test that wants to know the shape without
    /// reaching into the private data.
    static var appNames: Set<String> { Set(day.map(\.name)) }

    /// How many days back the sample reaches. Enough for the Memories heatmap and the week
    /// view to have a shape, not so many that a preview waits on the write.
    private static let daysOfHistory = 21

    /// Write the sample day into a store, today and on each of the days behind it.
    ///
    /// Earlier days are the same shape shifted and thinned, which is what makes a heatmap look
    /// like a heatmap: identical days would render as a flat grid, and random ones as noise.
    static func seed(into store: ActivityStore) throws {
        let midnight = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        for daysAgo in 0...daysOfHistory {
            let dayStart = startOfLocalDay(midnight - Int64(daysAgo) * dayMillis + 12 * 3_600_000)
            // A weekend is quieter, and every third day drops its afternoon. Deterministic,
            // so two runs of the same fixture produce the same picture.
            let weekday = Calendar.current.component(.weekday, from: date(dayStart))
            let quiet = weekday == 1 || weekday == 7
            for (index, stretch) in day.enumerated() {
                if quiet && index % 2 == 0 { continue }
                // Every third past day loses its afternoon, so the heatmap has light squares
                // as well as dark ones. Never today: today is the surface most previews are
                // pointed at, and a half day there reads as the fixture being thin.
                if daysAgo > 0 && daysAgo % 3 == 0 && stretch.startMinute > 13 * 60 { continue }
                let began = dayStart + Int64(stretch.startMinute) * 60_000
                // Never write the future: today's later stretches have not happened yet.
                guard began < Int64(Date().timeIntervalSince1970 * 1000) else { continue }
                let id = try store.openSession(
                    name: stretch.name, bundleID: stretch.bundleID, appPath: nil, startedAt: began
                )
                try store.closeSession(id: id, endedAt: began + Int64(stretch.minutes) * 60_000)
            }
        }
    }

    private static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    /// An `AppModel` over a fresh sample record, loaded and not recording.
    ///
    /// `reload()` rather than `start()`: `start()` would attach an `ActivityTracker` to
    /// `NSWorkspace` and a one-second timer, so a canvas left open would quietly record the
    /// apps you switch to while looking at it. A preview reads; it must not write.
    @MainActor
    static func model() -> AppModel {
        let model = AppModel(databaseURL: databaseURL())
        try? seed(into: model.store)
        // The rollup, again, and this is the order that matters. `AppModel.init` folds
        // finished days into daily summaries — on a database that was still empty a moment
        // ago. Memories and the heatmap read *summaries*, not sessions, so without this the
        // history is written and invisible: three weeks of days that render as a blank grid,
        // which looks like a working preview of a quiet life.
        try? model.store.rollupCompleteDays(now: Int64(Date().timeIntervalSince1970 * 1000))
        model.reload()
        return model
    }

    /// Where a preview's record is written: a fresh directory under the system temporary one,
    /// never `defaultDatabaseURL()`. Named rather than inlined so a test can hold this to it —
    /// a fixture that quietly started writing to the real record would be the worst bug in
    /// this file, and the only one that could not be seen by looking at the canvas.
    static func databaseURL(id: String = UUID().uuidString) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-previews/\(id)/activity.db")
    }

    /// Fill a database that has nothing in it, when `REPLAY_SEED` asks.
    ///
    /// Only ever called with `REPLAY_DB` also set, and only when the record is empty — so it
    /// cannot add invented sessions to a database somebody has been keeping. Off unless asked
    /// for: a scratch record that fills itself would be a surprise, and the surprise would
    /// eventually happen to the wrong file.
    @MainActor
    static func seedIfRequested(_ model: AppModel) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["REPLAY_SEED"] != nil, environment["REPLAY_DB"] != nil else { return }
        guard model.timeline.isEmpty else { return }
        do {
            try seed(into: model.store)
            // See `model()`: the summaries the history reads from are built by the rollup, and
            // the one in `AppModel.init` ran before any of this existed.
            try model.store.rollupCompleteDays(now: Int64(Date().timeIntervalSince1970 * 1000))
            model.reload()
            FileHandle.standardError.write(Data("Replay: seeded a sample record.\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("Replay: could not seed — \(error)\n".utf8))
        }
    }
}
#endif
