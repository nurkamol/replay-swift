import AppKit
import Foundation
import Observation
import ReplayCore
import UserNotifications

/// The quiet recaps macOS delivers on Replay's behalf.
///
/// Built entirely from the local database and handed to the system already written — nothing
/// is uploaded and there is no account behind them. Off until asked for, and asking is what
/// prompts for permission: this app requests nothing before the moment a request would mean
/// something, which is the same rule the tracker follows.
@MainActor
@Observable
final class NotificationsModel {
    enum Permission: Equatable {
        case unknown, granted, denied
    }

    private(set) var permission: Permission = .unknown

    private let model: AppModel
    private let preferences: Preferences

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
    }

    /// The notification centre, or nothing when this process is not an app.
    ///
    /// `UNUserNotificationCenter.current()` does not fail politely outside an application
    /// bundle — it raises `NSInternalInconsistencyException: bundleProxyForCurrentProcess is
    /// nil`, an Objective-C exception Swift cannot catch, so the process dies. Product ▸ Run
    /// in Xcode produced exactly that: SwiftPM builds a bare executable, and the app died
    /// inside `applicationDidFinishLaunching` before a window appeared.
    ///
    /// **The test is the `.app` extension, not the bundle identifier.** The obvious guard —
    /// `bundleIdentifier != nil` — is wrong, and wrong in a way only a third build path
    /// showed: under `xcodebuild test` the main bundle is Xcode's own test agent, which has
    /// an identifier and is not an app, so the guard passed and the run still crashed. Every
    /// host that is not a real app has a `bundleURL` that does not end in `.app`:
    ///
    /// | host                        | `bundleURL`                        | notifications |
    /// | --------------------------- | ---------------------------------- | ------------- |
    /// | the shipped app             | `/Applications/Replay.app`         | yes           |
    /// | Product ▸ Run, `swift run`  | `…/.build/debug/`                  | no            |
    /// | `swift test`                | `…/libexec/swift/pm/`              | no            |
    /// | `xcodebuild test`           | `…/Xcode/Agents/`                  | no            |
    ///
    /// Every call goes through here so that stays true for the next one added. A development
    /// run simply has no notifications, which is right — they are the one part of this app
    /// needing an identity to be delivered against, and `./scripts/make-app.sh` builds the
    /// bundle that has one.
    private var centre: UNUserNotificationCenter? {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    func refreshPermission() async {
        guard let centre else { return }
        let settings = await centre.notificationSettings()
        permission = switch settings.authorizationStatus {
        case .authorized, .provisional: .granted
        case .denied: .denied
        default: .unknown
        }
    }

    /// Ask, but only because something was switched on.
    @discardableResult
    func request() async -> Bool {
        guard let centre else { return false }
        do {
            let granted = try await centre
                .requestAuthorization(options: [.alert, .sound, .badge])
            permission = granted ? .granted : .denied
            return granted
        } catch {
            permission = .denied
            return false
        }
    }

    /// Rewrite every scheduled recap from the current settings.
    ///
    /// Cleared and rebuilt rather than patched: the schedule is small, and a set of requests
    /// edited in place drifts out of step with the switches that describe it.
    func reschedule() async {
        guard let centre else { return }
        centre.removeAllPendingNotificationRequests()
        guard permission == .granted else { return }

        if preferences.dailySummary {
            var when = DateComponents()
            when.hour = preferences.dailySummaryHour
            when.minute = 0
            schedule(
                id: "daily", title: "Today so far", body: dailyBody(),
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            )
        }

        if preferences.weeklyRecap {
            var when = DateComponents()
            // Sunday evening, looking back at the week rather than forward into one.
            when.weekday = 1
            when.hour = 19
            when.minute = 0
            schedule(
                id: "weekly", title: "Your week", body: weeklyBody(),
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            )
        }

        if preferences.onThisDayNotice, let memory = firstMemory() {
            var when = DateComponents()
            when.hour = 9
            when.minute = 0
            schedule(
                id: "on-this-day", title: "On this day",
                body: "\(memory.range.label): "
                    + "\(formatDurationShort(memory.summary.activeSeconds)) active"
                    + (memory.summary.topAppName.map { ", mostly \($0)" } ?? ""),
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            )
        }
    }

    private func schedule(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        centre?.add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }

    /// The text is written now rather than at delivery time, which means a repeating recap
    /// carries the figures from when it was scheduled. Rescheduled on every launch and on
    /// every settings change, so in practice it is a day old at most — and stating that is
    /// better than pretending the number is live.
    private func dailyBody() -> String {
        guard let summary = model.summary else { return "A quiet day so far." }
        return "\(formatDurationShort(summary.activeSeconds)) active across "
            + "\(summary.sessionCount) \(summary.sessionCount == 1 ? "session" : "sessions")."
    }

    private func weeklyBody() -> String {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        let summaries = (try? model.store.dailySummaries(
            from: today - 6 * dayMillis, to: today + dayMillis
        )) ?? []
        let total = summaries.reduce(0) { $0 + $1.activeSeconds }
        let days = summaries.filter { $0.activeSeconds > 0 }.count
        return "\(formatDurationShort(total)) across \(days) "
            + "\(days == 1 ? "day" : "days") this week."
    }

    private func firstMemory() -> Memories.Memory? {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let from = startOfLocalDay(now) - Int64(Memories.lookbackDays) * dayMillis
        let summaries = (try? model.store.dailySummaries(from: from, to: now + dayMillis)) ?? []
        return Memories.find(in: summaries, now: now).first
    }
}

/// Today's hours on the Dock icon.
///
/// Only past an hour: a badge reading "12m" is noise, and one that appears the moment the app
/// launches makes the Dock a counter you watch rather than a place you launch from.
@MainActor
enum DockBadge {
    /// The view the Dock draws for us, kept rather than rebuilt every five seconds.
    @MainActor private static let tile = DockTileView()

    @MainActor
    static func update(_ model: AppModel, enabled: Bool) {
        // `nil` under an hour, which is the same as no badge — it appears once the day has
        // earned it. See `DockBadgeLabel` for why whole hours, and `DockTileView` for why
        // Replay draws its own tile instead of setting `badgeLabel`.
        let label = enabled
            ? model.summary.flatMap { DockBadgeLabel.text(activeSeconds: $0.activeSeconds) }
            : nil
        if NSApp.dockTile.contentView !== tile { NSApp.dockTile.contentView = tile }
        tile.label = label
        NSApp.dockTile.display()
    }
}

