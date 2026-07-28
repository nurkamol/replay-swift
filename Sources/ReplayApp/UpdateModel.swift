import AppKit
import CryptoKit
import Foundation
import ReplayCore
import SwiftUI

/// The one place in Replay that touches the network, and only when asked to.
///
/// **Off by default, and that is the whole design.** Every other claim this app makes about
/// itself — no account, no telemetry, no crash reporting, nothing uploaded — survives
/// untouched, because this sends nothing. A check is a `GET` that carries no identifier, no
/// body and no query: GitHub learns an IP address and that somebody asked about a public
/// release, which is what any visit to the releases page tells them.
///
/// It checks and reports. It does not download and it does not replace anything. Replacing a
/// running app means verifying a signature, swapping a bundle and surviving interruption —
/// and until there is a Developer ID it would be swapping a working app for one Gatekeeper
/// refuses, which breaks the install rather than improving it.
///
/// Nothing here is contract-checked, because the reference has no updater: it ships through
/// the Glaze Store. The *decision* is in ``Updates`` where it can be tested; this is the
/// request and the state around it.
@MainActor
@Observable
final class UpdateModel {
    /// A release newer than this build, once one has been found.
    private(set) var available: Updates.Release?
    private(set) var checking = false
    /// How far an install has got, so the panel can say so rather than freeze.
    private(set) var install: Install = .idle

    enum Install: Equatable {
        case idle, downloading, verifying, installing, done

        var label: String? {
            switch self {
            case .idle: nil
            case .downloading: "Downloading…"
            case .verifying: "Checking it…"
            case .installing: "Installing…"
            case .done: "Restarting…"
            }
        }
    }
    /// Set only when the user asked for a check and it failed, so a silent daily check can
    /// never produce an error nobody was expecting.
    private(set) var failure: String?

    private let preferences: Preferences
    private let currentVersion: String

    init(preferences: Preferences, currentVersion: String = Replay.version) {
        self.preferences = preferences
        self.currentVersion = currentVersion
    }

    /// The daily check. Does nothing at all unless it was turned on.
    func checkIfDue() async {
        guard preferences.checkForUpdates else { return }
        guard Updates.shouldCheck(lastChecked: preferences.lastUpdateCheck) else { return }
        await check(userAsked: false)
    }

    /// A check somebody pressed a button for. Runs whether or not the daily one is on, and
    /// is the only path that surfaces an error — an unattended check that fails should stay
    /// quiet rather than interrupt.
    func checkNow() async {
        await check(userAsked: true)
    }

    private func check(userAsked: Bool) async {
        guard !checking else { return }
        checking = true
        failure = nil
        defer { checking = false }

        guard let url = URL(string: Updates.releasesEndpoint) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // GitHub asks for these two. The user agent is the app and its version and nothing
        // else — no machine identifier, no locale, nothing that would make one install
        // distinguishable from another.
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Replay/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            preferences.lastUpdateCheck = Date()
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                if userAsked {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    // 404 is the ordinary case before a first release exists, and saying
                    // "not found" would read as a fault.
                    failure = switch code {
                    // The ordinary case before a first release exists. Saying "not found"
                    // would read as a fault.
                    case 404: "There are no releases yet."
                    // Unauthenticated requests are capped per IP per hour, and this is what
                    // it looks like from here. Hit while testing, and a bare "GitHub replied
                    // 403" tells somebody nothing they can act on.
                    case 403, 429: "GitHub is rate-limiting this connection. Try again later."
                    default: "GitHub replied \(code)."
                    }
                }
                return
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json, let release = Updates.release(from: json) else {
                if userAsked { failure = "That reply did not look like a release." }
                return
            }
            available = Updates.isNewer(release.version, than: currentVersion) ? release : nil
            if userAsked, available == nil {
                failure = "Replay \(currentVersion) is the latest version."
            }
        } catch {
            // A failed check is not an event. No retry loop, no backoff, no logging to disk:
            // it will be tried again tomorrow, and a machine that is offline should not
            // accumulate anything because of it.
            if userAsked { failure = "Could not reach GitHub." }
        }
    }

    /// Stop offering this one. It comes back if a newer release appears.
    func dismiss() {
        if let available { preferences.skippedUpdate = available.version }
        available = nil
    }

    /// Whether the banner should show — a version the user has already waved away stays away.
    var shouldOffer: Bool {
        guard let available else { return false }
        return preferences.skippedUpdate != available.version
    }
}

