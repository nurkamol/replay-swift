# Roadmap — superseded

> **This document is history, not a plan.** Every feature it argued for has been built, and
> two of the things it filed under *"later, and honestly maybe never"* — the Canvas and
> Ambient mode — shipped. **`docs/BACKLOG.md` is the only list of remaining work**; if this
> file and that one disagree, that one is right.
>
> It is kept because the *arguments* were the useful part, and because a roadmap that was
> wrong about what mattered is worth being able to re-read. Retired 2026-07-28.
>
> The one item here that outlived it — that the interface has no test coverage — is now an
> open decision in `docs/BACKLOG.md` §3, where it can actually be answered.

---

## Now

### 1. Memories — "what were you doing on this day"

The smallest of the deferred subsystems and the one that pays for itself immediately,
because **it works on data the port already keeps**. Daily headlines survive the retention
window by design (SPEC §6), so a year-old day still has an active total and a top app long
after its raw events are gone. That is exactly what "on this day, last year" needs.

Everything else in this section needs new tables or new derivation. This needs a query.

**Scope:** a Memories surface listing days from earlier years that share today's calendar
date, plus a card on Today when one exists. Reads `daily_summaries`; no schema change.

### 2. Sign and notarise a build

The gap between "it works" and "you can hand it to someone". `scripts/make-app.sh` already
signs ad-hoc and is written to take a real identity when one exists.

**Blocked on a certificate, not on code.** This machine has no Developer ID at all, so the
next move is a decision — whether to pay for an Apple Developer account — rather than a
task. Worth deciding before the memory subsystems, because it changes who the work is for.

---

## Next

### 3. Collections and Projects

Grouping sessions by what they were *about* rather than when they happened. Both are
derived rather than stored in the reference, which means they belong in `ReplayCore` beside
the session derivation and can be pinned with fixtures the same way.

Collections come first: they key off the session category, which the port already computes
and checks. Projects need detection logic that has no equivalent here yet.

### 4. Story Mode

A day narrated back in a few plain sentences, built only from sessions already on screen.
Small, self-contained, and the one place the app's voice (SPEC §8) does the most work — a
sentence that overclaims is worse than no sentence.

### 5. PDF export

Dropped once, deliberately. If it returns, the route worth trying is an `NSPrintOperation`
against a real window rather than WebKit's PDF API, which hung twice. Low priority: the
reference's own PDF is a single page and tells the reader to use HTML for anything longer,
and HTML is built.

---

## Later, and honestly maybe never

- **Canvas.** A project of its own, and the largest thing in the reference. It would double
  the size of this port.
- **Contextual memories.** The largest subsystem after Canvas.
- **Notifications and digests.** Needs `UNUserNotificationCenter` authorisation — the first
  permission prompt this app would ever show, which is a decision about what Replay *is*
  and not a feature to slide in.
- **Screensaver / Ambient, Replay Movie, Autobiography.** Presentation layers over data
  that already exists. Pleasant; not load-bearing.

---

## Standing work, not features

These do not finish, and they are the reason the port stays trustworthy.

- **Stay level with the reference.** `node tools/port-queue.mjs` at the start of a session
  says what has moved upstream. The contract is regenerated, never hand-edited.
- **Shrink the "verified by reading" list.** Every surface added by running the app and
  looking at it is weaker than one pinned by a fixture. Two rounds of this have each found
  real divergences the eye had missed; there is no reason to think the third would not.
- **The interface has no test coverage at all.** The suite covers the core thoroughly and
  the UI not at all. Closing that needs a different kind of harness than `spec/` provides,
  and is the largest quiet risk in the project.
