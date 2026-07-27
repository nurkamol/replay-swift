import Foundation
import SQLite3

/// A line you write for your future self.
///
/// At the end of a day you can jot what you would like to remember about it — nothing more
/// than a note to the person who opens this six months from now. Keyed by the day rather
/// than by a session, because it is about the day as a whole.
public struct Reflection: Equatable, Sendable {
    public var dayStart: Int64
    public var text: String
    /// Zero for a day with nothing written.
    public var updatedAt: Int64

    public init(dayStart: Int64, text: String = "", updatedAt: Int64 = 0) {
        self.dayStart = dayStart
        self.text = text
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

extension ActivityStore {
    /// What was written for a day, or an empty reflection when nothing was.
    public func reflection(dayStart: Int64) throws -> Reflection {
        let rows = try query(
            "SELECT day_start, text, updated_at FROM reflections WHERE day_start = ?",
            [.int(dayStart)],
            row: reflection(from:)
        )
        return rows.first ?? Reflection(dayStart: dayStart)
    }

    /// Reflections across a window, oldest first.
    public func reflections(from: Int64, to: Int64) throws -> [Reflection] {
        try query(
            """
            SELECT day_start, text, updated_at FROM reflections
            WHERE day_start >= ? AND day_start < ?
            ORDER BY day_start ASC
            """,
            [.int(from), .int(to)],
            row: reflection(from:)
        )
    }

    /// Write a day's reflection, deleting the row when it is cleared back to empty.
    ///
    /// The same rule annotations follow: a blank row is not the same as nothing written,
    /// and keeping one would make "did I write about this day?" a question with two
    /// different answers.
    @discardableResult
    public func setReflection(dayStart: Int64, text: String, now: Int64) throws -> Reflection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            _ = try run("DELETE FROM reflections WHERE day_start = ?", [.int(dayStart)])
            return Reflection(dayStart: dayStart)
        }

        // `text` is stored as written, not trimmed: the trim decides whether there is
        // anything here, it does not edit what someone wrote.
        _ = try run(
            """
            INSERT INTO reflections (day_start, text, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(day_start) DO UPDATE SET
              text = excluded.text,
              updated_at = excluded.updated_at
            """,
            [.int(dayStart), .text(text), .int(now)]
        )
        return Reflection(dayStart: dayStart, text: text, updatedAt: now)
    }

    private func reflection(from statement: OpaquePointer) -> Reflection {
        Reflection(
            dayStart: sqlite3_column_int64(statement, 0),
            text: sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "",
            updatedAt: sqlite3_column_int64(statement, 2)
        )
    }
}

/// What Today asks you, which changes with the hour.
///
/// Two sentences rather than one, and the difference is the whole point: before six in the
/// evening the day is still happening and the question is about it in the abstract; from six
/// the day is ending, and the prompt says so. This port had a single prompt, and its wording
/// was not either of the reference's — "What do you want to remember about today?" against
/// "What would you like to remember about today?". Words are the product (SPEC §8), so both
/// of these come from the contract and the suite compares them character for character.
public enum ReflectionPrompt {
    /// The hour the wording turns, on a 24-hour clock.
    public static let eveningFromHour = 18
    public static let daytime = "What would you like to remember about today?"
    public static let evening = "Before the day ends — what would you like to remember about it?"

    /// The prompt for a given local hour.
    public static func forHour(_ hour: Int) -> String {
        hour >= eveningFromHour ? evening : daytime
    }
}
