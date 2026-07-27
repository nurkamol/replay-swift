import Foundation

/// Knowing *when* a memory matters.
///
/// Every feature that surfaces a memory — a right-time note, an anniversary, something
/// forgotten, an echo of past work, a thread gaining a chapter — produces a candidate with a
/// confidence score, and this decides whether, and which, to show.
///
/// Two ideas govern it. **Confidence** is built from real signals only: how recent, how long
/// the session ran, whether it was marked, the weight of the project behind it, whether the
/// work repeats. Nothing is invented, and a missing signal contributes nothing rather than
/// contributing zero. **Silence** is a valid answer: when nothing clears the threshold, the
/// right thing to show is nothing at all.
///
/// The scoring is deliberately simple and legible. It is a calm heuristic and not a model —
/// the point is restraint, so the arithmetic only ever has to justify staying quiet.
///
/// Ported from `memory-intelligence.ts` in the Glaze app.
public struct MemoryCandidate: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// You just opened something you had not in a while.
        case rightTime = "right-time"
        /// A meaningful date has come round.
        case anniversary
        /// Something worth revisiting that you have let lie.
        case forgotten
        /// Today's work resembles a past session.
        case echo
        /// A memory thread gained a new chapter.
        case threadUpdate = "thread-update"
        /// An "on this day" memory.
        case todayInHistory = "today-in-history"
    }

    /// Stable, and the unit of dismissal: two runs must produce the same id for the same
    /// underlying memory, or a dismissed memory comes back.
    public var id: String
    public var kind: Kind
    /// 0–1. Below the threshold, the memory stays silent.
    public var confidence: Double
    /// The line shown first — short, plain, personal.
    public var headline: String
    /// A supporting line, when there is more worth saying.
    public var detail: String?
    /// A day to open when the memory is chosen.
    public var dayStart: Int64?
    /// A project to open instead of a day, for threads and echoes.
    public var projectID: String?
    public var appPath: String?
    public var bundleID: String?
    /// Some memories can be put away as well as dismissed.
    public var archivable: Bool

    public init(
        id: String, kind: Kind, confidence: Double, headline: String,
        detail: String? = nil, dayStart: Int64? = nil, projectID: String? = nil,
        appPath: String? = nil, bundleID: String? = nil, archivable: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.confidence = confidence
        self.headline = headline
        self.detail = detail
        self.dayStart = dayStart
        self.projectID = projectID
        self.appPath = appPath
        self.bundleID = bundleID
        self.archivable = archivable
    }
}

// ── confidence primitives ─────────────────────────────────────────────────────
//
// Small, named normalisers, so every producer scores in the same vocabulary and a reader can
// see exactly what raised or lowered a memory's confidence.

/// Clamp into 0–1.
public func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }

/// A linear ramp: 0 at or below `zero`, 1 at or above `full`, proportional between. `full`
/// may sit below `zero` to ramp the other way.
public func ramp(_ value: Double, _ zero: Double, _ full: Double) -> Double {
    if full == zero { return value >= full ? 1 : 0 }
    return clamp01((value - zero) / (full - zero))
}

/// Recency as a signal that decays with age: about 1 when fresh, about a half at the
/// half-life, trailing toward 0. For memories where more recent means more relevant.
public func freshness(ageDays: Double, halfLifeDays: Double) -> Double {
    if ageDays <= 0 { return 1 }
    return clamp01(pow(0.5, ageDays / max(1, halfLifeDays)))
}

/// Combine weighted signals into one confidence.
///
/// The weights need not sum to anything: the result is the weighted average of the signals
/// actually present, so a producer can omit an unknown signal rather than pass a misleading
/// zero — which is the difference between "no evidence" and "evidence against".
public func blendConfidence(_ parts: [(signal: Double, weight: Double)]) -> Double {
    let active = parts.filter { $0.weight > 0 }
    let totalWeight = active.reduce(0) { $0 + $1.weight }
    if totalWeight == 0 { return 0 }
    let sum = active.reduce(0) { $0 + clamp01($1.signal) * $1.weight }
    return clamp01(sum / totalWeight)
}

/// Whole days between two instants, by division rather than by calendar.
public func daysBetween(_ a: Int64, _ b: Int64) -> Double {
    abs(Double(a - b)) / Double(dayMillis)
}

/// How much a session's own attributes argue for remembering it: its length, and whether it
/// was marked — a bookmark or a note is a deliberate "this mattered".
public func sessionMeaning(activeSeconds: Int, bookmarked: Bool, hasNote: Bool) -> Double {
    blendConfidence([
        // Twenty minutes is meaningful; two hours fully so.
        (ramp(Double(activeSeconds), 20 * 60, 2 * 60 * 60), 1),
        (bookmarked ? 1 : 0, bookmarked ? 1.4 : 0),
        (hasNote ? 1 : 0, hasNote ? 1 : 0),
    ])
}

/// How much a project's weight argues for remembering something tied to it.
public func projectMeaning(totalSeconds: Int, sessionCount: Int) -> Double {
    blendConfidence([
        // An hour is notable; ten a real body of work.
        (ramp(Double(totalSeconds), 60 * 60, 10 * 60 * 60), 1),
        // Recurrence: twice is something, eight times is a habit.
        (ramp(Double(sessionCount), 2, 8), 1),
    ])
}

// ── selection, and silence ────────────────────────────────────────────────────

public struct MemorySelection: Sendable {
    /// Nothing below this is shown.
    public var threshold: Double
    /// Dismissed, and filtered out entirely.
    public var dismissed: Set<String>
    /// Put away, and filtered out of active surfacing.
    public var archived: Set<String>

    public init(threshold: Double, dismissed: Set<String> = [], archived: Set<String> = []) {
        self.threshold = threshold
        self.dismissed = dismissed
        self.archived = archived
    }
}

/// The candidates worth showing, most confident first.
public func eligibleMemories(
    _ candidates: [MemoryCandidate], _ options: MemorySelection
) -> [MemoryCandidate] {
    candidates
        .filter {
            $0.confidence >= options.threshold
                && !options.dismissed.contains($0.id)
                && !options.archived.contains($0.id)
        }
        // By confidence alone, and *stably*: two candidates that score the same keep the
        // order the producers ran in.
        //
        // The reference's comment claims ties break by id. Its code does not — it sorts by
        // confidence with JavaScript's stable sort, so input order survives. Written to the
        // comment first and the fixture caught it. The comment is the wrong one of the two
        // to follow: what ships is the code.
        .enumerated()
        .sorted {
            $0.element.confidence == $1.element.confidence
                ? $0.offset < $1.offset
                : $0.element.confidence > $1.element.confidence
        }
        .map(\.element)
}

/// The single memory worth surfacing right now, or nothing.
///
/// Nothing is a real answer and the common one. A card that always has something to say
/// stops being a memory and becomes a feed.
public func selectLivingMemory(
    _ candidates: [MemoryCandidate], _ options: MemorySelection
) -> MemoryCandidate? {
    eligibleMemories(candidates, options).first
}

/// A plain-language name for a threshold, for the setting that controls it.
public func confidenceThresholdLabel(_ threshold: Double) -> String {
    if threshold >= 0.75 { return "Only the most meaningful" }
    if threshold >= 0.55 { return "Balanced" }
    if threshold >= 0.35 { return "Show more memories" }
    return "Show nearly everything"
}
