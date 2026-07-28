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
}
