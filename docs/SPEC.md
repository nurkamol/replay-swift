# What Replay does

The behaviour a port has to reproduce, in the order it matters. Values live in
`spec/constants.json` and are checked automatically; this file is for the rules that a
generated file cannot express — the ones a port gets wrong at the design level, where
every constant is right and the app is still subtly untrue.

Read alongside [SYNC.md](SYNC.md), which explains why some of this is generated and
some of it is prose.

---

## 1. What is recorded

Replay records **which application was frontmost, and when**. Nothing else. No
screenshots, no video, no window titles, no keystrokes, no content. One SQLite file in
the app's own container, and **nothing recorded is ever transmitted anywhere, under any
setting.**

There is one network request in the whole app, added by this port and off by default: an
update check against GitHub's public releases API (`Updates` / `UpdateModel`). It sends no
body, no identifier and no query, downloads nothing, and reads only a public version
number. The invariant it must never break is the one above — *no recorded data leaves the
machine* — not the weaker "no sockets", which was true until it wasn't and which no
generated check ever enforced. The reference has no equivalent, because it updates through
the Glaze Store; see `Guide.ownEntries` for how that difference is stated to the user
without editing the reference's own words.

**The record is written outside the container in exactly one case, and only when asked
for.** Since 0.9.4 Replay can write its own full backup on a schedule into a folder the
user chooses (`AutoBackup` / `AutoBackupModel`) — the same JSON the export panel has always
produced, in a place they named, on a disk they own. It is off until both a folder and a
schedule are set, it deletes only files matching its own naming pattern, and it is still
local: a copy of the record moving from one folder to another on the same Mac is not the
invariant above being bent. Written down here because "one SQLite file in the app's own
container" stopped being the whole sentence the moment this shipped, and a spec that quietly
stays a version behind is how a claim becomes untrue.

This is not a modesty claim, it is the product. It is why the app needs **no
permissions at all** — no Accessibility, no Automation, no Screen Recording — and that
is the property to defend above any feature. Concretely:

- Frontmost app: `NSWorkspace.didActivateApplicationNotification`, a public signal any
  app may observe.
- Presence: `CGEventSource.secondsSinceLastEventType` — a single integer, "seconds since
  the last input". Replay learns *that* input happened, never what it was.

The scale that follows from this: a heavy day is **~1,100 rows ≈ 175 KB**, so a year of
hard use is 50–60 MB. Measured on real data, not estimated.

## 2. The data model

Four tables, in `spec/schema.sql`. The shapes matter less than these three facts:

**Timestamps are epoch milliseconds.** Not seconds, not `Date`. The database is shared
ground between two implementations and all the arithmetic in derivation is defined in
milliseconds. Convert at the edges of the UI, never in the store.

**`events` holds two different kinds of thing.** `activated` rows are focus; `idle` rows
are measured absence, written as a stretch with `application_name = 'Away'`. Storing
absence explicitly is what lets a timeline *say* "away" instead of inferring it from a
suspicious gap. `launched`/`terminated` rows are recorded but no view depends on them.

**`daily_summaries` outlives raw activity.** This is the subtlest thing in the schema.
When the retention window prunes a day's events, its headline row is *all that remains
of that day* — it is what Memories, streaks, and long-range history read. Two rules
follow, and both have already been violated once:

- A rollup must never write a headline for a day with no rows behind it (otherwise a
  deleted day returns as an all-zero entry).
- A *rebuild* must never recompute days whose rows are gone (otherwise an import
  silently erases them — 23 of 30 days, in the test that caught it).

Those two pull in opposite directions, which is why `rebuildSummaries` is bounded to
the range the surviving rows cover rather than emptying the table.

## 3. Sessions are derived, never stored

A session is a *run of focus rows*, computed fresh every time from the event stream. It
has no row, no id, no persistence. Consequences:

- Deleting a session means deleting the rows behind it. There is nothing else to delete.
- A session's identity is **the timestamp of its first event**. That is what notes,
  bookmarks and tags are keyed to.
- Therefore: an annotation is live exactly while some event still starts at that
  instant. Delete that first row and the annotation describes nothing — it is an orphan
  and must be cleaned up. But a session that merely *included* a deleted app keeps its
  first row, its identity, and its note. Prune on reachability, never by application.

The derivation itself is in `Sources/ReplayCore/SessionBuilder.swift`, checked against
`spec/fixtures/`. In summary, per row in start order:

1. A hole of ≥ `recordingGapSeconds` since the previous row → close the run, emit an
   `unrecorded` break. Replay was not running.
2. An `idle` row → close the run, emit an `away` break.
3. A row of ≥ `idleBreakSeconds` → close the run, emit an `idle` break. One app holding
   focus for half an hour is absence, not concentration. (This is the fallback for data
   recorded before away stretches were measured.)
4. Otherwise the row extends the current run.

Then: a run under `minSessionSeconds` with fewer than 3 rows is a stray switch and is
dropped; breaks at either end are trimmed.

Two porting traps, both of which the fixtures catch:

- **Sort stability.** Rows are sorted by start time, and JavaScript's sort is stable.
  Equal timestamps must keep input order or app ordering and titles shift. Swift's
  `sorted(by:)` is *not* stable — the port sorts on `(value, originalOffset)`.
- **The open session.** A row with `ended_at IS NULL` is the session in progress; its
  duration is measured against `now`, not read from the row.

