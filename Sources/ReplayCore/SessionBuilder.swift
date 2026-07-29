import Foundation

/// What kind of work a session was, guessed from the applications in it.
///
/// Deliberately shallow. A wrong-but-confident category ("Design Session" for a day
/// in Xcode) is worse than the neutral fallback, so anything unrecognised stays
/// `.other` and the session is named after its dominant app instead.
public enum SessionCategory: String, Equatable, Sendable {
    case development = "Development"
    case research = "Research"
    case communication = "Communication"
    case writing = "Writing"
    case design = "Design"
    case media = "Media"
    case admin = "Admin"
    case other = "Other"
}

/// Matched against an application's display name, in order; first hit wins.
///
/// Kept identical to `CATEGORY_PATTERNS` in the Glaze app's `renderer/lib/sessions.ts`
/// and checked against `spec/constants.json` by the test suite — a session's title
/// depends on these, so a divergence renames sessions rather than merely
/// miscategorising them.
private let categoryPatterns: [(SessionCategory, String)] = [
    (.development,
     "terminal|iterm|warp|ghostty|alacritty|kitty|xcode|visual studio code|^code$|cursor|^zed$|sublime|intellij|pycharm|webstorm|goland|rubymine|phpstorm|android studio|docker|tableplus|sequel|postman|insomnia|fork|tower|sourcetree|nova|fleet|simulator|instruments"),
    (.research,
     "safari|chrome|firefox|^arc$|brave|microsoft edge|vivaldi|opera|chromium|orion|zen browser"),
    (.communication,
     "slack|telegram|whatsapp|discord|^mail$|messages|zoom|teams|mimestream|spark|outlook|signal|facetime|thunderbird|missive|front"),
    (.writing,
     "notes|obsidian|notion|^bear$|pages|microsoft word|ulysses|ia writer|craft|scrivener|typora|drafts|logseq"),
    (.design,
     "figma|sketch|photoshop|illustrator|affinity|pixelmator|canva|framer|principle|blender|after effects"),
    (.media,
     "^music$|spotify|^vlc$|quicktime|photos|^tv$|iina|infuse|podcast|final cut|davinci|audacity"),
    (.admin,
     "finder|commander one|forklift|path finder|system settings|system preferences|activity monitor|disk utility|console|keychain|app store|installer"),
]

private let compiledPatterns: [(SessionCategory, NSRegularExpression)] = categoryPatterns.compactMap {
    category, pattern in
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return nil
    }
    return (category, regex)
}

public func categorizeApp(_ applicationName: String) -> SessionCategory {
    let range = NSRange(applicationName.startIndex..., in: applicationName)
    for (category, regex) in compiledPatterns {
        if regex.firstMatch(in: applicationName, range: range) != nil { return category }
    }
    return .other
}

/// Which part of the day a timestamp falls in — the first word of every title.
public func dayPart(of epochMillis: Int64, calendar: Calendar = .current) -> String {
    let hour = calendar.component(
        .hour,
        from: Date(timeIntervalSince1970: Double(epochMillis) / 1000)
    )
    if hour < 5 { return "Late night" }
    if hour < 12 { return "Morning" }
    if hour < 17 { return "Afternoon" }
    if hour < 22 { return "Evening" }
    return "Late night"
}

/// What a session's title is made of, before it is a sentence.
///
/// A title is assembled at runtime — "Late night in Terminal" — so there is no whole string
/// in the source for a translator to be given, and a table of half-clauses cannot be put into
/// a language whose word order differs from English, which is most of them. This is the shape
/// the decision produces; ``english`` renders the contract and `Loc.sessionTitle` renders the
/// reader's language, both from the same branch. One decision, two renderings, so the two can
/// never disagree about which one a session got.
public enum SessionTitle: Equatable, Sendable {
    /// One app held most of the session: "Morning in Xcode".
    case inApp(part: String, app: String)
    /// No single app, but a category held enough: "Evening Research Session".
    case category(part: String, category: SessionCategory)
    /// Neither: "Morning Session".
    case plain(part: String)

