import Foundation

/// The coarse buckets the Timeline filters by.
///
/// Fewer than the session categories, and deliberately so: a row of nine chips is a control
/// panel, and the point of these is to narrow a day at a glance. Writing and Media have no
/// top-level bucket of their own and fall to Other, which is the reference's choice and is
/// pinned here so it stays one.
///
/// Ported from `FILTER_CATEGORIES` and `sessionFilterCategory` in the Glaze app.
public enum FilterCategory: String, CaseIterable, Sendable, Hashable {
    case development = "Development"
    case browsing = "Browsing"
    case communication = "Communication"
    case design = "Design"
    case utilities = "Utilities"
    case other = "Other"
}

/// Which bucket a whole session belongs to.
public func sessionFilterCategory(_ session: ActivitySession) -> FilterCategory {
    switch session.category {
    case .development: .development
    // "Research" is what the derivation calls it; "Browsing" is what a person would.
    case .research: .browsing
    case .communication: .communication
    case .design: .design
    case .admin: .utilities
    // Writing and Media have no bucket of their own.
    case .writing, .media, .other: .other
    }
}
