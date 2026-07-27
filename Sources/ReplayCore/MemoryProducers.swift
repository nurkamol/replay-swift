import Foundation

/// The things that might be worth remembering, each scored so the selector can decide.
///
/// Every producer here returns at most one candidate, and returns nothing far more often
/// than it returns something. That is the design: the surface they feed shows one memory or
/// none, so a producer that always had an answer would crowd out the ones that only speak
/// when they have something.
///
/// Ported from `right-time.ts`, `threads.ts` and `echoes.ts` in the Glaze app.
/// A project, as the producers need it. Enough to score it and to name it.
public struct MemoryProject: Sendable {
    public var id: String
    public var name: String
    public var apps: [Project.App]
    public var totalSeconds: Int
    public var sessionCount: Int
    public var firstSeen: Int64
    public var lastActive: Int64
    public var sessionStarts: [Int64]

    public init(
        id: String, name: String, apps: [Project.App], totalSeconds: Int,
        sessionCount: Int, firstSeen: Int64, lastActive: Int64, sessionStarts: [Int64]
    ) {
        self.id = id
        self.name = name
        self.apps = apps
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
        self.firstSeen = firstSeen
        self.lastActive = lastActive
        self.sessionStarts = sessionStarts
    }

    var meaning: Double {
        projectMeaning(totalSeconds: totalSeconds, sessionCount: sessionCount)
    }
}

// ── right time ────────────────────────────────────────────────────────────────

/// How far back to look for a previous use. Beyond this there is no number to give.
private let rightTimeLookbackDays = 90
/// Below this many days, opening something again is routine rather than a memory.
private let rightTimeMinGapDays = 6

/// "9 days", "3 weeks", "2 months" — a gap in the unit that reads best.
private func gapPhrase(_ days: Int) -> String {
    if days < 14 { return "\(days) \(days == 1 ? "day" : "days")" }
    if days < 60 {
        let weeks = Int((Double(days) / 7).rounded())
        return "\(weeks) \(weeks == 1 ? "week" : "weeks")"
    }
    let months = Int((Double(days) / 30).rounded())
    return "\(months) \(months == 1 ? "month" : "months")"
}

/// A note about the app most recently brought forward today, when there is a real gap
/// behind it.
///
/// Nothing when the app was in use last week: that is routine, and saying so would be noise
/// dressed as insight.
public func detectRightTime(
    events: [ActivityEvent],
    projects: [MemoryProject],
    now: Int64,
    calendar: Calendar = .current
) -> MemoryCandidate? {
    let todayStart = startOfLocalDay(now, calendar: calendar)
    let activations = events.filter { $0.type == .activated && $0.bundleIdentifier != nil }
    guard !activations.isEmpty else { return nil }

    // Whatever is in front right now.
    guard let latest = activations.max(by: { $0.startedAt < $1.startedAt }),
          latest.startedAt >= todayStart,
          let bundleID = latest.bundleIdentifier
    else { return nil }

    // When it was last used *before* today — the gap that might be worth a word.
    var priorUse: Int64 = 0
    var totalSeconds = 0
    for event in activations where event.bundleIdentifier == bundleID {
        totalSeconds += event.duration
        if event.startedAt < todayStart, event.startedAt > priorUse { priorUse = event.startedAt }
    }
    guard priorUse != 0 else { return nil }

    let gapDays = Int((Double(todayStart - startOfLocalDay(priorUse, calendar: calendar))
        / Double(dayMillis)).rounded())
    guard gapDays >= rightTimeMinGapDays else { return nil }

    // The project you were most likely in last time: among those leaning on this app, the
    // one active nearest that day.
    let lastUseDay = startOfLocalDay(priorUse, calendar: calendar)
    let candidates = projects.filter { $0.apps.contains { $0.bundleIdentifier == bundleID } }
    // The reference reduces and keeps the first on a tie, which `min(by:)` also does.
    let project = candidates.min {
        abs($0.lastActive - lastUseDay) < abs($1.lastActive - lastUseDay)
    }
    let context = project.map { ", while working on \($0.name)" } ?? ""

    let confidence = blendConfidence([
        // The gap itself: a week is notable, a couple of months fully so.
        (ramp(Double(gapDays), Double(rightTimeMinGapDays), 60), 1.2),
        // The context you were in gives the memory somewhere to stand.
        (project?.meaning ?? 0, project == nil ? 0 : 1),
        // And how much the app has meant across the window.
        (ramp(Double(totalSeconds), 60 * 60, 20 * 60 * 60), 0.8),
    ])

    return MemoryCandidate(
        // Keyed to today's open, so dismissing hides today's note and a future gap earns a
        // fresh one.
        id: "right-time:\(bundleID):\(todayStart)",
        kind: .rightTime,
        confidence: confidence,
        headline: "The last time you opened \(latest.applicationName) was "
            + "\(gapPhrase(gapDays)) ago\(context).",
        detail: (project?.sessionCount ?? 0) > 1
            ? "You'd spent \(formatDurationShort(project!.totalSeconds)) on it across "
                + "\(project!.sessionCount) sessions."
            : nil,
        dayStart: lastUseDay,
        appPath: latest.appPath,
        bundleID: bundleID
    )
}