/// A newer version exists, said once and quietly.
///
/// A bar at the top rather than a dialog: nothing is waiting on the answer, so it should be
/// possible to ignore it and carry on. The notes are shown because "an update is available"
/// is not a reason to install anything — what changed is.
struct UpdateBanner: View {
    let release: Updates.Release
    let updates: UpdateModel
    let onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var showingNotes = false

    var body: some View {
        HStack(spacing: Design.Space.card) {
            Image(systemName: "arrow.down.circle")
                .font(Design.Text.prose)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(String(format: Loc.t("Replay %@ is available"), "\(release.version)"))
                    .font(Design.Text.itemTitle)
                // A refusal or a failed install belongs here, where the eye already is,
                // rather than somewhere the person has to go looking for it.
                if let failure = updates.failure {
                    Text(failure)
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(format: Loc.t("You have %@."), "\(Replay.version)"))
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Design.Space.inline)
            if let progress = updates.install.label {
                // What it is doing, in place of the buttons. An install is short but not
                // instant, and a panel that simply stopped responding would read as a hang.
                HStack(spacing: Design.Space.inline) {
                    ProgressView().controlSize(.small)
                    Text(Loc.t(progress))
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                }
            } else {
                if !release.notes.isEmpty {
                    Button(Loc.t("What's Changed")) { showingNotes = true }
                }
                if release.isInstallable {
                    // Installs it here, rather than opening a page and leaving somebody to
                    // drag a bundle over the one they are running.
                    Button(Loc.t("Update")) { Task { await updates.install(release) } }
                        .buttonStyle(.borderedProminent)
                } else {
                    // No zip on that release — the only honest offer left is the page.
                    Button(Loc.t("Open the Release")) {
                        openURL(URL(string: release.url) ?? URL(string: Updates.releasesPage)!)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark").font(Design.Text.micro)
                }
                .buttonStyle(.plain)
                .help(Loc.t("Skip this version"))
            }
        }
        .padding(Design.Space.section)
        .background(.regularMaterial, in: RoundedRectangle(
            cornerRadius: Design.Radius.card, style: .continuous
        ))
        .padding(Design.Space.section)
        .frame(maxWidth: Design.Layout.readableWidth)
        .popover(isPresented: $showingNotes, arrowEdge: .bottom) {
            ReleaseNotes(text: release.notes)
        }
    }
}

/// What a release says, as GitHub's Markdown renders rather than as its source.
///
/// Two things it fixes. The notes arrived as literal `## Improvements` and `- Added…`,
/// because `Text` shows a string verbatim — a release note that shows its own punctuation is
/// a note nobody finishes reading. And the box was a fixed 560×380 for four bullets, so the
/// usual release opened a mostly empty panel; it now takes the height it needs and scrolls
/// only past the cap.
///
/// Deliberately a small hand-rolled subset — headings, bullets, blank lines — rather than a
/// Markdown renderer. These are release notes this project writes itself, `tools/release-notes.mjs`
/// generates them, and the alternative is carrying a parser for somebody else's arbitrary
/// document. Anything unrecognised falls through as a paragraph, which is the safe direction.
private struct ReleaseNotes: View {
    let text: String

    @State private var contentHeight: CGFloat = 0

    private var lines: [(id: Int, line: Substring)] {
        Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated())
            .map { (id: $0.offset, line: $0.element) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                ForEach(lines, id: \.id) { entry in
                    let line = entry.line.trimmingCharacters(in: .whitespaces)
                    if line.isEmpty {
                        Spacer().frame(height: Design.Space.inline)
                    } else if line.hasPrefix("#") {
                        Text(line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))
                            .font(Design.Text.itemTitle)
                            .padding(.top, Design.Space.hairline)
                    } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                        HStack(alignment: .firstTextBaseline, spacing: Design.Space.inline) {
                            Text("•").foregroundStyle(.secondary)
                            Text(markdown(String(line.dropFirst(2))))
                        }
                        .font(Design.Text.detail)
                    } else {
                        Text(markdown(line)).font(Design.Text.detail)
                    }
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Design.Space.section)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(
            width: Design.Layout.releaseNotesWidth,
            height: min(max(contentHeight, 1), Design.Layout.releaseNotesMaxHeight)
        )
    }

    /// Inline emphasis and links only. Falls back to the literal text if it will not parse,
    /// so a malformed note is unattractive rather than absent.
    private func markdown(_ source: String) -> AttributedString {
        (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }
}

