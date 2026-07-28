import Foundation
import ReplayCore

/// `replay` — the record, from a shell.
///
/// The one thing on the backlog that needs no Developer ID, which is why it exists: a signed
/// build gates the widget and gates App Intents being *discovered*, and this is the same
/// data with none of that in the way. It is also the second consumer of `ReplayCore` from
/// outside the app, after the intents, and the pair of them are what turns "the core is
/// reusable" from a claim into a fact.
///
/// **Read-only, with one exception that writes only where you point it.** `export` produces
/// a file at a path you gave; nothing here can change or delete the record. A CLI ends up in
/// scripts and cron jobs, and a flag that deletes a day is a bad thing to have within reach
/// of a typo — the same reasoning as the intents, and for stronger reasons.
///
/// No argument-parsing library, because this package has no dependencies and is not about to
/// gain one for four subcommands (CLAUDE.md). The parsing below is deliberately dull.

// ── the shape of the thing ────────────────────────────────────────────────────

let programName = "replay"

/// Exit codes a script can branch on. `1` is "you asked wrongly", `2` is "I could not
/// answer" — the distinction matters in a pipeline, where the first is a bug in the script
/// and the second is a fact about the data.
enum Exit: Int32 {
    case ok = 0, usage = 1, failed = 2
}

/// Every function here is `@MainActor`: top-level code in a `main.swift` is isolated to it
/// under Swift 6, and these all read the globals declared above. Stated rather than worked
/// around, because the alternative is threading an argument list through nine call sites to
/// avoid a keyword.
@MainActor
func fail(_ message: String, _ code: Exit = .failed) -> Never {
    FileHandle.standardError.write(Data("\(programName): \(message)\n".utf8))
    exit(code.rawValue)
}

@MainActor
func out(_ line: String) {
    FileHandle.standardOutput.write(Data("\(line)\n".utf8))
}

// ── arguments ─────────────────────────────────────────────────────────────────

var arguments = Array(CommandLine.arguments.dropFirst())

/// Pulls `--name value` out of the argument list and returns it, leaving the rest.
@MainActor
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: "--\(name)") else { return nil }
    guard index + 1 < arguments.count else { fail("--\(name) needs a value", .usage) }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

/// Pulls a `--flag` out and says whether it was there.
@MainActor
func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: "--\(name)") else { return false }
    arguments.remove(at: index)
    return true
}

let wantsJSON = flag("json")

// ── the store ─────────────────────────────────────────────────────────────────

/// Opened lazily, so `replay help` and `replay --version` work with no database at all —
/// including on a machine where the app has never run.
@MainActor
func openStore() -> ActivityStore {
    let path = option("database") ?? defaultDatabaseURL().path
    guard FileManager.default.fileExists(atPath: path) else {
        fail("no record at \(path) — has Replay ever run on this Mac?")
    }
    let store = ActivityStore(path: path)
    do { try store.open() } catch { fail("could not open \(path): \(error)") }
    return store
}

@MainActor
func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

/// Accepts what a person would type. `today`, `yesterday`, or `YYYY-MM-DD`.
///
/// Not `DateFormatter`'s lenient parsing, which would take "3" and give you the third of
/// this month without saying so. A date this tool cannot read is an error, because a script
/// that silently reports the wrong day is worse than one that stops.
@MainActor
func parseDay(_ text: String) -> Int64 {
    let today = startOfLocalDay(now())
    switch text.lowercased() {
    case "today": return today
    case "yesterday": return startOfLocalDay(today - dayMillis)
    default: break
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    guard let date = formatter.date(from: text) else {
        fail("cannot read \"\(text)\" as a date — use today, yesterday, or YYYY-MM-DD", .usage)
    }
    return startOfLocalDay(Int64(date.timeIntervalSince1970 * 1000))
}

/// A day as `YYYY-MM-DD`, in the timezone the day was lived in.
///
/// `ISO8601DateFormatter` formats in UTC unless told otherwise, so a local midnight east of
/// Greenwich comes out as the *previous* date — the first `replay today --json` on this
/// machine reported 2026-07-27 while the sentence beside it said "Today". Harmless to read
/// and poison in a script, which is the whole audience for `--json`.
@MainActor
func isoDay(_ dayStart: Int64) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = .current
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: Date(timeIntervalSince1970: Double(dayStart) / 1000))
}

/// One place that turns a value into either a line of text or a line of JSON, so every
/// command answers the same way and `--json` cannot be supported by some and not others.
@MainActor
func emit(_ sentence: String, _ fields: [String: Any]) {
    guard wantsJSON else { return out(sentence) }
    var payload = fields
    payload["sentence"] = sentence
    guard let data = try? JSONSerialization.data(
        withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
    ) else { fail("could not encode the answer as JSON") }
    out(String(decoding: data, as: UTF8.self))
}

// ── commands ──────────────────────────────────────────────────────────────────

