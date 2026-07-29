import Foundation
import ReplayCore
import Testing

/// Deciding whether a release is newer, without a network.
///
/// The check itself is one HTTP request and is not what goes wrong. What goes wrong is the
/// comparison: a version that cannot be read, a tag in a shape nobody expected, a response
/// whose fields moved. Every one of those should end as "no update" rather than as a prompt
/// about a release that does not exist — nagging somebody is a worse failure than being
/// quietly out of date, because they cannot act on it and cannot tell you are wrong.
@Suite("Updates")
struct UpdateBehaviour {

    @Test("A newer version is newer, in each position")
    func ordering() {
        #expect(Updates.isNewer("0.10.0", than: "0.9.0"))
        #expect(Updates.isNewer("1.0.0", than: "0.9.9"))
        #expect(Updates.isNewer("0.9.1", than: "0.9.0"))
        // The one a string comparison gets wrong: "0.10.0" < "0.9.0" alphabetically.
        #expect(!Updates.isNewer("0.9.0", than: "0.10.0"))
    }

    @Test("The same version is not an update")
    func sameIsNotNewer() {
        #expect(!Updates.isNewer("0.9.0", than: "0.9.0"))
        #expect(!Updates.isNewer("v0.9.0", than: "0.9.0"))
        #expect(!Updates.isNewer("0.8.0", than: "0.9.0"))
    }

    @Test("A leading v is accepted on either side")
    func tolerantOfTheTagPrefix() {
        #expect(Updates.isNewer("v1.0.0", than: "0.9.0"))
        #expect(Updates.isNewer("1.0.0", than: "v0.9.0"))
    }

    @Test("Anything unreadable is never an update")
    func unreadableIsNeverNewer() {
        for bad in ["", "latest", "1.0", "1.0.0.0", "v", "nightly-2026-07-28", "1.x.0", "-1.0.0"] {
            #expect(!Updates.isNewer(bad, than: "0.9.0"), "\(bad) should not read as newer")
            #expect(!Updates.isNewer("99.0.0", than: bad), "should not compare against \(bad)")
        }
    }

    @Test("A release is read from GitHub's shape")
    func readsARelease() {
        let json: [String: Any] = [
            "tag_name": "v0.10.0",
            "name": "Replay 0.10.0",
            "body": "  ### Added\n- A thing.  ",
            "html_url": "https://github.com/nurkamol/replay-swift/releases/tag/v0.10.0",
        ]
        let release = Updates.release(from: json)
        #expect(release?.version == "0.10.0")
        #expect(release?.name == "Replay 0.10.0")
        #expect(release?.notes == "### Added\n- A thing.")
        #expect(release?.url.hasSuffix("v0.10.0") == true)
    }

    @Test("A response missing fields degrades rather than throwing")
    func toleratesAMovingAPI() {
        // Only the tag is required. Everything else is somebody else's API and may move.
        let sparse: [String: Any] = ["tag_name": "v1.2.3"]
        let release = Updates.release(from: sparse)
        #expect(release?.version == "1.2.3")
        #expect(release?.name == "v1.2.3")
        #expect(release?.notes == "")
        #expect(release?.url == Updates.releasesPage)

        // And a tag that is not a version is not a release worth reporting.
        #expect(Updates.release(from: ["tag_name": "nightly"]) == nil)
        #expect(Updates.release(from: [:]) == nil)
    }

    @Test("It asks once a day, and once on a machine that has never asked")
    func interval() {
        #expect(Updates.shouldCheck(lastChecked: nil))
        let now = Date()
        #expect(!Updates.shouldCheck(lastChecked: now, now: now))
        #expect(!Updates.shouldCheck(lastChecked: now.addingTimeInterval(-3600), now: now))
        #expect(Updates.shouldCheck(lastChecked: now.addingTimeInterval(-Updates.checkInterval), now: now))
    }

    // MARK: - Not asking inside a window GitHub has already closed

