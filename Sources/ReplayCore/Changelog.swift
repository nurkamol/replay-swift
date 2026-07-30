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
    public static let fallbackVersion = "0.9.8"
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
        version: "0.9.8",
        title: "Three OS generations, and words you can read",
        changes: [
            "**The permissions Replay does not use now have rows**, in Settings \u{25B8} Privacy and on the welcome screen. Each says where it stands, Accessibility\u{2019}s button asks macOS to add Replay to the list so only the switch is left, and **Reset** takes back anything granted earlier \u{2014} which could not be done from inside the app at all before. Nothing here is required; every row off is the state Replay is built for.",
            "**Replay runs on macOS 14 Sonoma.** It needed macOS 26 before \u{2014} a version most Macs are not on. Two calls in the interface wanted something newer, both are guarded now, and nothing about the app changed on a current Mac.",
            "**Below macOS 26 the Surfaces setting offers Solid and Frosted, and not Glass.** A setting that silently did nothing would be worse than one that is not there. A Glass preference carried over from a newer Mac draws as Frosted.",
            "**The parts you read most are translated.** A session is called \"Late night in Terminal\" and a gap \"8m not recorded\" \u{2014} sentences assembled as you go, which had no whole string for a translator to be given. Titles, gaps, the headline figures, the sidebar and the time labels now follow the language you chose. Uzbek is complete at 519 strings.",
            "**A report on a schedule.** Settings \u{25B8} Data writes a report of the period that just *finished* \u{2014} yesterday, or the week just gone \u{2014} into a folder you choose. The sibling of the scheduled backup, with one difference: a backup is insurance you hope never to open, and this is the one file here meant to be read.",
            "The schedules section used to report one schedule as if it were both, so \"Nothing has been written yet\" could sit directly under a line saying a report had just been written.",
        ]
    ),
    Release(
        version: "0.9.7",
        title: "Replay speaks Uzbek",
        changes: [
            "**Replay can be read in another language.** Settings \u{25B8} General \u{25B8} Language lists the languages this build carries and switches immediately \u{2014} no relaunch. Leave it on Match System and nothing changes.",
            "**Uzbek is the first, and it is complete**: all 423 strings, including the Guide and every Settings explanation. It was machine-translated and wants a native reader, so corrections are welcome and take one command to apply.",
            "**Translating Replay is now a documented job rather than a favour.** `tools/translate.mjs` writes a CSV a person or a translation service can fill in and turns it back into what ships; `docs/TRANSLATING.md` explains the round trip. A language ships only when it is complete \u{2014} a half-translated app that claims a language is worse than one that does not.",
            "The sidebar had never been translatable at all: its names come from an enum, which no scan for literal text could see. The most visible column in the app was English in every language, and now is not.",
        ]
    ),
    Release(
        version: "0.9.6",
        title: "A pause that ends itself, and a story that moves like one",
        changes: [
            "**Pausing can end by itself.** Pause for fifteen minutes, an hour, or until tomorrow, and recording comes back on its own \u{2014} after a quit, or a night with the lid shut. The menu bar and Settings say when it ends. Pausing with no end is still there; what this fixes is forgetting, which costs the rest of the day silently.",
            "**Replay Story moved in lurches**, and the reason was an embellishment of this port\u{2019}s own: the camera arrived, stopped, crept toward the next stop, stopped again, then jerked away. The creep is gone, the pause between stops is still, and each hop now eases at both ends.",
            "**The timeline beside the Canvas travels with the story.** It used to sit on whatever was selected when the story began \u{2014} a camera moving through one memory beside a list describing another.",
            "**After an update, Replay says what you got:** What\u{2019}s New opens when you pressed Update, and a dismissible note appears when the version arrived by `brew upgrade` instead. A downgrade says nothing.",
            "**Compacting no longer freezes the window.** It runs on its own connection with recording paused, so the button can say what it is doing rather than the app going quiet for the length of a whole-file rewrite.",
        ]
    ),
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