    /// The English title, which is the contract the parity suite checks character for
    /// character. Nothing here may change without the reference changing first.
    public var english: String {
        switch self {
        case let .inApp(part, app): "\(part) in \(app)"
        case let .category(part, category): "\(part) \(category.rawValue) Session"
        case let .plain(part): "\(part) Session"
        }
    }
}

/// Decide what a session is called, from its apps.
///
/// One dominant app names the session after itself; otherwise a category with enough of the
/// time names it; otherwise it stays plain.
public func sessionTitle(
    apps: [SessionApp], startedAt: Int64, calendar: Calendar = .current
) -> (title: SessionTitle, category: SessionCategory) {
    let part = dayPart(of: startedAt, calendar: calendar)
    guard let top = apps.first else { return (.plain(part: part), .other) }

    var byCategory: [SessionCategory: Double] = [:]
    for app in apps {
        let category = categorizeApp(app.applicationName)
        byCategory[category, default: 0] += app.share
    }
    // Ties resolve by the pattern table's order, as they do in the Glaze app, where
    // insertion order into the Map comes from walking `apps` in time order.
    let ranked = byCategory
        .filter { $0.key != .other }
        .sorted { $0.value > $1.value }
    let topCategory = ranked.first?.key
    let topCategoryShare = ranked.first?.value ?? 0

    if top.share >= 0.65 {
        return (.inApp(part: part, app: top.applicationName), topCategory ?? .other)
    }
    if let topCategory, topCategoryShare >= 0.4 {
        return (.category(part: part, category: topCategory), topCategory)
    }
    return (.plain(part: part), .other)
}

/// Name a session from its apps: "Morning in Code", "Evening Research Session".
func nameSession(
    apps: [SessionApp], startedAt: Int64, calendar: Calendar = .current
) -> (title: String, category: SessionCategory) {
    let named = sessionTitle(apps: apps, startedAt: startedAt, calendar: calendar)
    return (named.title.english, named.category)
}

