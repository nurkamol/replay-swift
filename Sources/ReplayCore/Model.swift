import Foundation

/// The behavioural constants, mirrored from `spec/constants.json`.
///
/// Every value here exists in the Glaze app too, and the two must not drift. When
/// `tools/sync-spec.mjs` reports a change to `spec/constants.json`, this is the
/// first file to update. They are duplicated rather than parsed at runtime so the
/// shipping app carries no JSON it depends on — the test suite is what proves the
/// two copies still agree.
public enum Rules {
    /// No keyboard or mouse for this long means the user stepped away.
    public static let awayAfterSeconds: Int = 300
    /// How often input idleness is sampled.
    public static let idlePollSeconds: TimeInterval = 30
    /// Repeat launch/terminate notifications inside this window are one event.
    public static let pointEventDedupeSeconds: TimeInterval = 2

    /// A row this long is absence rather than concentration: a break, not focus.
    public static let idleBreakSeconds: Int = 1800
    /// A hole this long between rows means Replay was not running.
    public static let recordingGapSeconds: Int = 300
    /// Runs shorter than this, with fewer than 3 rows, are a stray switch.
    public static let minSessionSeconds: Int = 45

    /// Rows longer than this are excluded from every "active" total.
    public static let idleStretchSeconds: Int = 1800

    /// Compaction is only worth a full-file rewrite past both of these.
    public static let compactMinFreeRatio: Double = 0.2
    public static let compactMinFreePages: Int = 16
    /// Ids named per `DELETE … IN (…)`, bounded by SQLite's parameter limit.
    public static let deleteChunk: Int = 400

    /// Caps on a session's tags, applied after normalising.
    public static let maxTagLength: Int = 32
    public static let maxTags: Int = 12

    /// Background agents that steal focus without being "used".
    public static let ignoredBundleIDs: Set<String> = [
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.WindowManager",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.Spotlight",
        "com.apple.spotlight",
        "com.apple.wallpaper.agent",
        "com.apple.screencaptureui",
        "com.apple.ScreenSaver.Engine",
    ]
}

/// What kind of thing a stored row records.
///
/// `idle` rows are stretches with no input at all — time the Mac was on but nobody
/// was there. They are stored alongside focus rows so a timeline can say "away"
/// rather than inferring it from a long unbroken stretch.
public enum EventType: String, Codable, Sendable {
    case activated
    case launched
    case terminated
    case idle
}

/// One row of the `events` table.
///
/// Timestamps are epoch **milliseconds**, matching the Glaze app and therefore the
/// database on disk. Resist converting to `Date` at this layer: a database written
/// by either implementation has to be readable by the other, and the arithmetic in
/// the derivation is defined in milliseconds.
public struct ActivityEvent: Equatable, Sendable {
    public var id: Int64
    public var type: EventType
    public var applicationName: String
    public var bundleIdentifier: String?
    public var appPath: String?
    public var startedAt: Int64
    public var endedAt: Int64?
    public var duration: Int   // seconds; a snapshot, see effectiveDuration(now:)

    public init(
        id: Int64 = 0,
        type: EventType,
        applicationName: String,
        bundleIdentifier: String? = nil,
        appPath: String? = nil,
        startedAt: Int64,
        endedAt: Int64? = nil,
        duration: Int = 0
    ) {
        self.id = id
        self.type = type
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.appPath = appPath
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
    }

    /// The open session's duration grows until it is closed, so it is measured
    /// against `now` rather than read from the row.
    public func effectiveDuration(now: Int64) -> Int {
        guard endedAt != nil else {
            return max(0, Int((Double(now - startedAt) / 1000).rounded()))
        }
        return duration
    }
}

/// One application's share of a session.
public struct SessionApp: Equatable, Sendable {
    public var applicationName: String
    public var bundleIdentifier: String?
    public var appPath: String?
    public var seconds: Int
    public var share: Double
    public var switches: Int
}

/// Why a stretch of the timeline is not a session.
public enum BreakReason: String, Equatable, Sendable {
    /// A measured stretch with no keyboard or mouse input.
    case away
    /// One app held focus so long it must be absence (pre-`away` data).
    case idle
    /// A hole in the record: Replay was not running, or tracking was paused.
    case unrecorded
}

