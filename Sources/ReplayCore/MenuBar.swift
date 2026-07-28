import Foundation

/// The menu bar item, which answers two questions and no others.
///
/// The reference's own framing: *what am I in right now, and what was I just in.* This port
/// answered neither — it showed the day's total, its session count and its top application,
/// which are all things the window is for. A menu you pull down mid-task wants the last few
/// seconds, not the last few hours.
///
/// A surface that was never audited, because the list of eleven was built from the
/// reference's *router* and a status item has no route. Worth remembering: a route count
/// misses anything that is not a page.
public enum MenuBar {

    /// How many applications the recent list names. Deliberately few — the reference's word.
    public static let recentLimit = 4
    /// How far back it looks for them.
    public static let recentHours = 12

    /// The glyph, and it is load-bearing.
    ///
    /// **Not `clock.arrow.circlepath`.** In the menu bar that is Time Machine's icon, so a
    /// status item using it reads as a system backup service — confusing, and against the
    /// HIG. The reference says exactly this in a comment, and this port used that glyph
    /// anyway for months. A bar chart says "usage" and echoes the day arc on the summary
    /// card.
    public static let symbol = "chart.bar.xaxis"

    // MARK: - What is happening right now

    public enum Now: Equatable, Sendable {
        case paused
        case away
        /// In an application, and for how long.
        case inApplication(name: String, seconds: Int)
        /// Recording, but nothing has come through yet.
        case waiting
    }

    /// The four states, in the order the reference tests them.
    ///
    /// Order is the whole logic: paused beats away, away beats whatever the tracker last
    /// saw. Getting it the other way round would name an application you walked away from
    /// twenty minutes ago as the thing you are doing.
    public static func now(
        isRecording: Bool,
        isAway: Bool,
        current: (applicationName: String, startedAt: Int64)?,
        now: Int64
    ) -> Now {
        if !isRecording { return .paused }
        if isAway { return .away }
        guard let current else { return .waiting }
        let seconds = Int(((Double(now - current.startedAt)) / 1000).rounded())
        return .inApplication(name: current.applicationName, seconds: max(0, seconds))
    }

    public static let pausedLabel = "Tracking paused"
    public static let awayLabel = "Away from keyboard"
    public static let waitingLabel = "Waiting for activity…"
    public static let recentHeading = "Recently"

    /// How long you have been in the thing you are in.
    public static func focusedFor(_ seconds: Int) -> String {
        "Focused for \(shortDuration(seconds))"
    }

    /// The menu's own duration, which is not the app's.
    ///
    /// Under a minute this says "just now" where `formatDurationShort` says "<1m". Both are
    /// right for where they are: a figure in a table is scanned against other figures, and a
    /// menu pulled down mid-task is read as a sentence. "<1m" is a value you have to parse.
    public static func shortDuration(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    // MARK: - What you were just in

    /// The applications used most recently, most recent first.
    ///
    /// **Distinct applications, not distinct visits.** You bounce back to the same editor a
    /// dozen times an hour, and a list that repeats it is a switch log rather than an answer
    /// to "what was I just doing". The one you are in now is excluded for the same reason —
    /// it is already the line above.
    ///
    /// Read from the recorded rows rather than from a list kept in memory, so the menu
    /// cannot drift from what was actually written down.
    public static func recentApplications(
        in events: [ActivityEvent], excluding current: String?, limit: Int = recentLimit
    ) -> [String] {
        var seen = Set<String>()
        if let current { seen.insert(current) }
        var recent: [String] = []
        for event in events.reversed() where recent.count < limit {
            guard event.type == .activated else { continue }
            guard !seen.contains(event.applicationName) else { continue }
            seen.insert(event.applicationName)
            recent.append(event.applicationName)
        }
        return recent
    }

    // MARK: - The tooltip

    public static func tooltip(isRecording: Bool, current: String?) -> String {
        guard isRecording else { return "Replay — paused" }
        guard let current else { return "Replay — tracking" }
        return "Replay — \(current)"
    }
}
