import AppKit
import Foundation
import Observation
import ReplayCore

/// The memory space: the graph, and where each node sits in it.
///
/// The layout is a small force simulation run once when the graph is built, not continuously
/// — a field that keeps drifting is a screensaver rather than a map, and the whole point is
/// that things stay where you left them. Positions are seeded deterministically from each
/// node's id, so the same history lays out the same way every time the view opens.
@MainActor
@Observable
final class CanvasModel {
    private(set) var graph = CanvasGraph(nodes: [], edges: [], maxAppWeight: 0)
    private(set) var positions: [String: CGPoint] = [:]
    private(set) var loaded = false

    private let model: AppModel
    private let projects: ProjectsModel
    private let story: StoryModel

    init(model: AppModel, projects: ProjectsModel, story: StoryModel) {
        self.model = model
        self.projects = projects
        self.story = story
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let today = startOfLocalDay(now)
        let from = today - Int64(projectDays - 1) * dayMillis
        let events = ((try? model.store.sessions(from: from, to: today + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        let sessions = sessionsForWeek(events, now: now)

        if !projects.loaded { projects.load() }
        if !story.loaded { story.load() }

        let summaries = (try? model.store.dailySummaries(from: 0, to: today + dayMillis)) ?? []
        let moments = detectMoments(
            seed: try? model.store.momentSeed(),
            summaries: summaries, events: events, now: now
        )

        graph = buildCanvas(
            sessions: sessions,
            projects: projects.projects.map {
                CanvasProject(
                    id: $0.id, name: $0.name, category: $0.project.category,
                    apps: $0.project.apps, totalSeconds: $0.project.totalSeconds,
                    sessionCount: $0.project.sessionCount
                )
            },
            chapters: story.chapters.map {
                CanvasChapter(
                    id: $0.id, name: $0.name, category: $0.chapter.category,
                    apps: $0.chapter.apps,
                    totalActiveSeconds: $0.chapter.totalActiveSeconds,
                    dayCount: $0.chapter.dayCount,
                    startDay: $0.chapter.startDay, endDay: $0.chapter.endDay
                )
            },
            moments: moments
        )
        positions = Self.layout(graph)
        loaded = true
    }

    /// A force-directed layout, run to a fixed number of steps.
    ///
    /// Deliberately simple: repulsion between every pair, attraction along every edge, and a
    /// gentle pull toward the centre so nothing drifts off. Enough to separate the clusters
    /// the data already has, and no more — this is a picture of relationships, not a physics
    /// demonstration.
    private static func layout(_ graph: CanvasGraph) -> [String: CGPoint] {
        guard !graph.nodes.isEmpty else { return [:] }
        var points: [String: CGPoint] = [:]

        // Seeded from the node's own id, so the field is the same every time it is opened
        // rather than reshuffling on each visit.
        for node in graph.nodes {
            var hash: UInt64 = 1_469_598_103_934_665_603
            for byte in node.id.utf8 {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
            let angle = Double(hash % 3600) / 3600 * 2 * .pi
            let radius = 120 + Double((hash >> 12) % 220)
            points[node.id] = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
        }

        let ids = graph.nodes.map(\.id)
        // A collection is a hub, so it holds its members closer than an ordinary edge does.
        let restLength: (CanvasGraph.EdgeKind) -> Double = { kind in
            switch kind {
            case .collectionMember, .chapterCollection: 150
            case .projectApp: 110
            case .appApp: 190
            case .momentApp: 90
            }
        }

        for step in 0..<260 {
            // Cooling, so the field settles instead of oscillating.
            let cooling = 1 - Double(step) / 260
            var forces: [String: CGVector] = [:]

            for i in ids.indices {
                for j in (i + 1)..<ids.count {
                    let a = points[ids[i]]!, b = points[ids[j]]!
                    var dx = a.x - b.x, dy = a.y - b.y
                    var distance = (dx * dx + dy * dy).squareRoot()
                    // Two nodes exactly on top of each other have no direction to separate
                    // in; nudge them apart rather than dividing by zero.
                    if distance < 0.01 {
                        dx = Double((i &* 31 &+ j) % 7) - 3
                        dy = Double((i &* 17 &+ j) % 7) - 3
                        distance = max((dx * dx + dy * dy).squareRoot(), 0.01)
                    }
                    let push = 26_000 / (distance * distance)
                    forces[ids[i], default: .zero].dx += dx / distance * push
                    forces[ids[i], default: .zero].dy += dy / distance * push
                    forces[ids[j], default: .zero].dx -= dx / distance * push
                    forces[ids[j], default: .zero].dy -= dy / distance * push
                }
            }

            for edge in graph.edges {
                guard let a = points[edge.a], let b = points[edge.b] else { continue }
                let dx = b.x - a.x, dy = b.y - a.y
                let distance = max((dx * dx + dy * dy).squareRoot(), 0.01)
                let pull = (distance - restLength(edge.kind)) * 0.012
                forces[edge.a, default: .zero].dx += dx / distance * pull
                forces[edge.a, default: .zero].dy += dy / distance * pull
                forces[edge.b, default: .zero].dx -= dx / distance * pull
                forces[edge.b, default: .zero].dy -= dy / distance * pull
            }

            for id in ids {
                var point = points[id]!
                let force = forces[id] ?? .zero
                // Toward the centre, so a node with no edges does not sail away.
                point.x += (force.dx - point.x * 0.006) * cooling
                point.y += (force.dy - point.y * 0.006) * cooling
                points[id] = point
            }
        }

        return points
    }
}
