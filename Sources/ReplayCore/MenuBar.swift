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

    public static var pausedLabel: String { Loc.t("Tracking paused") }
    public static var awayLabel: String { Loc.t("Away from keyboard") }
    public static var waitingLabel: String { Loc.t("Waiting for activity…") }
    public static var recentHeading: String { Loc.t("Recently") }

    /// How long you have been in the thing you are in.
    ///
    /// Under a minute this is "Just now" rather than "Focused for just now", which is what
    /// composing it out of ``shortDuration`` produced and is not a sentence anybody would
    /// say. Worth recording: this read fine as a standalone row in the menu this replaced,
    /// and only became wrong when it moved under an application's name in the popover — the
    /// copy did not change, the context did.
    public static func focusedFor(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 1 { return Loc.t("Just now") }
        return String(format: Loc.t("Focused for %@"), shortDuration(seconds))
    }

    /// The menu's own duration, which is not the app's.
    ///
    /// Under a minute this says "just now" where `formatDurationShort` says "<1m". Both are
    /// right for where they are: a figure in a table is scanned against other figures, and a
    /// menu pulled down mid-task is read as a sentence. "<1m" is a value you have to parse.
    public static func shortDuration(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 1 { return Loc.t("just now") }
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
        guard isRecording else { return Loc.t("Replay — paused") }
        guard let current else { return Loc.t("Replay — tracking") }
        return String(format: Loc.t("Replay — %@"), current)
    }

    // MARK: - The popover

    /// What the popover shows beyond the menu, decided here so it can be tested.
    ///
    /// The menu answered two questions — what am I in, what was I just in — and answered them
    /// well enough that this does not replace it so much as give it room. A menu can only hold
    /// rows of text; a popover can show the goal as a bar, a session with the icons of the
    /// applications that were in it, and a pause control you do not have to read.
    ///
    /// Nothing here is contract-checked. The reference has no menu bar at all — it runs inside
    /// the Glaze shell — so this whole surface is this port's own, like ``OwnSettingsRow`` and
    /// `Guide.ownEntries`. Which makes the discipline more important rather than less: the
    /// decisions live here where a test can reach them, and the view only lays them out.
    public enum Popover {

        /// How many recent sessions the popover lists.
        ///
        /// Three, and the ceiling is the point. This is read while you are in the middle of
        /// something else — the whole thing has to be taken in without scrolling, or it is a
        /// worse Timeline rather than a quicker one.
        public static let sessionLimit = 3

        public static var todayHeading: String { Loc.t("Today") }
        public static var recentHeading: String { Loc.t("Recent sessions") }
        public static var goalHeading: String { Loc.t("Focus goal") }
        public static var emptyToday: String { Loc.t("Nothing recorded yet today.") }

        /// The day's total, said the way a person would say it.
        public static func todayLine(activeSeconds: Int, sessions: Int) -> String {
            guard activeSeconds > 0 || sessions > 0 else { return emptyToday }
            let count = sessions == 1
                ? Loc.t("1 session")
                : String(format: Loc.t("%@ sessions"), "\(sessions)")
            return String(format: Loc.t("%1$@ active · %2$@"), shortDuration(activeSeconds), count)
        }

        /// The goal in one line: what is left, or that there is nothing left.
        ///
        /// "Goal reached" rather than a percentage over 100. The app describes and does not
        /// grade (SPEC §8), and a figure that keeps climbing past the target invites you to
        /// read a finished day as still not enough.
        public static func goalLine(activeSeconds: Int, goalMinutes: Int) -> String {
            let progress = Goals.progress(activeSeconds: activeSeconds, goalMinutes: goalMinutes)
            if progress.met {
                return String(format: Loc.t("Goal reached — %@"), shortDuration(activeSeconds))
            }
            return String(
                format: Loc.t("%1$@ to go of %2$@"),
                shortDuration(progress.remainingSeconds), Goals.format(goalMinutes)
            )
        }

        /// The most recent sessions, newest first.
        ///
        /// Newest first because the popover is read top-down and the last thing you did is the
        /// thing you are most likely asking about. The Timeline orders a day the other way, and
        /// that is right there and wrong here.
        public static func sessions(
            in sessions: [ActivitySession], limit: Int = sessionLimit
        ) -> [ActivitySession] {
            Array(sessions.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
        }

        /// The pause control's own label, which is a verb rather than a state.
        public static func trackingLabel(isRecording: Bool) -> String {
            isRecording ? Loc.t("Pause recording") : Loc.t("Resume recording")
        }
    }
}
