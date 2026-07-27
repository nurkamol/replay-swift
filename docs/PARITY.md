# Parity ledger

Where this port stands against the Glaze app. Update it in the same commit as the code —
a ledger nobody trusts is worse than none.

**Level with:** Glaze 2.3.2 (`spec/constants.json` names the commit) · **Verified by:** `swift test` (or `swift run replay-parity`), 852 checks

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
| Canvas | done | the graph drawn as a field of real application icons, with pan that keeps gliding after a flick, pinch-zoom, selection and a way into whatever a node is. Layout is a force simulation run once, seeded from each node's id so the same history lays out the same way |
| Replay Story | done | the camera travels through a memory and the heaviest five things around it, dwelling on each and coming home — narration by motion, no words. The path is `tourPath`, ordered as the reference orders it and tie-broken explicitly; the camera's numbers are contract-checked. The line drawing itself between stops, the breath each stop lets out, and the lean toward the next one are **this port's own** — see the divergences |
| A node under the pointer | done | hover makes a node *active*, which upstream is one state covering three things — the focused node, a story's current stop, and the node being pointed at. Stronger ring, brighter bubble, and it keeps its label where collision would have dropped it, which is how a crowded node's name gets read without clicking it |
| Clear focus | done | a chip opposite the card that drops the selection and lets the field come forward again, Escape bound to it. The reference has the same control in the same corner |
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
| A past day, reopened | done | filters to runs that began that day (SPEC §5); reflection card and export; says so when a day's rows are pruned but its headline survives. Narrated by `DayStory`, and once a day is more than a week old it is placed in the chapter it belonged to with the four nearest days around it — `chapterContext`, tie-broken on `(distance, position)` because a day the same span either side ties exactly |
| Playback clock | done | `Playback` — the day's span mapped onto a fixed half-minute, and which moment a progress lands on. Its two constants are extracted from the reference and checked |
| Replay Day | done | the day played back: one moment at a time, a filmstrip at their real places in the day, scrubbing, three speeds, space to pause, Escape to leave |
| What's New | done | eleven releases, newest first, with the running version marked. Reachable from Help |
| Help menu | done | Welcome, Replay Guide (⌘?), What's New. The app had no Help menu at all, which is also where macOS puts its own search |
| Welcome | done | two pages, and two verification links rather than three — "Privacy & Security" was the parent of the other two and a third button under a green tick reads as a third thing to do. Two pages: the things Replay will not do unasked, each off by default, and the privacy claim shown working rather than asserted |
| Settings | done | General, Privacy, Data, Shortcuts, Guide, About. The Guide is the reference's sixteen questions and answers, generated into `spec/guide.json` and compared character for character. Surfaces (solid/frosted/glass), focus goal, contextual memories and threshold, morning briefing, Dock badge, the screensaver's idle drift and exit conditions, and the three notification recaps — each wired to real behaviour. The Shortcuts table is rendered from `Shortcuts.swift`, the same catalogue the View menu is built from, and `tools/shortcut-audit.mjs` checks the keys a view binds against it in both directions |
| Press and hover feedback | done | `RowButtonStyle` on 25 rows and cards — the reference's own `active:scale-[0.99]` at 90ms and `hover:bg-control-subtle` at 180ms, both on `easeStandard`. Reduced motion keeps the highlight and drops the give |
| Session card (expand, apps, note) | done | app breakdown, tags and a note when expanded; bookmark and delete behind the ⋯; marks and a warmed border when collapsed |
| Export a day / a session | partial | a day, a session, this week, this month, bookmarks, notes — as Markdown, CSV, JSON or HTML, carrying notes and tags. Scope selection and report text checked against the reference's own output. **No PDF** — see the divergence below |
| Dock badge | done | `Preferences.dockBadge`, whole hours only and nothing under one, as the reference has it — `DockBadgeLabel`, contract-checked and unit-tested |
| Memories / Today in History | done | fixed calendar offsets over the durable headlines, so a memory survives its day being pruned; the date arithmetic is fixture-pinned |
| Search | done | by session name, note or tag; by application; and a few phrases ("morning", "longest", "bookmarked") that go straight to a slice — checked against the reference's own predicates |
| Collections | done | derived from the session category — no table, nothing to file. Both orderings tie-broken, with the fixture built so both ties occur |
| Story Mode | done | a reopened day, narrated in a few sentences; five day shapes fixture-checked as text |

