@testable import ReplayCore
import Foundation
import Testing

/// What a focused thing pulls in with it.
///
/// Two rules that decide what a person sees when they point at something — the sessions
/// behind a node on the Canvas, and the chapter a past day belonged to. Neither is exported
/// upstream (both live inside a view), so neither is in the generated contract and neither
/// would fail loudly on drifting. The cases here are the ones where the two runtimes, or the
/// two node kinds, could plausibly disagree.
@Suite("Focus behaviour")
struct FocusBehaviour {

    private static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    private static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Int64 {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return Int64(calendar().date(from: parts)!.timeIntervalSince1970 * 1000)
    }

    private static func session(
        _ title: String, at start: Int64, category: SessionCategory = .development,
        apps: [String] = []
    ) -> ActivitySession {
        ActivitySession(
            title: title,
            category: category,
            startedAt: start,
            endedAt: start + 3_600_000,
            spanSeconds: 3600,
            activeSeconds: 3600,
            apps: apps.map {
                SessionApp(
                    applicationName: $0, bundleIdentifier: "com.test.\($0)",
                    appPath: nil, seconds: 3600, share: 1, switches: 1
                )
            },
            events: [],
            switches: 1
        )
    }

    private static func node(
        _ id: String, _ type: CanvasGraph.NodeType, ref: String
    ) -> CanvasGraph.Node {
        CanvasGraph.Node(
            id: id, type: type, label: id, subtitle: "", category: .development,
            weight: 1, appPath: nil, bundleID: nil, ref: ref
        )
    }

    // ── the canvas ────────────────────────────────────────────────────────────

    @Test("A node's neighbours are what it is joined to, and itself")
    func neighbours() {
        let graph = CanvasGraph(
            nodes: [],
            edges: [
                CanvasGraph.Edge(a: "a", b: "b", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "c", b: "a", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "d", b: "e", weight: 1, kind: .appApp),
            ],
            maxAppWeight: 1
        )
        // Itself included, so the focused node is not dimmed by its own rule.
        #expect(graph.neighbours(of: "a") == ["a", "b", "c"])
        // Edges are undirected here: being named second still counts.
        #expect(graph.neighbours(of: "b") == ["b", "a"])
        #expect(graph.neighbours(of: "nothing") == ["nothing"])
    }

    @Test("A Replay Story visits the heaviest neighbours and comes home")
    func tourPath() {
        // Built so two of them tie on weight, because a fixture that never ties would pass
        // against an unstable sort — the same reason the collections fixture ties twice.
        // `b` and `d` are both 5; upstream keeps them in edge order, so `b` has to come out
        // first because its edge is scanned first.
        func weighted(_ id: String, _ weight: Int) -> CanvasGraph.Node {
            var node = Self.node(id, .app, ref: id)
            node.weight = weight
            return node
        }
        let graph = CanvasGraph(
            nodes: [
                weighted("a", 100), weighted("b", 5), weighted("c", 9),
                weighted("d", 5), weighted("e", 1), weighted("f", 7), weighted("g", 3),
            ],
            edges: [
                CanvasGraph.Edge(a: "a", b: "b", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "c", b: "a", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "a", b: "d", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "a", b: "e", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "f", b: "a", weight: 1, kind: .appApp),
                CanvasGraph.Edge(a: "a", b: "g", weight: 1, kind: .appApp),
                // Nothing to do with `a`, so it is never a stop.
                CanvasGraph.Edge(a: "x", b: "y", weight: 1, kind: .appApp),
            ],
            maxAppWeight: 100
        )

        // Heaviest first, the tie in edge order, capped at five, and home again. `e` is the
        // lightest of six neighbours and is the one left out.
        #expect(graph.tourPath(from: "a") == ["a", "c", "f", "b", "d", "g", "a"])

        // The node itself is never a stop in the middle, even though `neighbours(of:)`
        // includes it — that one answers a different question.
        #expect(graph.tourPath(from: "a").dropFirst().dropLast().contains("a") == false)

        // A node joined to nothing still tours, degenerately, because the reference's path
        // is `[id, ...[], id]` and it runs it.
        #expect(graph.tourPath(from: "e") == ["e", "a", "e"])
        #expect(graph.tourPath(from: "alone") == ["alone", "alone"])
    }

