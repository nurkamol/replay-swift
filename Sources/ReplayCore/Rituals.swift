import Foundation

/// The shape your days tend to take.
///
/// Not a schedule and not a target — just the quiet patterns already in the history: the app
/// you usually open first, and the one that tends to lead each part of the day. A part only
/// counts once the same app has led it on more than one day, so a single sitting never
/// masquerades as a habit (SPEC §8).
///
/// Ported from `detectRituals` in the Glaze app.
public struct Rituals: Equatable, Sendable {
    public struct App: Equatable, Sendable {
        public var applicationName: String
        public var bundleIdentifier: String?
        public var appPath: String?
        /// Distinct days this app led.
        public var days: Int
    }

    public struct Slot: Equatable, Sendable {
        public var part: String
        public var app: App
    }

    /// The app that tends to lead each part of the day, in the order a day unfolds.
    public var slots: [Slot]
    /// The app your day most often begins with.
    public var firstApp: App?

    /// Public so a model can hold an empty one before anything is loaded.
    public init(slots: [Slot], firstApp: App?) {
        self.slots = slots
        self.firstApp = firstApp
    }
}

/// A part must lead on at least this many distinct days to count as a ritual.
private let ritualMinDays = 2

/// Presented in the order a day unfolds.
public let dayParts = ["Morning", "Afternoon", "Evening", "Late night"]

public func detectRituals(
    sessions: [ActivitySession], events: [ActivityEvent], calendar: Calendar = .current
) -> Rituals {
    /// One app's tally: which distinct days it led, and the order it was first seen in.
    struct Tally {
        var app: Rituals.App
        var days: Set<Int64>
        var order: Int
    }

    /// The app leading the most days, or nothing when the leader is a one-off.
    ///
    /// The reference walks its `Map` and keeps the first strictly-greater entry, so a tie
    /// goes to whichever was seen first. Insertion order is tracked here because Swift's
    /// dictionaries have none.
    func leader(_ tally: [String: Tally]) -> Rituals.App? {
        var best: Tally?
        for entry in tally.values.sorted(by: { $0.order < $1.order })
        where best == nil || entry.days.count > best!.days.count {
            best = entry
        }
        guard let best, best.days.count >= ritualMinDays else { return nil }
        var app = best.app
        app.days = best.days.count
        return app
    }

    // Which app leads each part of the day, tallied by distinct days.
    var byPart: [String: [String: Tally]] = [:]
    for session in sessions {
        guard let top = session.apps.first else { continue }
        let part = dayPart(of: session.startedAt, calendar: calendar)
        let key = top.bundleIdentifier ?? top.applicationName
        var bucket = byPart[part] ?? [:]
        if bucket[key] != nil {
            bucket[key]!.days.insert(startOfLocalDay(session.startedAt, calendar: calendar))
            if bucket[key]!.app.appPath == nil { bucket[key]!.app.appPath = top.appPath }
        } else {
            bucket[key] = Tally(
                app: Rituals.App(
                    applicationName: top.applicationName,
                    bundleIdentifier: top.bundleIdentifier,
                    appPath: top.appPath,
                    days: 0
                ),
                days: [startOfLocalDay(session.startedAt, calendar: calendar)],
                order: bucket.count
            )
        }
        byPart[part] = bucket
    }

    let slots = dayParts.compactMap { part -> Rituals.Slot? in
        leader(byPart[part] ?? [:]).map { Rituals.Slot(part: part, app: $0) }
    }

    // The app the day most often begins with — the first focus recorded each day.
    var firstByDay: [Int64: ActivityEvent] = [:]
    for event in events where event.type == .activated {
        let day = startOfLocalDay(event.startedAt, calendar: calendar)
        if let current = firstByDay[day], current.startedAt <= event.startedAt { continue }
        firstByDay[day] = event
    }
    var firstTally: [String: Tally] = [:]
    // Days in order, so the insertion order the tie-break depends on is the day order rather
    // than whatever a Swift dictionary happens to hand back.
    for day in firstByDay.keys.sorted() {
        let event = firstByDay[day]!
        let key = event.bundleIdentifier ?? event.applicationName
        if firstTally[key] != nil {
            firstTally[key]!.days.insert(day)
        } else {
            firstTally[key] = Tally(
                app: Rituals.App(
                    applicationName: event.applicationName,
                    bundleIdentifier: event.bundleIdentifier,
                    appPath: event.appPath,
                    days: 0
                ),
                days: [day],
                order: firstTally.count
            )
        }
    }

    return Rituals(slots: slots, firstApp: leader(firstTally))
}