### The ledger had been lying about eight rows

`Projects`, `Autobiography`, `Canvas`, `Screensaver / Ambient`, `Replay Movie`, `Contextual
memories`, `Notifications (digests)` and `Dock badge` sat at the foot of the same table
marked **later** — several of them directly contradicting a **done** row for the same
feature a dozen lines above. Every one of them is built: the views exist, the dock badge and
the three notification recaps are wired to real preferences, and upstream's "Replay Movie"
is this port's Replay Day, sharing the `Playback` clock the suite already checks. They were
written when the list was a plan and never struck off as the plan was carried out.

Recorded rather than quietly deleted, because it is the failure this document exists to
prevent — CLAUDE.md's own words are that a ledger nobody trusts is worse than none, and a
row that says *later* about something finished is exactly how the trust goes. The habit that
would have caught it is the one already written down: update the ledger in the same commit
as the code.

**And a ninth, found the same day by acting on it.** `A past day, reopened` was marked
*partial* with "No story or chapter context". Both were built: the view narrates the day
through `DayStory`, and `chapterContext` places any day over a week old in its chapter with
the four nearest days around it — with the `(distance, position)` tie-break spelled out and
three tests covering it, including the case where the day is too recent to have one. The row
was believed over the code, and an afternoon was very nearly spent rebuilding a finished
feature.

That is the cost this document has now demonstrated twice in one day, so it is worth stating
plainly: **an out-of-date ledger is not a tidiness problem, it is a source of wrong work.**
Before building anything this file calls missing, check the code.

### Nothing responded to being pressed, and a green check said otherwise

Every row, card, memory and search result was a `.plain` button: it opened something when
clicked and gave no sign that it *was* clickable, or that the click had landed. The reference
has `hover:bg-control-subtle` and `active:scale-[0.99]` with `active:bg-control` on all of
them. Ported as `RowButtonStyle`, using the reference's own values.

The part worth keeping: `Design.Motion.press` has been in `DesignSystem.swift` since the
beginning, is mirrored into `ParityKit`, and has been checked every run against the
reference's `pressMs: 90` — and **no view had ever used it**. The contract was green on a
number the app never applied to anything. A check can tell you two values agree; it cannot
tell you either one reaches a person. Worth remembering the next time a row of ticks is
mistaken for evidence.

The highlight opacities were measured rather than chosen. A card carries a translucent fill
of its own, which absorbs most of what is put behind it: at the first value the hover moved
the picture by 0.012 mean brightness — real in a diff, invisible to a person.

## What is left

In [BACKLOG.md](BACKLOG.md), not here. This file records what the port *is*; that one records
what it is *not yet*, in the order it is worth doing. Two lists of the same thing is how a
document starts lying, and this one has done it twice already — see the two notes above.

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
- **`NSWorkspace.icon(forFile:)` lies about its size.** It returns an image carrying the
  whole `.icns` ladder — 16 through 1024, each also at 2× — and reports `size` as 32×32
  regardless. AppKit picks a rung by that reported size, so every application icon in this
  app was drawn by scaling the 32-point rung up: invisible in an 18-point row, soft at the
  128 the Canvas uses, and plainly blurry once anyone zoomed the Canvas in. `IconCache`
  hands each view a copy whose `size` is the size that view asked for, which is what
  `NSImageView` has always done and what makes AppKit choose the matching rung. The copies
  share representations, so a second size costs a wrapper rather than a second bitmap. Any
  new use of `NSWorkspace.icon` that skips the cache is suspect.
