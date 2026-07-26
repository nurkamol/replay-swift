<!--
  A copy of the Glaze app's CHANGELOG.md — the reference implementation's release
  history, for context on what has shipped and when.

  Copied, not authored here. Refresh it with:
      cp "$GLAZE_SRC/CHANGELOG.md" docs/GLAZE-CHANGELOG.md
  (tools/port-queue.mjs reminds you when it has moved.)
-->

# Changelog

All notable changes to Replay. Everything stays local, offline, and private —
every entry below is built from your own recorded history, never invented.

## 2.3.2 — Away time, restored

### Fixed

- **Importing a backup no longer loses your away time.** An export writes every row,
  including the measured stretches when you were away from the keyboard — but the import
  only accepted focus rows, so restoring a backup dropped all of them. The timeline then
  relabelled those gaps "Replay wasn't running" rather than "away", which changed what the
  history said about a day rather than just losing detail. Only affects history that came
  in through Data ▸ Full backup ▸ Import; activity Replay recorded directly was never
  touched.

## 2.3.1 — Smaller pieces

- **Delete a single session** — a ⋯ menu at the foot of any expanded session, and
  the same action on its right-click menu. It removes exactly that run of events
  and any note or bookmark on it; the rest of the day is left alone and its
  headline is restated to match. Per-day delete arrived in 2.3.0; this is the
  finer grain of the same idea. The ⋯ sits in its own row below the note field
  rather than beside it — a destructive action doesn't belong in the space you
  type into — and nothing is added to a collapsed card, so the Timeline stays as
  quiet as it was.
- **Export one session** — Markdown, PDF, HTML, CSV or JSON, from that same ⋯
  menu. Named and titled after the session, so a single run of work can be saved
  on its own.
- **A day is the day it started.** A session that ran past midnight used to appear
  on both days when a past day was opened, because that view kept the events the
  range query reaches back for. Everywhere else in Replay a run belongs to the day
  it began — the Timeline groups that way, the headlines are computed that way, and
  deletion matches rows that way — so the day view now agrees.
- **Set goal from Today** — the focus goal card carries its own picker: every hour
  from 1 to 8, whatever custom target is active, and No goal. The figure and the
  control for it now sit together, instead of the goal being readable on Today but
  only changeable in Settings. Custom still opens Settings, where the hours and
  minutes fields live.
- The goal presets, bounds and formatting moved into `lib/goals.ts`, so Settings
  and the card can't drift into offering different sets of the same choice.
- **Compacting says what it will do, and guards itself.** Storage now shows how
  much a rewrite would hand back, so the button is never a mystery: a database
  that has only ever grown has nothing to reclaim, and says so instead of looking
  broken. Before rewriting, a copy of the database is taken; afterwards the result
  is checked with SQLite's own `integrity_check` and against the row count, and
  only a database that passes has its copy removed. If anything fails the copy is
  left on disk and named in the message, so there is always something to fall back
  to. Privacy's size figure now carries the same answer — "all in use", or how much
  is reclaimable — since that number is where the question gets asked.

### Fixed

- **Importing a backup no longer destroys old days.** A summary rebuild — triggered
  by an import or by excluding an app — emptied the headline table and recomputed
  it from the raw rows. For any day already pruned past the retention window there
  are no raw rows, and its headline was the only record of it left, so those days
  were silently erased: 23 of 30 in testing. The rebuild is now bounded to the
  range the surviving rows actually cover, and leaves older headlines alone.
- **Excluding an app no longer leaves orphaned notes.** Its rows were deleted but
  the notes, bookmarks and tags on affected sessions were not, leaving them pointed
  at sessions that could never be reached again — despite an excluded app being
  meant to leave no trace. Now only genuinely unreachable annotations are removed:
  a session that merely *included* the excluded app keeps its identity and its
  note.

## 2.3.0 — Forgetting a day

- **A ⋯ menu on every day** — a real macOS menu on each day's divider in the
  Timeline, and on the day's own page: open the day, export just that day, or
  delete it. Day-level actions used to sit inline, which put a permanent
  destructive button beside every day.
- **Delete a single day** — from that ⋯ menu, or by picking a day in Data ▸
  Storage. It takes that day's sessions, summary, reflection, notes and bookmarks
  with it, and leaves every other day untouched. A deleted day stays deleted: its
  headline goes too, so it can't come back as an empty entry the next time
  complete days are rolled up.
- **Export one day** — Markdown, PDF, HTML, CSV or JSON, straight from a day's ⋯
  menu. Previously the smallest slice you could export was all of Today.
