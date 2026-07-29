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

    /// The row's name, translated.
    ///
    /// **Translated here rather than at the call sites, and that is the fix for a whole class
    /// of miss.** These labels reach a `Picker` or a `Toggle` as a `String`, which selects
    /// SwiftUI's *non-localising* overload — so every one of the thirty-nine rows in Settings
    /// showed its English name while the explanation underneath it, which goes through
    /// `Loc.t`, was translated. One row of a translated app in English is a bug; a column of
    /// them beside translated prose is the app looking broken.
    ///
    /// ``base`` is what the contract compares — the reference's own wording, whatever the
    /// reader's language — and the parity suite uses that, so this cannot make 200 checks fail
    /// on a translated machine.
    public var label: String { Loc.t(rawValue) }

    /// The label as the reference writes it, for the contract rather than for a person.
    public var base: String { rawValue }

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

/// Settings rows this port has and the reference does not.
///
/// A deliberately separate list from ``SettingsRow``, and the parity suite checks it in the
/// *opposite* direction: every `SettingsRow` label must exist upstream, and every one of
/// these must **not**. That way an addition here can never quietly shadow a row the
/// reference already has a word for, and if upstream ever ships a setting by one of these
/// names the suite says so rather than letting the two meanings drift apart under one label.
///
/// Ambient mode upstream has no settings at all — it shows what it shows — and two of these
/// exist for a reason that only applies to a native app on a desk: an ambient screen is
/// usually a *second* screen, and a second screen is often one other people can see.
///
/// ``idleDisplay`` is the one that changes what an existing reference setting *means*.
/// Upstream, `screensaverIdleMinutes` starts the screensaver and nothing else —
/// `renderer/main/ambient.tsx` hard-codes `openAmbient("screensaver")` — so this row is the
/// switch that lets the same delay raise ambient mode instead. It defaults to the
/// screensaver, which is the reference's behaviour, so the divergence exists only for
/// somebody who asked for it.
/// The raw value is a *key*, not the label — unlike ``SettingsRow``, where the raw value is
/// the reference's own wording and that is the point. Here two rows are legitimately called
/// the same thing: the screensaver and ambient mode each offer to show the time, in their own
/// section, and "Show the time (ambient)" would be a label written for a programmer.
public enum OwnSettingsRow: String, CaseIterable, Sendable {
    case language
    case idleDisplay
    case idleHours
    case displayScreen
    case ambientStaysOpen
    case automaticBackup
    case backupFolder
    case screensaverClock
    case ambientClock
    case ambientCurrentApp
    case ambientCurrentSession
    case ambientBreath
    case checkForUpdates

    public var label: String { Loc.t(base) }

    /// The English, for the parity suite — these must *not* exist upstream, and that check
    /// has to compare English against English however the reader's Mac is set.
    public var base: String {
        switch self {
        case .language: "Language"
        case .idleDisplay: "When idle, show"
        case .idleHours: "Only at certain hours"
        case .displayScreen: "Show on"
        case .ambientStaysOpen: "Leave it open while you work"
        case .automaticBackup: "Automatic backup"
        case .backupFolder: "Backup folder"
        case .screensaverClock, .ambientClock: "Show the time"
        case .ambientCurrentApp: "Show the current application"
        case .ambientCurrentSession: "Show the current session"
        case .ambientBreath: "Gentle motion"
        case .checkForUpdates: "Check for updates"
        }
    }

    public var explanation: String {
        switch self {
        case .language:
            "Read Replay in a language your Mac is not set to. Anything this build has not "
                + "been translated into stays in English rather than showing you a key."
        case .idleDisplay:
            "Which of the two takes the screen when the delay below runs out. The "
                + "screensaver drifts through the day you have had; ambient mode holds "
                + "today's total still, in type you can read from across the room."
        case .idleHours:
            "Keep the drift to a span of the day — an evening, or the hours you are at "
                + "this desk. Outside it nothing starts on its own, and both can still be "
                + "opened by hand."
        case .displayScreen:
            "Which screen the screensaver and ambient mode take. Replay follows the "
                + "keyboard unless you name one; a named screen that is unplugged falls "
                + "back to the keyboard's and is remembered for when it returns."
        case .ambientStaysOpen:
            "Keep ambient mode up while you carry on working, instead of it closing the "
                + "moment you touch the keyboard. It takes the whole screen it is on, so "
                + "this only applies when that is a screen other than the one Replay's "
                + "window is on — otherwise there would be nothing to work in."
        case .automaticBackup:
            "Write the same full backup on a schedule, without being asked. Nothing leaves "
                + "this Mac — it is a file in a folder you choose, and Replay keeps the "
                + "eight most recent and removes its own older ones."
        case .backupFolder:
            "Where those copies go. Somewhere that is itself backed up is the point: a "
                + "second copy on the same disk survives a mistake, not a failure."
        case .screensaverClock:
            "A quiet clock in the corner. The one thing you are likely to want from a "
                + "screen you are walking past."
        case .ambientClock:
            "A clock above the day's total, for a screen you glance at rather than sit in "
                + "front of."
        case .ambientCurrentApp:
            "The application you are in right now, with its icon. Turn it off for a screen "
                + "other people can see."
        case .ambientCurrentSession:
            "What Replay is calling this stretch of work, and when it began."
        case .ambientBreath:
            "A slow swell on the application's icon, so a screen of live figures does not "
                + "read as a still picture of one. Off leaves ambient mode completely "
                + "still. Reduce Motion turns it off either way."
        case .checkForUpdates:
            "Once a day, ask GitHub whether a newer Replay exists. This is the only thing "
                + "in the app that uses the network, and it sends nothing about you or your "
                + "record — the same request as opening the releases page in a browser. "
                + "Nothing is downloaded or installed; you are told, and you decide."
        }
    }
}