// ── threads ───────────────────────────────────────────────────────────────────

/// Below this, returning is just continuing; at or above, a thread resumes.
private let threadResumeGapDays = 5

private func awayPhrase(_ days: Int) -> String {
    if days < 14 { return "\(days) days" }
    if days < 60 { return "\(Int((Double(days) / 7).rounded())) weeks" }
    return "\(Int((Double(days) / 30).rounded())) months"
}

/// The one thread that picked back up today after a real gap.
///
/// At most one, deliberately: this surface notes the thread that returned rather than
/// listing threads.
public func detectThreadUpdate(
    _ projects: [MemoryProject], now: Int64,
    calendar: Calendar = .current, locale: Locale = .current
) -> MemoryCandidate? {
    let today = startOfLocalDay(now, calendar: calendar)
    var best: MemoryCandidate?

    for project in projects {
        guard project.sessionStarts.count >= 2 else { continue }
        let times = project.sessionStarts.sorted()
        let latest = times[times.count - 1]
        guard startOfLocalDay(latest, calendar: calendar) == today else { continue }

        let previous = times[times.count - 2]
        let gapDays = Int((Double(
            startOfLocalDay(latest, calendar: calendar)
                - startOfLocalDay(previous, calendar: calendar)
        ) / Double(dayMillis)).rounded())
        guard gapDays >= threadResumeGapDays else { continue }

        let confidence = blendConfidence([
            (project.meaning, 1.2),
            (ramp(Double(gapDays), Double(threadResumeGapDays), 60), 1),
        ])
        if let best, best.confidence >= confidence { continue }

        let since = monthYearLabel(project.firstSeen, calendar: calendar, locale: locale)
        best = MemoryCandidate(
            id: "thread-update:\(project.id):\(today)",
            kind: .threadUpdate,
            confidence: confidence,
            headline: "You picked \(project.name) back up today, after "
                + "\(awayPhrase(gapDays)) away.",
            detail: "\(project.sessionCount) sessions since \(since) · "
                + "\(formatDurationShort(project.totalSeconds)) in all.",
            projectID: project.id,
            appPath: project.apps.first?.appPath,
            bundleID: project.apps.first?.bundleIdentifier
        )
    }

    return best
}

// ── echoes ────────────────────────────────────────────────────────────────────

/// Below this a project is still recent, and returning to it is continuing rather than
/// echoing.
private let echoMinDormantDays = 12
private let echoMinSimilarity = 0.5
private let echoMinTodaySeconds = 20 * 60
/// Echoes are held to a firm floor of their own, whatever the user's threshold is: a
/// resemblance should never speak unless it is really there.
private let echoConfidenceFloor = 0.58

