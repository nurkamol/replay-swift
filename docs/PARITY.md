# Parity ledger

Where this port stands against the Glaze app. Update it in the same commit as the code —
a ledger nobody trusts is worse than none.

**Level with:** Glaze 2.3.2 (`spec/constants.json` names the commit) · **Verified by:** `swift test` (or `swift run replay-parity`), 694 checks

Legend: **done** verified · **partial** works, gaps noted · **todo** not started · **later** deliberately deferred

---

## Core — recording and storage

| capability | status | notes |
|---|---|---|
| Schema (4 tables, 3 indexes) | done | checked byte-for-byte against `spec/schema.sql` |
| Open / close focus sessions | done | duration computed in SQL, as in the reference |
| Away stretches from idle time | done | `CGEventSource`, no permission needed |
| Launch / terminate rows | done | with the same de-duplication window |
| Ignored background agents | done | list checked against the spec |
| Excluded applications | done | persisted, applied to the tracker live, and excluding erases that app's history |
| Session derivation | done | 8 fixtures, exact match including titles and app order |
| Category table → titles | done | order-sensitive, checked |
| Daily headlines (rollup) | done | including the no-rows guard |
| Day summary (Today's figures) | done | fixture-checked: active, apps, sessions, focus rhythm, longest, top app |
| Bounded rebuild | done | the fix that stopped an import erasing pruned days |
| Retention prune | done | keeps headlines |
| Delete a session / a day | done | via the tracker, so in-memory state stays honest |
| Orphaned-annotation pruning | done | reachability, not by application |
| Compaction + thresholds | done | `reclaimableBytes` documented as a lower bound |
| Compaction safety (copy, verify) | done | `compactSafely` — copy, VACUUM, verify by integrity check **and** row count; a failed verify leaves the copy and names it |
| Reflections | done | read/write, keyed by day; shown on a reopened day, including one whose rows were pruned |
| Annotations (notes, bookmarks, tags) | done | read/write, tag normalisation, empty rows deleted rather than kept — 15 checks |
| Backup import | done | `swift run replay-import` — real 3,084-row export verified, see FINDINGS.md |
| Backup export | done | `Backup.encode` — every row, snake_case as the reference writes it; round-trips through this app's own reader |
| Constellation | done | `buildConstellation` — applications as stars, tied by direct switches, pairs under two dropped |
| Canvas graph | done | `buildCanvas` — every node and every edge compared, including the subtitles. 16 checks |
| Memory confidence & selection | done | `memory-intelligence` — the scoring vocabulary, the selector, and silence as a valid answer. 18 checks |
| Right-time / threads / echoes | done | three producers, each scored and each returning nothing far more often than something. 15 checks |
| Timeline filter buckets | done | `sessionFilterCategory` — six coarse buckets, with Writing and Media falling to Other. 9 checks |
| Anniversaries | done | exact dates only — a year to the day, or the six-month mark. 3 checks |
| Forgotten | done | old bookmarks, projects stepped away from, reflections worth rereading, each archivable. 5 checks |
| Morning briefing | done | `buildMorningBriefing` — yesterday's figures, the longest stretch, a thread worth continuing, a month ago, the oldest bookmark still waiting. 19 checks, including the two cases where it says nothing |
| Surprise me | done | `surprisePool` — the moments, the fuller days and the marked sessions, never today. 2 checks, and the order is pinned as well as the membership |
| Moments | done | `detectMoments` + `pickDailyQuote` — seven kinds, each with a threshold, compared as text. 7 checks |
| The archive | done | `computeLegacy` — first day, active days, years, and the applications behind all of it. 9 checks. Its figures live inside a view upstream, so the fixture re-declares them, as `sessionMatches` does |
| App relationships | done | `computeWorkflowPartners` + `computeRelationship` — switches, shared sessions, direction and average length. A pair must have been switched between twice to count. 11 checks |
| Rituals | done | `detectRituals` — the app that leads each part of the day and the one a day begins with, each needing more than one day to count. 6 checks |
| Chapters | done | `detectChapters` — eras from the durable headlines, split on character change or a gap over 16 days. 10 checks |
| Autobiography | done | `listPeriods` + `summarizePeriod` — the history as sentences, compared word for word. 9 checks |
| Projects | done | `detectProjects` — the same signature grouping as workflows but keeping the whole span, apps aggregated across every session, most recently active first. 10 checks. Names are the only thing stored |
| Relative day labels | done | `relativeDayLabel` and `shortDateLabel`, both locale renderings and both recorded rather than assumed |
| Application totals | done | `computeAppStats` — most-used first, idle stretches excluded, an open row measured against `now`, ties holding first-seen order. 7 checks |
| Resume target | done | `findResumeTarget` + `formatWhen` — the last session you actually stepped away from, never the one you are in. 25 checks, including both sides of the three-minute in-progress window |
| Workflows (recurring app combinations) | done | `detectWorkflows` — signature grouping, recurring-only, ranked by time. 8 checks. Projects and app-to-app relationships from the same module are **not** ported |
| Week summary | done | `computeWeekSummary` — seven days, per-day arcs, app shares and days-used, the weekday × hour rhythm grid and its peak. 31 checks against the reference's own output |

### Break copy, now covered

`describeBreak` was view code, so nothing checked it — and this port had drifted from the
reference in three places: an idle gap read "2m idle in Safari" instead of "2m break", its
explanation invented "One app held focus without input" where the reference names the app
that stayed in front, and an editorial comma had crept into the unrecorded line. The words
are the product (SPEC §8), so they are generated into the contract from the reference's own
function now and live in `ReplayCore` where the suite can reach them.


## App — the surfaces

| capability | status | notes |
|---|---|---|
| Menu bar item | done | current app, today's total, pause/resume, Open Today/Timeline, Settings, Quit |
| Design system | done | one file of tokens, every view reading from it, and `node tools/design-audit.mjs` failing the build if a view spells a number |
| Application menu | done | Replay / Edit / View / Window, so ⌘, ⌘W ⌘Q and — the one that bit — ⌘C/⌘V in a note field all work |
| Today | done | headline, top app, a morning briefing before lunchtime, a moment quoted as one line, a contextual memory when there is one worth showing, focus-goal card, a resume card that brings the app back to the front, reflection, sessions and breaks |
| Canvas | done | the graph drawn as a field of real application icons, with pan, pinch-zoom, selection and a way into whatever a node is. Layout is a force simulation run once, seeded from each node's id so the same history lays out the same way |
| Command palette | done | ⌘K over surfaces, applications, projects, recent days and the actions that are not places. **The matcher has no reference counterpart** — upstream leans on a JavaScript library's scoring — so it is the one behaviour here that no fixture covers |
| Screensaver | done | a slow drift through the day — the memory, today's sessions, the applications you keep. Borderless, on the screen Replay is on, Esc to leave. Not auto-started on a timer, unlike the reference |
| Museum | done | the day's featured moment, the milestones, the deepest stretches, what was bookmarked, what was written, and the work that took the most |
| My Story | done | the archive at a glance: how long, how much, which years, and the applications that ran through it |
| App relationships | done | reached from an application's "works alongside" list — which way the switching runs, and every session the two shared |
| Story | done | a hub over the narrative surfaces, plus the rituals a run of days settles into |
| Chapters | done | the eras, and a page for each: what it held, what led its days, and every day in it. Renameable |
| Autobiography | done | a period picker over every week, month and year the history touches, and the paragraph for it |
| Projects | done | a grid of what keeps coming back, and a page for each: how it grew, the apps that make it up, and every session under it. Renameable, with an empty name falling back to Replay's own description |
| Apps | done | ranked by time, with a Today/This Week/This Month window, pinned favourites, and a row leading into that application's own history |
| An application's history | done | header, the four figures, which collections it appears in, the applications it works alongside, and its recent sessions |
| This Week | done | the week's figures, a seven-row rhythm strip on a shared hour axis, the plain-language peak, the recurring application combinations, and the five most-used applications with how many days each appeared on |
| Timeline (days, dividers, ⋯ menus) | done | days newest-first, day-part dividers, range picker, per-day ⋯, filter chips by kind of work, and all nine layers — five that choose which sessions appear, one that governs the gaps, and three that add rows among the days |
| A past day, reopened | partial | filters to runs that began that day (SPEC §5); reflection card and export; says so when a day's rows are pruned but its headline survives. No story or chapter context |
| Welcome | done | two pages: the things Replay will not do unasked, each off by default, and the privacy claim shown working rather than asserted |
| Settings | partial | General, Privacy, Data, Shortcuts, Guide, About. Surfaces (solid/frosted/glass), focus goal, contextual memories and threshold, morning briefing, Dock badge, the screensaver's idle drift and exit conditions, and the three notification recaps — each wired to real behaviour. The Shortcuts table is written out by hand rather than derived, so it can drift from what is actually bound |
| Session card (expand, apps, note) | done | app breakdown, tags and a note when expanded; bookmark and delete behind the ⋯; marks and a warmed border when collapsed |
| Export a day / a session | partial | a day, a session, this week, this month, bookmarks, notes — as Markdown, CSV, JSON or HTML, carrying notes and tags. Scope selection and report text checked against the reference's own output. **No PDF** — see the divergence below |
| Dock badge | later | |
| Memories / Today in History | done | fixed calendar offsets over the durable headlines, so a memory survives its day being pruned; the date arithmetic is fixture-pinned |
| Search | done | by session name, note or tag; by application; and a few phrases ("morning", "longest", "bookmarked") that go straight to a slice — checked against the reference's own predicates |
| Collections | done | derived from the session category — no table, nothing to file. Both orderings tie-broken, with the fixture built so both ties occur |
| Projects | later | needs detection logic with no equivalent here yet |
| Story Mode | done | a reopened day, narrated in a few sentences; five day shapes fixture-checked as text |
| Autobiography | later | |
| Canvas | later | a project of its own |
| Screensaver / Ambient | later | |
| Replay Movie | later | |
| Contextual memories | later | the largest single subsystem after Canvas |
| Notifications (digests) | later | needs `UNUserNotificationCenter` authorisation |

## Known divergences to keep an eye on

- **Workflows and projects can each carry the same name several times over.** A workflow is
  named after the category most of its sessions were, and a project after that category plus
  its lead app — so a week spent mostly in a browser produces four "Research Workflow" rows,
  and real history produces three projects all called "Development · Terminal", told apart
  only by the app list beneath. Inherited, not introduced: the reference does the same, and
  both names are contract-checked. Left alone deliberately, and a project at least can be
  renamed. If it is ever changed, change it in the Glaze app first and let `spec/` carry it
  here.
- **A pushed screen had no way back.** A toolbar declared on the root view, or on the
  `NavigationStack` around it, vanishes the moment a destination is pushed: the innermost
  view's toolbar wins and a pushed screen has none. This window hosts SwiftUI inside an
  `NSWindow` rather than being a `WindowGroup`, so no automatic back button appeared to
  replace it — a reopened day or an application's history could only be left by clicking a
  sidebar item, and ⌘[ did nothing. The chrome is applied to every screen now. Worth keeping
  in mind before attaching any other toolbar here.
- **"Sessions" means two things.** On Apps, `sessionCount` counts *rows* — how many times an
  application came to the front — so Firefox reads "575 sessions" for a week in which Today
  would call the same span three. Inherited: the reference uses the same word for the same
  number. Left alone for the same reason as the workflow titles.
- **A comment that contradicts its own code.** `selectLivingMemory` upstream is documented
  as breaking ties "deterministically by id"; the code sorts by confidence alone, and
  JavaScript's stable sort means input order survives. This port was written to the comment,
  and the fixture failed on the one case built to tie. Follow the code — it is what ships.
- **Narrow no-break space before AM/PM.** Current macOS formats "2:14 AM" with U+202F;
  the ICU the reference runs against emits an ordinary space. The two strings look identical
  in a terminal and the fixture caught them differing. `Moments.clockLabel` folds U+202F to a
  space, which is the smaller wrong: it keeps both apps saying the same thing, and the
  difference is a runtime's ICU version rather than a decision either app made. Any other
  formatter that prints a time is a candidate for the same fold.
- **A "full backup" carries activity and nothing else.** The file holds the `events` table
  only: notes, tags, bookmarks and reflections are not in it, so exporting a backup, wiping a
  Mac and restoring returns your history and loses everything you wrote about it. Inherited —
  the reference's export is the same shape and the two files are meant to be interchangeable —
  but the Settings label says "Full backup", which oversells it. Pinned by a test that asserts
  the absence deliberately, so it is a recorded fact rather than something discovered too
  late. Worth fixing in the Glaze app first, since the format is shared.
- **`Text` group-separates an `Int`.** `Text("\(year)")` renders 2026 as "2,026" — the
  interpolation is a `LocalizedStringKey`'s, and it formats numbers. Concatenating with `+`
  first makes it a plain `String` and avoids it, which is why most counts in this app were
  already safe by accident. Found by looking at My Story. Any new `Text("\(someInt)")` is
  suspect.
- **Sort stability.** JavaScript's sort is stable; Swift's is not. The port sorts on
  `(value, originalOffset)` in `summarizeApps`, `buildTimeline`, `detectWorkflows`,
  `computeWeekSummary`, and both orderings in `Collections.compute`. Fixtures cover each — the collections one is built so two
  categories tie on total and two apps tie inside one, because a fixture that never ties
  would pass against an unstable sort. Do not "simplify" any of them away.
- **Two apps can share a display name.** Sessions fold apps on
  `bundleIdentifier ?? applicationName`, so the Glaze Replay and this port both appear as
  "Replay" in a collection's app list. It reads like a duplicate and is not one; the
  reference keys the same way, and folding on the name instead would merge two genuinely
  different applications.
- **`Rules` is duplicated.** The thresholds exist in `Model.swift` *and* in
  `spec/constants.json`. Deliberate: the shipping app should not depend on parsing JSON.
  The parity check is what keeps the two copies equal.
- **Different container.** The native app cannot read the Glaze app's live database.
  Migration is via the backup JSON, not the file.
- **Preferences live in `UserDefaults`, not a JSON file.** The reference keeps its settings
  in `userData/settings.json` because its tray, tracker and windows are separate processes.
  Natively they are one process, and `UserDefaults` is what a Mac app is expected to use.
  The *values* match the reference's defaults, which is the part a user would notice. The
  two apps could not share a settings file anyway — different containers.
- **Excluding an app is verified by the suite, not on real data.** `deleteByBundleIDs` and
  its consequences are checked, and the sheet was exercised in the running app, but no
  exclusion was ever confirmed against the real database: doing so permanently erases that
  app's history, which is not a thing to spend to prove a button works.
- **Fixtures are timezone-pinned, and the checks must honour that.** Session titles are
  named after the *local* day part, so every fixture records the timezone it was generated
  under (`UTC`) and the checks derive under that calendar rather than the machine's. Without
  it the suite passes only where the fixtures were made — see [FINDINGS.md](FINDINGS.md).
  Verified in UTC, America/New_York and Asia/Tokyo.
- **Calendar arithmetic normalises rather than clamps.** 31 March minus one month is 3
  March, not 28 February — JavaScript's `Date` overflows and the memory offsets have to
  agree across both apps. Swift's `Calendar.date(byAdding:)` clamps and would have been
  wrong; building `DateComponents` with an out-of-range day and letting `date(from:)`
  normalise reproduces it. Pinned at three month-ends and a leap day.
- **There is no PDF export, and that is a decision rather than an omission.** The reference
  offers one; two attempts at it here failed in WebKit — an unattached `WKWebView` never
  finishes loading, and once attached, `createPDF` hung with no timeout available on the
  call itself. The reference's own PDF is capped at a single page and tells the reader to
  use HTML for anything longer, so HTML is the format that actually carries a month. If PDF
  returns, the route worth trying is an `NSPrintOperation` on a real window rather than
  WebKit's PDF API. Until then the gap is stated here rather than half-built.
- **Report text is compared with one deliberate fold.** Foundation and Node disagree on the
  space before a meridiem (U+202F vs U+0020) because they bundle different ICU versions.
  The comparison folds non-breaking spaces onto plain ones and nothing else.
- **A session can display an end before its start.** Inherited from the reference's away
  handling, not introduced here — see [FINDINGS.md](FINDINGS.md).
- **Motion is part of the contract.** The durations and easing curves in
  `DesignSystem.swift` are the reference's own, extracted from its stylesheet into
  `spec/constants.json`. A port that guesses 0.2s where the reference says 180ms is not
  visibly wrong in a screenshot and is wrong every time anybody uses it.
- **The parity suite is the only test coverage.** It runs both as `swift test`
  (swift-testing, needs `DEVELOPER_DIR` set to the Xcode beta) and as
  `swift run replay-parity` (no Xcode). It covers the core thoroughly and everything else
  not at all — the tracker's timing behaviour and anything in the UI are unverified.

## What is left

Counted rather than estimated, and corrected — the previous version of this list was stale,
still claiming 8 of 20 routes after fourteen of them had landed.

**All 20 of the reference's routes exist.** What remains is depth inside them, plus the
platform work the brief asks for and the one thing blocked on paperwork.

1. **What's New**, and **Replay Day** — a day played back as a short film.
2. **A window sizing trap, twice now.** `NSHostingController` sizes its window to the SwiftUI
   content unless told not to. The screensaver came out 1728×2888; the welcome screen grew the
   main window's *saved* frame to 980×5580, which then reloaded as a window mostly below the
   screen. `hosting.sizingOptions = []` on any window whose size is its own.
3. **Canvas** has no synced timeline side panel and no focus mode.
4. **Search** has no saved searches, no time-range chips, and does not highlight matches.
5. **A past day** has no story or chapter context.
6. **PDF export** — dropped deliberately after WebKit failed twice; the route worth trying
   next is `NSPrintOperation` on a real window.
8. **Widen the model suite.** Nine cases cover the sharp edges; `ExportModel`,
    `SettingsModel` and `CollectionsModel` have none, and the tracker's live-state handling
    is still only exercised by using the app.
8. **The brief's platform integrations, none started**: App Intents, Widgets, Spotlight,
    Quick Look, Handoff/`NSUserActivity`, multiple windows and tabs, Services, sound and
    haptics.
9. **Sign and notarise.** Blocked on a certificate rather than on code — this machine has
    no Developer ID at all. A decision, not a task.

Done and no longer blocking:
- ~~The models were untestable~~ — they never were. This ledger recorded them as beyond
  reach "because they live in an executable target that no test can import", and that was
  simply false: `@testable import ReplayApp` works, and the only thing between those models
  and a test was someone writing one. Nine now run against a real SQLite file in a temporary
  directory — range filtering, the reopened-day rule, annotation caching, deletion, the
  week's seven days, and search's snapshot. Each was checked by breaking the code it guards:
  deleting the day filter in `HistoryModel.day` fails two of them.
- ~~This Week was missing entirely~~ — a whole reference surface the ledger had never
  recorded. `computeWeekSummary` is ported and generated into the contract (31 checks): the
  seven days, each day's hourly arc, application shares with how many days each appeared on,
  the weekday × hour rhythm grid and its busiest cell. The tie-break was the trap, as it
  always is — two applications level on seconds must hold the order they were first seen in,
  which JavaScript's stable sort gives free and Swift's does not. Verified by flipping it and
  watching the check fail.
- ~~Hard-coded values scattered through the views~~ — one design system, every view reading
  from it, and an audit in CI that fails the build if one drifts back. Changing
  `Radius.card` once visibly re-rounds every card in the app; that was checked by doing it.
- ~~Story Mode~~ — every clause filled from recorded activity, and a day too thin to narrate
  gets no story rather than a padded one. Compared as text, because the text is the claim.
- ~~Collections~~ — sessions gathered by the kind of work they were, derived rather than
  filed. `Admin` is shown as "Utilities", and `Other` is deliberately not a collection.
- ~~Memories~~ — the first of the deferred subsystems, and the one that needed no new table:
  it reads the headlines retention already keeps.
- ~~Search~~ — by name, note, tag, application, and a handful of phrases; the two application
  predicates kept apart (exact for a chosen app, substring for discovery), which the fixture
  caught the port getting wrong.
- ~~HTML export~~ — the reference's document, self-contained, with real app icons.
- ~~Export covered only one day~~ — today, this week, this month, bookmarks, notes, and a
  single session, each checked against the sessions the reference's own `selectScope` picked.
  Verified on real data: the count shown before the save panel (68) matched the exported
  file, and its per-day split (20/39/9) matched what Today and the day view report
  independently.
- ~~Nothing runs the suite but a human remembering to~~ — `.github/workflows/parity.yml`
  runs it on every push and pull request, in four timezones. It cannot check whether `spec/`
  is *current* — that needs the Glaze sources, which are not in this repository — only that
  the port still matches the contract as committed.
- ~~`groupByDay` and the report serialisers verified only by reading~~ — both now run against
  output the reference actually produced, generated under a pinned clock, timezone and
  locale. Finding five real divergences in the process, and one latent bug in the suite
  itself: it had only ever passed in the timezone its fixtures were made in.
- ~~The application menu, the focus goal, and Today's reflection~~ — ⌘, ⌘W and ⌘C/⌘V now
  work; the goal card was watched met (green ring, 3-day streak verified against the stored
  headlines) and unmet (96%, "21m to go", no flame, no red).
- ~~Export, reflections, menu-bar-only mode~~ — a day exports as Markdown/CSV/JSON carrying
  its notes and tags; a full backup round-tripped through this app's own reader (3,149 rows
  out, 3,149 recognised as already present on re-import); menu-bar-only flips the activation
  policy live, `Foreground` → `UIElement`, with no restart.
- ~~Settings~~ — General, Privacy, Data, Guide, About, in their own window. Excluded
  applications is persisted and applied live, retention prunes on change, and Compact runs
  the SPEC §7 sequence. Verified against the real database: reclaimed 12 KB with 3,144 rows
  and the integrity check intact, and no copy left behind.
- ~~Notes, tags and bookmarks~~ — read/write against the real database, marks on a collapsed
  card, and 15 checks. Tag normalisation is now part of the generated contract rather than
  hand-copied: `tools/sync-spec.mjs` extracts the two caps from the reference's `setTags`.
- ~~Today going stale while the window is open~~ — it re-derives on a 30s timer, matching
  the reference's `useNow`. Watched it move from 7h 4m to 7h 21m with the window untouched.
- ~~Timeline, and a past day reopened~~ — running against real data; the day view and the
  Timeline agree, and the SPEC §5 filter demonstrably drops a midnight-crossing run (one on
  2026-07-26 in the current database).
- ~~Menu bar item + Today~~ — running against real data; every headline figure matches the
  reference implementation on 3,097 imported rows.
- ~~Prototype the icon API under App Sandbox~~ — works with no entitlement, and real icons
  now render in the timeline.
- ~~Backup import~~ — verified against a real 3,084-row export; found and fixed a Glaze bug
  that was dropping away time. Both in [FINDINGS.md](FINDINGS.md).