- **The Canvas camera drifted for as long as it existed, and nothing could have said so.**
  Five values were this port's invention rather than the reference's: the focus zoom (1.8
  against 1.55), how far out the field would go (0.4 against 0.32), one press of zoom (1.35
  against 1.2), a spring where the reference eases out a cubic, and a pan that stopped dead
  where the reference glides. None of it was caught, and the reason is worth keeping: the
  canvas is view code on both sides, so it is not in the contract, and `port-queue.mjs` can
  only report that a UI file changed upstream — never what it now says. It reported nothing
  to port while all five were out. `spec/constants.json` has a generated `canvas` block now
  and the suite checks eighteen of these, which is the only reason the next one will be
  loud. **Any behaviour that lives in a Glaze view is in this blind spot until somebody
  generates it into the contract.**
- **Nothing tied `DesignSystem.swift` to the mirror the suite checks.** `ParityKit` cannot
  import `ReplayApp` — it is an executable — so the motion values are mirrored in
  `MotionChecks.swift` and compared against `spec/`. That comparison never touched the app:
  a value could be changed in the design system and the suite would go on agreeing with
  itself about a number nothing used. `tools/design-audit.mjs` now reads both files and
  fails if a mirrored value differs, which closes the chain — `spec/` fixes the mirror, the
  audit fixes the app to the mirror. Found while porting the canvas camera, which is exactly
  the change that would have slipped through.
- **Three places the canvas port is a mapping rather than a copy**, all because the input
  models differ rather than because anybody chose differently. The glide's decay is per
  *frame* upstream, inside a `requestAnimationFrame` loop, so the same flick coasts further
  on a 60 Hz display than a 120 Hz one; the port keeps the number and reads it at the 60 Hz
  it was written against, decaying by elapsed time. The reference's smooth zoom path is a
  trackpad pinch, which a browser delivers as a wheel event with `ctrlKey` — natively that
  is a `MagnifyGesture`, so what the exponential maps to here is two-finger scrolling, and a
  mouse wheel gets the firm 1.09 notch. And Replay Story sits on the selection card, because
  upstream distinguishes a hover preview from a focused node and this port has one card that
  only ever appears on a real click.
- **Four pieces of Canvas motion have no counterpart upstream, and are labelled here so
  nobody later mistakes them for parity.** The reference's tour is the camera and a lit
  node; the reference's field is still when nothing is happening. This port adds: a line
  that draws itself from the last stop to the current one as the camera flies; a single ring
  each stop breathes out on arrival; a slow lean toward the next stop through the 390ms the
  reference spends holding perfectly still; and a permanent sway — the whole field leaning
  0.6° each way over 44 seconds and drifting around a 6-point ellipse over 63. All four are
  off under reduced motion, and none of them changes a contract-checked number: they use the
  reference's own durations and fill the gaps between them. **If any of this is ever wanted
  in both apps, build it in the Glaze app first** — this is the wrong direction of travel and
  is only acceptable because it is decoration on top rather than behaviour underneath.
- **A local `NSEvent` monitor sees the whole app, and this one ate every scroll in it.**
  Canvas zooms on scroll, which SwiftUI has no gesture for, so it installs a local
  scroll-wheel monitor and returned `nil` from it unconditionally — swallowing the event so
  it could not also scroll whatever was behind. The comment justified that with "this surface
  has nothing else that scrolls", which was untrue when written (the timeline panel sits
  beside the field with a list in it) and became worse when the command palette arrived: with
  Canvas as the current surface, ⌘K opened a palette whose results could not be scrolled by
  mouse or trackpad. Reported, not caught — nothing tests scroll. The monitor now acts only
  when the pointer is over the field and nothing is layered over it, and passes every other
  scroll along untouched.
- **A closure made in `onAppear` freezes every plain property it reads.** The first fix for
  the above added `let paletteOpen` to `CanvasView` and guarded on it, and changed nothing:
  the monitor's closure is built once and captures the view *struct*, so a stored property
  read through that capture keeps its value from capture time for ever. `@State` does not
  behave this way — the wrapper reads shared storage — which is why `pointerInField` worked
  and `paletteOpen` silently did not. It is mirrored into `@State` now. **Any long-lived
  closure in a SwiftUI view is suspect here**: it sees `@State` live and everything else
  frozen, and the failure is invisible — the guard is simply always the old answer.
