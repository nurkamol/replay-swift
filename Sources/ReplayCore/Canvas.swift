import Foundation

/// The graph behind the memory space.
///
/// Projects, applications, collections, chapters and moments become nodes, tied by the
/// relationships that already exist in the data — a project to the apps it leans on, an app
/// to the apps you switch between, everything to the kind of work it belongs to. Nothing is
/// invented; every node and every edge is read from local records.
///
/// This builds the graph only. Layout and drawing live in the view, so the shape of a
/// history stays separate from how it is shown.
///
/// Ported from `buildCanvas` in the Glaze app.
public struct CanvasGraph: Equatable, Sendable {
    public enum NodeType: String, Equatable, Sendable {
        case collection, project, chapter, app, moment
    }

    public enum EdgeKind: String, Equatable, Sendable {
        case appApp = "app-app"
        case projectApp = "project-app"
        case collectionMember = "collection-member"
        case chapterCollection = "chapter-collection"
        case momentApp = "moment-app"
    }

    public struct Node: Equatable, Sendable {
        /// Type-prefixed and unique: `app:…`, `project:…`, `collection:…`, `chapter:…`.
        public var id: String
        public var type: NodeType
        public var label: String
        /// A short supporting line for the preview.
        public var subtitle: String
        public var category: SessionCategory
        /// Drives node size — seconds for most, membership for a collection.
        public var weight: Int
        public var appPath: String?
        public var bundleID: String?
        /// What to open: a project id, a bundle identifier, a category, a chapter id.
        public var ref: String
    }

    public struct Edge: Equatable, Sendable {
        public var a: String
        public var b: String
        public var weight: Int
        public var kind: EdgeKind
    }

    public var nodes: [Node]
    public var edges: [Edge]
    /// The strongest app-to-app tie, for scaling those lines.
    public var maxAppWeight: Int

    /// Public so a model can hold an empty graph before anything is loaded.
    public init(nodes: [Node], edges: [Edge], maxAppWeight: Int) {
        self.nodes = nodes
        self.edges = edges
        self.maxAppWeight = maxAppWeight
    }
}

/// What a chapter's span reads as on a node.
private func chapterRange(
    startDay: Int64, endDay: Int64, calendar: Calendar, locale: Locale
) -> String {
    let from = shortDayLabel(startDay, calendar: calendar, locale: locale)
    if startDay == endDay { return from }
    return "\(from) – \(shortDayLabel(endDay, calendar: calendar, locale: locale))"
}

/// One project as the canvas needs it — name resolved, apps and totals in hand.
public struct CanvasProject: Sendable {
    public var id: String
    public var name: String
    public var category: SessionCategory
    public var apps: [Project.App]
    public var totalSeconds: Int
    public var sessionCount: Int

    public init(
        id: String, name: String, category: SessionCategory,
        apps: [Project.App], totalSeconds: Int, sessionCount: Int
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.apps = apps
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
    }
}

/// One chapter, likewise.
public struct CanvasChapter: Sendable {
    public var id: String
    public var name: String
    public var category: SessionCategory
    public var apps: [Chapter.App]
    public var totalActiveSeconds: Int
    public var dayCount: Int
    public var startDay: Int64
    public var endDay: Int64

    public init(
        id: String, name: String, category: SessionCategory, apps: [Chapter.App],
        totalActiveSeconds: Int, dayCount: Int, startDay: Int64, endDay: Int64
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.apps = apps
        self.totalActiveSeconds = totalActiveSeconds
        self.dayCount = dayCount
        self.startDay = startDay
        self.endDay = endDay
    }
}

