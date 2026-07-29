import Foundation
import Observation
import ReplayCore
import SwiftUI

/// An application the user has asked Replay never to record.
///
/// The name and path are stored beside the bundle id on purpose: excluding an app also
/// erases its history, which would otherwise remove it from "apps you have used" and leave
/// no way to find it again to un-exclude it. Keeping its identity here means an excluded
/// app stays visible in the picker even once every trace of its activity is gone.
struct ExcludedApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var appPath: String?

    var id: String { bundleID }
}

/// Which surface the window opens on.
enum LaunchSurface: String, CaseIterable, Identifiable, Codable {
    case today, timeline
    var id: String { rawValue }
    /// Through `Loc`, like every other label a person reads: these reach a `Picker` as a
    /// `String`, which is SwiftUI's non-localising overload.
    var label: String { Loc.t(self == .today ? "Today" : "Timeline") }
}

/// Which full-screen display drifts in after a spell of quiet.
///
/// The reference has both of these modes — `AmbientMode = "ambient" | "screensaver"` — but
/// its idle timer only ever raises the screensaver: `openAmbient("screensaver")` is written
/// into `useScreensaverAutoStart` with nothing to change it. This is the choice that was
/// missing, and the default is the reference's behaviour so nothing moves unless it is
/// asked to.
enum IdleDisplay: String, CaseIterable, Identifiable, Codable {
    case screensaver, ambient

    var id: String { rawValue }

    var label: String {
        switch self {
        case .screensaver: Loc.t("Screensaver")
        case .ambient: Loc.t("Ambient mode")
        }
    }

    /// The line under "Auto-start when idle", which depends on what it will start.
    ///
    /// The screensaver's is the reference's own sentence rather than a copy of it, so the
    /// contract keeps the two in step and the wording cannot drift here. The ambient one is
    /// this port's, written to the same shape because it describes the same delay.
    var idleExplanation: String {
        switch self {
        case .screensaver: SettingsRow.autoStartWhenIdle.explanation ?? ""
        case .ambient:
            "Drift ambient mode in after this long with no activity, while Replay is "
                + "focused. Any key or movement wakes it."
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { Loc.t(rawValue.capitalized) }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The colour the app is tinted with.
///
/// `system` is the default and means "whatever this Mac's accent colour is" — the honest
/// starting point, because an app that arrives with its own opinion about accent colour has
/// overridden a choice the person already made in System Settings. The named options exist
/// for the case that motivates this setting: wanting *this* app to look different from every
/// other one, which the system accent cannot express.
///
/// The palette is macOS's own accent set rather than an invented one, so the choices here
/// are the choices the Appearance pane offers and nothing looks foreign next to a standard
/// control.
enum ThemeColour: String, CaseIterable, Identifiable, Codable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite

    var id: String { rawValue }

    var label: String {
        Loc.t(self == .system ? "Match System" : rawValue.capitalized)
    }

    /// `nil` means "do not override", which is not the same as any particular colour: it is
    /// what lets the app follow the accent live when the system's own changes.
    var colour: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        // Not `.gray`: the system's Graphite is a near-neutral the controls are designed
        // against, and plain gray reads as a disabled control rather than as a choice.
        case .graphite: Color(nsColor: .systemGray)
        }
    }

    /// A concrete colour for the places that cannot take a style — a `Canvas` fills with a
    /// `Color`, not with `.tint`.
    var resolved: Color { colour ?? .accentColor }

    /// The swatch shown in the picker.
    var swatch: Color { self == .system ? .accentColor : resolved }
}

/// Settings that outlive a launch.
///
/// `UserDefaults` rather than the JSON file the reference keeps: the two apps do not share
/// preferences (they cannot — different containers, and the native app never touches the
/// Glaze database), and this is what a Mac app is expected to use. The *values* still match
/// the reference's defaults, which is what a user would notice.
@MainActor
@Observable
final class Preferences {
    var appearance: Appearance {
        didSet { write(appearance.rawValue, "appearance") }
    }

