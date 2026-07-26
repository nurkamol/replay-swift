import Foundation

/// The session to offer picking back up.
///
/// Ported from `findResumeTarget` in the Glaze app.
public struct ResumeTarget: Equatable, Sendable {
    public var session: ActivitySession
    /// The app that took most of the session — what "resume" actually means here.
    public var app: SessionApp
    /// True when the session ended on an earlier calendar day.
    public var isEarlierDay: Bool
}

/// A session is treated as still running if its last row ended this recently.
private let inProgressSeconds = 3 * 60

/// The most recent session you have actually stepped away from.
///
/// Deliberately not "the latest session": while you are working, the latest session is the
/// one you are already in, and offering to resume it is noise. After a break this is the
/// morning's work; first thing tomorrow it is yesterday evening's.
public func findResumeTarget(
    _ items: [TimelineItem], now: Int64, calendar: Calendar = .current
) -> ResumeTarget? {
    let sessions = items.compactMap { item -> ActivitySession? in
        if case .session(let session) = item { return session }
        return nil
    }
    guard let newest = sessions.last else { return nil }

    let newestIsLive = Double(now - newest.endedAt) / 1000 < Double(inProgressSeconds)
    let target = newestIsLive ? sessions.dropLast().last : newest
    guard let target, let app = target.apps.first else { return nil }

    return ResumeTarget(
        session: target,
        app: app,
        isEarlierDay: startOfLocalDay(target.endedAt, calendar: calendar)
            != startOfLocalDay(now, calendar: calendar)
    )
}

/// When something happened, the way a person would say it.
///
/// "Today at 2:59 PM", "Yesterday at 9:42 PM", "Friday at 9:42 PM", "February 3 at 9:42 AM".
///
/// The clock is built by hand rather than by a formatter because the reference builds it by
/// hand: twelve-hour, and "AM"/"PM" as literal text rather than the locale's own symbols.
/// Matching that is the point — a formatter here would be more correct and would disagree
/// with the app people already use.
/// The locale is a separate parameter rather than read off the calendar: a `Calendar`
/// built for a timezone usually has no locale, and a nil one resolves a format template
/// against the root locale — where "February" comes back as "M02".
public func formatWhen(
    _ timestamp: Int64, now: Int64,
    calendar: Calendar = .current, locale: Locale = .current
) -> String {
    let then = Date(timeIntervalSince1970: Double(timestamp) / 1000)
    // Rounded, not truncated: across a daylight-saving boundary two local midnights are
    // 23 or 25 hours apart, and integer division would call yesterday "2 days ago" twice a
    // year. The reference rounds; so does this.
    let dayDiff = Int((Double(
        startOfLocalDay(now, calendar: calendar)
            - startOfLocalDay(timestamp, calendar: calendar)
    ) / Double(dayMillis)).rounded())

    let hour = calendar.component(.hour, from: then)
    let minute = calendar.component(.minute, from: then)
    let meridiem = hour < 12 ? "AM" : "PM"
    let twelve = hour % 12 == 0 ? 12 : hour % 12
    let clock = "\(twelve):\(String(format: "%02d", minute)) \(meridiem)"

    if dayDiff == 0 { return "Today at \(clock)" }
    if dayDiff == 1 { return "Yesterday at \(clock)" }

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    if dayDiff < 7 {
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
    } else {
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
    }
    return "\(formatter.string(from: then)) at \(clock)"
}
