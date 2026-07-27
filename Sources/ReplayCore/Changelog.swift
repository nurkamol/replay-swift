import Foundation

/// What each version of Replay actually gained.
///
/// The user-facing history, newest first, in the app's own voice — no marketing, and every
/// line describes something that changed rather than something that was worked on. The
/// canonical record stays in `CHANGELOG.md` at the repository root; this is the curated read
/// of it, and it is the same list the reference shows because it describes the same product.
public struct Release: Equatable, Sendable, Identifiable {
    public var version: String
    /// A short name for the release.
    public var title: String
    public var changes: [String]

    public var id: String { version }
}

public let releases: [Release] = [
    Release(
        version: "2.3.2",
        title: "Away time, restored",
        changes: [
            "Restoring a backup now brings your away time with it. An export always included the stretches when you were away from the keyboard, but the import quietly left them out — so a restored day showed those gaps as “Replay wasn't running” rather than “away”. Activity Replay recorded directly was never affected.",
        ]
    ),
    Release(
        version: "2.3.1",
        title: "Smaller pieces",
        changes: [
            "Delete a single session — a ⋯ menu at the foot of any expanded session, and on its right-click menu. It takes that run and any note on it; the rest of the day is left alone.",
            "Export one session — Markdown, PDF, HTML, CSV or JSON, from the same ⋯ menu, named after the session itself.",
            "Set the focus goal from Today — the goal card carries its own picker, so the figure and the control for it sit together.",
            "A session that ran past midnight no longer appears on two days when you open a past day. A run belongs to the day it began, as it does everywhere else.",
            "Fixed: importing a backup could erase the day-by-day headlines of days whose raw activity had already been pruned — the only record those days had left.",
            "Fixed: excluding an application left its notes and bookmarks behind, pointing at sessions that could no longer be reached.",
        ]
    ),
    Release(
        version: "2.3.0",
        title: "Forgetting a day",
        changes: [
            "A ⋯ menu on every day — on its divider in the Timeline and on the day's own page. Open the day, export just that day as Markdown, PDF, HTML, CSV or JSON, or delete it.",
            "Delete a single day — from that menu, or by picking a day in Settings ▸ Data ▸ Storage. Its sessions, summary, reflection and notes go with it, and every other day is left untouched.",
            "Space you free now comes back. Deleting history used to leave the size on disk unchanged; Replay now rewrites its database after a large deletion, and Data ▸ Storage can compact it on demand and tell you how much returned.",
            "A focus goal of any length — every hour from 1 to 8, plus Custom for a target that isn't a round number, like 45 minutes or 5½ hours.",
            "Storage settings say what a day of history actually costs — Replay records no video or screenshots, so it's a few hundred kilobytes.",
        ]
    ),
    Release(
        version: "2.2.0",
        title: "Replay any day",
        changes: [
            "Replay any day straight from the Timeline — a Replay button on each day's divider plays it back, morning to evening.",
            "A What's New history — Replay now keeps its own story, in Settings ▸ About and the Help menu.",
        ]
    ),
    Release(
        version: "2.1.1",
        title: "Polish",
        changes: [
            "Meaningful Moments now appear as their own stars on the Canvas.",
            "Today leads with the work you most recently stepped away from, and a Reflect shortcut brings the day's reflection into reach.",
            "Timeline, Canvas, and Today stay fast even after years of recorded history.",
        ]
    ),
    Release(
        version: "2.1.0",
        title: "Contextual Memory Intelligence & Replay Canvas",
        changes: [
            "Contextual memories that surface only when they're relevant — a return to an app after time away, an anniversary, a bookmark left unopened — and stay quiet otherwise.",
            "Replay Canvas: an infinite, explorable memory space of your projects, apps, collections and chapters, with a synced timeline and a camera that can tour a memory.",
            "Layered Timeline — read your days at any depth, from sessions to reflections to moments.",
            "Story Mode, weekly narratives, and a calm Morning Briefing.",
        ]
    ),
    Release(
        version: "2.0.0",
        title: "The Living Memory Engine",
        changes: [
            "Chapters, My Story, and the Museum — your history gathered and told back to you.",
            "Reflections and Meaningful Moments, drawn entirely from local activity.",
            "The first memory graph of the apps you move between.",
        ]
    ),
    Release(
        version: "1.3.0",
        title: "Reliving your day",
        changes: [
            "Replay Movie, Ambient mode, and a Screensaver — watch your day play back, or leave it drifting on a second screen.",
            "Collections, Projects, and the Constellation — your sessions by kind, the app combinations behind your work, and your apps as a field of connected stars.",
            "Reflections, daily memory quotes, and Surprise me, to rediscover a day at random.",
            "Meaningful search across everything, and a calendar heatmap to walk back to any day.",
        ]
    ),
    Release(
        version: "1.2.0",
        title: "Today in History",
        changes: [
            "A memory card on Today that resurfaces what you were doing on this date — a week, a month, a year ago.",
            "A Memories gallery and a calendar to open any past day, with a calm “then vs now” comparison.",
            "An optional “on this day” note each morning.",
            "Jump to a day by name in Search — “yesterday”, “last Friday”, “one year ago”.",
        ]
    ),
    Release(
        version: "1.1.0",
        title: "Sessions & Time Travel",
        changes: [
            "App-switching folded into named sessions with honest breaks and away-time.",
            "Time Travel & Replay — Today, Yesterday, the last 7 or 30 days, or play a day back.",
            "Notes, bookmarks & #tags on sessions, optional focus goals with a gentle streak, and search upgrades.",
            "Daily & weekly recaps, favourites and per-app history, and export to PDF, CSV, and JSON.",
        ]
    ),
    Release(
        version: "1.0.0",
        title: "The beginning",
        changes: [
            "The first release — a private, local timeline of the apps you use, held on this Mac and nowhere else.",
        ]
    ),
]