    /// What the app is tinted with. See ``ThemeColour``.
    var themeColour: ThemeColour {
        didSet { write(themeColour.rawValue, "themeColour") }
    }
    var launchSurface: LaunchSurface {
        didSet { write(launchSurface.rawValue, "launchSurface") }
    }
    /// How many days of raw activity to keep. `0` keeps everything — the default, because
    /// Replay never deletes history the user did not ask it to.
    var retentionDays: Int {
        didSet { write(retentionDays, "retentionDays") }
    }
    var excludedApps: [ExcludedApp] {
        didSet { writeJSON(excludedApps, "excludedApps") }
    }
    /// Live in the menu bar with no Dock icon. Off by default, as upstream.
    var menuBarOnly: Bool {
        didSet { write(menuBarOnly, "menuBarOnly") }
    }
    /// The surface the window was showing when it was last closed.
    ///
    /// Restored on launch unless the user has pinned an opening surface, because coming
    /// back to where you were is the behaviour a Mac app has — and the pinned choice is an
    /// explicit instruction that outranks it.
    var lastSurface: String {
        didSet { write(lastSurface, "lastSurface") }
    }

    /// A daily focus target in minutes, or `nil` for none.
    ///
    /// Off by default and opt-in on purpose: Replay describes the day, it does not set
    /// quotas — a goal exists only because its owner asked for one (SPEC §8).
    var focusGoalMinutes: Int? {
        didSet { write(focusGoalMinutes ?? 0, "focusGoalMinutes") }
    }

    /// The retention windows offered, from `spec/constants.json`.
    static let retentionOptions: [Int] = [0, 365, 180, 90]

    static func retentionLabel(_ days: Int) -> String {
        switch days {
        case 0: "Keep everything"
        case 365: "1 year"
        case 180: "6 months"
        case 90: "90 days"
        default: "\(days) days"
        }
    }

    /// Applications kept at the top of the Apps surface, in the order they were pinned.
    ///
    /// Bundle identifiers rather than names, so pinning survives a rename and two apps with
    /// the same display name stay apart.
    var pinnedApps: [String] {
        didSet { writeJSON(pinnedApps, "pinnedApps") }
    }

    func togglePinned(_ bundleID: String) {
        if let index = pinnedApps.firstIndex(of: bundleID) {
            pinnedApps.remove(at: index)
        } else {
            pinnedApps.append(bundleID)
        }
    }

    /// Queries kept for one-tap recall, newest first.
    var savedSearches: [String] {
        didSet { writeJSON(savedSearches, "savedSearches") }
    }

    /// A shortlist, not a history log — so recall stays something you read at a glance.
    static let maxSavedSearches = 12

    /// Save a query, or forget it if it is already saved.
    ///
    /// Matched case-insensitively so "Figma" and "figma" do not both pile up, but stored as
    /// typed: the list is read back, and a query lower-cased on the way in reads as a
    /// correction of something you wrote.
    func toggleSavedSearch(_ query: String) {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let without = savedSearches.filter { $0.lowercased() != value.lowercased() }
        savedSearches = without.count == savedSearches.count
            ? Array(([value] + without).prefix(Preferences.maxSavedSearches))
            : without
    }

    func isSaved(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !value.isEmpty && savedSearches.contains { $0.lowercased() == value }
    }

    /// The names given to projects, keyed by signature.
    ///
    /// The only thing about a project that is ever stored. Everything else is derived, so a
    /// project that stops recurring simply stops appearing — and its name waits here in case
    /// it comes back.
    var projectNames: [String: String] {
        didSet { writeJSON(projectNames, "projectNames") }
    }

    /// The names given to chapters, keyed by their first day.
    var chapterNames: [String: String] {
        didSet { writeJSON(chapterNames, "chapterNames") }
    }