    @Test("Each kind of node answers with the sessions it actually stands for")
    func sessionsBehindEachKind() {
        let monday = Self.at(2026, 7, 13, 9)
        let tuesday = Self.at(2026, 7, 14, 9)
        let sessions = [
            Self.session("Code", at: monday, category: .development, apps: ["Code"]),
            Self.session("Design", at: tuesday, category: .design, apps: ["Figma"]),
            Self.session("Both", at: tuesday + 7_200_000, category: .development, apps: ["Code", "Figma"]),
        ]
        let graph = CanvasGraph(nodes: [], edges: [], maxAppWeight: 1)

        // An application matches inside a session's apps — including one it shares.
        let app = graph.sessions(
            behind: Self.node("app:code", .app, ref: "com.test.Code"),
            in: sessions, calendar: Self.calendar()
        )
        #expect(app.map(\.title) == ["Both", "Code"])

        // A collection is a category, exactly.
        let collection = graph.sessions(
            behind: Self.node("c", .collection, ref: SessionCategory.design.rawValue),
            in: sessions, calendar: Self.calendar()
        )
        #expect(collection.map(\.title) == ["Design"])

        // A project owns its sessions rather than matching them, so an unknown signature
        // finds none rather than falling back to everything.
        let project = graph.sessions(
            behind: Self.node("p", .project, ref: "sig"),
            in: sessions,
            projectSessions: ["sig": [sessions[0]]],
            calendar: Self.calendar()
        )
        #expect(project.map(\.title) == ["Code"])
        #expect(
            graph.sessions(
                behind: Self.node("p", .project, ref: "missing"),
                in: sessions, calendar: Self.calendar()
            ).isEmpty
        )

        // A chapter is really a set of days.
        let chapter = graph.sessions(
            behind: Self.node("ch", .chapter, ref: "one"),
            in: sessions,
            chapterDays: ["one": [startOfLocalDay(tuesday, calendar: Self.calendar())]],
            calendar: Self.calendar()
        )
        #expect(chapter.map(\.title) == ["Both", "Design"])
    }

    /// The distinction that matters: a moment with no date must find *nothing*, not
    /// everything. An empty ref parsed as "no filter" would put the whole month behind a
    /// single undated star.
    @Test("A moment with no day behind it finds no sessions rather than all of them")
    func undatedMomentFindsNothing() {
        let sessions = [Self.session("Code", at: Self.at(2026, 7, 13, 9))]
        let graph = CanvasGraph(nodes: [], edges: [], maxAppWeight: 1)
        #expect(
            graph.sessions(
                behind: Self.node("m", .moment, ref: ""),
                in: sessions, calendar: Self.calendar()
            ).isEmpty
        )
        let dated = graph.sessions(
            behind: Self.node(
                "m", .moment,
                ref: String(startOfLocalDay(Self.at(2026, 7, 13, 9), calendar: Self.calendar()))
            ),
            in: sessions, calendar: Self.calendar()
        )
        #expect(dated.count == 1)
    }

    @Test("The panel is capped, newest first")
    func cappedAndOrdered() {
        let base = Self.at(2026, 7, 13, 0)
        let many = (0..<(CanvasGraph.focusSessionLimit + 10)).map {
            Self.session("s\($0)", at: base + Int64($0) * 60_000, category: .development)
        }
        let graph = CanvasGraph(nodes: [], edges: [], maxAppWeight: 1)
        let found = graph.sessions(
            behind: Self.node("c", .collection, ref: SessionCategory.development.rawValue),
            in: many, calendar: Self.calendar()
        )
        #expect(found.count == CanvasGraph.focusSessionLimit)
        // Newest first, so the cap drops the oldest rather than the most recent.
        #expect(found.first?.startedAt == many.last?.startedAt)
    }

    // ── a day's chapter ───────────────────────────────────────────────────────

    private static func chapter(_ id: String, days: [Int64]) -> Chapter {
        Chapter(
            id: id, startDay: days.min() ?? 0, endDay: days.max() ?? 0,
            category: .development, dayCount: days.count, totalActiveSeconds: 3600,
            apps: [], representativeDay: days.first ?? 0, days: days
        )
    }

    @Test("A day younger than a week is given no chapter context")
    func tooRecentForContext() {
        let today = Self.at(2026, 7, 27, 0)
        let chapters = [Self.chapter("one", days: [today - 2 * dayMillis, today])]
        // Six days old: still inside the stretch it belongs to.
        #expect(
            chapterContext(
                for: today - 6 * dayMillis, now: today + 12 * 3_600_000, chapters: chapters
            ) == nil
        )
    }

    @Test("An old day is placed in its chapter, with the nearest days around it")
    func contextOffersNearestDays() {
        let now = Self.at(2026, 7, 27, 12)
        let day = Self.at(2026, 7, 10, 0)
        let days = (0..<9).map { day + Int64($0 - 4) * dayMillis }
        let found = chapterContext(
            for: day, now: now, chapters: [Self.chapter("one", days: days)]
        )

        #expect(found?.chapter.id == "one")
        // The day itself is not among its own neighbours...
        #expect(found?.nearbyDays.contains(day) == false)
        // ...and the four nearest are taken, then read back newest first.
        #expect(found?.nearbyDays == [
            day + 2 * dayMillis, day + dayMillis, day - dayMillis, day - 2 * dayMillis,
        ])
    }

    @Test("A day in no chapter is given no context")
    func noChapterForThatDay() {
        let now = Self.at(2026, 7, 27, 12)
        let chapters = [Self.chapter("one", days: [Self.at(2026, 6, 1, 0)])]
        #expect(chapterContext(for: Self.at(2026, 7, 1, 0), now: now, chapters: chapters) == nil)
    }
}

