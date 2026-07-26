# Parity ledger

Where this port stands against the Glaze app. Update it in the same commit as the code —
a ledger nobody trusts is worse than none.

**Level with:** Glaze 2.3.2 (`spec/constants.json` names the commit) · **Verified by:** `swift test` (or `swift run replay-parity`), 379 checks

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

## App — the surfaces

| capability | status | notes |
|---|---|---|
| Menu bar item | done | current app, today's total, pause/resume, Open Today/Timeline, Settings, Quit |
| Application menu | done | Replay / Edit / View / Window, so ⌘, ⌘W ⌘Q and — the one that bit — ⌘C/⌘V in a note field all work |
| Today | done | headline, top app, focus-goal card, reflection, sessions and breaks |
| Timeline (days, dividers, ⋯ menus) | partial | days newest-first, day-part dividers, range picker, per-day ⋯ (open, export, delete). No layers or filters |
| A past day, reopened | partial | filters to runs that began that day (SPEC §5); reflection card and export; says so when a day's rows are pruned but its headline survives. No story or chapter context |
| Settings | partial | General, Privacy, Data, Guide, About in their own window, with the focus goal, backup export/import and menu-bar-only mode. No Shortcuts tab (no custom shortcuts yet), no digests |
| Session card (expand, apps, note) | done | app breakdown, tags and a note when expanded; bookmark and delete behind the ⋯; marks and a warmed border when collapsed |
| Export a day / a session | partial | a day as Markdown, CSV or JSON, carrying notes and tags — text checked against the reference's own output. PDF/HTML later; no session-level or multi-day scopes yet |
| Dock badge | later | |
| Memories / Today in History | later | |
| Search | later | |
| Collections / Projects | later | |
| Story Mode / Autobiography | later | |
| Canvas | later | a project of its own |
| Screensaver / Ambient | later | |
| Replay Movie | later | |
| Contextual memories | later | the largest single subsystem after Canvas |
| Notifications (digests) | later | needs `UNUserNotificationCenter` authorisation |

## Known divergences to keep an eye on

- **Sort stability.** JavaScript's sort is stable; Swift's is not. The port sorts on
  `(value, originalOffset)` in both `summarizeApps` and `buildTimeline`. A fixture covers
  it — do not "simplify" it away.
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
- **Report text is compared with one deliberate fold.** Foundation and Node disagree on the
  space before a meridiem (U+202F vs U+0020) because they bundle different ICU versions.
  The comparison folds non-breaking spaces onto plain ones and nothing else.
- **A session can display an end before its start.** Inherited from the reference's away
  handling, not introduced here — see [FINDINGS.md](FINDINGS.md).
- **The parity suite is the only test coverage.** It runs both as `swift test`
  (swift-testing, needs `DEVELOPER_DIR` set to the Xcode beta) and as
  `swift run replay-parity` (no Xcode). It covers the core thoroughly and everything else
  not at all — the tracker's timing behaviour and anything in the UI are unverified.

## Next three things

1. **Export scopes beyond one day** — this week, this month, bookmarks, notes, and a single
   session. The formats, the entry-building and the save panel all exist, and the text is now
   checked against the reference; what is missing is choosing what a report covers.
2. **Search**, the smallest door into the half of the app still marked `later` — Memories,
   Collections, Story Mode, Canvas — and the one most useful on its own.
3. **A CI run.** The suite is now timezone-portable and needs no Xcode
   (`swift run replay-parity`), which was the blocker. Nothing currently runs it but a human
   remembering to.

Done and no longer blocking:
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