// MARK: - Installing it

extension UpdateModel {

    /// Download the new version, prove it is the published one, and put it in place.
    ///
    /// **The safety is the feature.** Without a Developer ID there is no signature that proves
    /// authorship, so the trust here rests on two things and it is worth being precise about
    /// them: HTTPS to a repository named in the source, and the SHA-256 the release publishes
    /// beside the zip. That is the same model as a Homebrew formula with a `sha256`, and it is
    /// weaker than notarisation — it proves the bytes are the ones that release carries, not
    /// that the release is trustworthy. Anyone who can publish to the repository can publish
    /// an update. The README says so.
    ///
    /// Every step that could produce a half-installed application refuses instead:
    /// a missing hash, a hash that does not match, an archive that does not contain a Replay,
    /// a bundle whose signature does not verify, a version that is not the one advertised.
    @MainActor
    func install(_ release: Updates.Release) async {
        guard case .idle = install else { return }
        guard let downloadURL = release.downloadURL.flatMap(URL.init(string:)),
              let checksumURL = release.checksumURL.flatMap(URL.init(string:))
        else {
            failure = "That release has nothing to install."
            return
        }

        let bundle = Bundle.main.bundleURL
        let parent = bundle.deletingLastPathComponent()
        let reason = Updates.installability(
            bundlePath: bundle.path,
            isWritable: FileManager.default.isWritableFile(atPath: parent.path)
        )
        guard reason.canInstall else {
            failure = Updates.refusal(reason)
            return
        }

        // Staged beside the application rather than in the system temp directory, because
        // the replace at the end has to happen on one volume and /tmp is often not the one
        // /Applications is on.
        let staging = parent.appendingPathComponent(".replay-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }

        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            install = .downloading
            let (zipTemp, response) = try await URLSession.shared.download(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw Failure.message("The download did not arrive.")
            }
            let zip = staging.appendingPathComponent("Replay.zip")
            try FileManager.default.moveItem(at: zipTemp, to: zip)

            install = .verifying
            let (checksumData, _) = try await URLSession.shared.data(from: checksumURL)
            guard let expected = Updates.checksum(from: String(decoding: checksumData, as: UTF8.self))
            else { throw Failure.message("That release publishes no checksum, so it was not installed.") }

            let actual = try Self.sha256(of: zip)
            guard actual == expected else {
                throw Failure.message(
                    "The download did not match its published checksum, so it was not installed."
                )
            }

            // `ditto`, because a `.app` is symlinks and extended attributes and `unzip`
            // flattens both into a bundle that will not launch.
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
            let unpacked = staging.appendingPathComponent("Replay.app")
            guard FileManager.default.fileExists(atPath: unpacked.path) else {
                throw Failure.message("That archive did not contain Replay.")
            }

            install = .verifying
            try Self.check(unpacked, isVersion: release.version)

            install = .installing
            _ = try FileManager.default.replaceItemAt(bundle, withItemAt: unpacked)

            install = .done
            relaunch(at: bundle)
        } catch let error as Failure {
            install = .idle
            failure = error.text
        } catch {
            install = .idle
            failure = "The update could not be installed: \(error.localizedDescription)"
        }
    }

    private enum Failure: Error {
        case message(String)
        var text: String { if case .message(let t) = self { t } else { "" } }
    }

    /// The archive's hash, read in chunks so a large one is not held in memory twice.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Is this actually the Replay it claims to be?
    ///
    /// Three questions, and each has caught something in a rehearsal: is it signed at all
    /// (an unsigned bundle will not launch on Apple silicon), is it *this* application, and
    /// is it the version the release advertised.
    private static func check(_ app: URL, isVersion expected: String) throws {
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw Failure.message("The downloaded copy is not correctly signed, so it was not installed.")
        }
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any] else {
            throw Failure.message("The downloaded copy has no Info.plist.")
        }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw Failure.message("The downloaded copy is a different application.")
        }
        guard info["CFBundleShortVersionString"] as? String == expected else {
            throw Failure.message("The downloaded copy is not the version that was offered.")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.message("\(tool) failed.")
        }
    }

    /// Start the new copy, then leave.
    ///
    /// The replaced bundle is a different file from the one this process is executing, which
    /// keeps running from the old inode until it exits — so the order has to be open first,
    /// quit second, or the new copy is asked to start while the old one still holds the
    /// single-instance claim.
    private func relaunch(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
