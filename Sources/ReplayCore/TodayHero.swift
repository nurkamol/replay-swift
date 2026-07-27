import Foundation

/// Living Home: the one thing Today leads with, chosen for the day.
///
/// The reference's own idea, and its own words for why — *"instead of stacking every memory
/// card, Today features one — a single hero chosen for the day and rotated so the screen
/// never feels static."* This port had been showing all of them at once: the quote, the
/// resume card and today-in-history stacked on top of the briefing and the contextual memory,
/// so a rich day produced a column of cards before the day itself began.
///
/// Two rules, both the reference's. A session you stepped away from in the last few hours
/// always leads, because it puts *now* within reach at the top of the screen and nothing else
/// on Today is more useful than that. Otherwise the candidates rotate on the day number, so
/// the choice holds for a day and changes tomorrow — deterministic rather than random,
/// because a home screen that shuffles every time you look at it is not restful, it is busy.
public enum TodayHero: String, Sendable, CaseIterable {
    case resume
    case todayInHistory = "today-in-history"
    case reflection
    case quote
}

/// How fresh a resume target has to be to lead outright.
public let todayHeroRecentSeconds: Int64 = 6 * 60 * 60

/// How far back Today looks for a reflection worth offering again.
public let todayHeroReflectionLookbackDays = 30

/// What Today has available to lead with.
public struct TodayHeroOffer: Equatable, Sendable {
    /// When the session you stepped away from ended, or `nil` if there is nothing to resume.
    public var resumeEndedAt: Int64?
    public var hasFeaturedMemory: Bool
    /// A reflection written on some earlier day, worth reading again.
    public var hasRecentReflection: Bool
    public var hasQuote: Bool
    /// Two of the four are memories, and someone who turned history off asked not to be
    /// shown them.
    public var historyEnabled: Bool

    public init(
        resumeEndedAt: Int64? = nil,
        hasFeaturedMemory: Bool = false,
        hasRecentReflection: Bool = false,
        hasQuote: Bool = false,
        historyEnabled: Bool = true
    ) {
        self.resumeEndedAt = resumeEndedAt
        self.hasFeaturedMemory = hasFeaturedMemory
        self.hasRecentReflection = hasRecentReflection
        self.hasQuote = hasQuote
        self.historyEnabled = historyEnabled
    }
}

/// Which one of them leads today. `nil` when there is nothing to lead with, and that is a
/// real answer — most days Today has a headline and a list of sessions and needs no hero.
public func pickTodayHero(
    _ offer: TodayHeroOffer, now: Int64, todayStart: Int64
) -> TodayHero? {
    if let ended = offer.resumeEndedAt, now - ended < todayHeroRecentSeconds * 1000 {
        return .resume
    }

    // The order matters: it is the order the rotation walks, so it decides which hero a
    // given day lands on. Kept as the reference pushes them.
    var candidates: [TodayHero] = []
    if offer.resumeEndedAt != nil { candidates.append(.resume) }
    if offer.historyEnabled && offer.hasFeaturedMemory { candidates.append(.todayInHistory) }
    if offer.hasRecentReflection { candidates.append(.reflection) }
    if offer.historyEnabled && offer.hasQuote { candidates.append(.quote) }
    guard !candidates.isEmpty else { return nil }

    // Whole days since the epoch, floored. `todayStart` is a local midnight, so this is the
    // day's own number and every hero holds from midnight to midnight.
    let dayIndex = Int(floor(Double(todayStart) / Double(dayMillis)))
    return candidates[((dayIndex % candidates.count) + candidates.count) % candidates.count]
}

extension Memories {
    /// The memory Today would feature: the fullest day among them.
    ///
    /// Ties keep the earliest, which is the offset nearest today — the reference reduces with
    /// a strict `>`, so the first of an equal pair is never displaced.
    public static func pickFeatured(_ memories: [Memory]) -> Memory? {
        memories.reduce(nil) { best, memory in
            guard let best else { return memory }
            return memory.summary.activeSeconds > best.summary.activeSeconds ? memory : best
        }
    }
}