- **Canvas nodes have hover but deliberately no press.** An animation review flagged that
  nodes never answered being pointed at *or* pressed, and Apple's guidance wants feedback on
  pointer-down. Only half of that is parity: upstream binds `onPointerEnter` and makes a
  hovered node active, and its `onPointerDown` does nothing but stop propagation. So hover is
  ported and press is not. It leaves the app internally uneven — every row presses, no node
  does — and that unevenness is the reference's, which is the tie-breaker CLAUDE.md names. If
  a node should press, it should press in the Glaze app first.
- **Scroll-zoom pinned the wrong point, and the reference says which.** `zoom(by:)` scaled
  the offset uniformly, which keeps the *view centre* still. That is right for the toolbar
  buttons — upstream's `zoomBy` does exactly the same, because a press of a button is not
  aimed at anything — and wrong for a scroll, which is: upstream's `onWheel` preserves the
  point under the cursor, commented "so the memory under the cursor stays put". Zooming
  toward a node used to slide it away from you. Pinch was a third behaviour again, anchoring
  at the field's own origin, because `pinch` scaled `scale` without compensating `offset` at
  all. All three go through one anchored path now, with the anchor at the pointer for scroll
  and pinch and at the centre for the buttons.
- **Grabbing the field mid-flight jumped.** SwiftUI animates the rendered value and will not
  tell you what it is: `offset` and `zoom` hold the *destination* from the instant a flight
  begins. So a drag during a camera move added the translation to where the camera was going
  rather than to where it was, and the field snapped by the remaining distance on release.
  The flight is recorded now — curve, start, duration — so `catchCamera()` can evaluate the
  same `UnitCurve` at the elapsed fraction and commit the value already on screen. **This is
  a general SwiftUI trap, not a canvas one:** any code that reads an animating `@State` is
  reading the target, and the further through the animation it is, the more wrong it is.
- **The sway costs a redraw.** A `Canvas` does not interpolate, so anything that moves inside
  it has to be read off a clock, and a field that is never still needs that clock always
  running. It ticks at a third of the display's rate while the sway is all that is moving,
  and at full rate during the entrance or a story. That is a real cost this surface did not
  used to carry, and it is worth remembering before adding a fifth moving thing.
- **The number keys follow this port's sidebar, not the reference's.** Upstream the sidebar
  is a flat list of ten — Today, Apps, This Week, Timeline, Canvas, Memories, Story,
  Collections, Projects, Search — and ⌘1–⌘9 are near-positional in *that* order. This port
  groups the ten into three sections instead, which is its own decision and a deliberate one,
  but it had kept the reference's numbers: ⌘5 sat on Search at the second row and ⌘2 on Apps
  at the fifth, so the column read 1, 5, 3, 4, 2, 8, 7, 6, 9 top to bottom. The digits run
  1–9 down the sidebar now, and the View menu is ordered and separated to match. A shortcut
  column nobody can predict is worse than one nobody can see — and the keys were only
  coherent in an arrangement this app does not use. **If the sidebar is ever flattened to the
  reference's order, this should go back.**
- **The calendar picker was asked for and never built — here or upstream.** The Glaze
  history specifies Time Travel as "Today / Yesterday / Last 7 Days / Last 30 Days /
  Calendar Picker" (prompt 18). The reference has the four ranges and no calendar picker
  anywhere in its sources. It was dropped without a note, and this port inherited the four
  ranges without it. Recorded so the absence reads as a decision rather than an oversight:
  **building it here would mean shipping something the reference does not have**, which is
  the wrong direction for a port. If it is ever wanted, it belongs in the Glaze app first.
- **A Dock badge is gated by the notification badge permission, silently.** `NSApp.dockTile
  .badgeLabel` accepts a value and reads it back unchanged, and macOS then draws nothing
  unless the app holds that permission — any app linking `UserNotifications` is subject to
  it. This port asked for `[.alert, .sound]` and never `.badge`, so `badgeSetting` was
  `notSupported` and the badge never appeared. Every diagnostic on the app's side looked
  correct, including the read-back, which is what made it hard to find. The permission is
  requested now — but that only helps a fresh install. **macOS fixes the options at the first
  authorization and never re-prompts**, so every Mac that already said yes to Replay's recaps
  reports `notSupported` for ever and no amount of asking changes it. A badge saying how long
  you have been at your Mac is not a notification and should not wait on notification
  permission, so Replay draws its own Dock tile — `DockTileView`, the icon plus a capsule.
  Nothing to grant, nothing to refuse.
