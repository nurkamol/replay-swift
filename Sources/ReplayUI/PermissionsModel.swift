import AppKit
import ApplicationServices
import Observation
import ReplayCore

/// The permissions Replay does not need, and where they stand anyway.
///
/// **Replay records with none of these.** It reads which application is frontmost from
/// `NSWorkspace`, which every app may do, and that is the product (SPEC §1). So this is not a
/// setup checklist and must never read as one — nothing here is required, and a Mac with every
/// row empty is a Mac where Replay works perfectly.
///
/// It exists for two real cases. A managed or locked-down Mac can restrict what an
/// unprivileged app observes, and somebody sent to System Settings by their IT department
/// deserves better than "open Settings and find it yourself". And a permission granted once,
/// out of caution, is otherwise invisible and impossible to take back from inside the app.
///
/// **What macOS allows, and what it does not.** No application can grant itself a permission —
/// the TCC database is protected, and there is no API that adds and enables an entry. What
/// `requestAccessibility()` does is ask the system to prompt, which *adds Replay to the list*
/// so the switch is there to flip. That is the whole of the improvement: it removes the step
/// where somebody browses to `/Applications` and picks the app by hand.
///
/// And nothing here asks for a password. macOS collects authorisation itself, in its own
/// window; an app that put up a password field to "approve" a toggle would be collecting a
/// credential it has no business seeing, and it would not work.
@MainActor
@Observable
final class PermissionsModel {

    /// One row: what it is, and what can honestly be said about it.
    struct Permission: Identifiable, Sendable {
        let kind: Kind
        /// `nil` where macOS exposes no way to read it — see ``Kind/readable``.
        let granted: Bool?

        var id: String { kind.rawValue }
    }

    enum Kind: String, CaseIterable, Sendable {
        case accessibility
        case appManagement

        var label: String {
            switch self {
            case .accessibility: Loc.t("Accessibility")
            case .appManagement: Loc.t("App Management")
            }
        }

        var explanation: String {
            switch self {
            case .accessibility:
                Loc.t("Not used. Replay reads the frontmost application from macOS itself.")
            case .appManagement:
                Loc.t("Not used. Replay never modifies another application.")
            }
        }

        /// Whether an app can read its own state for this service.
        ///
        /// Accessibility has `AXIsProcessTrusted()`. App Management has nothing equivalent —
        /// no public API reports it, so a tick beside it would be a guess, and a guess in a
        /// permissions list is worse than an honest blank.
        var readable: Bool { self == .accessibility }

        /// The System Settings pane, and the `tccutil` service name — which are spelled
        /// differently, and getting that wrong resets nothing while appearing to work.
        var pane: String {
            switch self {
            case .accessibility: "Privacy_Accessibility"
            case .appManagement: "Privacy_AppBundles"
            }
        }

        var service: String {
            switch self {
            case .accessibility: "Accessibility"
            case .appManagement: "SystemPolicyAppBundles"
            }
        }
    }

    private(set) var permissions: [Permission] = []
    /// Set when a reset fails, so the row can say so rather than appearing to have worked.
    private(set) var errorMessage: String?

    init() { refresh() }

    /// Read what can be read. Cheap, and safe to call whenever the app comes forward.
    func refresh() {
        permissions = Kind.allCases.map { kind in
            Permission(kind: kind, granted: kind.readable ? AXIsProcessTrusted() : nil)
        }
    }

    /// Ask macOS to prompt for Accessibility.
    ///
    /// The prompt is the point: it puts Replay in the Accessibility list, so the person only
    /// has to turn the switch on. Without it they must open Settings, press `+`, and find the
    /// app in `/Applications` — which is the step this exists to remove.
    ///
    /// Only ever from a button. Called at launch it would be the app demanding a permission it
    /// does not use, which is the one thing this project promises never to do.
    func requestAccessibility() {
        // The key spelled out rather than read from `kAXTrustedCheckOptionPrompt`: that global
        // is a `var` in the C headers, so Swift 6 treats touching it as shared mutable state.
        // Its value is fixed API and has been since the call existed.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        refresh()
    }

    /// Open the pane for a permission, so somebody sent there lands on the right screen.
    func open(_ kind: Kind) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(kind.pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Take a permission back.
    ///
    /// `tccutil reset <service> <bundle id>` — **always with the bundle identifier.** Without
    /// it the same command resets that service for *every application on the Mac*, which is a
    /// catastrophe one missing argument away, so the identifier is required here rather than
    /// defaulted.
    @discardableResult
    func reset(_ kind: Kind) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            // No bundle means a development build; there is no entry to reset, and passing an
            // empty argument would be the whole-Mac reset described above.
            errorMessage = Loc.t("Only a bundled copy of Replay has permissions to reset.")
            return false
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", kind.service, bundleID]
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                errorMessage = String(
                    format: Loc.t("Couldn't reset %@."), kind.label
                )
                return false
            }
            errorMessage = nil
            refresh()
            return true
        } catch {
            errorMessage = String(format: Loc.t("Couldn't reset %@."), kind.label)
            return false
        }
    }

    /// Whether anything is granted that need not be.
    ///
    /// Deliberately not "is everything set up". The healthy state for this app is *nothing*
    /// granted, so the summary says the Mac is fine either way and never nags toward a switch.
    var anythingGranted: Bool {
        permissions.contains { $0.granted == true }
    }
}
