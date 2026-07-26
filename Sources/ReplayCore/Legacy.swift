import Foundation

/// The whole archive, at a glance.
///
/// How long the memory has been accumulating, the years it spans, and the applications that
/// ran through all of it. Read from the durable daily headlines, which is what makes it an
/// *archive* rather than a view of the last month: the raw rows behind most of these days
/// are long gone.
///
/// Ported from the `stats` computation in the Glaze app's legacy view.
public struct Legacy: Equatable, Sendable {
    public struct App: Equatable, Sendable {
        public var key: String
        public var applicationName: String
        public var appPath: String?
        public var seconds: Int
        public var days: Int
    }

    public var firstDay: Int64
    public var lastDay: Int64
    public var totalSeconds: Int
    public var activeDays: Int
    /// Newest first.
    public var years: [Int]
    /// The six applications that led the most time across the whole archive.
    public var favourites: [App]
}

/// Everything the archive knows about itself, or nothing when there is no history yet.
public func computeLegacy(
    _ summaries: [DailySummary],
    appPaths: [String: String] = [:],
    calendar: Calendar = .current
) -> Legacy? {
    let active = summaries.filter { $0.activeSeconds > 0 }
    if active.isEmpty { return nil }

    var apps: [String: (app: Legacy.App, order: Int)] = [:]
    for summary in active {
        let key = summary.topBundleID ?? summary.topAppName ?? "unknown"
        if apps[key] != nil {
            apps[key]!.app.seconds += summary.topSeconds
            apps[key]!.app.days += 1
        } else {
            apps[key] = (
                Legacy.App(
                    key: key,
                    applicationName: summary.topAppName ?? key,
                    appPath: summary.topBundleID.flatMap { appPaths[$0] },
                    seconds: summary.topSeconds,
                    days: 1
                ),
                apps.count
            )
        }
    }

    let years = Set(active.map {
        calendar.component(.year, from: Date(timeIntervalSince1970: Double($0.dayStart) / 1000))
    }).sorted(by: >)

    return Legacy(
        firstDay: active.map(\.dayStart).min()!,
        lastDay: active.map(\.dayStart).max()!,
        totalSeconds: active.reduce(0) { $0 + $1.activeSeconds },
        activeDays: active.count,
        years: years,
        favourites: apps.values
            .sorted {
                $0.app.seconds == $1.app.seconds
                    ? $0.order < $1.order
                    : $0.app.seconds > $1.app.seconds
            }
            .prefix(6)
            .map(\.app)
    )
}
