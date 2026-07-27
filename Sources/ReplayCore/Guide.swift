import Foundation

/// The Guide: sixteen questions and the answers Replay gives them.
///
/// Every word here is the reference's, and that is the point. This is the largest single
/// body of copy in the app, all of it read by a person, and SPEC §8 says the words are the
/// product. It is generated into `spec/guide.json` from the Glaze sources and compared
/// character for character by the parity suite — retyping sixteen answers by hand would be
/// sixteen chances to paraphrase, and nothing would have noticed.
///
/// This port previously answered four questions of its own devising: what Replay records,
/// permissions, what a session is, and why the file does not shrink. Reasonable questions,
/// none of them the reference's, and between them they left out where the data lives, what
/// the Canvas is, what Contextual Memory Intelligence is, and how to pause tracking.
///
/// Here rather than in the view for the usual reason: `ParityKit` cannot import `ReplayApp`,
/// and copy that matters is worth comparing against the real thing rather than a mirror.
public enum Guide {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let question: String
        public let answer: String
        public var id: String { question }
    }

    /// In the reference's own order, which runs from how it works to what you can do about
    /// it — recording, storage, permissions, then the surfaces, then the controls.
    public static let entries: [Entry] = [
        Entry(
            question: "How does Replay know what I’m doing?",
            answer: "It notices which application is frontmost using macOS’s standard "
                + "app-switch signal, and records the app’s name and how long it stayed in "
                + "front. Never what’s inside a window, never your keystrokes, never "
                + "content."
        ),
        Entry(
            question: "Where does my data live?",
            answer: "In a single database file in your own user folder — the Privacy tab "
                + "shows the exact path. It never leaves this Mac: no cloud, no account, no "
                + "network."
        ),
        Entry(
            question: "Which permissions does Replay need?",
            answer: "None for the tracking itself. Replay reads which app is frontmost "
                + "through macOS’s standard app-switch signal, which any app can observe — "
                + "so it needs no Accessibility, Automation, or App Management permission, "
                + "and it never inspects your window contents. Privacy ▸ Recording shows a "
                + "live check that it’s working, with links into System Settings if you’re "
                + "on a managed Mac that asks for Accessibility anyway."
        ),
        Entry(
            question: "Why is Memories empty?",
            answer: "Memories resurfaces past days that share today’s date, so it only has "
                + "the history Replay has recorded so far. It fills in over the coming "
                + "weeks and months — the longer Replay runs, the richer it gets."
        ),
        Entry(
            question: "What are Collections, Projects, and the Canvas?",
            answer: "Different lenses on the same local history. Collections gather your "
                + "sessions by the kind of work they were. Projects surface the app "
                + "combinations that keep recurring, and let you name them. The Canvas lays "
                + "your projects, apps, collections, chapters and moments out as an "
                + "explorable space you can pan and zoom — click a memory to focus what "
                + "connects to it, double-click to open it, or open a synced timeline "
                + "beside it. Nothing to set up; it fills in as Replay runs."
        ),
        Entry(
            question: "Replay sometimes surfaces a memory on its own — what is that?",
            answer: "That’s Contextual Memory Intelligence: when something becomes relevant — "
                + "you return to an app after a while away, an anniversary comes round, a "
                + "bookmark has been sitting unopened — Replay quietly surfaces it on "
                + "Today, and stays silent when nothing is worth saying. Every card can be "
                + "dismissed, and you can tune how often it speaks, or turn it off "
                + "entirely, in Settings ▸ General ▸ Contextual memories."
        ),
        Entry(
            question: "Can I write something to remember about a day?",
            answer: "Yes — a Reflection. On Today, and on any past day you open, there’s a "
                + "line to jot what you’d like to remember. It’s kept locally with "
                + "everything else and turns up in Search. You can also press Replay Day on "
                + "Today to watch the day play back as a short movie."
        ),
        Entry(
            question: "Can I stop Replay recording an app?",
            answer: "Yes — Privacy ▸ Excluded applications. Excluding an app also erases the "
                + "history already recorded for it, so it leaves no trace."
        ),
        Entry(
            question: "Can I delete just one session?",
            answer: "Yes — open a session and use the ⋯ menu at the foot of it, or "
                + "right-click the session anywhere it appears. Either removes exactly that "
                + "run and any note or bookmark on it; the rest of the day stays, and the "
                + "day's totals are restated to match. That same ⋯ menu exports just that "
                + "session."
        ),
        Entry(
            question: "Can I delete a single day?",
            answer: "Yes, three ways: the ⋯ menu on that day's divider in the Timeline, the "
                + "same ⋯ menu on the day's own page, or Data ▸ Storage ▸ Delete a single "
                + "day. Any of them removes that day's sessions, its summary, its "
                + "reflection, and any notes or bookmarks on it, and leaves every other day "
                + "alone. For bigger sweeps, Data ▸ Storage can stop keeping raw activity "
                + "past 90 days, 6 months, or a year, and Privacy ▸ Clear History erases "
                + "everything."
        ),
        Entry(
            question: "How much space does Replay use?",
            answer: "Very little — Replay records no video, screenshots, or window contents, "
                + "only which app was in front and when. That's a few hundred kilobytes for "
                + "a heavy day, so tens of megabytes across a year. Privacy shows the "
                + "database's exact size and where it lives."
        ),
        Entry(
            question: "I deleted history but the size on disk didn't change — why?",
            answer: "Deleting rows frees space inside the database file without shrinking the "
                + "file itself; the room is kept for future writes. Replay rewrites the "
                + "file after a large deletion so the space returns to your disk, and Data "
                + "▸ Storage ▸ Compact database does it on demand and tells you how much "
                + "came back."
        ),
        Entry(
            question: "Do the notifications cost anything?",
            answer: "No. The daily, weekly, and “on this day” recaps are built entirely from "
                + "your local data and delivered by macOS. Nothing is uploaded, and there’s "
                + "no account behind them."
        ),
        Entry(
            question: "How do I start the screensaver, and how does it close?",
            answer: "Start it from the Screensaver button at the bottom of the sidebar, from "
                + "⌘K ▸ Screensaver, or let it drift in on its own — General ▸ Screensaver "
                + "can auto-start it after a spell of inactivity. Esc and the ✕ always "
                + "close it; whether a click, a key, or mouse movement also closes it is up "
                + "to you in that same section (mouse movement is off by default, so a "
                + "hand-started screensaver stays put)."
        ),
        Entry(
            question: "How do I keep a copy of my history?",
            answer: "Data ▸ Export report saves a slice as Markdown, PDF, HTML, CSV, or JSON "
                + "— the HTML report carries app icons and styling, and PDF stays to one "
                + "page with a pointer to HTML for longer spans. A single day exports from "
                + "the ⋯ menu on its divider in the Timeline. Full backup exports the whole "
                + "database, and importing merges rather than overwriting."
        ),
        Entry(
            question: "Can I pause tracking?",
            answer: "Any time — from the menu bar or Privacy ▸ Activity tracking. Replay "
                + "stops recording immediately, and your history is left untouched."
        ),
    ]
}