    /// Whether Replay may surface a memory on Today at all. The master switch, on by
    /// default — the feature is the product, not an add-on.
    /// Whether Replay looks back at all: the memory card on Today, and Memories in the
    /// sidebar.
    ///
    /// Separate from ``contextualMemories`` because they are different offers. This one is
    /// *today in history* — the same date, earlier years — and it is either shown or it is
    /// not. The other is the quieter thing that speaks only when something becomes relevant.
    /// The reference keeps two switches; this port had one, and read the wrong one, so
    /// turning the quiet thing off silently removed today-in-history as well.
    var todayInHistory: Bool {
        didSet { write(todayInHistory, "todayInHistory") }
    }

    var contextualMemories: Bool {
        didSet { write(contextualMemories, "contextualMemories") }
    }

    /// How sure Replay has to be before it says anything. Higher means quieter.
    var memoryThreshold: Double {
        didSet { write(memoryThreshold, "memoryThreshold") }
    }

    /// Memories put away, by id.
    var dismissedMemories: [String] {
        didSet { writeJSON(dismissedMemories, "dismissedMemories") }
    }

    var archivedMemories: [String] {
        didSet { writeJSON(archivedMemories, "archivedMemories") }
    }

    /// Whether the morning briefing appears at all.
    var morningBriefing: Bool {
        didSet { write(morningBriefing, "morningBriefing") }
    }

    /// Days whose briefing has been put away, by local midnight.
    var dismissedBriefings: [String] {
        didSet { writeJSON(dismissedBriefings, "dismissedBriefings") }
    }

    /// What every surface is made of.
    var surfaceStyle: SurfaceStyle {
        didSet { write(surfaceStyle.rawValue, "surfaceStyle") }
    }

    /// Today's hours on the Dock icon, once there is an hour to show.
    var dockBadge: Bool {
        didSet { write(dockBadge, "dockBadge") }
    }

    /// How long the window must sit untouched before a display drifts in. Zero is off,
    /// and off is the default — a thing that takes over the screen on its own should be
    /// asked for.
    ///
    /// The key keeps the reference's name because it is the reference's setting, and because
    /// renaming it would silently forget the delay every existing install has chosen. What it
    /// starts is ``idleDisplay``.
    var screensaverIdleMinutes: Int {
        didSet { write(screensaverIdleMinutes, "screensaverIdleMinutes") }
    }

    /// Which of the two the delay above raises. See ``IdleDisplay``.
    var idleDisplay: IdleDisplay {
        didSet { write(idleDisplay.rawValue, "idleDisplay") }
    }

    /// Whether the drift is confined to a span of the day, and which span.
    ///
    /// Off by default: a delay somebody set is an answer to "when", and adding a second
    /// "when" they did not ask for would make the first one wrong. The hours are stored
    /// whether or not the limit is on, so turning it off and on again does not forget them.
    var idleHoursLimited: Bool {
        didSet { write(idleHoursLimited, "idleHoursLimited") }
    }

    var idleFromHour: Int {
        didSet { write(idleFromHour, "idleFromHour") }
    }

    var idleUntilHour: Int {
        didSet { write(idleUntilHour, "idleUntilHour") }
    }

    /// The screen the screensaver and ambient mode take, by its own name.
    ///
    /// Empty means "wherever the keyboard is", which is what the app did before this existed
    /// and stays the default. A name is kept even while that display is unplugged — the
    /// alternative is a setting that silently forgets what you asked for the moment you
    /// close the laptop.
    var displayScreenName: String {
        didSet { write(displayScreenName, "displayScreenName") }
    }

    /// How often Replay writes a full backup on its own, and where.
    ///
    /// Off with no folder until somebody chooses both. The path is stored as a plain path
    /// rather than a bookmark because this app is not sandboxed — see the note in
    /// ``AutoBackupModel``, which is where that will have to change if it ever is.
    var autoBackupCadence: AutoBackup.Cadence {
        didSet { write(autoBackupCadence.rawValue, "autoBackupCadence") }
    }

