# Changelog

What has changed in the native port, newest first.

This is a port, so "added" usually means *reached parity with the Glaze app on*, and the
interesting entries are the ones where the two implementations disagreed. Those are called
out, because a divergence found is worth more than a feature shipped: it is the only thing
that tells you the contract is doing its job.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions
follow the Glaze app's, so "level with 2.3.2" means this port matches that release.

## Unreleased — 0.1.0

The first version that is an application rather than a library with a placeholder `main`.
Level with **Glaze 2.3.2** (`d355ba2`), verified by **418 checks**.

### Added

- **Recording.** A menu bar item that records all day, with the current app, today's total,
  pause/resume, and the surfaces behind it. No Accessibility, Automation, or Screen
  Recording permission — that property is the product.
- **Today.** The day's headline, its top app, an optional focus goal, a reflection, and the
  sessions and gaps that made it up.
- **Timeline.** Recent days newest-first with day-part dividers, a range picker, and a
  per-day menu to open, export, or delete.
- **A past day, reopened**, filtered to the runs that *began* that day.
- **Notes, tags and bookmarks** on a session, with marks visible on a collapsed card.
- **Reflections** — a line you write for a day, on Today and on any day you reopen.
- **Search** by session name, note, tag or application, plus a few phrases ("morning",
  "longest", "bookmarked") that go to a slice rather than matching literally.
- **Settings** — General, Privacy, Data, Guide, About — with excluded applications,
  retention, database compaction, and menu-bar-only mode.
- **Export.** A day, a session, or a scope (this week, this month, bookmarks, notes) as
  Markdown, CSV, JSON or HTML; and a full backup in the format both implementations read.
- **Backup import**, verified against a real 3,084-row export from the Glaze app.
- **An application menu**, without which ⌘, ⌘W and — the one that bit — ⌘C and ⌘V in a note
  field did nothing.
- **Memories** — what you were doing on this date a week, a month, or up to two years ago,
  read from the durable daily headlines so a memory outlives the day's raw events.
- **CI** running the parity suite on every push, in four timezones.

### Fixed — differences found between the two implementations

These are the ones worth reading. Each was invisible until something checked it.

- **A backup this app wrote, this app could not read.** The writer named its JSON keys after
  Swift properties (`applicationName`) where a backup carries SQLite column names
  (`application_name`). Every row failed the reader's guard and was counted as skipped, so a
  file full of malformed rows parsed as a valid, empty backup. Caught by a round-trip check,
  not by reading the output.
- **The parity suite only passed in one timezone.** Session titles are named after the local
  day part, so the derivation fixtures had quietly recorded the machine that generated them.
  The suite would have failed the first time it ran anywhere else.
- **Five divergences in the report formats**, none of which reading the reference had found:
  an abbreviated timestamp where the reference uses `toLocaleString()`; a two-digit year
  where JavaScript renders four; a time range that collapsed its shared meridiem, which is
  right on a card and wrong in a document; a missing `scope` field in the JSON; and an
  `exportedAt` without the milliseconds `toISOString()` writes.
- **Two application-matching predicates collapsed into one.** The reference keeps an exact
  match (for an app you chose) apart from a substring match (for discovering one by typing).
  Merging them is invisible until an app's name is a prefix of another's.
- **Today's figures went stale** while the window sat open, because the day was only
  re-derived when the tracker recorded a switch. It now re-derives on the reference's 30s
  interval.
- **Away time was being dropped on import** by the Glaze app itself, which omitted `idle`
  from its accepted row types — relabelling every away stretch as "Replay wasn't running".
  Fixed upstream; the accepted set is now pinned in the generated contract so neither
  implementation can lose one silently again.
- **Calendar arithmetic clamped where the reference overflows.** 31 March minus one month is
  3 March in JavaScript and 28 February with Swift's `date(byAdding:)`. A memory labelled
  "one month ago" has to mean the same day in both apps.
- **The About panel claimed Apache 2.0** after the port was relicensed under MIT.

### Fixed — bugs in this port

- **An HTML report weighed 89 MB.** `NSImage.size` sets the point size and nothing about the
  pixels, so every icon tile carried the 1024px master from the iconset. Redrawn into a
  64×64 bitmap: 482 KB, identical on screen.
- **The same icons were inlined once per use** — fifty-odd icons appearing three hundred
  times in one document. Defined once as CSS classes and referenced by name.

### Known gaps

- **No PDF export.** Two attempts failed in WebKit; the reference's own PDF is a single page
  and points readers at HTML for anything longer. See `docs/PARITY.md` for what to try next.
- **The app is not signed for distribution.** `scripts/make-app.sh` signs ad-hoc, which runs
  on the machine that built it and nowhere else.
- **Most of the memory subsystems are not started** — Collections, Story Mode, Canvas.
- **The suite covers the core, not the interface.** Every UI behaviour above was verified by
  running the app against real data, which is weaker than a fixture and is recorded as such
  in the ledger.
