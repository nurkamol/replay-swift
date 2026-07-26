import Foundation

/// A day's headline figures — what Today leads with.
///
/// Every number here is derived from the *filtered* event set: rows longer than
/// `idleStretchSeconds` are excluded, so "active" means what a person would take it to
/// mean rather than counting a Mac left open overnight as use. See SPEC §4.
public struct DaySummary: Equatable, Sendable {
    public var activeSeconds: Int
    public var appsUsed: Int
    /// Real sessions, not app switches.
    public var sessionCount: Int
    public var switches: Int
    /// Active seconds per hour of the day, index 0–23.
    public var arc: [Int]
    public var mostUsed: SessionApp?
    public var longestSession: ActivitySession?
    /// How fragmented the day was. `nil` until there is enough switching to say anything
    /// honest about it — see ``Focus``.
    public var focus: Focus?

    /// The mean length of one uninterrupted stretch on a single app before switching away.
    public struct Focus: Equatable, Sendable {
        public var averageStretchSeconds: Int
        /// A plain word for the rhythm, never a score.
        public var quality: Quality
        public enum Quality: String, Equatable, Sendable {
            case deep, steady, scattered
        }
    }
}

/// Below either threshold there is not enough of a day to characterise, and guessing
/// would be the kind of confident-but-wrong claim this app avoids.
private let focusMinSwitches = 4
private let focusMinSeconds = 5 * 60

/// Compute a day's headline from its rows and the timeline already built from them.
///
/// Ported from `computeDaySummary` in the Glaze app. Note it takes both the raw events and
/// the derived timeline: session counts come from the timeline, but the totals are computed
/// from the events directly, after filtering.
public func computeDaySummary(
    events: [ActivityEvent],
    timeline: [TimelineItem],
    dayStart: Int64,
    now: Int64
) -> DaySummary {
    let sessions = timeline.compactMap { item -> ActivitySession? in
        if case .session(let session) = item { return session }
        return nil
    }
    let active = excludeIdleStretches(events, now: now)
    let (apps, activeSeconds) = summarizeApps(active, now: now)

    let longest = sessions.max { $0.activeSeconds < $1.activeSeconds }

    var focus: DaySummary.Focus?
    if active.count >= focusMinSwitches && activeSeconds >= focusMinSeconds {
        let average = Int((Double(activeSeconds) / Double(active.count)).rounded())
        let quality: DaySummary.Focus.Quality =
            average >= 6 * 60 ? .deep : average >= 150 ? .steady : .scattered
        focus = DaySummary.Focus(averageStretchSeconds: average, quality: quality)
    }

    return DaySummary(
        activeSeconds: activeSeconds,
        appsUsed: apps.count,
        sessionCount: sessions.count,
        switches: active.count,
        arc: dayArc(active, dayStart: dayStart, now: now),
        mostUsed: apps.first,
        longestSession: longest,
        focus: focus
    )
}

/// Active seconds per hour of the day, spreading each row across the hours it spans.
func dayArc(_ events: [ActivityEvent], dayStart: Int64, now: Int64) -> [Int] {
    var hours = [Double](repeating: 0, count: 24)
    let hourMillis: Int64 = 60 * 60 * 1000

    for event in events {
        let from = event.startedAt
        let to = event.endedAt ?? from + Int64(event.effectiveDuration(now: now)) * 1000
        guard to > from else { continue }

        var cursor = from
        while cursor < to {
            let hourIndex = Int(floor(Double(cursor - dayStart) / Double(hourMillis)))
            let hourEnd = dayStart + Int64(hourIndex + 1) * hourMillis
            let slice = min(to, hourEnd) - cursor
            if hourIndex >= 0 && hourIndex < 24 {
                hours[hourIndex] += Double(slice) / 1000
            }
            cursor += max(slice, 1)   // never stall, even on a zero-length slice
        }
    }
    return hours.map { Int($0.rounded()) }
}

/// "<1m", "45m", "2h", "1h 23m" — the app's one duration format.
///
/// Ported from `formatDurationShort`. Used everywhere a length is shown, so a change here
/// is visible on every surface.
public func formatDurationShort(_ seconds: Int) -> String {
    let totalMinutes = Int((Double(seconds) / 60).rounded())
    if totalMinutes < 1 { return "<1m" }
    if totalMinutes < 60 { return "\(totalMinutes)m" }
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
}

/// "9:11 – 10:27 AM", collapsing the meridiem when both ends share one.
public func formatRange(_ startedAt: Int64, _ endedAt: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm"
    let meridiem = DateFormatter()
    meridiem.dateFormat = "a"

    let from = Date(timeIntervalSince1970: Double(startedAt) / 1000)
    let to = Date(timeIntervalSince1970: Double(endedAt) / 1000)
    let fromMeridiem = meridiem.string(from: from)
    let toMeridiem = meridiem.string(from: to)

    if fromMeridiem == toMeridiem {
        return "\(formatter.string(from: from)) – \(formatter.string(from: to)) \(toMeridiem)"
    }
    return "\(formatter.string(from: from)) \(fromMeridiem) – \(formatter.string(from: to)) \(toMeridiem)"
}
