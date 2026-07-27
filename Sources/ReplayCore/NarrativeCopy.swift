import Foundation

/// The words the narrative surfaces say.
///
/// Story, Chapters and Autobiography are almost entirely prose. Between them they are a hub
/// of four cards that each explain themselves, three subtitles, three empty states and two
/// footnotes — and until the audit of 2026-07-28 nothing held any of it. Every one had been
/// paraphrased: close in meaning, not one of them the reference's own sentence, and the
/// footnotes missing outright. SPEC §8 says the copy *is* the product, which is the whole
/// reason this file exists rather than a comment saying "keep these in sync".
///
/// Generated into `spec/narrative-copy.json` and checked character for character, the same
/// way the Guide's sixteen answers and the Settings rows are. Changing a word fails the
/// suite by name.
public enum NarrativeCopy {

    // MARK: - Story, the hub

    public static let storyTitle = "Your story"
    public static let storySubtitle =
        "The long view of your work — told back to you, gathered into eras, and reflected "
        + "in the rhythms you fall into."

    /// The four ways in, in the order the reference lays them out. `My Story` runs the full
    /// width above the other three: it is the whole archive, and they are ways into parts
    /// of it.
    public static let storyHub: [(title: String, detail: String)] = [
        (
            "My Story",
            "The whole of it at a glance — how long you've been building, and everything it "
                + "holds."
        ),
        ("Autobiography", "Your history told back to you, a month or a year at a time."),
        ("Chapters", "Your history divided into the eras it naturally fell into."),
        ("Museum", "A curated walk through the best of your history."),
    ]

    public static let ritualsLabel = "Your rituals"
    /// The rule, said out loud. Without it a ritual looks like something the app decided,
    /// and the last clause is the part that matters: nothing here was set or scheduled.
    public static let ritualsFootnote =
        "A part becomes a ritual once the same app has led it on more than one day. Read "
        + "only from your history — nothing set, nothing scheduled."
    public static let ritualsEmptyTitle = "Your rituals will appear here"
    public static let ritualsEmptyDetail =
        "As the days repeat, Replay notices the app you usually open first and the ones "
        + "that tend to lead each part of your day."

    // MARK: - Chapters

    public static let chaptersSubtitle =
        "Your history, divided into the eras it naturally fell into — and yours to name."
    public static let chaptersEmptyTitle = "No chapters yet"
    public static let chaptersEmptyDetail =
        "As the days add up, Replay gathers the ones that share a character into chapters "
        + "you can revisit and name — a week or two of history is enough for the first."

    // MARK: - Autobiography

    public static let autobiographySubtitle =
        "Your history, told back to you — a week, a month, or a year at a time, only from "
        + "what you actually did."
    public static let autobiographyEmptyTitle = "Your story is still being written"
    public static let autobiographyEmptyDetail =
        "Once Replay has recorded a few days, it will begin telling the story of each week, "
        + "month, and year back to you here."
    /// The claim the feature rests on. "Told back to you" invites the question of who is
    /// doing the telling, and this answers it.
    public static let autobiographyFootnote =
        "Every sentence is drawn only from your own local history. Nothing is invented."

    // MARK: - Museum

    public static let museumSubtitle =
        "A quiet walk through the best of your history — the memories, the deep focus, the "
        + "things you kept."
    /// The five rooms, in order. Four of the five had been renamed in this port — "Things
    /// you wrote" for *Reflections*, "The work that took the most" for *Projects that
    /// mattered* — which reads as the same museum with different signage, and is not.
    public static let museumSections = [
        "Milestones", "Greatest focus", "Bookmarks", "Reflections", "Projects that mattered",
    ]
    public static let museumEmptyTitle = "The museum is still filling"
    public static let museumEmptyDetail =
        "As you work, bookmark a session, and jot a reflection, the most meaningful pieces "
        + "of your history gather here."

    // MARK: - My Story

    public static let legacySubtitle =
        "The whole of it, at a glance — how long you've been building this memory, and "
        + "everything it holds."
    /// Three sections. This port had two: **Growth** — the heatmap over the whole archive —
    /// was missing outright, which is why the audit found it.
    public static let legacySections = ["Years", "Growth", "Favourite applications"]
    public static let legacyEmptyTitle = "Your story is just beginning"
    public static let legacyEmptyDetail =
        "As the days, chapters, and projects accumulate, this becomes a lasting archive of "
        + "your digital history."

    // MARK: - An application's own page, and a pair's

    /// Both of these name the window — thirty days — rather than saying "the kept history".
    /// The window is the answer to "why is this empty", and a reader cannot infer it.
    public static let appHistoryEmptyTitle = "No recent history"
    public static let appHistoryEmptyDetail =
        "Replay hasn\u{2019}t recorded this application in the last 30 days."
    public static let relationshipEmptyTitle = "No shared history"
    public static let relationshipEmptyDetail =
        "These two apps haven\u{2019}t been used together in the last 30 days."
}
