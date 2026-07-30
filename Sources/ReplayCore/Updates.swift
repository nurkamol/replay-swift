import Foundation

/// Whether a newer Replay exists, decided without touching the network.
///
/// **This app had no networking code at all, and adding some is a real change to what it
/// is.** The README's claim was "no cloud, no account, no telemetry, no update check", and
/// three of those four still hold. So the shape here is deliberate: the *decision* — is that
/// release newer than this one, and what does it say — is pure, tested, and lives in the
/// core; the one HTTP request lives in the app, behind a switch that is off until somebody
/// turns it on.
///
/// It checks and tells you. It does not download, and it does not replace anything. A
/// self-updater has to verify a signature, swap a bundle and survive being interrupted
/// halfway — and it would be replacing a working app with an unsigned one until there is a
/// Developer ID, which breaks the install rather than improving it. Notifying costs one
/// request and can be wrong only by being out of date.
public enum Updates {

    /// Where the releases are. A constant rather than a setting: an update check pointed at
    /// a host the user can change is a much larger promise than this feature makes.
    public static let releasesEndpoint =
        "https://api.github.com/repos/nurkamol/replay-swift/releases/latest"
    public static let releasesPage = "https://github.com/nurkamol/replay-swift/releases/latest"

    /// How long between checks. Once a day, and only while the app is running.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    /// A release, as much of it as this app cares about.
    ///
    /// `Codable` so the last one seen can be kept between launches. That is not a cache for
    /// speed: a conditional request answered `304 Not Modified` carries no body at all, so
    /// without a stored copy the app would come back from that reply knowing nothing — and
    /// would have to spend a second request to learn what it already knew yesterday.
    public struct Release: Equatable, Sendable, Codable {
        public var version: String
        public var name: String
        public var notes: String
        public var url: String
        /// The zipped application, when the release carries one.
        public var downloadURL: String?
        /// The published SHA-256 of that zip. Without it there is no install: an update that
        /// cannot be checked is a download from the internet run as an application.
        public var checksumURL: String?

        public init(
            version: String, name: String, notes: String, url: String,
            downloadURL: String? = nil, checksumURL: String? = nil
        ) {
            self.version = version
            self.name = name
            self.notes = notes
            self.url = url
            self.downloadURL = downloadURL
            self.checksumURL = checksumURL
        }

        /// Whether this release can be installed in place rather than opened in a browser.
        public var isInstallable: Bool { downloadURL != nil && checksumURL != nil }
    }

    // MARK: - Whether replacing this copy is a safe thing to do

    /// Why an in-place update is or is not possible.
    ///
    /// Refusing loudly matters more here than anywhere else in the app: the alternative to a
    /// refusal is overwriting somebody's application with a downloaded file.
    public enum Installability: Equatable, Sendable {
        case ready
        /// Installed by Homebrew. Replacing the bundle would leave `brew` believing it has a
        /// version it no longer has, and the next `brew upgrade` would fight this one.
        case managedByHomebrew
        /// Running from App Translocation — the read-only randomised mount Gatekeeper uses
        /// for a quarantined app. There is nothing here to replace; the real copy is wherever
        /// it was downloaded to, and moving it to Applications is what clears this.
        case translocated
        /// The bundle is somewhere this user cannot write.
        case notWritable

        public var canInstall: Bool { self == .ready }
    }

    /// Decide from a bundle path alone, so it is testable without touching a filesystem.
    ///
    /// `writable` is passed in rather than looked up for the same reason.
    public static func installability(
        bundlePath: String, isWritable: Bool
    ) -> Installability {
        // Homebrew keeps everything under a Cellar, whatever the prefix.
        if bundlePath.contains("/Cellar/") { return .managedByHomebrew }
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        if !isWritable { return .notWritable }
        return .ready
    }

    /// What to tell somebody who cannot update in place.
    public static func refusal(_ reason: Installability) -> String? {
        switch reason {
        case .ready:
            nil
        case .managedByHomebrew:
            "Replay was installed with Homebrew. Run `brew upgrade nurkamol/tap/replay-app` "
                + "so Homebrew and this copy stay in agreement."
        case .translocated:
            "macOS is running Replay from a temporary read-only copy, which happens to an "
                + "app that has not been moved out of the folder it was downloaded to. Move "
                + "Replay to your Applications folder and open it again."
        case .notWritable:
            "Replay is in a folder this account cannot write to. Move it to your Applications "
                + "folder, or download the new version yourself."
        }
    }

    // MARK: - The checksum

    /// Pull the hash out of a `shasum`-format file: the hash, whitespace, then a filename.
    ///
    /// Returns `nil` for anything that does not look like exactly one SHA-256, which is the
    /// safe direction: no hash means no install.
    public static func checksum(from file: String) -> String? {
        let first = file.split(separator: "\n").first.map(String.init) ?? ""
        let hash = first.split(separator: " ").first.map(String.init) ?? ""
        let trimmed = hash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 64,
              trimmed.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return trimmed
    }

    /// A version as comparable parts. Anything unparseable sorts as nothing at all.
    ///
    /// Deliberately strict: `1.2.3`, optionally with a leading `v`. No pre-release suffixes,
    /// no build metadata — this project tags `v0.9.0` and nothing else, and a lenient parser
    /// would silently accept a tag it then compared wrongly. A tag this cannot read is
    /// treated as "no update", which is the safe direction to be wrong in.
    public static func parse(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix("v")
            ? String(version.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst())
            : version.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3, numbers.allSatisfy({ $0 >= 0 }) else { return nil }
        return numbers
    }

