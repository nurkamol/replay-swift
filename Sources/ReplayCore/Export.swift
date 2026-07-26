import Foundation
import SQLite3

/// Turning what is on screen into a file you keep.
///
/// Two different things live here, and they are not interchangeable. A **report** is for
/// reading — Markdown, CSV, JSON shaped for a person or a spreadsheet, carrying the notes
/// and tags you wrote. A **backup** is for restoring — every row, losing nothing, in the
/// format `spec/constants.json` pins. Exporting a report and calling it a backup is how
/// people lose history, so the two are named apart everywhere they appear.
public enum Report {

    /// A session together with what the user wrote on it — the unit every format serialises.
    public struct Entry: Equatable, Sendable {
        public var session: ActivitySession
        public var annotation: SessionAnnotation?

        public init(session: ActivitySession, annotation: SessionAnnotation? = nil) {
            self.session = session
            self.annotation = annotation
        }
    }

    /// How dates and times in a report are rendered.
    ///
    /// Injectable rather than always `.current` because the generated fixture is produced
    /// under a pinned locale and timezone — without a seam to match it, a check of report
    /// text would only ever pass on a machine set the same way. Real exports use the
    /// user's own settings, which is the default.
    public struct Environment: Sendable {
        public var locale: Locale
        public var timeZone: TimeZone

        public init(locale: Locale = .current, timeZone: TimeZone = .current) {
            self.locale = locale
            self.timeZone = timeZone
        }

        public static let current = Environment()
    }

    public enum Format: String, CaseIterable, Sendable {
        case markdown, csv, json

        public var label: String {
            switch self {
            case .markdown: "Markdown"
            case .csv: "CSV"
            case .json: "JSON"
            }
        }

        public var fileExtension: String {
            switch self {
            case .markdown: "md"
            case .csv: "csv"
            case .json: "json"
            }
        }
    }

    /// The default filename for an export.
    ///
    /// Named for the date it covers rather than how it was reached: a file called
    /// "Replay Today" stops being true tomorrow.
    public static func defaultName(label: String, format: Format, now: Date = Date()) -> String {
        let stamp = ISO8601DateFormatter().string(from: now).prefix(10)
        return "Replay \(label) \(stamp).\(format.fileExtension)"
    }

    public static func build(
        _ format: Format,
        label: String,
        entries: [Entry],
        now: Date = Date(),
        environment: Environment = .current
    ) -> String {
        switch format {
        case .markdown: markdown(label: label, entries: entries, now: now, environment: environment)
        case .csv: csv(entries, environment: environment)
        case .json: json(label: label, entries: entries, now: now)
        }
    }

    // ── markdown ──────────────────────────────────────────────────────────────

