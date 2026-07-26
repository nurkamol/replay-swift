# Parity ledger

Where this port stands against the Glaze app. Update it in the same commit as the code —
a ledger nobody trusts is worse than none.

**Level with:** Glaze 2.3.1 (`9dcd1bb`) · **Verified by:** `swift test` (or `swift run replay-parity`), 188 checks

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
| Bounded rebuild | done | the fix that stopped an import erasing pruned days |
| Retention prune | done | keeps headlines |
| Delete a session / a day | done | via the tracker, so in-memory state stays honest |
| Orphaned-annotation pruning | done | reachability, not by application |
| Compaction + thresholds | done | `reclaimableBytes` documented as a lower bound |
| Compaction safety (copy, verify) | todo | the store has the pieces; the sequence is not wired |
| Reflections | todo | table exists; no read/write yet |
| Annotations (notes, bookmarks, tags) | todo | table and pruning exist; no read/write yet |
| Backup export / import | todo | needed for migration off Glaze — see SYNC.md |

## App — the surfaces

| capability | status | notes |
|---|---|---|
| Menu bar item | todo | `NSStatusItem`; current app + pause |
| Today | todo | v1 |
| Timeline (days, dividers, ⋯ menus) | todo | v1 |
| A past day, reopened | todo | v1 — **must filter to runs that began that day** (SPEC §5) |
| Settings | todo | v1: General, Privacy, Data/Storage, Guide, About |
| Session card (expand, apps, note) | todo | v1 |
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
- **The parity suite is the only test coverage.** It runs both as `swift test`
  (swift-testing, needs `DEVELOPER_DIR` set to the Xcode beta) and as
  `swift run replay-parity` (no Xcode). It covers the core thoroughly and everything else
  not at all — the tracker's timing behaviour and anything in the UI are unverified.

## Next three things

1. **Backup import**, so a Glaze user's history can move over and the port has real data
   to develop against. Format is pinned in `spec/constants.json` (`replay.activity` v1).
2. **Menu bar item + Today**, the smallest thing that is recognisably Replay.
3. **Timeline**, with the session card and its ⋯ menu.

~~Prototype the icon API under App Sandbox~~ — **done**, and it works with no entitlement.
See [FINDINGS.md](FINDINGS.md).