    /// Is `candidate` newer than `current`?
    ///
    /// False whenever either side cannot be read, so an unreadable tag or a build with no
    /// version never produces a spurious "update available". Being silently out of date is a
    /// smaller failure than nagging somebody about a release that does not exist.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        for (lhs, rhs) in zip(a, b) where lhs != rhs { return lhs > rhs }
        return false
    }

    /// The reply from GitHub's "latest release" endpoint, reduced to what is shown.
    ///
    /// Hand-decoded rather than through `Codable` so a field appearing, disappearing or
    /// changing type is a `nil` rather than a thrown error that loses the whole response —
    /// this is somebody else's API and the app should not break when it moves.
    public static func release(from json: [String: Any]) -> Release? {
        guard let tag = json["tag_name"] as? String, parse(tag) != nil else { return nil }
        let notes = (json["body"] as? String) ?? ""
        // The zip and its published hash, found by shape rather than by exact name so a
        // change to the version in the filename cannot silently disable updating.
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        func asset(endingIn suffix: String) -> String? {
            assets.first {
                ($0["name"] as? String)?.hasSuffix(suffix) == true
            }?["browser_download_url"] as? String
        }
        return Release(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            name: (json["name"] as? String) ?? tag,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            url: (json["html_url"] as? String) ?? releasesPage,
            downloadURL: asset(endingIn: ".zip"),
            checksumURL: asset(endingIn: ".zip.sha256")
        )
    }

    /// Whether enough time has passed to ask again.
    public static func shouldCheck(
        lastChecked: Date?, notBefore: Date? = nil, now: Date = Date()
    ) -> Bool {
        // A window GitHub has already told us is closed. Asking inside it can only produce
        // the same 403 and spend one of the sixty an hour that were the problem to begin
        // with. `notBefore` is `x-ratelimit-reset` from the last refusal, and it outranks
        // the daily schedule in one direction only: it can delay a check, never bring one
        // forward.
        if let notBefore, now < notBefore { return false }
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= checkInterval
    }

    /// When GitHub says the rate-limit window reopens, from `x-ratelimit-reset`.
    ///
    /// The header is whole seconds since 1970. Anything else — absent, empty, not a number,
    /// or a time already past — is `nil`, which the caller reads as "no reason to wait".
    /// Deliberately not clamped to some maximum: if GitHub says an hour, the honest thing is
    /// to wait an hour rather than to decide it cannot have meant it.
    public static func retryAfter(header: String?, now: Date = Date()) -> Date? {
        guard let header = header?.trimmingCharacters(in: .whitespaces), !header.isEmpty,
              let epoch = TimeInterval(header)
        else { return nil }
        let when = Date(timeIntervalSince1970: epoch)
        return when > now ? when : nil
    }

    /// What a launch should say about the version it is running, if anything.
    ///
    /// The self-updater replaces the bundle and restarts, so "after the update" is a *later
    /// launch* rather than a moment in the install. Which means the only place this can be
    /// decided is here, from what the last run wrote down.
    public enum LaunchNote: Equatable, Sendable {
        /// Nothing to say: a first run, the same version again, or a downgrade.
        case nothing
        /// The user pressed Update seconds ago and the app disappeared and came back. Show
        /// them what they got — they asked a question and this is its answer.
        case whatsNew
        /// The version changed without anyone pressing anything in Replay: `brew upgrade`, or
        /// a bundle dragged into place. Worth mentioning, not worth a window taking the
        /// screen — SPEC §8's "never interrupt" is about exactly this difference.
        case quietly
        /// The same version, deliberately installed again.
        ///
        /// **The case a version comparison cannot see.** Every other note here is decided by
        /// whether the number went up; a reinstall's number is identical by definition, so
        /// without a flag the answer is `.nothing` and the app comes back from a swap saying
        /// nothing at all. Somebody pressed a button because they believed their copy was
        /// wrong, and silence is the one response that leaves them no better off.
        case reinstalled
    }

    /// Decide from the two versions and how the change happened.
    ///
    /// A *downgrade* says nothing at all. Somebody who has just put an older copy back has
    /// done it deliberately, and a window announcing the release they were escaping would be
    /// the app arguing with them.
    public static func launchNote(
        previous: String?, current: String, selfUpdated: Bool, reinstalled: Bool = false
    ) -> LaunchNote {
        // No previous version means a first run — or the first run after this was added,
        // which is the same thing as far as anyone can tell. Announcing a release to somebody
        // who has just installed the app is telling them what they already chose.
        guard let previous, !previous.isEmpty else { return .nothing }
        guard isNewer(current, than: previous) else {
            // Same version — or older. A reinstall is the one reason that is worth saying,
            // and only because somebody asked for it seconds ago. Checked after `isNewer` so
            // a stale flag can never dress an ordinary update up as a reinstall.
            return reinstalled ? .reinstalled : .nothing
        }
        return selfUpdated ? .whatsNew : .quietly
    }

    /// Whether a reply means "nothing has changed since the copy you already have".
    ///
    /// Its own function because the *consequence* is the interesting part: a 304 carries no
    /// body, so the caller has to answer from what it stored last time rather than from this
    /// reply. It is **not** a free request on this endpoint — see `docs/FINDINGS.md`, where
    /// the counter was measured decrementing on a 304 exactly as it does on a 200.
    public static func isUnchanged(status: Int) -> Bool { status == 304 }
}