/// Living Home: which single card Today leads with.
@Suite("Today's hero")
struct TodayHeroBehaviour {
    private static let day = 86_400_000 as Int64

    /// A Thursday midnight, so the day number is a known one.
    private static func midnight(_ daysSinceEpoch: Int64) -> Int64 { daysSinceEpoch * day }

    @Test("A session you just stepped away from always leads")
    func freshResumeWins() {
        // Day 20,601 with all four available rotates to today-in-history — which is the
        // point of picking it: if the freshness rule did nothing, both halves below would
        // come back the same, and the test would pass while proving nothing.
        let today = Self.midnight(20_601)
        let now = today + 10 * 3_600_000
        let all = TodayHeroOffer(
            hasFeaturedMemory: true, hasRecentReflection: true, hasQuote: true
        )

        var fresh = all
        fresh.resumeEndedAt = now - 3_600_000
        #expect(pickTodayHero(fresh, now: now, todayStart: today) == .resume)

        // Seven hours old is past the six-hour window, so it stops overriding and takes its
        // turn with the rest.
        var stale = all
        stale.resumeEndedAt = now - 7 * 3_600_000
        #expect(pickTodayHero(stale, now: now, todayStart: today) == .todayInHistory)
    }

    @Test("The choice holds for a day and changes the next")
    func rotatesByDay() {
        let offer = TodayHeroOffer(
            hasFeaturedMemory: true, hasRecentReflection: true, hasQuote: true
        )
        // Three candidates, so the rotation has period three and every one is reached.
        let picks = (0..<6).map { index -> TodayHero? in
            let today = Self.midnight(20_600 + Int64(index))
            return pickTodayHero(offer, now: today + 1, todayStart: today)
        }
        #expect(Set(picks.compactMap { $0 }).count == 3)
        #expect(picks[0] == picks[3])
        #expect(picks[1] == picks[4])
        #expect(picks[0] != picks[1])

        // And it does not change through the day it was chosen for.
        let today = Self.midnight(20_600)
        let morning = pickTodayHero(offer, now: today + 3_600_000, todayStart: today)
        let night = pickTodayHero(offer, now: today + 23 * 3_600_000, todayStart: today)
        #expect(morning == night)
    }

    @Test("History off leaves only what is yours, and nothing is a real answer")
    func historyOffAndEmpty() {
        let today = Self.midnight(20_600)
        // The quote and today-in-history are memories; a reflection is your own writing.
        let offer = TodayHeroOffer(
            hasFeaturedMemory: true, hasRecentReflection: true, hasQuote: true,
            historyEnabled: false
        )
        #expect(pickTodayHero(offer, now: today + 1, todayStart: today) == .reflection)

        // Most days there is nothing to lead with, and Today leads with nothing.
        #expect(pickTodayHero(TodayHeroOffer(), now: today + 1, todayStart: today) == nil)
    }

    @Test("The featured memory is the fullest day, ties keeping the nearer one")
    func featuredIsFullest() {
        func memory(_ dayStart: Int64, _ seconds: Int) -> Memories.Memory {
            Memories.Memory(
                range: Memories.Range(key: "m\(dayStart)", label: "", dayStart: dayStart),
                summary: DailySummary(dayStart: dayStart, activeSeconds: seconds)
            )
        }
        let memories = [memory(1, 600), memory(2, 900), memory(3, 900)]
        // 2 and 3 tie; the earlier in the list wins, which is the nearer offset to today.
        #expect(Memories.pickFeatured(memories)?.range.dayStart == 2)
        #expect(Memories.pickFeatured([]) == nil)
    }
}
