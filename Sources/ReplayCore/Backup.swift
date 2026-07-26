import Foundation

/// Reading the Glaze app's backup files.
///
/// The two apps have separate containers and will never share a live database, so this is
/// the migration path: a user exports from Glaze (Settings ▸ Data ▸ Full backup ▸ Export)
/// and imports here. Plain readable JSON rather than a copy of the SQLite file, on
/// purpose — a backup of someone's own activity should be something they can open and
/// check before trusting it anywhere.
///
/// The format is pinned in `spec/constants.json` as `replay.activity` version 1.
public enum Backup {

    public static let format = "replay.activity"
    public static let version = 1

    /// The row types an import accepts.
    ///
    /// `idle` matters and is easy to miss: an export writes *every* row, away stretches
    /// included. Dropping them is not a partial restore but a change of meaning — a gap
    /// with no `idle` row behind it is shown as "Replay wasn't running" rather than
    /// "away". The Glaze app shipped without it and was fixed; `spec/constants.json`
    /// records the accepted set so neither implementation can lose one silently again.
    public static let acceptedTypes: Set<EventType> = [.activated, .launched, .terminated, .idle]

    /// A row as it appears in a backup file — everything except the local id, which is not
    /// carried over because ids belong to whichever database they were written in.
    public struct Row: Equatable, Sendable {
        public var type: EventType
        public var applicationName: String
        public var bundleIdentifier: String?
        public var startedAt: Int64
        public var endedAt: Int64?
        public var duration: Int
        public var metadata: String?
    }

    public struct ReadResult: Sendable {
        public var rows: [Row]
        /// Rows rejected as malformed. A partly-corrupt file restores what survives.
        public var skipped: Int
        public var exportedAt: String?
        public var appVersion: String?
        /// The count the file claims, for comparison against what was actually read.
        public var declaredCount: Int?
    }

    public enum ReadError: Error, CustomStringConvertible {
        case notJSON
        case wrongFormat(String?)
        case noEvents

        public var description: String {
            switch self {
            case .notJSON:
                "that file isn't a Replay backup — it couldn't be read as JSON"
            case .wrongFormat(let found):
                "that isn't a Replay backup (its format is \(found ?? "missing"), expected \(Backup.format))"
            case .noEvents:
                "that backup contains no events"
            }
        }
    }

    /// Pull valid rows out of a backup, dropping anything malformed.
    ///
    /// An import runs against a file the user may have edited by hand, so every field is
    /// checked before it reaches SQL. Deliberately lenient about individual rows and
    /// strict about the envelope: a wrong `format` means this is not a Replay backup and
    /// nothing should be imported, but one bad row should not lose the other 40,000.
    ///
    /// Kept behaviourally identical to `readBackupEvents` in the Glaze app, including
    /// rounding non-integer timestamps and clamping a negative duration to zero.
    public static func read(_ data: Data) throws -> ReadResult {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else { throw ReadError.notJSON }

        guard let foundFormat = root["format"] as? String, foundFormat == format else {
            throw ReadError.wrongFormat(root["format"] as? String)
        }
        guard let events = root["events"] as? [Any] else { throw ReadError.noEvents }

        var rows: [Row] = []
        var skipped = 0

        for raw in events {
            guard let event = raw as? [String: Any],
                  let typeName = event["type"] as? String,
                  let type = EventType(rawValue: typeName),
                  acceptedTypes.contains(type),
                  let name = event["application_name"] as? String, !name.isEmpty,
                  let startedAt = (event["started_at"] as? NSNumber)?.doubleValue,
                  startedAt.isFinite
            else {
                skipped += 1
                continue
            }

            let endedAt = (event["ended_at"] as? NSNumber)?.doubleValue
            let duration = (event["duration"] as? NSNumber)?.doubleValue ?? 0

            rows.append(Row(
                type: type,
                applicationName: name,
                bundleIdentifier: event["bundle_identifier"] as? String,
                startedAt: Int64(startedAt.rounded()),
                endedAt: endedAt.flatMap { $0.isFinite ? Int64($0.rounded()) : nil },
                duration: max(0, Int(duration.isFinite ? duration.rounded() : 0)),
                metadata: event["metadata"] as? String
            ))
        }

        return ReadResult(
            rows: rows,
            skipped: skipped,
            exportedAt: root["exportedAt"] as? String,
            appVersion: root["appVersion"] as? String,
            declaredCount: (root["eventCount"] as? NSNumber)?.intValue
        )
    }

    public static func read(contentsOf url: URL) throws -> ReadResult {
        try read(Data(contentsOf: url))
    }
}

extension ActivityStore {

    /// Merge backup rows into the database, skipping any already present.
    ///
    /// **Merges, never overwrites.** Identity is `(type, started_at, bundle_identifier)` —
    /// the tracker cannot open two sessions for the same app at the same instant, so that
    /// triple is stable across an export and back, which makes importing the same file
    /// twice a no-op. Ids are deliberately not carried over; they are local to whichever
    /// database wrote them.
    @discardableResult
    public func restore(rows: [Backup.Row]) throws -> (imported: Int, skipped: Int) {
        guard !rows.isEmpty else { return (0, 0) }
        var imported = 0
        var skipped = 0

        try transaction {
            for row in rows {
                let existing = try queryFirst(
                    """
                    SELECT 1 FROM events
                    WHERE type = ? AND started_at = ?
                      AND IFNULL(bundle_identifier, '') = IFNULL(?, '')
                    LIMIT 1
                    """,
                    [
                        .text(row.type.rawValue), .int(row.startedAt),
                        row.bundleIdentifier.map(Value.text) ?? .null,
                    ]
                )
                if existing {
                    skipped += 1
                    continue
                }

                try execute(
                    """
                    INSERT INTO events
                      (type, application_name, bundle_identifier, started_at, ended_at, duration, metadata)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(row.type.rawValue),
                        .text(row.applicationName),
                        row.bundleIdentifier.map(Value.text) ?? .null,
                        .int(row.startedAt),
                        row.endedAt.map(Value.int) ?? .null,
                        .int(Int64(row.duration)),
                        row.metadata.map(Value.text) ?? .null,
                    ]
                )
                imported += 1
            }
        }
        return (imported, skipped)
    }

    /// Import a backup and settle everything that follows from it.
    ///
    /// Imported rows can land on past days, changing headlines already stored for them, so
    /// the summaries are rebuilt — bounded to the range the rows now cover, which is what
    /// keeps a restore from erasing days whose activity was pruned long ago.
    @discardableResult
    public func importBackup(from url: URL, now: Int64) throws -> (imported: Int, skipped: Int, malformed: Int) {
        let result = try Backup.read(contentsOf: url)
        let restored = try restore(rows: result.rows)
        if restored.imported > 0 { try rebuildSummaries(now: now) }
        return (restored.imported, restored.skipped, result.skipped)
    }
}
