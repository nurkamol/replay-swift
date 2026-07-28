import Foundation

/// This build's version, for the two places that need one when `Info.plist` is not there.
///
/// `scripts/make-app.sh` is the source of truth — it writes `CFBundleShortVersionString`,
/// and everything reads that first. This is the fallback for running the binary outside a
/// bundle, and it existed twice as a literal `"0.1.0"` in two different files, which is
/// exactly how a version number goes stale in one place and not the other.
public enum Replay {
    public static let version = "0.9.0"
}

/// What each version of Replay actually gained.
///
/// The user-facing history, newest first, in the app's own voice — no marketing, and every
/// line describes something that changed rather than something that was worked on. The
/// canonical record stays in `CHANGELOG.md` at the repository root; this is the curated read
/// of it.
///
/// **This is *this* app's history, not the reference's.** It used to be the Glaze app's
/// release list — 1.0.0 through 2.3.2 — on the reasoning that the two describe the same
/// product. That stopped being defensible the moment this port took a version of its own:
/// About said 0.9.0 and What's New said "2.3.2 — Away time, restored", which is a release
/// nobody running this app has ever had. The reference's history is not lost; it is kept
/// verbatim in `docs/GLAZE-CHANGELOG.md`, which is where a record of somebody else's
/// releases belongs.
public struct Release: Equatable, Sendable, Identifiable {
    public var version: String
    /// A short name for the release.
    public var title: String
    public var changes: [String]

    public var id: String { version }
}

public let releases: [Release] = [
    Release(
        version: "0.9.0",
        title: "Everything, on your own Mac",
        changes: [
            "Replay records which application is in front, all day, and turns it into a day you can read back. It asks for no permissions at all — no Accessibility, no Automation, no Screen Recording — because that is the point of it rather than a limitation.",
            "**Today** leads with one thing rather than a stack: the session you stepped away from, a memory from this date, a reflection you wrote, or a quote — chosen for the day and changed tomorrow.",
            "**The Timeline** is your recent days, newest first, with the gaps left in. Being away and not being recorded are shown as different things, because they are.",
            "**Search** finds a session by name, note, tag or application — and understands a few phrases like \u{201C}morning\u{201D}, \u{201C}longest\u{201D} and \u{201C}bookmarked\u{201D}, which take you to a slice of the day rather than matching the word.",
            "**Memories** shows what this date held a week, a month and up to two years ago, and a calendar of every day you have recorded. It keeps working after the raw activity is pruned, because a day\u{2019}s headline outlives it.",
            "**Your story** — an autobiography told back to you a month at a time, the eras your history fell into, a museum of the best of it, and the rhythms your days settle into. Every sentence is drawn from your own history. Nothing is invented.",
            "**The Canvas** is the whole record as a field you can fly through, and **Replay Story** flies it for you: a camera tour through a memory and the things around it, which narrates by moving rather than by writing.",
            "**Replay Day** plays a day back at 1\u{00D7}, 2\u{00D7} or 5\u{00D7}. **Ambient mode** puts today on a second screen in type you can read across a room, and the **screensaver** drifts through your day when you have gone.",
            "**Projects and Collections** appear on their own — the applications that keep coming back together, and every session of one kind — with nothing to set up and nothing to file.",
            "**Export** a day, a session or a scope as Markdown, CSV, JSON or HTML, and take a full backup that both this app and the Glaze app can read.",
            "This is the first version that has everything the Glaze app has. It is not signed for distribution yet, which is the only thing between it and a build you could pass to somebody.",
        ]
    ),
]