    @Test("A named rate-limit window holds a due check back until it reopens")
    func waitsOutTheWindow() {
        let now = Date()
        let due = now.addingTimeInterval(-Updates.checkInterval)
        // Due by the clock, and refused anyway while the window is shut.
        #expect(!Updates.shouldCheck(
            lastChecked: due, notBefore: now.addingTimeInterval(600), now: now
        ))
        // The moment it reopens, the ordinary rule decides again.
        #expect(Updates.shouldCheck(
            lastChecked: due, notBefore: now.addingTimeInterval(-1), now: now
        ))
    }

    @Test("A window that has passed never brings a check forward")
    func neverAsksSooner() {
        let now = Date()
        // Not due — checked a minute ago — and an expired window does not change that. A
        // limit that could *advance* a check would be a way to ask more often by asking
        // too often.
        #expect(!Updates.shouldCheck(
            lastChecked: now.addingTimeInterval(-60), notBefore: now.addingTimeInterval(-60),
            now: now
        ))
    }

    @Test("The reset header is read as a moment, and nonsense as none")
    func resetHeader() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(Updates.retryAfter(header: "1000600", now: now)
            == Date(timeIntervalSince1970: 1_000_600))
        // Whitespace is the ordinary shape of a header value.
        #expect(Updates.retryAfter(header: " 1000600 ", now: now) != nil)
        // A window that has already passed is no reason to wait.
        #expect(Updates.retryAfter(header: "999999", now: now) == nil)
        #expect(Updates.retryAfter(header: nil, now: now) == nil)
        #expect(Updates.retryAfter(header: "", now: now) == nil)
        #expect(Updates.retryAfter(header: "soon", now: now) == nil)
    }

    // MARK: - What a launch says about the version it is running

    @Test("A first run announces nothing")
    func firstRunIsQuiet() {
        // Nothing was written down, so there is nothing to compare — and telling somebody
        // who has just installed the app what is new in it is telling them what they chose.
        #expect(Updates.launchNote(previous: nil, current: "0.9.6", selfUpdated: false) == .nothing)
        #expect(Updates.launchNote(previous: "", current: "0.9.6", selfUpdated: true) == .nothing)
    }

    @Test("The same version again says nothing, however it got here")
    func sameVersionIsQuiet() {
        #expect(Updates.launchNote(previous: "0.9.6", current: "0.9.6", selfUpdated: false) == .nothing)
        // Even with the flag set — a self-update that ended on the version it started from
        // did not update anything, whatever it thinks.
        #expect(Updates.launchNote(previous: "0.9.6", current: "0.9.6", selfUpdated: true) == .nothing)
    }

    @Test("An update somebody pressed Update for opens What's New")
    func askedForItGetsTheWindow() {
        #expect(Updates.launchNote(previous: "0.9.5", current: "0.9.6", selfUpdated: true) == .whatsNew)
    }

    @Test("An update from outside the app gets the banner instead")
    func arrivedQuietlyGetsTheBanner() {
        // `brew upgrade`, or a bundle dragged into place. Nobody is waiting on an answer, so
        // nothing takes the screen.
        #expect(Updates.launchNote(previous: "0.9.5", current: "0.9.6", selfUpdated: false) == .quietly)
    }

    @Test("A downgrade says nothing at all")
    func downgradeIsQuiet() {
        // Putting an older copy back is deliberate. Announcing the release they just escaped
        // would be the app arguing with them.
        #expect(Updates.launchNote(previous: "0.9.6", current: "0.9.5", selfUpdated: false) == .nothing)
        #expect(Updates.launchNote(previous: "0.9.6", current: "0.9.5", selfUpdated: true) == .nothing)
    }

    @Test("A version that cannot be read is not an update")
    func unreadableIsQuiet() {
        #expect(Updates.launchNote(previous: "nightly", current: "0.9.6", selfUpdated: true) == .nothing)
        #expect(Updates.launchNote(previous: "0.9.5", current: "", selfUpdated: true) == .nothing)
    }

    @Test("Only 304 means unchanged")
    func unchangedStatus() {
        #expect(Updates.isUnchanged(status: 304))
        #expect(!Updates.isUnchanged(status: 200))
        #expect(!Updates.isUnchanged(status: 403))
    }

    @Test("A release survives being stored and read back, assets included")
    func releaseRoundTrips() throws {
        // What a 304 answers from. If this ever stopped round-tripping, an unchanged reply
        // would come back as an update with no download and the banner would offer a page
        // instead of an install — quietly, and only for people whose check returned 304.
        let release = Updates.Release(
            version: "0.9.5", name: "Replay 0.9.5", notes: "Notes",
            url: "https://example.invalid/releases/v0.9.5",
            downloadURL: "https://example.invalid/Replay-0.9.5.zip",
            checksumURL: "https://example.invalid/Replay-0.9.5.zip.sha256"
        )
        let data = try JSONEncoder().encode(release)
        #expect(try JSONDecoder().decode(Updates.Release.self, from: data) == release)
    }
}

/// Installing an update in place, which is the part that can do damage.
///
/// Everything here is about refusing. The alternative to a correct refusal is overwriting
/// somebody's application with a file off the internet, so the cases that say *no* are worth
/// more tests than the case that says yes.
@Suite("Installing an update")
struct UpdateInstallBehaviour {

