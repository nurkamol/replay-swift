import Foundation

/// How two applications are used together.
///
/// Where `detectWorkflows` finds recurring *combinations*, this finds the bond between a
/// pair: how often you switch between them, how many sessions they share, which way you tend
/// to go, and how long those sessions run. The same descriptive spirit — how you already
/// work, reflected back, with no suggestion attached.
///
/// Ported from `computeWorkflowPartners` and `computeRelationship` in the Glaze app.
public struct AppIdentity: Equatable, Sendable {
    public var key: String
    public var applicationName: String
    public var bundleIdentifier: String?
    public var appPath: String?
}

public struct WorkflowPartner: Equatable, Sendable {
    public var identity: AppIdentity
    /// Direct switches between the two, either direction, across all sessions.
    public var switches: Int
    /// Sessions in which both took part.
    public var sharedSessions: Int
    /// Switches from the anchor to this partner.
    public var forward: Int
    /// And back.
    public var backward: Int
    /// Mean active length of the sessions the two shared.
    public var averageTogetherSeconds: Int
}

/// The applications most entwined with `anchorKey`, strongest first.
///
/// Only real partners survive: a pair must have been switched between at least twice, so a
/// single incidental hop never reads as a relationship.
public func computeWorkflowPartners(
    _ sessions: [ActivitySession], anchorKey: String
) -> [WorkflowPartner] {
    struct Accumulating {
        var identity: AppIdentity
        var switches = 0
        var sharedSessions = 0
        var forward = 0
        var backward = 0
        var togetherSecondsSum = 0
        var order: Int
    }
    var partners: [String: Accumulating] = [:]

    for session in sessions {
        guard session.apps.contains(where: { appKey($0) == anchorKey }) else { continue }

        // One tick per partner per session, for the shared count and the average.
        var partnerKeys: [String] = []
        for app in session.apps where appKey(app) != anchorKey {
            let key = appKey(app)
            if partners[key] == nil {
                partners[key] = Accumulating(
                    identity: AppIdentity(
                        key: key,
                        applicationName: app.applicationName,
                        bundleIdentifier: app.bundleIdentifier,
                        appPath: app.appPath
                    ),
                    order: partners.count
                )
            } else if partners[key]!.identity.appPath == nil {
                partners[key]!.identity.appPath = app.appPath
            }
            if !partnerKeys.contains(key) { partnerKeys.append(key) }
        }
        for key in partnerKeys {
            partners[key]!.sharedSessions += 1
            partners[key]!.togetherSecondsSum += session.activeSeconds
        }

        // Direct switches: consecutive focus changes touching the anchor. Re-sorted
        // defensively, as upstream — a session's rows should already be in order.
        let events = session.events.sorted { $0.startedAt < $1.startedAt }
        for index in events.indices.dropLast() {
            let from = events[index].bundleIdentifier ?? events[index].applicationName
            let to = events[index + 1].bundleIdentifier ?? events[index + 1].applicationName
            if from == to { continue }
            if from == anchorKey, partners[to] != nil {
                partners[to]!.forward += 1
                partners[to]!.switches += 1
            } else if to == anchorKey, partners[from] != nil {
                partners[from]!.backward += 1
                partners[from]!.switches += 1
            }
        }
    }

    return partners.values
        .filter { $0.switches >= 2 }
        .sorted {
            if $0.switches != $1.switches { return $0.switches > $1.switches }
            if $0.sharedSessions != $1.sharedSessions { return $0.sharedSessions > $1.sharedSessions }
            return $0.order < $1.order
        }
        .map { entry in
            WorkflowPartner(
                identity: entry.identity,
                switches: entry.switches,
                sharedSessions: entry.sharedSessions,
                forward: entry.forward,
                backward: entry.backward,
                averageTogetherSeconds: entry.sharedSessions > 0
                    ? Int((Double(entry.togetherSecondsSum) / Double(entry.sharedSessions)).rounded())
                    : 0
            )
        }
}

/// The full relationship between two applications, for their own page.
public struct Relationship: Equatable, Sendable {
    public var a: AppIdentity
    public var b: AppIdentity
    public var switches: Int
    /// Switches from a to b.
    public var aToB: Int
    /// And back.
    public var bToA: Int
    public var sharedSessions: Int
    public var averageTogetherSeconds: Int
    /// The sessions the two shared, newest first.
    public var sessions: [ActivitySession]
}

/// Identities are discovered from the shared sessions, so a page works from bundle
/// identifiers alone. `nil` when the two have never actually appeared together.
public func computeRelationship(
    _ sessions: [ActivitySession], keyA: String, keyB: String
) -> Relationship? {
    var identityA: AppIdentity?
    var identityB: AppIdentity?
    var aToB = 0
    var bToA = 0
    var togetherSecondsSum = 0
    var shared: [ActivitySession] = []

    for session in sessions {
        guard let appA = session.apps.first(where: { appKey($0) == keyA }),
              let appB = session.apps.first(where: { appKey($0) == keyB })
        else { continue }

        // Kept fresh only until a path is found, so the icon comes from whichever session
        // actually knew where the app lived.
        if identityA == nil || identityA?.appPath == nil { identityA = identity(of: appA) }
        if identityB == nil || identityB?.appPath == nil { identityB = identity(of: appB) }

        shared.append(session)
        togetherSecondsSum += session.activeSeconds

        let events = session.events.sorted { $0.startedAt < $1.startedAt }
        for index in events.indices.dropLast() {
            let from = events[index].bundleIdentifier ?? events[index].applicationName
            let to = events[index + 1].bundleIdentifier ?? events[index + 1].applicationName
            if from == keyA && to == keyB { aToB += 1 } else if from == keyB && to == keyA { bToA += 1 }
        }
    }

    guard let identityA, let identityB, !shared.isEmpty else { return nil }

    return Relationship(
        a: identityA,
        b: identityB,
        switches: aToB + bToA,
        aToB: aToB,
        bToA: bToA,
        sharedSessions: shared.count,
        averageTogetherSeconds: Int((Double(togetherSecondsSum) / Double(shared.count)).rounded()),
        sessions: shared.sorted { $0.startedAt > $1.startedAt }
    )
}

private func identity(of app: SessionApp) -> AppIdentity {
    AppIdentity(
        key: appKey(app),
        applicationName: app.applicationName,
        bundleIdentifier: app.bundleIdentifier,
        appPath: app.appPath
    )
}
