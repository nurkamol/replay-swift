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
    public struct Release: Equatable, Sendable {
        public var version: String
        public var name: String
        public var notes: String
        public var url: String

        public init(version: String, name: String, notes: String, url: String) {
            self.version = version
            self.name = name
            self.notes = notes
            self.url = url
        }
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
        return Release(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            name: (json["name"] as? String) ?? tag,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            url: (json["html_url"] as? String) ?? releasesPage
        )
    }

    /// Whether enough time has passed to ask again.
    public static func shouldCheck(lastChecked: Date?, now: Date = Date()) -> Bool {
        guard let lastChecked else { return true }
        return now.timeIntervalSince(lastChecked) >= checkInterval
    }
}
