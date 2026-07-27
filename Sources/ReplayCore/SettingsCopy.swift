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
    case compactDatabase = "Compact database"

    public var label: String { rawValue }
}
