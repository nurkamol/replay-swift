import Foundation
import SQLite3

/// What the user added to a session: a note, a bookmark, tags.
///
/// Sessions are derived on the fly and have no row of their own, so an annotation is keyed
/// by the session's start timestamp — the one piece of a session's identity that is stable
/// for a past day, because the first event of a run does not move once the day is over.
public struct SessionAnnotation: Equatable, Sendable {
    /// The session's `startedAt` in epoch milliseconds — its stable identity.
    public var sessionStart: Int64
    public var note: String
    public var bookmarked: Bool
    public var tags: [String]
    /// Zero for a session with nothing stored.
    public var updatedAt: Int64

    public init(
        sessionStart: Int64,
        note: String = "",
        bookmarked: Bool = false,
        tags: [String] = [],
        updatedAt: Int64 = 0
    ) {
        self.sessionStart = sessionStart
        self.note = note
        self.bookmarked = bookmarked
        self.tags = tags
        self.updatedAt = updatedAt
    }

    /// Nothing worth a row: no note, not bookmarked, no tags.
    public var isEmpty: Bool {
        note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !bookmarked && tags.isEmpty
    }
}

/// Normalise tags the way the reference does: trim, drop leading `#`, lowercase, cap the
/// length, drop blanks, dedupe keeping first-seen order, then cap the count.
///
/// This is behaviour rather than decoration — "#Deep Work" and "deep work" have to land on
/// one tag, or a filter silently splits in two. The caps come from `spec/constants.json`.
public func normalizeTags(_ raw: [String]) -> [String] {
    var seen = Set<String>()
    var clean: [String] = []
    for candidate in raw {
        var tag = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        while tag.hasPrefix("#") { tag.removeFirst() }
        tag = String(tag.lowercased().prefix(Rules.maxTagLength))
        guard !tag.isEmpty, !seen.contains(tag) else { continue }
        seen.insert(tag)
        clean.append(tag)
    }
    return Array(clean.prefix(Rules.maxTags))
}

extension ActivityStore {
    /// Annotations for the sessions that began within `[from, to)`, oldest first.
    ///
    /// A whole range in one query: a day of session cards should cost one read, not one
    /// per card.
    public func annotations(from: Int64, to: Int64) throws -> [SessionAnnotation] {
        try query(
            """
            SELECT session_start, note, bookmarked, tags, updated_at FROM annotations
            WHERE session_start >= ? AND session_start < ?
            ORDER BY session_start ASC
            """,
            [.int(from), .int(to)],
            row: annotation(from:)
        )
    }

    /// Every bookmarked session, newest first.
    public func bookmarkedAnnotations() throws -> [SessionAnnotation] {
        try query(
            """
            SELECT session_start, note, bookmarked, tags, updated_at FROM annotations
            WHERE bookmarked = 1 ORDER BY session_start DESC
            """,
            [],
            row: annotation(from:)
        )
    }

    /// One session's annotation, or an empty one when it has none stored.
    public func annotation(sessionStart: Int64) throws -> SessionAnnotation {
        let rows = try query(
            """
            SELECT session_start, note, bookmarked, tags, updated_at FROM annotations
            WHERE session_start = ?
            """,
            [.int(sessionStart)],
            row: annotation(from:)
        )
        return rows.first ?? SessionAnnotation(sessionStart: sessionStart)
    }

    /// Every distinct tag in use, sorted — for suggesting what already exists.
    public func allTags() throws -> [String] {
        let raw = try query(
            "SELECT tags FROM annotations WHERE tags IS NOT NULL", [],
            row: { statement in
                sqlite3_column_text(statement, 0).map { String(cString: $0) }
            }
        )
        var seen = Set<String>()
        for value in raw { for tag in decodeTags(value) { seen.insert(tag) } }
        return seen.sorted()
    }

    public func setNote(sessionStart: Int64, note: String, now: Int64) throws -> SessionAnnotation {
        var next = try annotation(sessionStart: sessionStart)
        next.note = note
        return try write(next, now: now)
    }

    public func setBookmarked(
        sessionStart: Int64, bookmarked: Bool, now: Int64
    ) throws -> SessionAnnotation {
        var next = try annotation(sessionStart: sessionStart)
        next.bookmarked = bookmarked
        return try write(next, now: now)
    }

    public func setTags(sessionStart: Int64, tags: [String], now: Int64) throws -> SessionAnnotation {
        var next = try annotation(sessionStart: sessionStart)
        next.tags = normalizeTags(tags)
        return try write(next, now: now)
    }

    /// Drop the annotations on sessions that began within `[from, to)` — for a deleted day.
    ///
    /// Notes and bookmarks are memories of the sessions being erased, so they go with them
    /// rather than surviving as orphans pointing at sessions that no longer exist.
    @discardableResult
    public func deleteAnnotations(from: Int64, to: Int64) throws -> Int {
        try run(
            "DELETE FROM annotations WHERE session_start >= ? AND session_start < ?",
            [.int(from), .int(to)]
        )
    }

    /// Write a merged annotation, deleting the row when nothing is left on it.
    ///
    /// An annotation cleared back to empty leaves no blank row behind, so "has an
    /// annotation" and "has something to say" stay the same question.
    private func write(_ annotation: SessionAnnotation, now: Int64) throws -> SessionAnnotation {
        var next = annotation
        next.updatedAt = now

        if next.isEmpty {
            _ = try run(
                "DELETE FROM annotations WHERE session_start = ?", [.int(next.sessionStart)]
            )
            next.updatedAt = 0
            return next
        }

        let trimmed = next.note.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try run(
            """
            INSERT INTO annotations (session_start, note, bookmarked, tags, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(session_start) DO UPDATE SET
              note = excluded.note,
              bookmarked = excluded.bookmarked,
              tags = excluded.tags,
              updated_at = excluded.updated_at
            """,
            [
                .int(next.sessionStart),
                trimmed.isEmpty ? .null : .text(next.note),
                .int(next.bookmarked ? 1 : 0),
                next.tags.isEmpty ? .null : .text(encodeTags(next.tags)),
                .int(next.updatedAt),
            ]
        )
        return next
    }

    private func annotation(from statement: OpaquePointer) -> SessionAnnotation {
        SessionAnnotation(
            sessionStart: sqlite3_column_int64(statement, 0),
            note: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "",
            bookmarked: sqlite3_column_int64(statement, 2) != 0,
            tags: decodeTags(sqlite3_column_text(statement, 3).map { String(cString: $0) }),
            updatedAt: sqlite3_column_int64(statement, 4)
        )
    }
}

/// Tags are stored as a JSON array of strings, as the reference writes them — the two
/// implementations read each other's database, so the encoding is part of the contract.
func encodeTags(_ tags: [String]) -> String {
    (try? String(data: JSONEncoder().encode(tags), encoding: .utf8)) as? String ?? "[]"
}

/// Anything unreadable decodes to no tags rather than throwing: a corrupt cell should cost
/// its tags, not the session card that shows them.
func decodeTags(_ raw: String?) -> [String] {
    guard let raw, let data = raw.data(using: .utf8) else { return [] }
    return (try? JSONDecoder().decode([String].self, from: data)) ?? []
}
