import Foundation

/// Your sessions, gathered by the kind of work they were.
///
/// Nothing to set up and nothing to file: a session already knows its category, so a
/// collection is every session of one kind with its running totals. They appear only when
/// there is something in them and grow on their own as sessions are recorded — which is why
/// there is no table here and never will be. A collection the user has to maintain is a
/// filing system, and this app does not ask for one.
public enum Collections {

    /// The categories worth surfacing, in the order the reference lists them.
    ///
    /// `Admin` is shown as **Utilities**: the category name is what the derivation calls it,
    /// the label is what a person is shown, and the two are deliberately not the same word.
    /// `Other` is absent on purpose — a session the app could not confidently name is not a
    /// kind of work, and collecting them would be inventing a theme for a scattered hour.
    public static let categories: [(category: SessionCategory, label: String)] = [
        (.development, "Development"),
        (.design, "Design"),
        (.research, "Research"),
        (.communication, "Communication"),
        (.writing, "Writing"),
        (.media, "Media"),
        (.admin, "Utilities"),
    ]

    public static func isCollectable(_ category: SessionCategory) -> Bool {
        categories.contains { $0.category == category }
    }

    public static func label(for category: SessionCategory) -> String {
        categories.first { $0.category == category }?.label ?? category.rawValue
    }

    public struct App: Equatable, Sendable {
        public var applicationName: String
        public var appPath: String?
        public var seconds: Int
    }

    public struct Collection: Equatable, Sendable {
        public var category: SessionCategory
        public var label: String
        public var sessionCount: Int
        public var totalSeconds: Int
        /// The apps that most defined this collection, most time first.
        public var apps: [App]
    }

    /// How many apps a collection names. More than a handful stops being a description of
    /// the work and becomes a list of everything.
    public static let appLimit = 5

    /// Fold sessions into their collections, fullest first.
    ///
    /// Both orderings here are tie-broken explicitly. JavaScript's sort is stable, so the
    /// reference falls back on insertion order without saying so; Swift's is not, and two
    /// collections with equal totals would otherwise swap places between launches. The
    /// fixture covers a tie for exactly this reason — see the note in `docs/PARITY.md`.
    public static func compute(_ sessions: [ActivitySession]) -> [Collection] {
        struct Bucket {
            var sessionCount = 0
            var totalSeconds = 0
            var apps: [String: App] = [:]
            /// First-seen order, so an app's position does not depend on dictionary hashing.
            var appOrder: [String] = []
        }

        var byCategory: [SessionCategory: Bucket] = [:]
        for session in sessions where isCollectable(session.category) {
            var bucket = byCategory[session.category] ?? Bucket()
            bucket.sessionCount += 1
            bucket.totalSeconds += session.activeSeconds
            for app in session.apps {
                let key = app.bundleIdentifier ?? app.applicationName
                if var existing = bucket.apps[key] {
                    existing.seconds += app.seconds
                    bucket.apps[key] = existing
                } else {
                    bucket.apps[key] = App(
                        applicationName: app.applicationName,
                        appPath: app.appPath,
                        seconds: app.seconds
                    )
                    bucket.appOrder.append(key)
                }
            }
            byCategory[session.category] = bucket
        }

        // Built in the declared category order, so the tiebreak below is that order.
        var collections: [Collection] = []
        for definition in categories {
            guard let bucket = byCategory[definition.category], bucket.sessionCount > 0 else {
                continue
            }
            // Written out rather than chained: the same expression as one fluent chain
            // defeats the type-checker.
            var ordered: [(position: Int, app: App)] = []
            for (position, key) in bucket.appOrder.enumerated() {
                if let app = bucket.apps[key] { ordered.append((position, app)) }
            }
            ordered.sort { left, right in
                if left.app.seconds != right.app.seconds {
                    return left.app.seconds > right.app.seconds
                }
                return left.position < right.position
            }
            let apps = ordered.prefix(appLimit).map(\.app)

            collections.append(Collection(
                category: definition.category,
                label: definition.label,
                sessionCount: bucket.sessionCount,
                totalSeconds: bucket.totalSeconds,
                apps: Array(apps)
            ))
        }

        var ranked = Array(collections.enumerated())
        ranked.sort { left, right in
            if left.element.totalSeconds != right.element.totalSeconds {
                return left.element.totalSeconds > right.element.totalSeconds
            }
            return left.offset < right.offset
        }
        return ranked.map(\.element)
    }
}