    // MARK: - Where it must refuse

    @Test("A Homebrew copy is left to Homebrew")
    func homebrew() {
        let path = "/opt/homebrew/Cellar/replay-app/HEAD-abc123/Replay.app"
        #expect(Updates.installability(bundlePath: path, isWritable: true) == .managedByHomebrew)
        // Writable is not the question: replacing it would leave brew believing it has a
        // version it no longer has, and the next upgrade would fight this one.
        #expect(!Updates.installability(bundlePath: path, isWritable: true).canInstall)
        #expect(Updates.refusal(.managedByHomebrew)?.contains("brew upgrade") == true)
    }

    @Test("A translocated copy has nothing to replace")
    func translocated() {
        let path = "/private/var/folders/xy/AppTranslocation/ABC-123/d/Replay.app"
        #expect(Updates.installability(bundlePath: path, isWritable: false) == .translocated)
        // The advice has to be the thing that actually fixes it.
        #expect(Updates.refusal(.translocated)?.contains("Applications") == true)
    }

    @Test("A read-only location refuses rather than half-installing")
    func readOnly() {
        #expect(
            Updates.installability(bundlePath: "/Applications/Replay.app", isWritable: false)
                == .notWritable
        )
    }

    @Test("An ordinary writable install is ready")
    func ready() {
        let it = Updates.installability(bundlePath: "/Applications/Replay.app", isWritable: true)
        #expect(it == .ready)
        #expect(it.canInstall)
        #expect(Updates.refusal(.ready) == nil)
    }

    @Test("Homebrew wins over writability, and translocation over both")
    func precedence() {
        // A Cellar path is always Homebrew's even if this account can write to it.
        #expect(
            Updates.installability(bundlePath: "/opt/homebrew/Cellar/x/Replay.app", isWritable: true)
                == .managedByHomebrew
        )
    }

    // MARK: - The checksum, which is the only thing standing between a download and trust

    @Test("A shasum-format line yields its hash")
    func checksum() {
        let file = "a73465f5b900b6a9b60d4049209ceb076a7faad93847661746b8038547f04cb8  build/Replay-0.9.2.zip\n"
        #expect(Updates.checksum(from: file) == "a73465f5b900b6a9b60d4049209ceb076a7faad93847661746b8038547f04cb8")
    }

    @Test("Anything that is not exactly one SHA-256 yields nothing")
    func checksumRejects() {
        // No hash means no install, so every one of these has to fail closed.
        #expect(Updates.checksum(from: "") == nil)
        #expect(Updates.checksum(from: "not a hash  file.zip") == nil)
        #expect(Updates.checksum(from: "abc123  file.zip") == nil)           // too short
        #expect(Updates.checksum(from: String(repeating: "z", count: 64)) == nil)  // not hex
        #expect(Updates.checksum(from: "<html>404</html>") == nil)
    }

    @Test("Case and stray whitespace do not defeat it")
    func checksumTolerates() {
        let upper = "A73465F5B900B6A9B60D4049209CEB076A7FAAD93847661746B8038547F04CB8  x.zip"
        #expect(Updates.checksum(from: upper)?.hasPrefix("a73465") == true)
    }

    // MARK: - A release that cannot be installed

    @Test("A release with no assets is not installable, and says so")
    func notInstallable() {
        let release = Updates.Release(version: "1.0.0", name: "x", notes: "", url: "u")
        #expect(!release.isInstallable)
    }

    @Test("Both the zip and its hash are required, not either")
    func bothRequired() {
        let zipOnly = Updates.Release(
            version: "1.0.0", name: "x", notes: "", url: "u", downloadURL: "z"
        )
        // A zip with no published hash is a download from the internet run as an application.
        #expect(!zipOnly.isInstallable)
        let both = Updates.Release(
            version: "1.0.0", name: "x", notes: "", url: "u", downloadURL: "z", checksumURL: "s"
        )
        #expect(both.isInstallable)
    }

    @Test("The assets are found by shape, so a version in the filename cannot break it")
    func assetsFromJSON() {
        let json: [String: Any] = [
            "tag_name": "v2.5.0",
            "html_url": "https://example.com/r",
            "assets": [
                ["name": "Replay-2.5.0.zip.sha256", "browser_download_url": "https://e/sha"],
                ["name": "Replay-2.5.0.zip", "browser_download_url": "https://e/zip"],
                ["name": "notes.pdf", "browser_download_url": "https://e/pdf"],
            ],
        ]
        let release = Updates.release(from: json)
        #expect(release?.downloadURL == "https://e/zip")
        #expect(release?.checksumURL == "https://e/sha")
    }
}