/// The strongest resemblance between today and a dormant project, or nothing.
public func detectEcho(
    events: [ActivityEvent],
    projects: [MemoryProject],
    now: Int64,
    calendar: Calendar = .current,
    locale: Locale = .current
) -> MemoryCandidate? {
    // The apps that carried the most time today.
    var byApp: [String: (seconds: Int, order: Int)] = [:]
    for event in events where event.type == .activated {
        guard let id = event.bundleIdentifier else { continue }
        if byApp[id] != nil {
            byApp[id]!.seconds += event.effectiveDuration(now: now)
        } else {
            byApp[id] = (event.effectiveDuration(now: now), byApp.count)
        }
    }
    let ranked = byApp
        .sorted { $0.value.seconds == $1.value.seconds
            ? $0.value.order < $1.value.order
            : $0.value.seconds > $1.value.seconds }
    let todaySeconds = ranked.reduce(0) { $0 + $1.value.seconds }
    let todayIDs = Set(ranked.prefix(4).map(\.key))
    guard todaySeconds >= echoMinTodaySeconds, todayIDs.count >= 2 else { return nil }

    var best: (project: MemoryProject, score: Double)?
    for project in projects {
        let dormantDays = Int((Double(now - project.lastActive) / Double(dayMillis)).rounded())
        guard dormantDays >= echoMinDormantDays else { continue }
        let projectApps = Set(project.apps.compactMap(\.bundleIdentifier))
        guard !projectApps.isEmpty else { continue }
        // Jaccard overlap: shared over the union, so a project with many apps does not win
        // simply by having many.
        let shared = todayIDs.intersection(projectApps).count
        let union = todayIDs.union(projectApps).count
        let score = union == 0 ? 0 : Double(shared) / Double(union)
        guard score >= echoMinSimilarity, shared >= 2 else { continue }
        if best == nil || score > best!.score { best = (project, score) }
    }
    guard let best else { return nil }

    let dormantDays = Int((Double(now - best.project.lastActive) / Double(dayMillis)).rounded())
    let confidence = blendConfidence([
        (best.score, 1.4),
        (best.project.meaning, 1),
        (ramp(Double(dormantDays), Double(echoMinDormantDays), 120), 0.6),
    ])
    guard confidence >= echoConfidenceFloor else { return nil }

    let when = relativeDayLabel(
        best.project.lastActive, now: now, calendar: calendar, locale: locale
    ).lowercased()
    return MemoryCandidate(
        id: "echo:\(best.project.id):\(isoDay(now, calendar: calendar))",
        kind: .echo,
        confidence: confidence,
        headline: "Today echoes your \(best.project.name) work.",
        detail: "The same tools you were in \(when) — worth a look back.",
        projectID: best.project.id,
        appPath: best.project.apps.first?.appPath,
        bundleID: best.project.apps.first?.bundleIdentifier
    )
}

/// "July 2026" — a month and year, for a since-line.
private func monthYearLabel(_ millis: Int64, calendar: Calendar, locale: Locale) -> String {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate("MMMMy")
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
}

