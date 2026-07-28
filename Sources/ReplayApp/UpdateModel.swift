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
                    failure = code == 404
                        ? "There are no releases yet."
                        : "GitHub replied \(code)."
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
                Text(String(format: Loc.t("You have %@."), "\(Replay.version)"))
                    .font(Design.Text.detail)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Design.Space.inline)
            if !release.notes.isEmpty {
                Button(Loc.t("What's Changed")) { showingNotes = true }
            }
            Button(Loc.t("Get It")) { openURL(URL(string: release.url) ?? URL(string: Updates.releasesPage)!) }
                .buttonStyle(.borderedProminent)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark").font(Design.Text.micro)
            }
            .buttonStyle(.plain)
            .help(Loc.t("Skip this version"))
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