@MainActor
func showDay(_ dayStart: Int64) {
    let store = openStore()
    let moment = now()
    guard let day = try? Answers.day(dayStart, store: store, now: moment) else {
        fail("could not read that day")
    }
    emit(day.sentence, [
        "day": isoDay(day.dayStart),
        "activeSeconds": day.activeSeconds,
        "sessions": day.sessionCount,
        "applications": day.appsUsed,
        "topApplication": day.topApp as Any,
    ])
}

@MainActor
func showApplication(_ name: String, on dayStart: Int64) {
    let store = openStore()
    guard let found = try? Answers.application(
        named: name, on: dayStart, store: store, now: now()
    ) else {
        // Nothing recorded is an answer, not a failure — a script asking "how long in Xcode"
        // on a day you never opened it should get zero and carry on.
        emit("No record of \(name) on \(fullDayLabel(dayStart)).", [
            "application": name, "seconds": 0, "found": false, "day": isoDay(dayStart),
        ])
        return
    }
    emit("\(formatDurationShort(found.seconds)) in \(found.name) on \(fullDayLabel(dayStart)).", [
        "application": found.name, "seconds": found.seconds, "found": true,
        "day": isoDay(dayStart),
    ])
}

@MainActor
func exportReport() {
    let formatName = option("format") ?? "markdown"
    guard let format = Report.Format(rawValue: formatName) else {
        fail("unknown format \"\(formatName)\" — one of "
            + Report.Format.allCases.map(\.rawValue).joined(separator: ", "), .usage)
    }
    let scopeName = option("scope") ?? "today"
    guard let scope = Report.Scope(rawValue: scopeName) else {
        fail("unknown scope \"\(scopeName)\" — one of "
            + Report.Scope.allCases.map(\.rawValue).joined(separator: ", "), .usage)
    }

    let store = openStore()
    let moment = now()
    let todayStart = startOfLocalDay(moment)
    let from = todayStart - Int64(Report.fetchDays - 1) * dayMillis
    guard let events = try? store.sessions(from: from, to: todayStart + dayMillis) else {
        fail("could not read the record")
    }
    let sessions = Report.sessions(in: events.filter { $0.startedAt >= from }, now: moment)
    let notes = ((try? store.annotations(from: from, to: todayStart + dayMillis)) ?? [])
    let byStart = Dictionary(notes.map { ($0.sessionStart, $0) }, uniquingKeysWith: { a, _ in a })
    let entries = Report.select(
        scope, sessions: sessions, annotations: byStart, todayStart: todayStart
    )
    let text = Report.build(format, label: scope.label, entries: entries, now: Date())

    // To a file if asked, otherwise to standard output — so `replay export | pbcopy` works
    // and the tool composes with everything else on the machine.
    if let path = option("output") {
        do { try text.write(toFile: path, atomically: true, encoding: .utf8) }
        catch { fail("could not write \(path): \(error)") }
        FileHandle.standardError.write(
            Data("\(programName): wrote \(entries.count) sessions to \(path)\n".utf8)
        )
    } else {
        out(text)
    }
}

@MainActor
func usage() {
    out("""
    \(programName) — your own record, from a shell. Reads only; nothing here changes it.

    USAGE
      \(programName) today                     how long today has held, and what most of it was
      \(programName) day <when>                the same for a day: today, yesterday, or YYYY-MM-DD
      \(programName) app <name> [--on <when>]  how long one application had, default today
      \(programName) export [options]          a report, to standard output or a file
      \(programName) help                      this
      \(programName) --version                 the version this was built from

    EXPORT
      --format <\(Report.Format.allCases.map(\.rawValue).joined(separator: "|"))>
      --scope  <\(Report.Scope.allCases.map(\.rawValue).joined(separator: "|"))>
      --output <path>                          omit to write to standard output

    EVERYWHERE
      --json                                   answer as JSON instead of a sentence
      --database <path>                        read a different database

    EXIT
      0 answered · 1 asked wrongly · 2 could not answer
    """)
}

// ── dispatch ──────────────────────────────────────────────────────────────────

if flag("version") { out("\(programName) \(Replay.version)"); exit(0) }

guard let command = arguments.first else { usage(); exit(Exit.usage.rawValue) }
arguments.removeFirst()

switch command {
case "today":
    showDay(startOfLocalDay(now()))

case "day":
    guard let when = arguments.first else {
        fail("day needs a date — today, yesterday, or YYYY-MM-DD", .usage)
    }
    showDay(parseDay(when))

case "app":
    guard let name = arguments.first else { fail("app needs a name", .usage) }
    arguments.removeFirst()
    showApplication(name, on: parseDay(option("on") ?? "today"))

case "export":
    exportReport()

case "help", "--help", "-h":
    usage()

default:
    fail("unknown command \"\(command)\" — try `\(programName) help`", .usage)
}