/// Assemble the graph.
///
/// Node counts are capped so the field stays a legible landscape rather than a hairball. The
/// busiest of each kind win, which is also what a person recognises first.
public func buildCanvas(
    sessions: [ActivitySession],
    projects: [CanvasProject],
    chapters: [CanvasChapter],
    moments: [Moment],
    maxApps: Int = 16,
    maxProjects: Int = 10,
    maxChapters: Int = 6,
    maxMoments: Int = 8,
    calendar: Calendar = .current,
    locale: Locale = .current
) -> CanvasGraph {
    var nodes: [CanvasGraph.Node] = []
    var edges: [CanvasGraph.Edge] = []
    var nodeIDs: Set<String> = []

    // Applications, and the switches between them.
    let constellation = buildConstellation(sessions, maxNodes: maxApps)
    func appID(_ key: String) -> String { "app:\(key)" }
    var appByPath: [String: String] = [:]
    for app in constellation.nodes {
        let id = appID(app.key)
        nodeIDs.insert(id)
        if let path = app.appPath, appByPath[path] == nil { appByPath[path] = id }
        nodes.append(CanvasGraph.Node(
            id: id, type: .app, label: app.applicationName,
            subtitle: "\(formatDurationShort(app.totalSeconds)) · \(app.sessionCount) "
                + "\(app.sessionCount == 1 ? "session" : "sessions")",
            category: app.category, weight: app.totalSeconds,
            appPath: app.appPath, bundleID: app.bundleIdentifier,
            ref: app.bundleIdentifier ?? app.key
        ))
    }
    for edge in constellation.edges {
        edges.append(CanvasGraph.Edge(
            a: appID(edge.a), b: appID(edge.b), weight: edge.weight, kind: .appApp
        ))
    }

    // Projects, tied to the applications they lean on.
    for project in projects.enumerated()
        .sorted(by: {
            $0.element.totalSeconds == $1.element.totalSeconds
                ? $0.offset < $1.offset
                : $0.element.totalSeconds > $1.element.totalSeconds
        })
        .prefix(maxProjects)
        .map(\.element) {
        let id = "project:\(project.id)"
        nodeIDs.insert(id)
        nodes.append(CanvasGraph.Node(
            id: id, type: .project, label: project.name,
            subtitle: "\(formatDurationShort(project.totalSeconds)) · \(project.sessionCount) "
                + "\(project.sessionCount == 1 ? "session" : "sessions")",
            category: project.category, weight: project.totalSeconds,
            appPath: project.apps.first?.appPath,
            bundleID: project.apps.first?.bundleIdentifier,
            ref: project.id
        ))
        for app in project.apps {
            let target = appID(app.bundleIdentifier ?? app.applicationName)
            if nodeIDs.contains(target) {
                edges.append(CanvasGraph.Edge(
                    a: id, b: target, weight: app.seconds, kind: .projectApp
                ))
            }
        }
    }

    // Chapters.
    for chapter in chapters.enumerated()
        .sorted(by: {
            $0.element.totalActiveSeconds == $1.element.totalActiveSeconds
                ? $0.offset < $1.offset
                : $0.element.totalActiveSeconds > $1.element.totalActiveSeconds
        })
        .prefix(maxChapters)
        .map(\.element) {
        let id = "chapter:\(chapter.id)"
        nodeIDs.insert(id)
        nodes.append(CanvasGraph.Node(
            id: id, type: .chapter, label: chapter.name,
            subtitle: chapterRange(
                startDay: chapter.startDay, endDay: chapter.endDay,
                calendar: calendar, locale: locale
            ) + " · \(chapter.dayCount) \(chapter.dayCount == 1 ? "day" : "days")",
            category: chapter.category, weight: chapter.totalActiveSeconds,
            appPath: chapter.apps.first?.appPath,
            bundleID: chapter.apps.first?.bundleIdentifier,
            ref: chapter.id
        ))
    }

    // Collections: the kinds of work, as the clusters everything gathers into.
    var memberWeight: [SessionCategory: Int] = [:]
    var memberCount: [SessionCategory: Int] = [:]
    var categoryOrder: [SessionCategory] = []
    for node in nodes where node.type != .collection && Collections.isCollectable(node.category) {
        if memberWeight[node.category] == nil { categoryOrder.append(node.category) }
        memberWeight[node.category, default: 0] += node.weight
        memberCount[node.category, default: 0] += 1
    }
    for category in categoryOrder {
        let count = memberCount[category] ?? 0
        // A cluster needs at least a couple of members to be one.
        if count < 2 { continue }
        let id = "collection:\(category.rawValue)"
        nodeIDs.insert(id)
        nodes.append(CanvasGraph.Node(
            id: id, type: .collection, label: Collections.label(for: category),
            subtitle: "\(count) \(count == 1 ? "member" : "members")",
            category: category, weight: memberWeight[category] ?? 0,
            appPath: nil, bundleID: nil, ref: category.rawValue
        ))
    }
    // Pull every member toward its collection, and each chapter to its kind.
    for node in nodes where node.type != .collection && Collections.isCollectable(node.category) {
        let hub = "collection:\(node.category.rawValue)"
        guard nodeIDs.contains(hub) else { continue }
        edges.append(CanvasGraph.Edge(
            a: hub, b: node.id, weight: 1,
            kind: node.type == .chapter ? .chapterCollection : .collectionMember
        ))
    }

    // Moments: small stars, tied to the application they involve when there is one. Never a
    // fabricated link — a moment with no application simply floats.
    for moment in moments.prefix(maxMoments) {
        let id = "moment:\(moment.key)"
        if nodeIDs.contains(id) { continue }
        nodeIDs.insert(id)
        nodes.append(CanvasGraph.Node(
            id: id, type: .moment, label: moment.title, subtitle: moment.detail,
            category: .other, weight: 1,
            appPath: moment.appPath, bundleID: nil,
            ref: moment.dayStart.map(String.init) ?? ""
        ))
        if let path = moment.appPath, let target = appByPath[path] {
            edges.append(CanvasGraph.Edge(a: id, b: target, weight: 1, kind: .momentApp))
        }
    }

    return CanvasGraph(nodes: nodes, edges: edges, maxAppWeight: constellation.maxWeight)
}