/// Fold a run's rows into per-application totals, most time first.
public func summarizeApps(_ events: [ActivityEvent], now: Int64) -> (apps: [SessionApp], activeSeconds: Int) {
    var order: [String] = []
    var byApp: [String: SessionApp] = [:]
    var activeSeconds = 0

    for event in events {
        let seconds = event.effectiveDuration(now: now)
        activeSeconds += seconds
        let key = event.bundleIdentifier ?? event.applicationName
        if var existing = byApp[key] {
            existing.seconds += seconds
            existing.switches += 1
            if existing.appPath == nil, let path = event.appPath { existing.appPath = path }
            byApp[key] = existing
        } else {
            order.append(key)
            byApp[key] = SessionApp(
                applicationName: event.applicationName,
                bundleIdentifier: event.bundleIdentifier,
                appPath: event.appPath,
                seconds: seconds,
                share: 0,
                switches: 1
            )
        }
    }

    // Sort by time, but keep first-seen order for equal times — JavaScript's sort is
    // stable and the fixtures were generated with it, so ties must break the same way.
    var apps = order.compactMap { byApp[$0] }
    apps = apps.enumerated()
        .sorted { lhs, rhs in
            if lhs.element.seconds != rhs.element.seconds {
                return lhs.element.seconds > rhs.element.seconds
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)

    let denominator = activeSeconds == 0 ? 1 : activeSeconds
    for index in apps.indices { apps[index].share = Double(apps[index].seconds) / Double(denominator) }
    return (apps, activeSeconds)
}

/// Turn a stream of rows into the timeline the UI reads: sessions, and the breaks
/// between them.
///
/// This is the single most important function to port faithfully — every headline
/// figure, title, and total in the app comes out of it — so it is checked against
/// `spec/fixtures/`, which holds the output the Glaze implementation actually
/// produced for the same inputs.
///
/// The rules, in the order they are applied to each row:
///   1. A hole of `recordingGapSeconds` or more since the previous row means Replay
///      was not running: close the run and emit an `unrecorded` break.
///   2. An `idle` row is a measured away stretch: close the run, emit an `away` break.
///   3. A row of `idleBreakSeconds` or more is absence rather than focus (this is the
///      fallback for data recorded before away stretches were measured): close the
///      run, emit an `idle` break.
///   4. Anything else extends the current run.
/// Finally: a run under `minSessionSeconds` with fewer than 3 rows is a stray switch
/// and is dropped, and breaks at either end are trimmed because they say nothing
/// about the shape of the day.
public func buildTimeline(
    _ events: [ActivityEvent], now: Int64, calendar: Calendar = .current
) -> [TimelineItem] {
    let ordered = events
        .filter { $0.type == .activated || $0.type == .idle }
        .enumerated()
        .sorted { lhs, rhs in
            if lhs.element.startedAt != rhs.element.startedAt {
                return lhs.element.startedAt < rhs.element.startedAt
            }
            return lhs.offset < rhs.offset   // stable, as in the reference implementation
        }
        .map(\.element)

    var items: [TimelineItem] = []
    var pending: [ActivityEvent] = []
    var pendingEnd: Int64 = 0

    func flushSession() {
        guard !pending.isEmpty else { return }
        let (apps, activeSeconds) = summarizeApps(pending, now: now)
        let startedAt = pending[0].startedAt
        let endedAt = pendingEnd

        if activeSeconds < Rules.minSessionSeconds && pending.count < 3 {
            pending = []
            return
        }

        let named = nameSession(apps: apps, startedAt: startedAt, calendar: calendar)
        items.append(.session(ActivitySession(
            title: named.title,
            category: named.category,
            startedAt: startedAt,
            endedAt: endedAt,
            spanSeconds: max(0, Int((Double(endedAt - startedAt) / 1000).rounded())),
            activeSeconds: activeSeconds,
            apps: apps,
            events: pending,
            switches: pending.count
        )))
        pending = []
    }

    for event in ordered {
        let seconds = event.effectiveDuration(now: now)
        let endedAt = event.endedAt ?? event.startedAt + Int64(seconds) * 1000

        // 1. A hole since the last row.
        if !pending.isEmpty {
            let gapSeconds = Int((Double(event.startedAt - pendingEnd) / 1000).rounded())
            if gapSeconds >= Rules.recordingGapSeconds {
                let gapStart = pendingEnd
                flushSession()
                items.append(.breakItem(ActivityBreak(
                    reason: .unrecorded,
                    startedAt: gapStart,
                    endedAt: event.startedAt,
                    seconds: gapSeconds,
                    applicationName: nil,
                    appPath: nil
                )))
            }
        }

        // 2. A measured away stretch.
        if event.type == .idle {
            flushSession()
            items.append(.breakItem(ActivityBreak(
                reason: .away,
                startedAt: event.startedAt,
                endedAt: endedAt,
                seconds: seconds,
                applicationName: nil,
                appPath: nil
            )))
            pendingEnd = max(pendingEnd, endedAt)
            continue
        }

        // 3. One app holding focus far too long.
        if seconds >= Rules.idleBreakSeconds {
            flushSession()
            items.append(.breakItem(ActivityBreak(
                reason: .idle,
                startedAt: event.startedAt,
                endedAt: endedAt,
                seconds: seconds,
                applicationName: event.applicationName,
                appPath: event.appPath
            )))
            pendingEnd = endedAt
            continue
        }

        pending.append(event)
        pendingEnd = endedAt
    }

    flushSession()

    while let first = items.first, case .breakItem = first { items.removeFirst() }
    while let last = items.last, case .breakItem = last { items.removeLast() }

    return items
}

/// Drop the long unbroken stretches that sessionization treats as breaks.
///
/// Totals built from raw rows count those stretches as use, which is how a Mac left
/// open overnight becomes "15h active in Finder". Every headline figure is derived
/// from this filtered set, so "active" means what a person would take it to mean.
public func excludeIdleStretches(_ events: [ActivityEvent], now: Int64) -> [ActivityEvent] {
    events.filter { $0.type != .idle && $0.effectiveDuration(now: now) < Rules.idleBreakSeconds }
}
