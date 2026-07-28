import Foundation

extension Report {

    /// What goes on the one page of a PDF report.
    ///
    /// **One page, on purpose, and not because this port gave up.** The reference's own PDF
    /// is capped at a single page and tells the reader to use HTML for anything longer, so
    /// a paginated PDF would not be closer to the reference — it would be a different
    /// feature. That cap is what makes this tractable at all: the three WebKit routes tried
    /// here all died on pagination (`printOperation` never returning, a file growing past
    /// 100 MB for sixty rows), and a single fixed-size page needs none of it.
    ///
    /// So this is a *summary* rather than a second copy of the report — which also answers
    /// the objection recorded in the ledger, that a PDF would be a second document to keep
    /// in step with the HTML one. It is not the same document at a different size; it is the
    /// first page's worth, with a line telling you where the rest is.
    ///
    /// The decisions live here rather than in the view because a page that silently drops
    /// rows is the one thing this must never do quietly — how many fit, how many were left,
    /// and what the reader is told about them are all things a test can hold.
    public enum PDF {

        // MARK: - The page

        /// US Letter at 72dpi, which is what `CGContext`'s default media box is and what a
        /// Mac prints on unless told otherwise. A4 would be 595×842; the difference matters
        /// only if someone prints it, and the file carries no paper size preference either
        /// way.
        public static let pageWidth: Double = 612
        public static let pageHeight: Double = 792
        public static let margin: Double = 48

        /// How tall one session row is drawn, and therefore how many fit.
        public static let rowHeight: Double = 22
        /// Everything above the rows: the title, the date range, the stat line and its rule.
        public static let headerHeight: Double = 132
        /// Left for the footer, whether or not there is an overflow note to put in it.
        public static let footerHeight: Double = 54

        /// How many session rows fit on the page.
        ///
        /// Derived rather than picked, so changing a margin cannot silently change how much
        /// of a month you get without anybody noticing.
        public static var rowsPerPage: Int {
            let usable = pageHeight - (margin * 2) - headerHeight - footerHeight
            return max(1, Int(usable / rowHeight))
        }

        // MARK: - What the page says

        public struct Page: Equatable, Sendable {
            public var title: String
            /// "14 sessions · 4h 20m active", the same two figures the HTML report leads with.
            public var summary: String
            /// The rows that fit, in the order they were given.
            public var rows: [Report.Entry]
            /// How many did not fit. Zero when the whole span is on the page.
            public var omitted: Int
            /// The line that says where the rest went, or `nil` when nothing was left off.
            public var overflowNote: String?
            /// Always present: what made this, and when.
            public var footer: String

            public init(
                title: String, summary: String, rows: [Report.Entry],
                omitted: Int, overflowNote: String?, footer: String
            ) {
                self.title = title
                self.summary = summary
                self.rows = rows
                self.omitted = omitted
                self.overflowNote = overflowNote
                self.footer = footer
            }
        }

        /// The note shown when the span is longer than a page.
        ///
        /// It names the format that *does* carry the whole thing rather than apologising.
        /// A document that says "truncated" and stops has told the reader they have the
        /// wrong file without telling them which is the right one.
        public static func overflowNote(omitted: Int) -> String {
            let sessions = omitted == 1 ? "1 more session" : "\(omitted) more sessions"
            return "\(sessions) not shown — export as HTML for the whole span."
        }

        /// Build the page from a report's entries.
        public static func page(
            label: String,
            entries: [Report.Entry],
            environment: Environment = .current,
            generatedAt: Date = Date()
        ) -> Page {
            let fitting = Array(entries.prefix(rowsPerPage))
            let omitted = max(0, entries.count - fitting.count)
            let totalSeconds = entries.reduce(0) { $0 + $1.session.activeSeconds }
            let sessions = entries.count == 1 ? "1 session" : "\(entries.count) sessions"

            return Page(
                title: label,
                // Counted over *everything*, not over what fitted. A summary that described
                // only the visible rows would quietly disagree with the same export as HTML.
                summary: "\(sessions) · \(formatDurationShort(totalSeconds)) active",
                rows: fitting,
                omitted: omitted,
                overflowNote: omitted > 0 ? overflowNote(omitted: omitted) : nil,
                footer: footer(generatedAt: generatedAt, environment: environment)
            )
        }

        public static func footer(generatedAt: Date, environment: Environment = .current) -> String {
            let formatter = DateFormatter()
            formatter.locale = environment.locale
            formatter.timeZone = environment.timeZone
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Replay · \(formatter.string(from: generatedAt))"
        }

        /// One row's three columns: what it was, when, and how long.
        public static func row(_ entry: Report.Entry, environment: Environment = .current)
            -> (title: String, when: String, duration: String)
        {
            (
                entry.session.title,
                // `timeLabel` twice rather than `formatRange`: the latter collapses a shared
                // meridiem ("9:11 – 9:42 AM"), which is right on a card and wrong in a
                // document — one of the five report divergences this port already found and
                // fixed. A PDF is a document.
                "\(timeLabel(entry.session.startedAt, environment)) – "
                    + "\(timeLabel(entry.session.endedAt, environment))",
                formatDurationShort(entry.session.activeSeconds)
            )
        }
    }
}
