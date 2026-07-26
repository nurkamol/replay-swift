import Foundation

/// One application's share of a span.
///
/// Ported from `computeAppStats` in the Glaze app. Note `sessionCount` counts *rows*, not
/// derived sessions — it is how many times the app came to the front, which is the number
/// the Apps surface means by "times opened".
public struct AppStat: Equatable, Sendable {
    public var applicationName: String
    public var bundleIdentifier: String?
    public var appPath: String?
    public var totalSeconds: Int
    public var sessionCount: Int
    public var lastUsedAt: Int64

    /// The key an app is counted under — its bundle identifier, or its name when it has
    /// none. Two apps sharing a display name stay apart; one app renamed folds together.
    public var key: String { bundleIdentifier ?? applicationName }
}

/// Aggregate per-application usage from a set of rows, most-used first.
///
/// Idle stretches should be excluded before calling this, as the reference does at every
/// call site: "how long in this app" means time at the keyboard, not a Mac left open with
/// the app in front (SPEC §4).
public func computeAppStats(_ events: [ActivityEvent], now: Int64) -> [AppStat] {
    struct Accumulating {
        var stat: AppStat
        /// The reference builds a `Map` and sorts by seconds alone. JavaScript's sort is
        /// stable, so two apps level on time hold the order they were first seen in.
        var order: Int
    }
    var byApp: [String: Accumulating] = [:]

    for event in events {
        let key = event.bundleIdentifier ?? event.applicationName
        let seconds = event.effectiveDuration(now: now)
        if var existing = byApp[key] {
            existing.stat.totalSeconds += seconds
            existing.stat.sessionCount += 1
            existing.stat.lastUsedAt = max(existing.stat.lastUsedAt, event.startedAt)
            if existing.stat.appPath == nil { existing.stat.appPath = event.appPath }
            byApp[key] = existing
        } else {
            byApp[key] = Accumulating(
                stat: AppStat(
                    applicationName: event.applicationName,
                    bundleIdentifier: event.bundleIdentifier,
                    appPath: event.appPath,
                    totalSeconds: seconds,
                    sessionCount: 1,
                    lastUsedAt: event.startedAt
                ),
                order: byApp.count
            )
        }
    }

    return byApp.values
        .sorted {
            $0.stat.totalSeconds == $1.stat.totalSeconds
                ? $0.order < $1.order
                : $0.stat.totalSeconds > $1.stat.totalSeconds
        }
        .map(\.stat)
}
