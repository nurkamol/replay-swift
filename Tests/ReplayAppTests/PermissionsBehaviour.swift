import Foundation
import Testing
@testable import ReplayUI

/// The permissions Replay does not use.
///
/// Most of this cannot be tested without granting something, which no test may do. What *can*
/// be pinned is the part that would be a catastrophe: `tccutil reset <service>` with no bundle
/// identifier resets that service **for every application on the Mac**. One missing argument
/// between "take Replay off the Accessibility list" and "take everything off it".
@MainActor
@Suite("Permissions")
struct PermissionsBehaviour {

    @Test("Reset refuses when there is no bundle to name")
    func refusesWithoutABundle() {
        // Under `swift test` there is no application bundle, so `Bundle.main.bundleIdentifier`
        // is nil — which is exactly the case that must not shell out. If this ever returns
        // true here, the guard has gone and the command being run is the whole-Mac one.
        let permissions = PermissionsModel()
        #expect(permissions.reset(.accessibility) == false)
        #expect(permissions.errorMessage != nil)
    }

    @Test("Every permission names a pane and a service, and they are not the same word")
    func namesAreDistinct() {
        // System Settings and `tccutil` spell these differently — `Privacy_AppBundles` against
        // `SystemPolicyAppBundles`. Passing one where the other belongs resets nothing while
        // appearing to succeed, which is the failure nobody would notice.
        for kind in PermissionsModel.Kind.allCases {
            #expect(!kind.pane.isEmpty)
            #expect(!kind.service.isEmpty)
            #expect(kind.pane != kind.service)
        }
    }

    @Test("Only the permission macOS can report is claimed to be readable")
    func onlyAccessibilityIsReadable() {
        // App Management has no public status API. Claiming otherwise would put a confident
        // tick beside a guess.
        #expect(PermissionsModel.Kind.accessibility.readable)
        #expect(!PermissionsModel.Kind.appManagement.readable)
    }

    @Test("A row exists for every kind, and an unreadable one says nothing rather than no")
    func rowsMatchKinds() {
        let permissions = PermissionsModel()
        #expect(permissions.permissions.count == PermissionsModel.Kind.allCases.count)
        let appManagement = permissions.permissions.first { $0.kind == .appManagement }
        // nil, not false: "we cannot tell" and "it is off" are different claims.
        #expect(appManagement?.granted == nil)
    }
}