## 4. "Active" means what a person would mean

Every headline figure excludes rows longer than `idleStretchSeconds`. Without that
filter, a Mac left open overnight reads as "15h active in Finder" — technically true of
the data and a lie about the day.

This filter appears in the SQL (`duration < ?`), in the derivation, and in
`excludeIdleStretches`. All three must agree.

## 5. A day is the day a run started

The single definition: **local midnight, bucketed by `started_at`.**

The timeline groups that way, headlines are computed that way, retention prunes that
way, and per-day deletion matches rows that way. So a session that crosses midnight
belongs to the day it *began* — not to both, and not to the day it ended.

The one place this leaks: the range query for a day deliberately reaches back (a long
away stretch may have begun before the window and reach into it), so a view showing a
single day **must filter to runs that began that day**. The Glaze app shipped without
that filter and a session spanning midnight appeared on two days at once.

### And a week begins on Monday

Not the locale's answer. `Calendar.firstWeekday` is Sunday in en-US, and the reference
settles the question itself — `startOfWeek` is `(d.getDay() + 6) % 7`, commented "days since
Monday". Every surface that groups by week has to agree, or two of them draw the same seven
days differently.

This one had already gone wrong once. `startOfWeek` was private to the autobiography, so
when the memory heatmap needed a week boundary it reached for `firstWeekday` instead and
drew a grid the rest of the app did not recognise. There is one `ReplayCore.startOfWeek`
now, and the suite checks all seven weekdays land on their Monday.

**Locale is not timezone.** CI runs in four timezones and would never have caught this: the
grid was wrong in a Monday-first *locale*, at any hour, in any zone.

## 6. Deletion, at three grains

| grain | what goes |
|---|---|
| session | its rows, and any annotation keyed to its first row |
| day | its rows, its headline, its reflection, its annotations |
| everything | all rows, all headlines, all reflections, all annotations |

Plus the retention window, which prunes rows but **keeps headlines** — the one deletion
that deliberately leaves a trace, because a summary of a day is worth more than nothing.

After any of them: restate the affected days' headlines (a day still has other
sessions), prune orphaned annotations, and compact if enough dead space accumulated.

## 7. Space on disk is counter-intuitive

Worth writing down because it generated a support question and a wrong public claim
before it was understood:

**SQLite does not shrink its file when you delete rows.** Freed pages go on a freelist
and get reused. Delete a year of history and the size on disk is unchanged. `VACUUM`
rewrites the file and hands the space back.

Two facts that shape the UI:

- **A freelist of zero does not mean a vacuum recovers nothing.** `VACUUM` also repacks
  partially-filled pages — in testing it recovered 2% of a database whose freelist was
  zero. So `freelist × page_size` is a **lower bound**; report it as "at least", and
  never disable a compact action because it reads zero.
- **`PRAGMA integrity_check` throws on a badly damaged file** rather than returning a
  row saying so. Catch it, or a caller's recovery path is skipped by an uncaught error.

Compaction is only worth a full-file rewrite past both `compactMinFreeRatio` and
`compactMinFreePages` — otherwise deleting one day out of a year rewrites the whole
file for 0.3% of dead space.

Safety, in order: copy the file, `VACUUM`, verify with `integrity_check` **and** a row
count, and only then delete the copy. If verification fails, *leave the copy on disk and
name it in the message*. Deliberately no automatic restore: swapping files underneath
live connections is a more dangerous path than the one it guards, and `VACUUM` is
already transactional.

## 8. The voice

Not decoration — it constrains behaviour, so a port that ignores it is wrong in a way
users will feel.

Replay **describes a day rather than grading it**. There is exactly one evaluative
surface, the optional focus goal, and it is off by default, never turns red, and never
scolds a quiet day. Nothing is inferred and presented as fact: a category it cannot
confidently name stays "Other" and the session is named after its dominant app instead.
When there is nothing worth saying, the app says nothing rather than filling space.

Destructive actions are confirmed, name what they will remove, and are kept out of the
places people type. Numbers explain themselves — "452 KB, all in use" rather than a
figure that invites "why doesn't that go down?".

### Where the voice comes from

The rules above were reconstructed from the shipped code. The *reasoning* behind them was
not in the code — it was in the 110 prompts that built the Glaze app over three days, now
kept at `~/coding/glaze-app/Replay-prompt-history.md`. They repeat a small set of
constraints so consistently that they are worth stating as rules rather than as taste:

- **Never gamify.** Stated four separate times. Memory cards for a first session or a
  longest focus are *memories, not rewards* — "never create artificial achievements", "never
  celebrate with confetti", "keep the tone reflective".
- **Never judge the user.** The weekly view was specified with "avoid productivity scores,
  do not judge the user — the goal is remembering, not measuring".
- **Never fabricate.** "Never invent. Never hallucinate. Never exaggerate." Every sentence
  the app writes has to summarise data it actually holds, which is why the autobiography and
  the day stories are assembled from verified figures rather than phrased freely.
- **Never interrupt.** Contextual memories were specified as "never interrupt, never display
  popups — subtle inline cards", always dismissable, always disableable.
- **Extend, do not redesign.** Three of the four large feature specs open by saying so.

This matters for the port because these are the questions the source cannot answer. When a
change proposes a streak, a score, a badge, or a sentence the data does not support, the
answer is here.