- **The space actually comes back.** Deleting rows frees room *inside* the
  database file without shrinking it, so clearing history used to leave the size
  on disk unchanged. Replay now rewrites the file whenever a bulk delete leaves
  enough dead space to be worth it — a deleted day, a retention prune, Clear
  History, or excluding an app — and Data ▸ Storage ▸ Compact database does it on
  demand and reports what it reclaimed.
- **A focus goal of any length** — every whole hour from 1 to 8 as a one-click
  choice, plus Custom for a target that isn't a round number: 45 minutes, 5½
  hours. The backend always accepted any value; only the picker was restrictive.
  A goal that isn't one of the presets now shows as Custom rather than leaving the
  picker blank.
- Storage in Settings now says plainly what a day of history costs, and the Guide
  answers where the space goes.

## 2.2.0 — Replay any day

- Replay any day from the Timeline — a Replay button on each day's divider plays
  it back, morning to evening.
- A What's New release history, in Settings ▸ About and the Help menu.

## 2.1.1 — Polish

- **Canvas** — Meaningful Moments now appear as their own small stars, tied to the
  app they involve when there is one.
- **Today** — leads with the work you most recently stepped away from, so your
  latest session sits at the top; a Reflect shortcut in the toolbar brings the
  day's reflection into reach without scrolling.
- **Performance** — history-heavy views (Timeline, Canvas, Today) stay fast even
  after years of recorded activity.

## 2.1.0 — Contextual Memory Intelligence & Replay Canvas

Replay learns *when* a memory matters, and gives your history a place to be wandered.

### Contextual Memory Intelligence
Replay now surfaces a memory only when it's relevant — and stays quiet when
nothing is worth saying.

- **Right-Time Memories** — when you return to an app after a while, Replay notes
  how long it's been and what you were doing last.
- **Anniversaries** — a year since you began this memory, six months since a
  project started, your first bookmark or reflection.
- **Forgotten Memories** — old bookmarks, projects you've stepped away from, and
  reflections worth rereading, with Open · Archive · Dismiss.
- **Memory Threads & Echoes** — a project picked back up is noted; a day that
  resembles past work quietly says so.
- **Morning Briefing** — a calm look back at yesterday when you open Replay in the
  morning, with one memory to carry into today.
- **Story Mode** — any past day narrated back in a few plain sentences.
- **Personal Narrative** — the Autobiography now tells your weeks, too.
- **Meaningful Silence & Confidence** — a single confidence threshold governs it
  all; if nothing clears the bar, Replay shows nothing.

### Replay Canvas
A new infinite memory space — the visual heart of Replay.

- **Explorable landscape** of your projects, apps, collections, and chapters,
  tied by the relationships already in your history.
- **Fluid camera** — pan with inertia, pinch or scroll to zoom toward the cursor,
  and eased fly-to when you focus a memory.
- **Level of detail** — a calm constellation of your biggest memories zoomed out,
  gathering detail as you move closer.
- **Focus & Replay Story** — click a memory to focus its network; let the camera
  tour it and the things around it.
- **Split view** — a synced Timeline panel beside the canvas.

### Layered Timeline
Read your timeline at different depths — toggle Sessions, Projects, Collections,
Bookmarks, Notes, Activity, Reflections, Moments, and Memories independently.

### Today
Today now leads with the work you most recently stepped away from, so your latest
session sits at the top — while the day still reads morning to evening. A Reflect
shortcut brings the day's reflection into view without scrolling.

### Craft
A quieter, more native feel throughout — a gentle glow on bookmarked memories,
smoother card motion, consistent macOS interaction patterns, and a history layer
that stays fast even after years of use.

## 2.0.0 — The Living Memory Engine

Replay grows from an activity tracker into a private memory companion — Chapters,
My Story, Museum, and the first Constellation, all drawn from local history.

## 1.3.0 — Reliving your day

- Replay Movie, Ambient mode, and a Screensaver — watch your day play back, or
  leave it drifting on a second screen.
- Collections, Projects, and the Constellation — your sessions by kind, the app
  combinations behind your work, and your apps as a field of connected stars.
- Reflections, daily memory quotes, and Surprise me.
- Meaningful search across everything, and a calendar heatmap.

## 1.2.0 — Today in History

- A memory card on Today that resurfaces this date a week, a month, a year ago.
- A Memories gallery and a calendar to open any past day, with a "then vs now".
- An optional "on this day" note each morning, and jump-to-a-day by name in Search.

## 1.1.0 — Sessions & Time Travel

- App-switching folded into named sessions with honest breaks.
- Time Travel & Replay — Today, Yesterday, the last 7/30 days, or play a day back.
- Notes, bookmarks & #tags, optional focus goals, search upgrades, recaps,
  favourites, per-app history, and export to PDF/CSV/JSON.

## 1.0.0 — The beginning

The first release — a private, local timeline of the apps you use.
