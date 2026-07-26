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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = (defaults.string(forKey: "appearance").flatMap(Appearance.init)) ?? .system
        launchSurface = (defaults.string(forKey: "launchSurface").flatMap(LaunchSurface.init)) ?? .today
        retentionDays = defaults.integer(forKey: "retentionDays")
        excludedApps = (defaults.data(forKey: "excludedApps"))
            .flatMap { try? JSONDecoder().decode([ExcludedApp].self, from: $0) } ?? []
    }

    var excludedBundleIDs: Set<String> { Set(excludedApps.map(\.bundleID)) }

    private func write(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }

    private func writeJSON<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