    /// Grouped by day, so the document reads like a journal rather than a table.
    static func markdown(
        label: String, entries: [Entry], now: Date, environment: Environment
    ) -> String {
        var lines = ["# Replay — \(label)", ""]
        let count = entries.count
        // Built from a template rather than `dateStyle = .short`, which renders a two-digit
        // year ("2/2/26") where JavaScript's `toLocaleString()` renders four ("2/2/2026").
        // The template keeps the ordering and separators the reader's locale expects while
        // pinning the fields the reference actually prints.
        let stamp = DateFormatter()
        stamp.locale = environment.locale
        stamp.timeZone = environment.timeZone
        stamp.setLocalizedDateFormatFromTemplate("yyyyMdjmmss")
        lines.append(
            "_\(count) \(count == 1 ? "session" : "sessions"), exported \(stamp.string(from: now))_"
        )
        lines.append("")

        var currentDay = ""
        for entry in entries {
            let day = longDayLabel(entry.session.startedAt, environment)
            if day != currentDay {
                currentDay = day
                lines.append("## \(day)")
                lines.append("")
            }

            let bookmark = entry.annotation?.bookmarked == true ? " ⭐" : ""
            let apps = entry.session.apps.count
            lines.append("### \(entry.session.title)\(bookmark)")
            lines.append("")
            // Both ends carry their meridiem here, unlike the collapsed range on a session
            // card: a line read out of context in a document cannot borrow the other end's.
            lines.append(
                "**\(timeLabel(entry.session.startedAt, environment)) – "
                    + "\(timeLabel(entry.session.endedAt, environment))** · "
                    + "\(formatDurationShort(entry.session.activeSeconds)) · "
                    + "\(apps) \(apps == 1 ? "app" : "apps")"
            )
            lines.append("")
            lines.append("Applications:")
            lines.append("")
            for app in entry.session.apps {
                lines.append("- \(app.applicationName) — \(formatDurationShort(app.seconds))")
            }
            lines.append("")

            if let tags = entry.annotation?.tags, !tags.isEmpty {
                lines.append("Tags: \(tags.map { "#\($0)" }.joined(separator: " "))")
                lines.append("")
            }
            let note = entry.annotation?.note.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !note.isEmpty {
                lines.append("> \(note.replacingOccurrences(of: "\n", with: "\n> "))")
                lines.append("")
            }
        }

        if entries.isEmpty {
            lines.append("_Nothing to export for this selection._")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // ── csv ───────────────────────────────────────────────────────────────────

    /// Quote when the value carries a comma, quote, or newline; double any quote inside.
    public static func csvCell(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func csv(_ entries: [Entry], environment: Environment = .current) -> String {
        let header = [
            "Date", "Start", "End", "Duration", "Category", "Title",
            "Applications", "Tags", "Bookmarked", "Note",
        ]
        var rows = [header.joined(separator: ",")]
        for entry in entries {
            let session = entry.session
            let cells = [
                longDayLabel(session.startedAt, environment),
                timeLabel(session.startedAt, environment),
                timeLabel(session.endedAt, environment),
                formatDurationShort(session.activeSeconds),
                session.category.rawValue,
                session.title,
                session.apps.map(\.applicationName).joined(separator: "; "),
                (entry.annotation?.tags ?? []).map { "#\($0)" }.joined(separator: " "),
                entry.annotation?.bookmarked == true ? "yes" : "",
                entry.annotation?.note ?? "",
            ]
            rows.append(cells.map(csvCell).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    // ── json ──────────────────────────────────────────────────────────────────

    static func json(label: String, entries: [Entry], now: Date) -> String {
        // Milliseconds, because that is what JavaScript's `toISOString()` writes and a
        // consumer of both implementations' exports should not have to handle two shapes.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func stamp(_ millis: Int64) -> String {
            iso.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
        }

        let sessions: [[String: Any]] = entries.map { entry in
            [
                "title": entry.session.title,
                "startedAt": stamp(entry.session.startedAt),
                "endedAt": stamp(entry.session.endedAt),
                "activeSeconds": entry.session.activeSeconds,
                "category": entry.session.category.rawValue,
                "apps": entry.session.apps.map { app in
                    [
                        "name": app.applicationName,
                        "seconds": app.seconds,
                        "share": (app.share * 100).rounded() / 100,
                    ] as [String: Any]
                },
                "note": entry.annotation?.note ?? "",
                "tags": entry.annotation?.tags ?? [],
                "bookmarked": entry.annotation?.bookmarked ?? false,
            ]
        }

        let payload: [String: Any] = [
            "exportedAt": iso.string(from: now),
            // The reference names an arbitrary label "day" — the named scopes it also has
            // (today, week, month, bookmarks, notes) are not built here yet.
            "scope": "day",
            "label": label,
            "sessionCount": entries.count,
            "sessions": sessions,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        ) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// "Sunday, July 26" — how a day is named inside a report.
func longDayLabel(_ millis: Int64, _ environment: Report.Environment = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = environment.locale
    formatter.timeZone = environment.timeZone
    formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
}

/// "9:11 AM" — one end of a range, where `formatRange` would collapse the meridiem.
func timeLabel(_ millis: Int64, _ environment: Report.Environment = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = environment.locale
    formatter.timeZone = environment.timeZone
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
}

extension Backup {
    /// Everything in the database, as the format both implementations read.
    ///
    /// Every row, not only the ones a view reads: a backup that quietly drops `idle` rows
    /// relabels every away stretch as "Replay wasn't running" on restore. That happened
    /// once upstream, which is why the accepted set is pinned in the spec and why this
    /// writes `rowsForBackup` rather than the timeline query.
    public static func encode(rows: [Row], appVersion: String, now: Date = Date()) -> Data {
        // Column names, not property names. The reference exports its rows straight out of
        // SQLite (`{ id, ...rest }` over a row), so a backup carries `application_name`,
        // not `applicationName` — and `Backup.read`, which has been checked against a real
        // 3,084-row Glaze export, expects exactly that. Writing camelCase here produced a
        // file this app's own reader silently read as empty.
        let events: [[String: Any]] = rows.map { row in
            var event: [String: Any] = [
                "type": row.type.rawValue,
                "application_name": row.applicationName,
                "started_at": row.startedAt,
                "duration": row.duration,
            ]
            event["bundle_identifier"] = row.bundleIdentifier ?? NSNull()
            event["ended_at"] = row.endedAt ?? NSNull()
            event["metadata"] = row.metadata ?? NSNull()
            return event
        }

        let payload: [String: Any] = [
            "format": Backup.format,
            "version": Backup.version,
            "exportedAt": ISO8601DateFormatter().string(from: now),
            "appVersion": appVersion,
            "eventCount": rows.count,
            "events": events,
        ]
        return (try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
    }
}

extension ActivityStore {
    /// Every row, in the shape a backup file stores — ids left behind, because an id
    /// belongs to whichever database issued it.
    public func rowsForBackup() throws -> [Backup.Row] {
        try query(
            """
            SELECT type, application_name, bundle_identifier, started_at, ended_at, duration, metadata
            FROM events ORDER BY started_at ASC, id ASC
            """,
            [],
            row: { statement in
                func text(_ column: Int32) -> String? {
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                }
                return Backup.Row(
                    type: EventType(rawValue: text(0) ?? "activated") ?? .activated,
                    applicationName: text(1) ?? "",
                    bundleIdentifier: text(2),
                    startedAt: sqlite3_column_int64(statement, 3),
                    endedAt: sqlite3_column_type(statement, 4) == SQLITE_NULL
                        ? nil : sqlite3_column_int64(statement, 4),
                    duration: Int(sqlite3_column_int64(statement, 5)),
                    metadata: text(6)
                )
            }
        )
    }
}
