import Foundation

/// A recurring application combination, remembered.
///
/// A project is a workflow that keeps coming back — the same apps, session after session.
/// Where `detectWorkflows` answers "what recurred this week", this keeps the whole span, so
/// a combination can have a page of its own with a first-seen date and every session under
/// it. Derived locally from the sessions already built for the timeline; the only thing
/// stored is a name, and only if you type one.
///
/// Ported from `detectProjects` in the Glaze app.
public struct Project: Equatable, Sendable {
    /// One application's part in the project, aggregated across every session.
    public struct App: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String?
        public var appPath: String?
        public var seconds: Int

        /// Public so a memory producer, or the parity suite, can build one from a fixture
        /// rather than deriving a whole project to reach it.
        public init(
            applicationName: String, bundleIdentifier: String?, appPath: String?, seconds: Int
        ) {
            self.applicationName = applicationName
            self.bundleIdentifier = bundleIdentifier
            self.appPath = appPath
            self.seconds = seconds
        }
    }

    /// The signature — sorted top-app keys, joined. Stable across runs, which is what makes
    /// it safe to store a custom name against.
    public var id: String
    public var category: SessionCategory
    /// The apps that most defined the project, most time first, capped at five.
    public var apps: [App]
    public var totalSeconds: Int
    public var sessionCount: Int
    public var firstSeen: Int64
    public var lastActive: Int64
    /// Every session under this project, newest first.
    public var sessions: [ActivitySession]
}

/// How far back projects are gathered from — the kept-history window.
public let projectDays = 30

/// Fold sessions into projects by their app signature.
///
/// Like `detectWorkflows`, a combination must recur across two or more sessions to count.
/// Unlike it, apps are aggregated across *every* session rather than taken from the first,
/// so "frequently used apps" reflects the whole project and not one sitting.
public func detectProjects(_ sessions: [ActivitySession]) -> [Project] {
    var groups: [String: (sessions: [ActivitySession], order: Int)] = [:]
    for session in sessions {
        let top = Array(session.apps.prefix(3))
        // A project is a combination, not a single app.
        if top.count < 2 { continue }
        let signature = top.map(appKey).sorted().joined(separator: "|")
        if groups[signature] != nil {
            groups[signature]!.sessions.append(session)
        } else {
            groups[signature] = ([session], groups.count)
        }
    }

    return groups
        .compactMap { id, group -> (Project, Int)? in
            guard group.sessions.count >= 2 else { return nil }

            var apps: [String: (app: Project.App, order: Int)] = [:]
            var totalSeconds = 0
            var firstSeen = Int64.max
            var lastActive: Int64 = 0
            for session in group.sessions {
                totalSeconds += session.activeSeconds
                firstSeen = min(firstSeen, session.startedAt)
                lastActive = max(lastActive, session.endedAt)
                for app in session.apps {
                    let key = appKey(app)
                    if apps[key] != nil {
                        apps[key]!.app.seconds += app.seconds
                        if apps[key]!.app.appPath == nil { apps[key]!.app.appPath = app.appPath }
                    } else {
                        apps[key] = (
                            Project.App(
                                applicationName: app.applicationName,
                                bundleIdentifier: app.bundleIdentifier,
                                appPath: app.appPath,
                                seconds: app.seconds
                            ),
                            apps.count
                        )
                    }
                }
            }

            let project = Project(
                id: id,
                category: mostCommonCategory(group.sessions),
                apps: apps.values
                    .sorted {
                        $0.app.seconds == $1.app.seconds
                            ? $0.order < $1.order
                            : $0.app.seconds > $1.app.seconds
                    }
                    .prefix(5)
                    .map(\.app),
                totalSeconds: totalSeconds,
                sessionCount: group.sessions.count,
                firstSeen: firstSeen,
                lastActive: lastActive,
                sessions: group.sessions.sorted { $0.startedAt > $1.startedAt }
            )
            return (project, group.order)
        }
        // Most recently active first — a project you touched today sits above one from last
        // month. Ties hold their first-seen order, which JavaScript's stable sort gives free.
        .sorted {
            $0.0.lastActive == $1.0.lastActive
                ? $0.1 < $1.1
                : $0.0.lastActive > $1.0.lastActive
        }
        .map(\.0)
}

/// The key an app is counted under — its bundle identifier, or its name as a fallback.
public func appKey(_ app: SessionApp) -> String {
    app.bundleIdentifier ?? app.applicationName
}

/// The name Replay gives a project before you rename it.
///
/// The kind of work and the app it leans on ("Development · Terminal"), or the two lead apps
/// when the kind is unclear. Descriptive, never a guess at what you would call it — which is
/// the point of letting you type your own.
public func projectDefaultName(_ project: Project) -> String {
    // A softer word for a couple of categories, so a default name reads naturally.
    let word: String? = {
        switch project.category {
        case .other: nil
        case .admin: "Utilities"
        default: project.category.rawValue
        }
    }()
    let lead = project.apps.first?.applicationName
    if let word, let lead { return "\(word) · \(lead)" }
    if let lead, project.apps.count > 1 { return "\(lead) · \(project.apps[1].applicationName)" }
    return lead ?? "Project"
}

/// The project's shown name — a custom label if one was typed, else the descriptive default.
public func resolveProjectName(_ project: Project, names: [String: String]) -> String {
    let custom = names[project.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return custom.isEmpty ? projectDefaultName(project) : custom
}