    var autoBackupFolder: String {
        didSet { write(autoBackupFolder, "autoBackupFolder") }
    }

    /// When the last unattended backup was written. Nil until one has been.
    var lastAutoBackup: Date? {
        didSet { defaults.set(lastAutoBackup, forKey: "lastAutoBackup") }
    }

    /// Whether ambient mode is a thing you leave up.
    ///
    /// Only takes effect when it opens on a screen other than the one Replay's window is on;
    /// see `showAmbient`. A display that covers the screen you are typing in and refuses to
    /// leave is not a feature.
    var ambientStaysOpen: Bool {
        didSet { write(ambientStaysOpen, "ambientStaysOpen") }
    }

    /// What dismisses it. Escape and the close button always do, whatever these say.
    var screensaverExitOnMouseMove: Bool {
        didSet { write(screensaverExitOnMouseMove, "screensaverExitOnMouseMove") }
    }

    var screensaverExitOnClick: Bool {
        didSet { write(screensaverExitOnClick, "screensaverExitOnClick") }
    }

    var screensaverExitOnKey: Bool {
        didSet { write(screensaverExitOnKey, "screensaverExitOnKey") }
    }

    /// What ambient mode shows. All three on to begin with, because a display you have to
    /// configure before it says anything is not a display.
    ///
    /// These have no counterpart upstream — the reference's ambient mode has no settings —
    /// which is why they are `OwnSettingsRow` rather than `SettingsRow`. Two of them are
    /// there for one reason: an ambient screen is often a *second* screen, and a second
    /// screen is often one other people can see. What you are working on is the part you
    /// might not want on it.
    var screensaverClock: Bool {
        didSet { write(screensaverClock, "screensaverClock") }
    }

    var ambientClock: Bool {
        didSet { write(ambientClock, "ambientClock") }
    }

    var ambientCurrentApp: Bool {
        didSet { write(ambientCurrentApp, "ambientCurrentApp") }
    }

    var ambientCurrentSession: Bool {
        didSet { write(ambientCurrentSession, "ambientCurrentSession") }
    }

    /// The one moving thing in ambient mode.
    ///
    /// On by default, and the reference's own — but a switch because this is a surface made
    /// for the corner of your eye, and peripheral vision is *more* sensitive to motion than
    /// central vision, not less. A 4% swell is nothing at minute one and can be a small
    /// irritation at hour three, and which of those you are is not something a default can
    /// know. Reduce Motion still wins over it either way.
    /// Whether Replay asks GitHub, once a day, if a newer version exists.
    ///
    /// **Off, and it stays off until somebody turns it on.** This is the only setting in the
    /// app that causes a network request, and the app's whole claim is that nothing leaves
    /// the Mac — so it defaults to the state that keeps that true, and the Settings row says
    /// in as many words what a check sends.
    var checkForUpdates: Bool {
        didSet { write(checkForUpdates, "checkForUpdates") }
    }

    /// When it last asked, so it asks once a day rather than once a launch.
    var lastUpdateCheck: Date? {
        didSet { defaults.set(lastUpdateCheck, forKey: "lastUpdateCheck") }
    }

    /// A version the user waved away. The offer returns when a newer one appears.
    var skippedUpdate: String? {
        didSet { defaults.set(skippedUpdate, forKey: "skippedUpdate") }
    }

    /// The `ETag` GitHub gave with the last successful check.
    ///
    /// Sent back as `If-None-Match`, which turns an unchanged answer into a `304` carrying no
    /// body — so the check moves bytes only on the day something actually changed.
    ///
    /// **It does not save rate limit, and the comment here used to say it did.** GitHub
    /// documents 304s as exempt, and on this *unauthenticated* endpoint they are not:
    /// measured, three requests decremented `x-ratelimit-remaining` three times whether they
    /// answered 304 or 200 (`docs/FINDINGS.md`). What reduces requests is not asking —
    /// `lastUpdateCheck` and ``updateRetryAfter``.
    var updateETag: String? {
        didSet { defaults.set(updateETag, forKey: "updateETag") }
    }