/// "2026-07-27" — the calendar day, for an id that changes once a day.
///
/// The reference slices a UTC ISO string, which names the wrong day either side of midnight
/// in most of the world. Built from the local calendar here, which is what the id means.
private func isoDay(_ millis: Int64, calendar: Calendar) -> String {
    let parts = calendar.dateComponents(
        [.year, .month, .day], from: Date(timeIntervalSince1970: Double(millis) / 1000)
    )
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

// ── anniversaries ─────────────────────────────────────────────────────────────

/// If today is an exact anniversary of `originDay`, how far back it reaches.
///
/// Years land on the same month and day; the six-month mark lands on the same day of the
/// month half a year on. Anything else is not an anniversary today — approximate ones would
/// mean something to say most days, which is the opposite of the point.
private func anniversary(
    of originDay: Int64, today: Int64, calendar: Calendar
) -> (unit: String, count: Int)? {
    let origin = calendar.dateComponents(
        [.year, .month, .day], from: Date(timeIntervalSince1970: Double(originDay) / 1000)
    )
    let now = calendar.dateComponents(
        [.year, .month, .day], from: Date(timeIntervalSince1970: Double(today) / 1000)
    )
    guard now.day == origin.day else { return nil }

    if now.month == origin.month, let y1 = now.year, let y0 = origin.year, y1 > y0 {
        return ("year", y1 - y0)
    }
    guard let y1 = now.year, let y0 = origin.year, let m1 = now.month, let m0 = origin.month
    else { return nil }
    let months = (y1 - y0) * 12 + (m1 - m0)
    return months == 6 ? ("month", 6) : nil
}

/// "One year", "3 years", "Six months" — the span an anniversary marks.
private func spanPhrase(_ unit: String, _ count: Int) -> String {
    if unit == "year" { return count == 1 ? "One year" : "\(count) years" }
    return "Six months"
}

/// What a reflection or a bookmark's first mark is, for an anniversary.
public struct DatedText: Sendable {
    public var dayStart: Int64
    public var text: String

    public init(dayStart: Int64, text: String) {
        self.dayStart = dayStart
        self.text = text
    }
}

/// Every anniversary that falls on today.
public func detectAnniversaries(
    seed: MomentSeed?,
    projects: [MemoryProject],
    bookmarks: [SessionAnnotation],
    reflections: [DatedText],
    now: Int64,
    calendar: Calendar = .current
) -> [MemoryCandidate] {
    let today = startOfLocalDay(now, calendar: calendar)
    let year = calendar.component(
        .year, from: Date(timeIntervalSince1970: Double(today) / 1000)
    )
    var out: [MemoryCandidate] = []

    func add(
        _ type: String, _ originDay: Int64, _ confidence: Double, _ headline: String,
        appPath: String? = nil, bundleID: String? = nil
    ) {
        out.append(MemoryCandidate(
            id: "anniversary:\(type):\(originDay):\(year)",
            kind: .anniversary, confidence: confidence, headline: headline,
            dayStart: originDay, appPath: appPath, bundleID: bundleID
        ))
    }

    // The memory itself — the day you started keeping it.
    if let firstEventAt = seed?.firstEventAt {
        let origin = startOfLocalDay(firstEventAt, calendar: calendar)
        if let marked = anniversary(of: origin, today: today, calendar: calendar),
           marked.unit == "year" {
            add(
                "origin", origin, min(0.98, 0.88 + Double(marked.count) * 0.03),
                "\(spanPhrase(marked.unit, marked.count)) ago today, "
                    + "you began keeping this memory."
            )
        }
    }

    // Projects — six months, or a year, since the work began.
    for project in projects {
        let origin = startOfLocalDay(project.firstSeen, calendar: calendar)
        guard let marked = anniversary(of: origin, today: today, calendar: calendar) else {
            continue
        }
        add(
            "project:\(project.id)", origin,
            blendConfidence([
                (marked.unit == "year" ? 1 : 0.7, 1),
                (project.meaning, 1.2),
            ]),
            "\(spanPhrase(marked.unit, marked.count)) since you began \(project.name)."
        )
    }

    // Applications — a year since you first opened one that stuck around.
    for app in seed?.appFirstSeen ?? [] {
        let origin = startOfLocalDay(app.firstAt, calendar: calendar)
        guard let marked = anniversary(of: origin, today: today, calendar: calendar),
              marked.unit == "year" else { continue }
        add(
            "app:\(app.bundleIdentifier)", origin,
            0.6 + min(0.2, Double(marked.count) * 0.1),
            "\(spanPhrase(marked.unit, marked.count)) since you first opened "
                + "\(app.applicationName).",
            appPath: app.appPath, bundleID: app.bundleIdentifier
        )
    }

    // The first session you ever marked.
    let marked = bookmarks.filter { $0.updatedAt > 0 }
    if let firstMark = marked.min(by: { $0.updatedAt < $1.updatedAt }) {
        let origin = startOfLocalDay(firstMark.updatedAt, calendar: calendar)
        if let anniv = anniversary(of: origin, today: today, calendar: calendar),
           anniv.unit == "year" {
            add(
                "first-bookmark",
                startOfLocalDay(firstMark.sessionStart, calendar: calendar), 0.7,
                "\(spanPhrase(anniv.unit, anniv.count)) since you saved your first bookmark."
            )
        }
    }

    // And the first thing you wrote down to remember.
    if let firstReflection = reflections.min(by: { $0.dayStart < $1.dayStart }) {
        let origin = startOfLocalDay(firstReflection.dayStart, calendar: calendar)
        if let anniv = anniversary(of: origin, today: today, calendar: calendar),
           anniv.unit == "year" {
            add(
                "first-reflection", origin, 0.72,
                "\(spanPhrase(anniv.unit, anniv.count)) since you wrote your first reflection."
            )
        }
    }

    return out
}

// ── forgotten ─────────────────────────────────────────────────────────────────

/// Old enough that it may genuinely have slipped your mind.
private let forgottenBookmarkMinDays = 45
private let forgottenProjectMinDays = 21
private let forgottenReflectionMinDays = 120

/// "9 days", "3 weeks", "2 months", "over a year".
private func agePhrase(_ days: Int) -> String {
    if days < 14 { return "\(days) days" }
    if days < 60 { return "\(Int((Double(days) / 7).rounded())) weeks" }
    if days < 365 { return "\(Int((Double(days) / 30).rounded())) months" }
    let years = days / 365
    return years == 1 ? "over a year" : "\(years) years"
}

/// A single-line preview of something longer.
private func excerpt(_ text: String, max: Int = 90) -> String {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    if clean.count <= max { return clean }
    return String(clean.prefix(max - 1)) + "…"
}

/// Old-but-meaningful things worth revisiting.
///
/// These can be archived as well as dismissed: putting one away for good is a different act
/// from saying "not today", and something you deliberately kept deserves both.
public func detectForgotten(
    projects: [MemoryProject],
    bookmarks: [SessionAnnotation],
    reflections: [DatedText],
    now: Int64,
    calendar: Calendar = .current
) -> [MemoryCandidate] {
    let today = startOfLocalDay(now, calendar: calendar)
    var out: [MemoryCandidate] = []

    func age(_ day: Int64) -> Int {
        Int((Double(today - day) / Double(dayMillis)).rounded())
    }

    for mark in bookmarks {
        let day = startOfLocalDay(mark.sessionStart, calendar: calendar)
        let days = age(day)
        guard days >= forgottenBookmarkMinDays else { continue }
        out.append(MemoryCandidate(
            id: "forgotten:bookmark:\(mark.sessionStart)",
            kind: .forgotten,
            confidence: blendConfidence([
                (sessionMeaning(
                    activeSeconds: 0, bookmarked: true, hasNote: !mark.note.isEmpty
                ), 1),
                (ramp(Double(days), Double(forgottenBookmarkMinDays), 240), 1),
            ]),
            headline: "A bookmark you saved \(agePhrase(days)) ago.",
            detail: mark.note.isEmpty ? nil : excerpt(mark.note),
            dayStart: day,
            archivable: true
        ))
    }

    for project in projects {
        let day = startOfLocalDay(project.lastActive, calendar: calendar)
        let days = age(day)
        guard days >= forgottenProjectMinDays else { continue }
        let meaning = project.meaning
        // Only work with real weight behind it: "you have not returned to a thing you did
        // twice" is not a memory, it is a nag.
        guard meaning >= 0.25 else { continue }
        out.append(MemoryCandidate(
            id: "forgotten:project:\(project.id):\(day)",
            kind: .forgotten,
            confidence: blendConfidence([
                (meaning, 1.2),
                (ramp(Double(days), Double(forgottenProjectMinDays), 150), 1),
            ]),
            headline: "You haven't returned to \(project.name) in \(agePhrase(days)).",
            dayStart: day,
            appPath: project.apps.first?.appPath,
            bundleID: project.apps.first?.bundleIdentifier,
            archivable: true
        ))
    }

    for reflection in reflections {
        guard !reflection.text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        let day = startOfLocalDay(reflection.dayStart, calendar: calendar)
        let days = age(day)
        guard days >= forgottenReflectionMinDays else { continue }
        out.append(MemoryCandidate(
            id: "forgotten:reflection:\(day)",
            kind: .forgotten,
            confidence: blendConfidence([
                (0.7, 1),
                (ramp(Double(days), Double(forgottenReflectionMinDays), 500), 1),
            ]),
            headline: "A reflection you wrote \(agePhrase(days)) ago.",
            detail: excerpt(reflection.text),
            dayStart: day,
            archivable: true
        ))
    }

    // Most confident first, and stably — two of equal weight keep the order they were
    // gathered in, which is bookmarks, then projects, then reflections.
    return out.enumerated()
        .sorted {
            $0.element.confidence == $1.element.confidence
                ? $0.offset < $1.offset
                : $0.element.confidence > $1.element.confidence
        }
        .map(\.element)
}
