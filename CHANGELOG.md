# Changelog

What has changed in the native port, newest first.

This is a port, so "added" usually means *reached parity with the Glaze app on*, and the
interesting entries are the ones where the two implementations disagreed. Those are called
out, because a divergence found is worth more than a feature shipped: it is the only thing
that tells you the contract is doing its job.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**This port carries its own version and states which Glaze release it is level with.** The
two are not the same number and should not be: they are different codebases at different
stages, and this one has no 2.3.1 to have shipped. So an entry reads "0.9.0 … level with
Glaze 2.3.2", and the reference's version moves without dragging this one along. (This
paragraph used to say versions *followed* Glaze's, while the entry below was numbered
independently — the document asserted both schemes at once.)

**1.0.0 is reserved for the first build that can be handed to somebody**: signed with a
Developer ID and notarised. Everything before it is a version of the source.

## 0.9.0 — 2026-07-28

Feature-complete: every route the reference has, both of its display modes, and the whole of
its Settings. Nine rather than one because nothing is missing against the reference, and not
ten because it still cannot be installed by anyone but the person who built it. Level with **Glaze 2.3.2** (`d355ba2`), verified by **931
contract checks and 61 behaviour cases**.

Dated rather than released. `scripts/make-app.sh` signs ad-hoc, which runs on the machine
that built it and nowhere else, so this is a version of the source and not something anyone
can be handed. Signing is the only thing standing between the two, and it needs a Developer
ID rather than any more code.

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
- **Collections** — every session of one kind, with its running totals and the apps that
  defined it. Derived from the category a session already has, so there is nothing to file.
- **Story Mode** — a reopened day told back in a few plain sentences, every clause filled
  from recorded activity. A day too thin to narrate honestly gets no story rather than a
  padded one.
- **A design system.** Every visual constant — radii, spacing, typography, motion, springs,
  materials, elevation, shadows, colour, icon sizes, window and sheet metrics, card chrome —
  in one file, with every view reading from it. `node tools/design-audit.mjs` fails the
  build if a view hard-codes a value, so the system cannot rot one plausible number at a
  time. The motion tokens are the reference's own, extracted into the generated contract and
  checked by the parity suite.
- **CI** running the parity suite on every push, in four timezones, plus the design audit.

### Added — the rest of the surfaces

- **Projects** — the app combinations that keep coming back, named descriptively and
  renameable, with a page each.
- **Canvas** — the whole history as a field you can fly through, and **Replay Story**, a
  camera tour that narrates a memory by moving rather than by writing.
- **Story, Chapters, Autobiography, Museum and My Story** — the long view: your history
  divided into eras, told back to you a month at a time, and the best of it curated.
- **Relationships and an application's own page** — what two apps do together, and what one
  app has done across the record.
- **This Week**, **Replay Day** (scrub a day back at 1×, 2× or 5×), and a **screensaver**.
- **Ambient mode** — a distraction-free full-screen clock for a second monitor, the second
  of the reference's two display modes.
- **A welcome screen**, a **Dock badge** showing whole active hours, and a **command
  palette** that reaches every surface, application and project by name.
- **One catalogue for keyboard shortcuts**, feeding the View menu, the Settings table and
  the sidebar hints, with `tools/shortcut-audit.mjs` checking all three agree.
- **A Display pane in Settings** for the screensaver and ambient mode — the reference's own
  grouping for the pair.

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

### Fixed — divergences the audits found

Seven surface audits, each comparing a view against its reference beside it. Every one found
something; these are the ones worth naming.

- **The memory heatmap shaded days against the busiest day in view**, not against fixed
  amounts of time — so a quiet month and a heavy one looked identical, and a square's
  darkness meant nothing you could compare across a year.
- **Today was missing from its own year.** The reference builds the grid forwards from 370
  days ago; 53 weeks is 371 days, so it ends between today and six days before it.
- **The narrative surfaces were entirely paraphrase** — every subtitle and empty state on
  Story, Chapters and Autobiography, with both footnotes missing outright.
- **My Story was missing a section** the reference has, found by diffing section labels.
- **The screensaver's close button and exit hint had never been visible**, pushed off-screen
  by a `ZStack` sizing to its drifting column.
- **The Timeline built every row before showing one**, which read as a slow query and was
  not: the data is 22ms.

### Known gaps

- **No PDF export.** Three WebKit routes tried and dead. Reviving it means leaving WebKit
  and drawing the report into a `CGContext` by hand. See `docs/PARITY.md`.
- **The app is not signed for distribution.**
- **The suite covers the core, not the interface.** Every UI behaviour above was verified by
  running the app against real data, which is weaker than a fixture and is recorded as such
  in the ledger. Three bugs this release were invisible to every automated check and were
  found only by looking: a Settings toggle bound to the wrong `Bool`, chrome laid out
  off-screen, and a test suite leaking a `UserDefaults` domain per fixture. That is the
  argument for a UI test target, which is an open decision in `docs/BACKLOG.md`.
