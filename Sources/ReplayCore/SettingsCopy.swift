import Foundation

/// The name on a Settings row, as the reference names it.
///
/// Words a person reads, so the same argument as the Guide: `spec/settings-copy.json` carries
/// the reference's own labels and the suite compares these against it. This port had drifted
/// on eight of them — "Appearance" for "Theme", "Open on" for "Open to", "Menu bar only" for
/// "Menu bar mode", "Daily recap" for "Daily summary" — each a reasonable word, none of them
/// the reference's, and nothing able to notice.
///
/// One of them was worse than a synonym: this port used "How sure Replay must be" as the
/// *label* of the confidence control, which upstream uses as its **description**. The row was
/// named after its own explanation.
///
/// Only the rows this port has. The contract carries all 36; the difference between the two
/// is the list of what is still missing, and `docs/BACKLOG.md` keeps it.
public enum SettingsRow: String, CaseIterable, Sendable {
    case theme = "Theme"
    case openTo = "Open to"
    case menuBarMode = "Menu bar mode"
    case dockBadge = "Dock badge"
    case welcomeScreen = "Welcome screen"
    case dailyFocus = "Daily focus"
    case customTarget = "Custom target"
    case todayInHistory = "Today in History"
    case surfaceMemories = "Surface memories"
    case howOftenToSpeak = "How often to speak"
    case morningBriefing = "Morning briefing"
    case autoStartWhenIdle = "Auto-start when idle"
    case exitOnMouseMovement = "Exit on mouse movement"
    case exitOnClick = "Exit on click"
    case exitOnKeyPress = "Exit on key press"
    case dailySummary = "Daily summary"
    case weeklyRecap = "Weekly recap"
    case onThisDay = "On this day"
    case tracked = "Tracked"
    case excluded = "Excluded"
    case events = "Events"
    case onDisk = "On disk"
    case activityTracking = "Activity tracking"
    case excludedApplications = "Excluded applications"
    case activityHistory = "Activity history"
    case fullBackup = "Full backup"
    case keepActivityFor = "Keep activity for"
    case deleteASingleDay = "Delete a single day"
    case resetReplay = "Reset Replay"
    case compactDatabase = "Compact database"

    public var label: String { rawValue }

    /// The line under the row, as the reference writes it. `nil` where it has none —
    /// the readouts on the Privacy tab are figures rather than settings, and a figure that
    /// needs explaining is the wrong figure.
    public var explanation: String? {
        switch self {
        case .theme: "Match the system or lock to a single appearance."
        case .openTo: "The view Replay shows when the window opens."
        case .menuBarMode: "Hide the Dock icon and keep Replay running in the menu bar."
        case .dockBadge:
            "Show today's active hours on the Dock icon. Appears once you've "
                + "been active an hour."
        case .welcomeScreen: "Show the introduction again in the main window."
        case .dailyFocus: "How much focused time you're aiming for each day."
        case .customTarget: nil
        case .todayInHistory:
            "Show the memory card on Today, and the Memories view in the "
                + "sidebar."
        case .surfaceMemories:
            "Show the occasional inline memory on Today when the moment fits. "
                + "Each one can be dismissed."
        case .howOftenToSpeak:
            "How sure Replay must be before surfacing a memory. Higher means "
                + "rarer, but only when it truly matters."
        case .morningBriefing:
            "A calm look back at yesterday when you open Replay in the morning "
                + "— and one memory to carry into today."
        case .autoStartWhenIdle:
            "Drift the screensaver in after this long with no activity, while "
                + "Replay is focused. Any key or movement wakes it."
        case .exitOnMouseMovement:
            "Dismiss the screensaver when the pointer moves. Off by default, so "
                + "a hand-started screensaver stays until you reach for it."
        case .exitOnClick: "Dismiss the screensaver on a mouse click or tap."
        case .exitOnKeyPress:
            "Dismiss the screensaver on any key. Esc and the ✕ always close it, "
                + "whatever these are set to."
        case .dailySummary: "A recap of the day's focus, delivered at the time you choose."
        case .weeklyRecap: "A look back every Sunday evening at the week just gone."
        case .onThisDay:
            "A once-a-day reminder of what you were doing on this date in the "
                + "past."
        case .tracked: nil
        case .excluded: nil
        case .events: nil
        case .onDisk:
            "Replay reads which app is frontmost through macOS’s standard "
                + "signal — it needs no Accessibility, Automation, or App Management "
                + "permission to do it, and never looks inside your windows. The "
                + "links are only for verifying, or a locked-down Mac."
        case .activityTracking: "Observe which apps you use to build your private timeline."
        case .excludedApplications:
            "Choose apps Replay should never record. Excluding one also removes "
                + "its history."
        case .activityHistory: "Permanently delete every event Replay has recorded on this Mac."
        case .fullBackup:
            "Export the entire database as JSON, or import one — importing "
                + "merges, never overwrites."
        case .keepActivityFor:
            "Older raw events are removed past this window. Keeping everything "
                + "never deletes a thing; your day-by-day headlines are kept either "
                + "way, so history and streaks survive."
        case .deleteASingleDay:
            "Takes that day's sessions, summary, reflection, and any notes or "
                + "bookmarks with it, and leaves every other day untouched. Any day "
                + "can also be deleted — or exported on its own — from the ⋯ menu on "
                + "its divider in the Timeline."
        case .resetReplay:
            "Deletes all activity, settings, and preferences, then returns to "
                + "the welcome screen."
        case .compactDatabase:
            "There is no undo — export a backup first if you want to keep your "
                + "timeline."
        }
    }
}
