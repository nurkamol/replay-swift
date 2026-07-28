import AppIntents
import Foundation
import ReplayCore

/// Replay, asked a question from somewhere else.
///
/// Shortcuts, Spotlight and Siri, over the record this app already keeps. Everything here is
/// a *question* — nothing an intent can do changes anything, and that is deliberate rather
/// than a first step. A Shortcut runs unattended; an unattended thing that can delete a day
/// is a bad trade for any convenience it buys, and this app's whole claim is about keeping
/// a record rather than editing one.
///
/// The sentences come from ``Answers`` in `ReplayCore`, where they can be tested. What is
/// here is only the plumbing: parameters, titles, and the phrases Siri listens for.
///
/// **These run whether or not the app is open.** Each opens the database read-only, answers,
/// and closes it — no model, no tracker, nothing that assumes a window exists. SQLite takes
/// as many readers as you like alongside the writer, so asking a question while Replay is
/// recording is safe and needs no coordination.
private func openStore() throws -> ActivityStore {
    let store = ActivityStore(path: defaultDatabaseURL().path)
    try store.open()
    return store
}

private func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

/// "How long was I active today?"
struct TodayActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Today's Activity"
    static let description = IntentDescription(
        "How long you have been active today, and what most of it was.",
        categoryName: "Your day"
    )
    /// Answers without bringing the app forward. The point of asking from a Shortcut is not
    /// having to look at the app.
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = try openStore()
        let now = nowMillis()
        let day = try Answers.day(startOfLocalDay(now), store: store, now: now)
        return .result(value: day.sentence, dialog: IntentDialog(stringLiteral: day.sentence))
    }
}

/// "What did I do on Tuesday?"
struct DayActivityIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Activity for a Day"
    static let description = IntentDescription(
        """
        How long a given day held, and what most of it was. Reads the record Replay already \
        keeps; days it never saw are reported as such rather than as zero.
        """,
        categoryName: "Your day"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Date", kind: .date)
    var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Get activity for \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = try openStore()
        let day = try Answers.day(
            Int64(date.timeIntervalSince1970 * 1000), store: store, now: nowMillis()
        )
        return .result(value: day.sentence, dialog: IntentDialog(stringLiteral: day.sentence))
    }
}

/// "How long was I in Xcode today?"
struct ApplicationTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Time in an Application"
    static let description = IntentDescription(
        "How long one application had on a given day.",
        categoryName: "Your day"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Application")
    var application: String

    @Parameter(title: "Date", kind: .date)
    var date: Date

    static var parameterSummary: some ParameterSummary {
        Summary("Get time in \(\.$application) on \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = try openStore()
        let dayStart = Int64(date.timeIntervalSince1970 * 1000)
        let found = try Answers.application(
            named: application, on: dayStart, store: store, now: nowMillis()
        )
        // Says which day it looked at. "No record" without a date is the kind of answer
        // that sends somebody hunting for a bug that is really a wrong parameter.
        let sentence: String
        if let found {
            sentence = "\(formatDurationShort(found.seconds)) in \(found.name) "
                + "on \(fullDayLabel(startOfLocalDay(dayStart)))."
        } else {
            sentence = "No record of \(application) on "
                + "\(fullDayLabel(startOfLocalDay(dayStart)))."
        }
        return .result(value: sentence, dialog: IntentDialog(stringLiteral: sentence))
    }
}

/// The phrases Siri and Spotlight listen for.
///
/// `${applicationName}` is required in every phrase — the system will not accept a shortcut
/// that does not name its app — so each reads as something a person would actually say with
/// "Replay" in it, rather than a command with the app's name bolted on.
struct ReplayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayActivityIntent(),
            phrases: [
                "How long have I been active in \(.applicationName)",
                "What does \(.applicationName) say about today",
                "\(.applicationName) today",
            ],
            shortTitle: "Today's Activity",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: DayActivityIntent(),
            phrases: [
                "Get a day from \(.applicationName)",
                "What did \(.applicationName) record that day",
            ],
            shortTitle: "A Day's Activity",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: ApplicationTimeIntent(),
            phrases: [
                "How long was I in an app with \(.applicationName)",
                "Ask \(.applicationName) about an application",
            ],
            shortTitle: "Time in an Application",
            systemImageName: "app.badge"
        )
    }
}
