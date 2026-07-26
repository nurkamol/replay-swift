import Foundation

/// Your applications as a field of connected stars.
///
/// Each application is a node; two are tied the more you move between them. The same
/// co-occurrence the workflow features read, arranged for the eye rather than the ledger.
///
/// Ported from `buildConstellation` in the Glaze app.
public struct Constellation: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public var key: String
        public var applicationName: String
        public var appPath: String?
        public var bundleIdentifier: String?
        public var category: SessionCategory
        public var totalSeconds: Int
        public var sessionCount: Int
    }

    public struct Edge: Equatable, Sendable {
        public var a: String
        public var b: String
        /// Times switched directly between the two, either direction.
        public var weight: Int
    }

    public var nodes: [Node]
    public var edges: [Edge]
    /// The strongest single edge, for scaling line intensity.
    public var maxWeight: Int
}

/// The busiest `maxNodes` applications as stars, tied by how often you switched between
/// them. Only pairs switched between at least twice become a line, so the field stays
/// legible rather than a web.
public func buildConstellation(
    _ sessions: [ActivitySession], maxNodes: Int = 18
) -> Constellation {
    struct Accumulating {
        var applicationName: String
        var appPath: String?
        var bundleIdentifier: String?
        var totalSeconds = 0
        var sessions: Set<Int64> = []
        var order: Int
    }
    var apps: [String: Accumulating] = [:]
    var pairs: [String: (weight: Int, order: Int)] = [:]

    for session in sessions {
        for app in session.apps {
            let key = appKey(app)
            if apps[key] != nil {
                apps[key]!.totalSeconds += app.seconds
                apps[key]!.sessions.insert(session.startedAt)
                if apps[key]!.appPath == nil { apps[key]!.appPath = app.appPath }
            } else {
                apps[key] = Accumulating(
                    applicationName: app.applicationName,
                    appPath: app.appPath,
                    bundleIdentifier: app.bundleIdentifier,
                    totalSeconds: app.seconds,
                    sessions: [session.startedAt],
                    order: apps.count
                )
            }
        }

        let events = session.events.sorted { $0.startedAt < $1.startedAt }
        for index in events.indices.dropLast() {
            let from = events[index].bundleIdentifier ?? events[index].applicationName
            let to = events[index + 1].bundleIdentifier ?? events[index + 1].applicationName
            if from == to { continue }
            // Sorted, so a pair is one key whichever way it was traversed.
            let key = from < to ? "\(from) \(to)" : "\(to) \(from)"
            if pairs[key] != nil { pairs[key]!.weight += 1 } else { pairs[key] = (1, pairs.count) }
        }
    }

    // Built in two steps rather than one chain: the single expression was more than the
    // type checker would take.
    var ranked: [(node: Constellation.Node, order: Int)] = []
    for (key, entry) in apps {
        let node = Constellation.Node(
            key: key,
            applicationName: entry.applicationName,
            appPath: entry.appPath,
            bundleIdentifier: entry.bundleIdentifier,
            category: categorizeApp(entry.applicationName),
            totalSeconds: entry.totalSeconds,
            sessionCount: entry.sessions.count
        )
        ranked.append((node, entry.order))
    }
    ranked.sort {
        $0.node.totalSeconds == $1.node.totalSeconds
            ? $0.order < $1.order
            : $0.node.totalSeconds > $1.node.totalSeconds
    }
    let nodes = ranked.prefix(maxNodes).map(\.node)

    let keep = Set(nodes.map(\.key))
    var edges: [(edge: Constellation.Edge, order: Int)] = []
    var maxWeight = 0
    for (key, entry) in pairs.sorted(by: { $0.value.order < $1.value.order }) {
        guard entry.weight >= 2, let separator = key.firstIndex(of: " ") else { continue }
        let a = String(key[key.startIndex..<separator])
        let b = String(key[key.index(after: separator)...])
        guard keep.contains(a), keep.contains(b) else { continue }
        edges.append((Constellation.Edge(a: a, b: b, weight: entry.weight), entry.order))
        maxWeight = max(maxWeight, entry.weight)
    }

    return Constellation(
        nodes: nodes,
        edges: edges
            .sorted {
                $0.edge.weight == $1.edge.weight
                    ? $0.order < $1.order
                    : $0.edge.weight > $1.edge.weight
            }
            .map(\.edge),
        maxWeight: maxWeight
    )
}