    /// The release that `ETag` belongs to, so a `304` has something to answer with.
    ///
    /// Encoded rather than kept in memory: a 304 on the first check after a launch would
    /// otherwise leave the app knowing nothing, and an update that exists would go unmentioned
    /// until something changed again.
    var lastSeenRelease: Updates.Release? {
        didSet { writeJSON(lastSeenRelease, "lastSeenRelease") }
    }

    /// The language the interface is read in, or empty for whatever the Mac is set to.
    ///
    /// Empty is the default and stays the default: following the system is the behaviour
    /// somebody already chose once, in System Settings. This exists for the case the system
    /// cannot express — reading an app in a language your Mac is not in.
    var languageCode: String {
        didSet {
            write(languageCode, "languageCode")
            Loc.override = languageCode.isEmpty ? nil : languageCode
        }
    }

    /// When a timed pause ends, or nil when recording — or paused with no end.
    ///
    /// Persisted because a pause with a stated end has to outlive a quit to mean anything:
    /// "until tomorrow" is a promise about tomorrow, not about this process. An *indefinite*
    /// pause is deliberately not stored — see ``Pause/stillPaused(until:now:)``.
    var pausedUntil: Date? {
        didSet { defaults.set(pausedUntil, forKey: "pausedUntil") }
    }

    /// A report on a schedule: how often, where, in what, and when the last one went.
    ///
    /// Off with no folder until both are chosen, exactly like the backup beside it.
    var reportCadence: AutoBackup.Cadence {
        didSet { write(reportCadence.rawValue, "reportCadence") }
    }

    var reportFolder: String {
        didSet { write(reportFolder, "reportFolder") }
    }

    var reportFormat: Report.Format {
        didSet { write(reportFormat.rawValue, "reportFormat") }
    }

    var lastReport: Date? {
        didSet { defaults.set(lastReport, forKey: "lastReport") }
    }

    /// The version that ran last time, so a launch can tell it is a new one.
    ///
    /// Written on every launch, which makes this true for *any* way the bundle changed —
    /// the in-app updater, `brew upgrade`, or somebody dragging a new copy into place. The
    /// updater's own flag below is what separates the case where a person is waiting for an
    /// answer from the case where the app simply came back different.
    var lastRunVersion: String {
        didSet { write(lastRunVersion, "lastRunVersion") }
    }

    /// Set the instant before the updater restarts the app, and cleared the moment the new
    /// launch has read it. It is the only thing that survives the process boundary between
    /// "I pressed Update" and "here is what you got".
    var selfUpdated: Bool {
        didSet { write(selfUpdated, "selfUpdated") }
    }

    /// When the rate-limit window GitHub named reopens, from `x-ratelimit-reset`.
    ///
    /// Nil unless the last reply was a refusal. It only ever delays a check — see
    /// `Updates.shouldCheck` — because a limit that could bring a check *forward* would be a
    /// way to ask more often by asking too often.
    var updateRetryAfter: Date? {
        didSet { defaults.set(updateRetryAfter, forKey: "updateRetryAfter") }
    }

    var ambientBreath: Bool {
        didSet { write(ambientBreath, "ambientBreath") }
    }

    /// A recap of the day, at an hour of your choosing. Off until asked for, and asking is
    /// what prompts macOS for permission — nothing is requested before then.
    var dailySummaryHour: Int {
        didSet { write(dailySummaryHour, "dailySummaryHour") }
    }

    var dailySummary: Bool {
        didSet { write(dailySummary, "dailySummary") }
    }

    var weeklyRecap: Bool {
        didSet { write(weeklyRecap, "weeklyRecap") }
    }

    var onThisDayNotice: Bool {
        didSet { write(onThisDayNotice, "onThisDayNotice") }
    }

