import Foundation

/// This build's version.
///
/// **Reads `Info.plist` first, and that is a correction rather than a refinement.** The
/// comment here used to say "everything reads that first" and it was not true: this literal
/// was what `UpdateModel` compared against, so a 0.9.2 build believed it was 0.9.0, told its
/// owner "you have 0.9.0", and would have offered an update to a version it was already
/// running. `scripts/make-app.sh` writes the plist and nothing wrote this, which is exactly
/// the drift the old comment claimed to have prevented.
///
/// The literal survives as the fallback for running the binary outside a bundle — the CLI,
/// the parity suite — and `tools/version-audit.mjs` fails the build when it disagrees with
/// `make-app.sh`, the changelog, or the in-app release list.
public enum Replay {
    public static let version: String =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? fallbackVersion

    /// The version in the source, for when there is no bundle to ask.
    public static let fallbackVersion = "0.9.5"
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
        version: "0.9.5",
        title: "The update check stops wasting its own attempts",
        changes: [
            "**A refused check no longer counts as the day\u{2019}s check.** If GitHub turns the request away \u{2014} usually because too many have come from your network in an hour \u{2014} Replay used to record it as having asked and wait a full day. Meanwhile a check that failed because the Mac was offline retried freely. Exactly backwards, and now only an answer counts.",
            "**It says when the limit clears** rather than \u{201C}try again later\u{201D}, and does not ask again before then. GitHub names the time in its reply; Replay reads it.",
            "**The check asks a smaller question.** It sends the tag from last time, so an unchanged answer comes back empty instead of carrying a release it already had. That saves bytes rather than requests \u{2014} measured, GitHub counts it either way, and the release notes say so rather than claiming otherwise.",
        ]
    ),
    Release(
        version: "0.9.4",
        title: "A second screen, and backups you never take",
        changes: [
            "**Ambient mode can be left open on another screen.** It stops taking the keyboard and stops closing when you type, which is what a display on a second monitor is for. Only on a screen other than the one Replay\u{2019}s window is on \u{2014} a display that covers your work and answers no keys is a trap rather than a feature.",
            "**Settings \u{25B8} Display says which screen** the screensaver and ambient mode take, and which of the two drifts in when you go quiet \u{2014} after how long, and only between hours you choose if you would rather it kept to an evening.",
            "**Replay can keep its own backups.** The same full backup, every day or every week, into a folder you choose: written whole or not at all, eight kept, and only its own older copies removed. Off until you choose a folder; nothing leaves this Mac, as ever.",
            "**Mark the stretch you are in from the menu bar**, or with \u{21E7}\u{2318}N from anywhere \u{2014} a bookmark, or a note in a small panel. The moment worth writing down is the one you are in, and it passes while you are finding the session in a window.",
            "**\u{201C}Theme: Light\u{201D} left half the app dark.** The appearance reached the main window and the menu bar panel and no others, so Settings and What\u{2019}s New followed the system instead. Fixed in the one place every window reads it from.",
        ]
    ),
    Release(
        version: "0.9.3",
        title: "Updates that install themselves",
        changes: [
            "**Replay can update itself.** When a newer version exists, the banner\u{2019}s button downloads it, checks it against the checksum published beside it, makes sure it is signed and is this application and is the version it claimed to be, and then replaces itself and restarts.",
            "What that trust rests on is worth knowing: a secure connection to Replay\u{2019}s own repository, and that published checksum. It proves the download is the one the release carries \u{2014} not that the release is trustworthy, because Replay has no Apple Developer ID to prove who made it. Leave the check off if that is not a trust you want to extend.",
            "It declines rather than doing damage in three cases: a copy installed by Homebrew is left to `brew upgrade`, a copy macOS is running from its temporary read-only folder has nothing to replace, and a read-only location refuses rather than half-installing.",
        ]
    ),
    Release(
        version: "0.9.2",
        title: "The app opens",
        changes: [
            "0.9.1 shipped a build that would not launch: it could not find the file holding its own text, and stopped rather than carrying on in English. It carries on in English now.",
            "The release is checked by running it before it is published, which is the only way to catch a build that passes every test and still cannot open.",
        ]
    ),
    Release(
        version: "0.9.1",
        title: "PDF, the menu bar, and a record that cannot corrupt itself",
        changes: [
            "**Export as PDF** \u{2014} one page, with a line telling you where the rest is when a span is longer than that. Export as HTML for the whole of it.",
            "**The menu bar opens rather than dropping down.** What you are in and for how long, the day\u{2019}s total, the focus goal, the last three sessions, and a pause control \u{2014} without opening the window.",
            "**Two copies of Replay could zero each other\u{2019}s live session.** Opening a second copy while one was recording set the stretch you were in the middle of to nothing. A second copy now hands the first one the front and leaves.",
            "The year grid\u{2019}s weekday key sat a hundred points from the year it labelled, the week\u{2019}s rhythm left a dead gap before its durations, and a page never grew with its window. All three were only ever visible, and all three are fixed.",
        ]
    ),
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