// ── focus ─────────────────────────────────────────────────────────────────────

extension CanvasGraph {
    /// How many sessions the panel beside a focused node will list. The reference's cap:
    /// this is the timeline *behind* one memory, not a second Timeline surface.
    public static let focusSessionLimit = 60

    /// Everything one node is joined to, by id.
    ///
    /// Used to dim the rest of the field when something is focused. Built per call rather
    /// than cached because it is asked for once per selection, not once per frame — and a
    /// cache keyed on a graph that is rebuilt whenever the window opens is a cache that is
    /// wrong more often than it is useful.
    public func neighbours(of id: String) -> Set<String> {
        var found: Set<String> = [id]
        for edge in edges {
            if edge.a == id { found.insert(edge.b) }
            if edge.b == id { found.insert(edge.a) }
        }
        return found
    }

    /// The sessions a node stands for, newest first.
    ///
    /// Each kind answers a different question, which is why this is a switch rather than one
    /// predicate: a project owns its sessions outright, an application is matched inside
    /// them, a collection is a category, and a chapter and a moment are both really *days*.
    /// A node whose day is unknown — a moment with no date — has no sessions rather than all
    /// of them, which is the distinction that matters.
    public func sessions(
        behind node: Node,
        in sessions: [ActivitySession],
        projectSessions: [String: [ActivitySession]] = [:],
        chapterDays: [String: Set<Int64>] = [:],
        calendar: Calendar = .current
    ) -> [ActivitySession] {
        let matched: [ActivitySession]
        switch node.type {
        case .project:
            matched = projectSessions[node.ref] ?? []
        case .app:
            matched = sessions.filter { session in
                session.apps.contains {
                    ($0.bundleIdentifier ?? $0.applicationName) == node.ref
                }
            }
        case .collection:
            matched = sessions.filter { $0.category.rawValue == node.ref }
        case .chapter:
            let days = chapterDays[node.ref] ?? []
            matched = sessions.filter {
                days.contains(startOfLocalDay($0.startedAt, calendar: calendar))
            }
        case .moment:
            guard let day = Int64(node.ref) else { return [] }
            matched = sessions.filter {
                startOfLocalDay($0.startedAt, calendar: calendar) == day
            }
        }
        // Sorted on (start, title) rather than start alone: Swift's sort is not stable, and
        // two sessions that begin in the same millisecond would otherwise swap between
        // selections of the same node.
        return Array(
            matched.sorted {
                $0.startedAt != $1.startedAt
                    ? $0.startedAt > $1.startedAt
                    : $0.title < $1.title
            }
            .prefix(CanvasGraph.focusSessionLimit)
        )
    }
}
