# Parity ledger

Where this port stands against the Glaze app. Update it in the same commit as the code —
a ledger nobody trusts is worse than none.

**Level with:** Glaze 2.3.2 (`spec/constants.json` names the commit) · **Verified by:** `swift test` (or `swift run replay-parity`), 298 checks

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
| Excluded applications | partial | tracker honours the set; no persistence or UI yet |
| Session derivation | done | 8 fixtures, exact match including titles and app order |
| Category table → titles | done | order-sensitive, checked |
| Daily headlines (rollup) | done | including the no-rows guard |
| Day summary (Today's figures) | done | fixture-checked: active, apps, sessions, focus rhythm, longest, top app |
| Bounded rebuild | done | the fix that stopped an import erasing pruned days |
| Retention prune | done | keeps headlines |
| Delete a session / a day | done | via the tracker, so in-memory state stays honest |
| Orphaned-annotation pruning | done | reachability, not by application |
| Compaction + thresholds | done | `reclaimableBytes` documented as a lower bound |
| Compaction safety (copy, verify) | todo | the store has the pieces; the sequence is not wired |
| Reflections | todo | table exists; no read/write yet |
| Annotations (notes, bookmarks, tags) | done | read/write, tag normalisation, empty rows deleted rather than kept — 15 checks |
| Backup import | done | `swift run replay-import` — real 3,084-row export verified, see FINDINGS.md |
| Backup export | todo | writing a backup, for the other direction |

## App — the surfaces

| capability | status | notes |
|---|---|---|
| Menu bar item | done | current app, today's total, pause/resume, Open Today, Quit |
| Today | partial | headline, top app, sessions, breaks, expandable cards. No reflection or focus-goal card yet |
| Timeline (days, dividers, ⋯ menus) | partial | days newest-first, day-part dividers, range picker, per-day ⋯ (open, delete). No layers, filters, or per-day export |
| A past day, reopened | partial | filters to runs that began that day (SPEC §5); says so when a day's rows are pruned but its headline survives. No reflection, story, or chapter context |
| Settings | todo | v1: General, Privacy, Data/Storage, Guide, About |
| Session card (expand, apps, note) | done | app breakdown, tags and a note when expanded; bookmark and delete behind the ⋯; marks and a warmed border when collapsed |
| Export a day / a session | todo | Markdown, CSV, JSON first; PDF/HTML later |
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
- **`groupByDay` has no fixture.** It is generated-spec-adjacent behaviour (SPEC §5) that
  `tools/sync-spec.mjs` does not emit scenarios for, so it is verified by reading against
  `activity.ts:487` and by the day view and Timeline agreeing on real data — not by the
  suite. A fixture would need a change to the sync tool.
- **A session can display an end before its start.** Inherited from the reference's away
  handling, not introduced here — see [FINDINGS.md](FINDINGS.md).
- **The parity suite is the only test coverage.** It runs both as `swift test`
  (swift-testing, needs `DEVELOPER_DIR` set to the Xcode beta) and as
  `swift run replay-parity` (no Xcode). It covers the core thoroughly and everything else
  not at all — the tracker's timing behaviour and anything in the UI are unverified.

## Next three things

1. **Settings** — General, Privacy, Data/Storage, Guide, About. Excluded applications is
   already honoured by the tracker and has nowhere to be edited, which is the most visible
   half-built thing left.
2. **Export a day / a session** — Markdown, CSV, JSON. Now worth doing: annotations exist,
   so an export can carry the note and tags rather than being reissued later with a column
   added.
3. **Reflections** — the day's written memory. The table exists; it is the same read/write
   shape as annotations, keyed by day rather than by session, and it is what a reopened day
   is most obviously missing.

Done and no longer blocking:
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
