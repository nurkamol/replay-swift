import Foundation
import ReplayCore
import Testing
@testable import ReplayUI

/// The notification centre, asked for where there is no bundle to own one.
///
/// `UNUserNotificationCenter.current()` raises `NSInternalInconsistencyException:
/// bundleProxyForCurrentProcess is nil` outside an app bundle. It is an Objective-C
/// exception, so Swift cannot catch it and the process dies — which is what Product ▸ Run in
/// Xcode used to do, since SwiftPM builds a bare executable with no `Info.plist`. The app
/// crashed inside `applicationDidFinishLaunching`, before any window appeared.
///
/// These cases can only make that claim because this test process has no bundle either:
/// `Bundle.main.bundleIdentifier` is nil under `swift test`, so every call below takes the
/// same path the crash took. Before the fix this suite would not have failed — it would have
/// killed the whole run.
@MainActor
@Suite("Notifications without a bundle")
struct NotificationsBehaviour {

    /// Its own database and its own defaults suite, like the other app suites here, so a run
    /// leaves nothing behind and two of these cannot see each other's settings.
    private static func model() throws -> NotificationsModel {
        let id = UUID().uuidString
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("replay-notification-tests-\(id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = AppModel(databaseURL: directory.appendingPathComponent("activity.db"))
        let defaults = try #require(UserDefaults(suiteName: "replay.tests.\(id)"))
        return NotificationsModel(model: app, preferences: Preferences(defaults: defaults))
    }

    @Test("The premise: this process is not an app, which is why the rest means anything")
    func notAnAppHere() {
        // Deliberately not `bundleIdentifier == nil`. That held under `swift test`, whose
        // host is SwiftPM's helper, and failed under `xcodebuild test`, whose host is Xcode's
        // test agent — an identifier, no app. The `.app` extension is the property both
        // runners share with every other non-app host, and it is what the guard checks.
        #expect(Bundle.main.bundleURL.pathExtension != "app")
    }

    @Test("Asking for permission is a no-op rather than a crash")
    func refreshing() async throws {
        let notifications = try Self.model()
        await notifications.refreshPermission()
        // Unknown, not denied: nothing was refused, there was simply nobody to ask. Saying
        // "denied" would put a permission prompt in Settings that could never be satisfied.
        #expect(notifications.permission == .unknown)
    }

    @Test("Requesting authorisation reports failure instead of dying")
    func requesting() async throws {
        let notifications = try Self.model()
        #expect(await notifications.request() == false)
    }

    @Test("Rescheduling every recap does nothing at all")
    func rescheduling() async throws {
        let notifications = try Self.model()
        await notifications.reschedule()
        #expect(notifications.permission == .unknown)
    }
}