    /// Whether the welcome has been through once. Settings can put it back.
    var seenWelcome: Bool {
        didSet { write(seenWelcome, "seenWelcome") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = (defaults.string(forKey: "appearance").flatMap(Appearance.init)) ?? .system
        themeColour = (defaults.string(forKey: "themeColour").flatMap(ThemeColour.init)) ?? .system
        // Glass by default, because that is what the system does now.
        surfaceStyle = (defaults.string(forKey: "surfaceStyle")
            .flatMap(SurfaceStyle.init)) ?? .glass
        launchSurface = (defaults.string(forKey: "launchSurface").flatMap(LaunchSurface.init)) ?? .today
        // On by default, as upstream. Looking back is what the app is for; the setting exists
        // to turn it off, not to ask permission for it.
        todayInHistory = defaults.object(forKey: "todayInHistory") as? Bool ?? true
        retentionDays = defaults.integer(forKey: "retentionDays")
        excludedApps = (defaults.data(forKey: "excludedApps"))
            .flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
        menuBarOnly = defaults.bool(forKey: "menuBarOnly")
        dockBadge = defaults.object(forKey: "dockBadge") as? Bool ?? false
        seenWelcome = defaults.bool(forKey: "seenWelcome")
        screensaverIdleMinutes = defaults.integer(forKey: "screensaverIdleMinutes")
        // The screensaver unless somebody says otherwise, which is what the reference does
        // with the same delay.
        idleDisplay = (defaults.string(forKey: "idleDisplay").flatMap(IdleDisplay.init))
            ?? .screensaver
        idleHoursLimited = defaults.bool(forKey: "idleHoursLimited")
        // Nine to six when nothing has been chosen — a span somebody would actually pick,
        // so switching the limit on does something sensible before it is adjusted. Zero and
        // absent are indistinguishable in `UserDefaults`, and midnight is a real hour, so
        // the pair is read as "set" only once the limit itself has been.
        let storedFrom = defaults.object(forKey: "idleFromHour") as? Int
        let storedUntil = defaults.object(forKey: "idleUntilHour") as? Int
        idleFromHour = storedFrom ?? 9
        idleUntilHour = storedUntil ?? 18
        displayScreenName = defaults.string(forKey: "displayScreenName") ?? ""
        ambientStaysOpen = defaults.bool(forKey: "ambientStaysOpen")
        autoBackupCadence = (defaults.string(forKey: "autoBackupCadence")
            .flatMap(AutoBackup.Cadence.init)) ?? .off
        autoBackupFolder = defaults.string(forKey: "autoBackupFolder") ?? ""
        lastAutoBackup = defaults.object(forKey: "lastAutoBackup") as? Date
        // Mouse movement is off by default, so a screensaver you started by hand stays until
        // you reach for it rather than vanishing when the pointer twitches.
        screensaverExitOnMouseMove = defaults.bool(forKey: "screensaverExitOnMouseMove")
        screensaverExitOnClick = defaults.object(forKey: "screensaverExitOnClick") as? Bool ?? true
        screensaverExitOnKey = defaults.object(forKey: "screensaverExitOnKey") as? Bool ?? true
        screensaverClock = defaults.object(forKey: "screensaverClock") as? Bool ?? true
        ambientClock = defaults.object(forKey: "ambientClock") as? Bool ?? true
        ambientCurrentApp = defaults.object(forKey: "ambientCurrentApp") as? Bool ?? true
        ambientCurrentSession = defaults.object(forKey: "ambientCurrentSession") as? Bool ?? true
        ambientBreath = defaults.object(forKey: "ambientBreath") as? Bool ?? true
        checkForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? false
        lastUpdateCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
        skippedUpdate = defaults.string(forKey: "skippedUpdate")
        updateETag = defaults.string(forKey: "updateETag")
        lastSeenRelease = (defaults.data(forKey: "lastSeenRelease"))
            .flatMap { try? JSONDecoder().decode(Updates.Release.self, from: $0) }
        updateRetryAfter = defaults.object(forKey: "updateRetryAfter") as? Date
        reportCadence = (defaults.string(forKey: "reportCadence")
            .flatMap(AutoBackup.Cadence.init)) ?? .off
        reportFolder = defaults.string(forKey: "reportFolder") ?? ""
        reportFormat = (defaults.string(forKey: "reportFormat")
            .flatMap(Report.Format.init)) ?? .markdown
        lastReport = defaults.object(forKey: "lastReport") as? Date
        languageCode = defaults.string(forKey: "languageCode") ?? ""
        pausedUntil = defaults.object(forKey: "pausedUntil") as? Date
        lastRunVersion = defaults.string(forKey: "lastRunVersion") ?? ""
        selfUpdated = defaults.bool(forKey: "selfUpdated")
        let hour = defaults.integer(forKey: "dailySummaryHour")
        dailySummaryHour = hour == 0 ? 18 : hour
        dailySummary = defaults.bool(forKey: "dailySummary")
        weeklyRecap = defaults.bool(forKey: "weeklyRecap")
        onThisDayNotice = defaults.bool(forKey: "onThisDayNotice")
        pinnedApps = (defaults.data(forKey: "pinnedApps"))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        savedSearches = (defaults.data(forKey: "savedSearches"))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        projectNames = (defaults.data(forKey: "projectNames"))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        chapterNames = (defaults.data(forKey: "chapterNames"))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        // Absent means on: a fresh install should have the feature, not have to find it.
        contextualMemories = defaults.object(forKey: "contextualMemories") as? Bool ?? true
        morningBriefing = defaults.object(forKey: "morningBriefing") as? Bool ?? true
        dismissedBriefings = (defaults.data(forKey: "dismissedBriefings"))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        // Balanced by default. Zero and absent both mean "never set", which is not the same
        // as "show me everything".
        let threshold = defaults.double(forKey: "memoryThreshold")
        memoryThreshold = threshold > 0 ? threshold : 0.55
        dismissedMemories = (defaults.data(forKey: "dismissedMemories"))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        archivedMemories = (defaults.data(forKey: "archivedMemories"))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        lastSurface = defaults.string(forKey: "lastSurface") ?? ""
        // Zero and absent both mean "no goal", so an unset default reads as off.
        let goal = defaults.integer(forKey: "focusGoalMinutes")
        focusGoalMinutes = goal > 0 ? goal : nil

        // After every stored property exists, because this reaches outside `self` — and the
        // chosen language has to be in force before the first view asks for a word.
        Loc.override = languageCode.isEmpty ? nil : languageCode
    }

    var excludedBundleIDs: Set<String> { Set(excludedApps.map(\.bundleID)) }


    /// Every key this type persists, so a reset removes exactly those and no others.
    private static let ownKeys = [
        "appearance",
        "archivedMemories",
        "chapterNames",
        "contextualMemories",
        "dailySummary",
        "dailySummaryHour",
        "dismissedBriefings",
        "dismissedMemories",
        "dockBadge",
        "excludedApps",
        "focusGoalMinutes",
        "lastSurface",
        "launchSurface",
        "memoryThreshold",
        "menuBarOnly",
        "morningBriefing",
        "onThisDayNotice",
        "pinnedApps",
        "projectNames",
        "retentionDays",
        "savedSearches",
        "screensaverExitOnClick",
        "screensaverExitOnKey",
        "screensaverClock",
        "ambientClock",
        "ambientCurrentApp",
        "ambientCurrentSession",
        "ambientBreath",
        "checkForUpdates",
        "lastUpdateCheck",
        "skippedUpdate",
        "updateETag",
        "lastSeenRelease",
        "updateRetryAfter",
        "reportCadence",
        "reportFolder",
        "reportFormat",
        "lastReport",
        "languageCode",
        "pausedUntil",
        "lastRunVersion",
        "selfUpdated",
        "screensaverExitOnMouseMove",
        "screensaverIdleMinutes",
        "idleDisplay",
        "idleHoursLimited",
        "idleFromHour",
        "idleUntilHour",
        "displayScreenName",
        "ambientStaysOpen",
        "autoBackupCadence",
        "autoBackupFolder",
        "lastAutoBackup",
        "seenWelcome",
        "surfaceStyle",
        "themeColour",
        "todayInHistory",
        "weeklyRecap",
    ]

    /// Back to a first run: every stored preference forgotten and re-read at its default.
    ///
    /// Key by key rather than `removePersistentDomain`, which would also take what
    /// `UserDefaults` keeps on the app's behalf — window frames, split positions, the things
    /// nobody thinks of as settings and nobody asked to lose.
    ///
    /// The values are copied from a freshly built instance rather than restated here, so the
    /// defaults live in exactly one place: this cannot drift from `init`, because it *is*
    /// `init`.
    func reset() {
        for key in Self.ownKeys { defaults.removeObject(forKey: key) }
        let fresh = Preferences(defaults: defaults)
        appearance = fresh.appearance
        themeColour = fresh.themeColour
        launchSurface = fresh.launchSurface
        retentionDays = fresh.retentionDays
        excludedApps = fresh.excludedApps
        menuBarOnly = fresh.menuBarOnly
        lastSurface = fresh.lastSurface
        focusGoalMinutes = fresh.focusGoalMinutes
        pinnedApps = fresh.pinnedApps
        savedSearches = fresh.savedSearches
        projectNames = fresh.projectNames
        chapterNames = fresh.chapterNames
        todayInHistory = fresh.todayInHistory
        contextualMemories = fresh.contextualMemories
        memoryThreshold = fresh.memoryThreshold
        dismissedMemories = fresh.dismissedMemories
        archivedMemories = fresh.archivedMemories
        morningBriefing = fresh.morningBriefing
        dismissedBriefings = fresh.dismissedBriefings
        surfaceStyle = fresh.surfaceStyle
        dockBadge = fresh.dockBadge
        screensaverIdleMinutes = fresh.screensaverIdleMinutes
        idleDisplay = fresh.idleDisplay
        idleHoursLimited = fresh.idleHoursLimited
        idleFromHour = fresh.idleFromHour
        idleUntilHour = fresh.idleUntilHour
        displayScreenName = fresh.displayScreenName
        ambientStaysOpen = fresh.ambientStaysOpen
        autoBackupCadence = fresh.autoBackupCadence
        autoBackupFolder = fresh.autoBackupFolder
        lastAutoBackup = fresh.lastAutoBackup
        screensaverExitOnMouseMove = fresh.screensaverExitOnMouseMove
        screensaverExitOnClick = fresh.screensaverExitOnClick
        screensaverExitOnKey = fresh.screensaverExitOnKey
        screensaverClock = fresh.screensaverClock
        ambientClock = fresh.ambientClock
        ambientCurrentApp = fresh.ambientCurrentApp
        ambientCurrentSession = fresh.ambientCurrentSession
        ambientBreath = fresh.ambientBreath
        checkForUpdates = fresh.checkForUpdates
        lastUpdateCheck = fresh.lastUpdateCheck
        skippedUpdate = fresh.skippedUpdate
        updateETag = fresh.updateETag
        lastSeenRelease = fresh.lastSeenRelease
        updateRetryAfter = fresh.updateRetryAfter
        reportCadence = fresh.reportCadence
        reportFolder = fresh.reportFolder
        reportFormat = fresh.reportFormat
        lastReport = fresh.lastReport
        languageCode = fresh.languageCode
        pausedUntil = fresh.pausedUntil
        lastRunVersion = fresh.lastRunVersion
        selfUpdated = fresh.selfUpdated
        dailySummaryHour = fresh.dailySummaryHour
        dailySummary = fresh.dailySummary
        weeklyRecap = fresh.weeklyRecap
        onThisDayNotice = fresh.onThisDayNotice
        seenWelcome = fresh.seenWelcome
    }

    private func write(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func writeJSON<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
