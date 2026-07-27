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
    var label: String { self == .today ? "Today" : "Timeline" }
}

enum Appearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
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

    /// How long the window must sit untouched before the screensaver drifts in. Zero is off,
    /// and off is the default — a thing that takes over the screen on its own should be
    /// asked for.
    var screensaverIdleMinutes: Int {
        didSet { write(screensaverIdleMinutes, "screensaverIdleMinutes") }
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
        // Glass by default, because that is what the system does now.
        surfaceStyle = (defaults.string(forKey: "surfaceStyle")
            .flatMap(SurfaceStyle.init)) ?? .glass
        launchSurface = (defaults.string(forKey: "launchSurface").flatMap(LaunchSurface.init)) ?? .today
        retentionDays = defaults.integer(forKey: "retentionDays")
        excludedApps = (defaults.data(forKey: "excludedApps"))
            .flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
        menuBarOnly = defaults.bool(forKey: "menuBarOnly")
        dockBadge = defaults.object(forKey: "dockBadge") as? Bool ?? false
        seenWelcome = defaults.bool(forKey: "seenWelcome")
        screensaverIdleMinutes = defaults.integer(forKey: "screensaverIdleMinutes")
        // Mouse movement is off by default, so a screensaver you started by hand stays until
        // you reach for it rather than vanishing when the pointer twitches.
        screensaverExitOnMouseMove = defaults.bool(forKey: "screensaverExitOnMouseMove")
        screensaverExitOnClick = defaults.object(forKey: "screensaverExitOnClick") as? Bool ?? true
        screensaverExitOnKey = defaults.object(forKey: "screensaverExitOnKey") as? Bool ?? true
        let hour = defaults.integer(forKey: "dailySummaryHour")
        dailySummaryHour = hour == 0 ? 18 : hour
        dailySummary = defaults.bool(forKey: "dailySummary")
        weeklyRecap = defaults.bool(forKey: "weeklyRecap")
        onThisDayNotice = defaults.bool(forKey: "onThisDayNotice")
        pinnedApps = (defaults.data(forKey: "pinnedApps"))
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
    }

    var excludedBundleIDs: Set<String> { Set(excludedApps.map(\.bundleID)) }

    private func write(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func writeJSON<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
