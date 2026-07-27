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

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = switch settings.authorizationStatus {
        case .authorized, .provisional: .granted
        case .denied: .denied
        default: .unknown
        }
    }

    /// Ask, but only because something was switched on.
    @discardableResult
    func request() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
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
        let centre = UNUserNotificationCenter.current()
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
        UNUserNotificationCenter.current().add(
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
    static func update(_ model: AppModel, enabled: Bool) {
        guard enabled, let summary = model.summary, summary.activeSeconds >= 3600 else {
            NSApp.dockTile.badgeLabel = nil
            return
        }
        NSApp.dockTile.badgeLabel = formatDurationShort(summary.activeSeconds)
    }
}
