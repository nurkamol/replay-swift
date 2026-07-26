import Foundation

/// The recurring application combinations behind a week.
///
/// A workflow is a set of apps that keep showing up together — an editor with a terminal and
/// a browser, say. Derived locally from the sessions already built for the timeline: no
/// model, no network, just the observation that the same handful of apps recur. A
/// combination has to appear in more than one session to count, so a one-off pairing never
/// masquerades as a habit.
///
/// Ported from `detectWorkflows` in the Glaze app.
public struct Workflow: Equatable, Sendable {
    /// One of the apps that defines a combination. Identity only — the time is on the
    /// workflow, not on its members.
    public struct App: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String?
        public var appPath: String?
    }

    /// The sorted app keys, joined. Stable across runs, so it can key a stored name later.
    public var id: String
    /// "Development Workflow", "Mixed Workflow".
    public var title: String
    public var category: SessionCategory
    /// The apps that define this combination, most-used first.
    public var apps: [App]
    /// Total time across every session of this workflow.
    public var totalSeconds: Int
    /// How many sessions matched this combination.
    public var sessionCount: Int
}

/// How many of a session's top apps define its signature.
private let signatureSize = 3

/// Group sessions into workflows by their app signature — the sorted set of their top apps.
///
/// Only combinations of at least two apps that recur across two or more sessions are
/// returned, ranked by total time.
public func detectWorkflows(_ sessions: [ActivitySession]) -> [Workflow] {
    struct Group {
        var apps: [Workflow.App]
        var sessions: [ActivitySession]
        /// The order this signature was first seen in. The reference groups into a `Map`
        /// and sorts by time alone; JavaScript's sort is stable, so two workflows level on
        /// seconds hold their insertion order. Swift's is not, hence this.
        var order: Int
    }
    var groups: [String: Group] = [:]

    for session in sessions {
        let top = Array(session.apps.prefix(signatureSize))
        // A workflow is a combination, not a single app.
        if top.count < 2 { continue }

        let signature = top
            .map { $0.bundleIdentifier ?? $0.applicationName }
            .sorted()
            .joined(separator: "|")

        if var existing = groups[signature] {
            existing.sessions.append(session)
            // Keep the richest app list seen — the one carrying paths, so the icons draw.
            if top.contains(where: { $0.appPath != nil }),
               !existing.apps.contains(where: { $0.appPath != nil }) {
                existing.apps = top.map(identity)
            }
            groups[signature] = existing
        } else {
            groups[signature] = Group(
                apps: top.map(identity), sessions: [session], order: groups.count
            )
        }
    }

    return groups
        .compactMap { signature, group -> (Workflow, Int)? in
            // Recurring only.
            guard group.sessions.count >= 2 else { return nil }
            let category = mostCommonCategory(group.sessions)
            return (
                Workflow(
                    id: signature,
                    title: "\(category == .other ? "Mixed" : category.rawValue) Workflow",
                    category: category,
                    apps: group.apps,
                    totalSeconds: group.sessions.reduce(0) { $0 + $1.activeSeconds },
                    sessionCount: group.sessions.count
                ),
                group.order
            )
        }
        .sorted {
            $0.0.totalSeconds == $1.0.totalSeconds
                ? $0.1 < $1.1
                : $0.0.totalSeconds > $1.0.totalSeconds
        }
        .map(\.0)
}

/// Every session across a span, built per day so a run never straddles midnight.
///
/// Unlike `Report.sessions` this does not re-sort: the day order is what the reference's
/// `groupSessionsForWeek` hands to workflow detection, and that order decides which of two
/// equally long workflows comes first.
public func sessionsForWeek(
    _ events: [ActivityEvent], now: Int64, calendar: Calendar = .current
) -> [ActivitySession] {
    groupByDay(events, calendar: calendar).flatMap { group in
        buildTimeline(group.events, now: now, calendar: calendar).compactMap {
            if case .session(let session) = $0 { return session } else { return nil }
        }
    }
}

/// The category most of these sessions were. Ties go to the one seen first, as upstream.
func mostCommonCategory(_ sessions: [ActivitySession]) -> SessionCategory {
    var counts: [SessionCategory: Int] = [:]
    var order: [SessionCategory] = []
    for session in sessions {
        if counts[session.category] == nil { order.append(session.category) }
        counts[session.category, default: 0] += 1
    }
    var best = SessionCategory.other
    var bestCount = -1
    for category in order where counts[category]! > bestCount {
        best = category
        bestCount = counts[category]!
    }
    return best
}

private func identity(_ app: SessionApp) -> Workflow.App {
    Workflow.App(
        applicationName: app.applicationName,
        bundleIdentifier: app.bundleIdentifier,
        appPath: app.appPath
    )
}
