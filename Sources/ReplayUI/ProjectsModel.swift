import Foundation
import Observation
import ReplayCore

/// The recurring combinations of apps behind your work.
///
/// Nothing is filed and nothing is created: a project appears because the same handful of
/// apps kept coming back, and disappears if that stops being true. The only thing stored is
/// a name, and only if one is typed — which is why the store has no projects table.
@MainActor
@Observable
final class ProjectsModel {
    /// A project with the name it is shown under.
    struct Named: Identifiable {
        var project: Project
        /// Custom if one was typed, else the descriptive default.
        var name: String
        /// Whether that name is the user's rather than Replay's.
        var named: Bool

        var id: String { project.id }
    }

    private(set) var projects: [Named] = []
    private(set) var loaded = false

    private let model: AppModel
    private let preferences: Preferences

    init(model: AppModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
    }

    func load() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let from = startOfLocalDay(now) - Int64(projectDays - 1) * dayMillis
        let events = ((try? model.store.sessions(from: from, to: now + dayMillis)) ?? [])
            .filter { $0.startedAt >= from }
        projects = detectProjects(sessionsForWeek(events, now: now)).map(named)
        model.annotations.load(from: from, to: now + dayMillis)
        loaded = true
    }

    func project(_ id: String) -> Named? {
        projects.first { $0.id == id }
    }

    /// Give a project a name, or take one away.
    ///
    /// An emptied name is removed rather than stored blank, so the project falls back to its
    /// description instead of showing nothing.
    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var names = preferences.projectNames
        if trimmed.isEmpty { names.removeValue(forKey: id) } else { names[id] = trimmed }
        preferences.projectNames = names
        projects = projects.map { named($0.project) }
    }

    private func named(_ project: Project) -> Named {
        let names = preferences.projectNames
        let custom = names[project.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Named(
            project: project,
            name: resolveProjectName(project, names: names),
            named: !custom.isEmpty
        )
    }
}