- **`NSApp.applicationIconImage` can hand back the generic document icon.** It resolves
  through Launch Services, which caches by bundle path, so a bundle rewritten in place — which
  `scripts/make-app.sh` does on every build — can answer from a stale entry. That is the
  "sometimes" in an app icon that is sometimes missing: nothing is wrong with the icon, the
  lookup is stale. `BundleIcon` reads the `.icns` out of the bundle and keeps `NSApp`'s copy
  as a fallback.
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
  offers one; three attempts here have failed, all in WebKit:
  1. An unattached `WKWebView` never finishes loading.
  2. Attached, `createPDF` hung, with no timeout available on the call itself.
  3. `printOperation(with:)` on an attached view — the route this ledger recommended
     trying — *does* get past loading, and then paginates without end: `run()` never
     returns and the file grows past 100 MB for a sixty-row document. Sizing the view to
     `document.documentElement.scrollHeight` first, which is the usual fix, changes
     nothing. `dataWithPDF(inside:)` on the same view returns an 838-byte empty page,
     because WebKit renders out of process and the `NSView` has nothing to draw.

  The reference's own PDF is capped at a single page and tells the reader to use HTML for
  anything longer, so HTML is the format that actually carries a month. The next route
  worth trying is not WebKit at all — a second document built as a SwiftUI view and
  rendered through `ImageRenderer`'s CGContext — but that is a *second* report to keep in
  step with the HTML one, which is the thing this port's one-body-one-stylesheet rule
  exists to avoid. Until that trade is worth making, the gap is stated here rather than
  half-built.
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

**All 20 of the reference's routes exist.** What remains is the platform work the brief
asks for, one format that has resisted three attempts, and the thing blocked on paperwork.

1. **The brief's platform integrations, none started**: App Intents, Widgets, Spotlight,
   Quick Look, Handoff/`NSUserActivity`, multiple windows and tabs, Services, sound and
   haptics. Two of these — Widgets and App Intents — need extension targets that
   SwiftPM plus a hand-rolled `make-app.sh` cannot produce, so they are a build-system
   change before they are a feature.
2. **PDF export** — see the divergence above. Three routes tried, all dead.
3. **Sign and notarise.** Blocked on a certificate rather than on code — this machine has
   no Developer ID at all. A decision, not a task.
4. **A window sizing trap, three times now.** `NSHostingController` sizes its window to the
   SwiftUI content unless told not to. `hosting.sizingOptions = []` on any window whose
   size is its own. Kept here because it is the mistake most likely to be made again.

Done and no longer blocking:
- ~~Canvas had no focus mode and no synced timeline~~ — selecting a node now pulls the rest
  of the field back, and a panel beside it lists the sessions behind that node, where a
  session opens its day. Each node kind resolves differently and the undated moment is
  pinned: it must find nothing rather than everything.
- ~~A past day had no chapter context~~ — a day older than a week says which chapter it
  belonged to and offers the days either side. Younger than that gets nothing, because a day
  still inside its own chapter has no distance to be seen from.
- ~~Search was well short of the reference~~ — collections, projects, reflections, a
  date-phrase jump, span chips, saved searches and match highlighting all landed. The date
  arithmetic is the part under test: "last month" on 31 March is 3 March in both apps.
- ~~`ExportModel`, `SettingsModel` and `CollectionsModel` had no tests~~ — nine cases, all
  verified by breaking the code they guard. Settings is the one that matters: it is the only
  model that erases, and it erases on a promise.
- ~~The app could only be tinted by the system accent~~ — a theme colour in Settings, macOS's
  own accent palette, carried into every window. The trap was that `NSHostingController`
  builds its `rootView` once, outside any body, so a `.tint` written there is read at
  construction and never again; it takes a `View` (`Themed`) rather than a modifier.
- ~~Replay Day only worked on today~~ — any past day, from the Timeline's ⋯ menu or a
  reopened day's toolbar, with the label travelling alongside the sessions.
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