/// A run of focus rows, named — the unit the whole app is built around.
///
/// Sessions have no row of their own. They are derived from the event stream every
/// time, which is why deleting one means deleting the rows behind it.
public struct ActivitySession: Equatable, Sendable {
    public var title: String
    public var category: SessionCategory
    public var startedAt: Int64
    public var endedAt: Int64
    public var spanSeconds: Int
    public var activeSeconds: Int
    public var apps: [SessionApp]
    public var events: [ActivityEvent]
    public var switches: Int

    /// Public so the parity suite can build one to ask a question about, rather than
    /// deriving a whole timeline to reach a session with the right category on it.
    public init(
        title: String, category: SessionCategory, startedAt: Int64, endedAt: Int64,
        spanSeconds: Int, activeSeconds: Int, apps: [SessionApp],
        events: [ActivityEvent], switches: Int
    ) {
        self.title = title
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.spanSeconds = spanSeconds
        self.activeSeconds = activeSeconds
        self.apps = apps
        self.events = events
        self.switches = switches
    }
}

public struct ActivityBreak: Equatable, Sendable {
    public var reason: BreakReason
    public var startedAt: Int64
    public var endedAt: Int64
    public var seconds: Int
    public var applicationName: String?
    public var appPath: String?

    /// Public so the parity suite can build one from a fixture rather than deriving a
    /// whole timeline to reach a single gap.
    public init(
        reason: BreakReason, startedAt: Int64, endedAt: Int64, seconds: Int,
        applicationName: String? = nil, appPath: String? = nil
    ) {
        self.reason = reason
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.seconds = seconds
        self.applicationName = applicationName
        self.appPath = appPath
    }
}

public enum TimelineItem: Equatable, Sendable {
    case session(ActivitySession)
    case breakItem(ActivityBreak)
}

/// A durable per-day headline, kept even after the rows behind it are pruned.
///
/// This is the record that outlives raw activity: once the retention window drops a
/// day's events, its headline is *all* that is left of it, which is why rebuilding
/// summaries has to be bounded to the days that still have rows.
public struct DailySummary: Equatable, Sendable {
    public var dayStart: Int64
    public var activeSeconds: Int
    public var topBundleID: String?
    public var topAppName: String?
    public var topSeconds: Int

    public init(
        dayStart: Int64,
        activeSeconds: Int,
        topBundleID: String? = nil,
        topAppName: String? = nil,
        topSeconds: Int = 0
    ) {
        self.dayStart = dayStart
        self.activeSeconds = activeSeconds
        self.topBundleID = topBundleID
        self.topAppName = topAppName
        self.topSeconds = topSeconds
    }
}

/// Local midnight for a timestamp — the app's single definition of "which day".
///
/// Everything buckets by the day a run *started*: the timeline groups that way,
/// headlines are computed that way, and deletion matches rows that way. A session
/// that crosses midnight belongs to the day it began, not to both.
public func startOfLocalDay(_ epochMillis: Int64, calendar: Calendar = .current) -> Int64 {
    let date = Date(timeIntervalSince1970: Double(epochMillis) / 1000)
    let start = calendar.startOfDay(for: date)
    return Int64((start.timeIntervalSince1970 * 1000).rounded())
}

public let dayMillis: Int64 = 24 * 60 * 60 * 1000

/// What the Dock badge says, and whether it says anything at all.
///
/// Whole hours only — "1h", "4h" — and nothing under one. The reference's own reasoning is
/// that a badge is read at a glance from across a desk: minutes are noise at that distance,
/// and a badge reading "4h 23m" is a figure you have to stop and parse. This port had been
/// formatting it with `formatDurationShort`, which is right everywhere a number is read
/// deliberately and wrong here.
///
/// Pure, so the rule can be tested without a Dock.
public enum DockBadgeLabel {
    public static let hourSeconds = 3600
    public static let minimumHours = 1

    /// `nil` when the day has not earned a badge yet.
    public static func text(activeSeconds: Int) -> String? {
        let hours = activeSeconds / hourSeconds
        return hours >= minimumHours ? "\(hours)h" : nil
    }
}
