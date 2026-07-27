# Animation plans

Produced by `improve-animations` against commit `6354afc` on 2026-07-28, auditing
`Sources/ReplayApp` against the eight categories in the skill's `AUDIT.md`.

**Headline: the motion in this app is largely already right.** No `easeIn` anywhere, no
`transition: all` equivalent, no `scale(0)`, no animation on keyboard-driven navigation,
reduced motion plumbed through a single `MotionPreference` wrapper, asymmetric press/release
timing, two deliberately different stagger scales, and a Canvas that already tiers its
redraw rate. Three of the eight categories produced nothing. What follows is what survived
vetting — one real seam and two pieces of housekeeping.

| # | Plan | Severity | Category | Contract impact | Status |
| --- | --- | --- | --- | --- | --- |
| 001 | [Tour drift velocity seam](001-tour-drift-velocity-seam.md) | MEDIUM | Interruptibility & physicality | None | DONE |
| 002 | [Heatmap range cross-fade](002-heatmap-range-crossfade.md) | LOW (additive) | Missed opportunities | None | DONE |
| 003 | [Retire dead motion declarations](003-retire-dead-motion-declarations.md) | LOW | Cohesion & tokens | None | DONE |

None of the three moves a contract-checked value. The parity suite must report **882
checks** before and after each.

## Recommended order

**001 → 002 → 003.** No hard dependencies; the order is by value.

- **001** is the only finding that changes how something *feels*. Do it first and alone, so
  the feel check is not confounded.
- **002** is additive and independent.
- **003** touches seventeen files but must produce no visible change, so it is the safest to
  batch and the easiest to verify — run it last, when nothing else is in flight to confuse
  "nothing changed" with "nothing was checked".

One soft interaction: 003 deletes unused `@Environment(\.motion)` declarations, and 002 adds
a genuine one to `MemoriesView`'s `Heatmap`. If 002 lands first, 003 must leave it alone —
noted in 003's boundaries.

## Considered and deliberately not reported

Per the skill's Hard Rule 5, documented deliberate tradeoffs are noted, not re-litigated:

- **The Canvas sway** — 0.6° over 44s plus a 6pt ellipse over 63s, costing a permanent 30fps
  redraw. Already an open decision in `docs/BACKLOG.md` §3 with the argument written out on
  both sides, and it is the user's call rather than an audit's.
- **The screensaver's `.linear(...).repeatForever(...)`** — correct. AUDIT §2 puts constant
  motion on a linear curve, and this is a marquee. It also handles reduced motion by
  *slowing* from 90s to 240s rather than stopping, which is what "fewer and gentler, not
  zero" means.
- **The command palette's 120ms fade** — AUDIT §1 says a palette opened by reflex should
  have no animation at all (Raycast has none). At 120ms with no movement this is close
  enough to none that the difference is theoretical, and the reasoning is written into the
  token. Only the comment was wrong; 003 fixes that.
- **No transition on sidebar section changes** (`RootView.swift:600`) — correct and load
  bearing. ⌘1–⌘9 is a keyboard action hit many times a day, which AUDIT §1 says gets no
  animation, ever. Each surface's own `.settlesIn(_:)` stagger is the arrival cue. 002's
  boundaries call this out so it does not get "fixed".

## What could not be judged from code

The tour's flight-to-drift seam (001) is confirmable by reading — an ease-out ending at
zero velocity followed immediately by a constant-velocity ramp is a discontinuity on paper.
But *how much* it shows depends on the drift share and the field's scale at that zoom, and
that can only be settled by watching it. 001's feel check says so and asks for a
side-by-side.
