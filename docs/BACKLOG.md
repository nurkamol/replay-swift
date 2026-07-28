# Backlog

What is left, in the order it is worth doing. **This is the only list of remaining work** —
[PARITY.md](PARITY.md) records what the port *is*, this records what it is *not yet*.

Sections 1–5 are all one kind of thing: catching up with the reference, or unblocking a
build. **§6 is the first that is not.** Everything Replay does today exists because the
Glaze app does it, and "is this right?" has had an answer that could be looked up. Beyond
parity there is no reference to check against and no contract to generate — the questions
become ordinary product questions, answered by argument rather than by `sync-spec.mjs`.
Worth keeping in its own section for exactly that reason: the discipline that has served
this port does not apply there, and pretending otherwise would be the easiest way to lose
it. If a
task is finished, tick it here and update the ledger in the same commit; if a task turns out
to be already done, say so here rather than deleting the line, because that has happened
twice and both times it cost real work.

**Before starting anything on this list, check the code.** The ledger has been wrong twice —
eight rows marked *later* for shipped features, and a *partial* row for a finished one that
sent an afternoon toward rebuilding it. A line here is a claim about the code, not evidence.

Sizes are honest guesses: **S** an hour or so · **M** half a day · **L** a day or more ·
**?** unknown until someone looks.

---

## 1 · Settings, from the audit of 2026-07-28

The largest remaining gap in the app, and it is all user-facing words — which SPEC §8 calls
the product.

- [x] **The Guide answers four questions; the reference answers sixteen.** `S`+`M` — done
      2026-07-28. Generated into `spec/guide.json`; 33 checks; an apostrophe fails it.
      Not one of ours is upstream's — different questions, different wording. Ours: what
      Replay records, permissions, what a session is, why the file does not shrink. Upstream
      also covers where the data lives, why Memories is empty, what Collections/Projects/the
      Canvas are, what Contextual Memory Intelligence is, reflections and Replay Day,
      excluding an app, deleting a session, deleting a day, disk space, whether notifications
      cost anything, starting and closing the screensaver, keeping a copy, pausing tracking.
      · Where: `Sources/ReplayApp/SettingsView.swift` `GuideTab.entries`, upstream
        `renderer/settings/settings-view.tsx` `const FAQ`
      · **Generate it into `spec/`** rather than retyping it, the way `describeBreak` is. Then
        it cannot drift, and the sixteen answers stay the reference's rather than becoming
        sixteen paraphrases.
      · Done when: the suite compares all sixteen question-and-answer pairs character for
        character, and changing one word fails it by name.

- [x] **Settings rows are labelled differently throughout.** `S` — done 2026-07-28.
      Eight were wrong. `spec/settings-copy.json` carries all 36 of the reference's labels
      and `SettingsRow` in `ReplayCore` carries the 27 this port has; the suite checks every
      one belongs. Comparing the two lists is what surfaced the two items below.

- [x] **A separate "Today in History" toggle.** `S` — done 2026-07-28. Two independent
      switches now, Living Home reads the right one, and Memories leaves the sidebar when
      looking back is off, as upstream.

      ~~Original entry:~~ `S`
      Upstream has two independent switches where this port has one. `todayInHistory` shows
      the memory card on Today and the Memories view in the sidebar; `contextualMemories` is
      the quieter thing that surfaces a memory when it becomes relevant. This port has only
      the second, so Living Home reads `contextualMemories` where it should read
      `todayInHistory` — turning contextual memories off currently also removes
      today-in-history from the hero rotation, which is not what either switch means.
      · Found by diffing the reference's row labels against ours.

- [x] **Reset Replay.** `M` — done 2026-07-28. `Preferences.reset()` forgets every key this
      type owns — not `removePersistentDomain`, which would also take window frames and the
      other things `UserDefaults` keeps on the app's behalf.

      ~~Was:~~ `M`
      "Deletes all activity, settings, and preferences, then returns to the welcome screen."
      This port has Clear History, which removes activity and leaves every preference behind,
      so there is no way back to a first run. Destructive, so it wants the same confirmation
      Clear History has — SPEC §8: name what it will remove.

- [x] **Seven controls still say nothing.** `S` — done 2026-07-28. All eighteen named
      controls render the reference's line now.

      ~~Was:~~ `S`
      All 29 of the reference's descriptions are in `spec/settings-copy.json` and in
      `SettingsRow.explanation`, checked character for character. **Eleven of the eighteen
      named controls render theirs**; the remaining seven are `Picker`s and multi-line
      controls that `.explains(_:)` was not applied to, because appending a modifier to a
      one-line `Toggle` is a safe mechanical edit and reaching into a picker's body is not.
      Nothing is missing from the contract — this is finishing the rendering.
      · Was: the reference carries **29** per-row descriptions — "Hide the Dock icon and keep Replay
      running in the menu bar", "Appears once you've been active an hour". This port has 12
      footnotes and tooltips between them. Every control works and most are unexplained.

- [x] **Delete a specific day, from Settings.** `M` — done 2026-07-28. A bounded picker in
      Data ▸ Storage, days read from the durable headlines with today added from the front,
      `deletableDaysWindow` contract-checked at the reference's 60.

      ~~Was:~~ `M`
      `deleteDay` exists in the store and the model and is reachable from exactly one place:
      the Timeline's per-day ⋯ menu. So removing a day means finding it in a list first. The
      reference puts a picker in **Privacy ▸ Your data** listing only days it has a record
      of — read from the durable headlines, with today added from the front because today is
      never summarised while it is still being written — bounded by its own
      `DELETABLE_DAYS_WINDOW = 60`, which is uncontracted.
      · Asked for directly in the Glaze history, prompt 83.
      · This is a missing *route* to an existing capability, not new machinery.

- [x] **About has no What's New button.** `S` — done 2026-07-28.

## 2 · Surfaces nobody has audited

Five audits so far have each found something real — a stagger three times too slow, Today
stacking six cards where the reference shows one, the canvas dimming drifted, its fade and
label rules missing outright. The later-built surfaces look better than the early ones, so
expect thinner results as this goes on. That is still worth knowing rather than assuming.

Each is `M` and the method is the same: read the upstream view beside ours, compare
behaviour first and constants second, and generate anything that matches-by-luck into `spec/`.

- [x] **Memories · Collections · Projects** — audited 2026-07-28. Eight findings, all fixed;
      the heatmap was the substance of it. See the ledger. Two things worth carrying into the
      remaining audits: the reference staggers *each card*, and this port kept applying the
      stagger to the container, so three surfaces arrived as a block; and both of Memories'
      "no data" paths were whole-page empty states where upstream empties one section and
      leaves the rest of the screen usable.
- [x] **Story, Chapters, Autobiography** — audited 2026-07-28. Almost the whole of these
      three surfaces is prose and nothing held any of it: every subtitle and empty state was
      a paraphrase and both footnotes were missing outright. Generated into
      `spec/narrative-copy.json`; 22 checks. Also: Story's rituals section vanished when
      empty rather than explaining itself — the same mistake Memories made — and the hub
      cards arrived as a block rather than one at a time.
- [x] **Museum · My Story · App history · Relationships** — audited 2026-07-28. Twelve more
      checks. **My Story was missing a whole section**: the reference has Years, *Growth* and
      Favourite applications, and this port had two of the three — found by diffing the
      section labels, not by reading the code. It also had no subtitle at all. Four of the
      museum's five rooms were renamed, and both "nothing here" states said "the kept
      history" where the reference names the window: thirty days.
- [x] **Replay Day · Screensaver · Welcome** — audited 2026-07-28. **Section 2 is done.**
      Replay Day's constants were already contracted and correct; the screensaver's drift
      matched exactly and is now checked rather than merely agreeing. Welcome turned up a
      real bug — see the ledger — and one missing surface, below.

## 2b · Found by the audits

- [x] **Ambient Mode.** Built 2026-07-28. Reached by ⇧⌘A, the View menu, the palette's new
      **Display** group and the sidebar footer. Its breath is contracted at the reference's
      6s / 1.04 / 0.96 and checked. **Section 2b is closed.**

      ~~Was:~~ `M` The reference has *two* display modes behind its command palette —
      Ambient Mode and Screensaver — and this port has only the screensaver. Ambient is a
      distraction-free full-screen clock: today's total at 72–180px, the current session, a
      six-second breathe that stops under reduced motion. `renderer/main/ambient.tsx`
      lines 140–248; the mode switch is `AmbientMode = "ambient" | "screensaver"` at line 26
      and the palette entry is `command-palette.tsx:253` under a **Display** group, with
      keywords "ambient, focus, second monitor, big, now, distraction free".
      · Found auditing the screensaver on 2026-07-28. It is a *mode*, not a route, which is
        why the "all 20 routes" count in CLAUDE.md missed it — worth remembering that the
        route count is not a completeness measure.
      · This port's screensaver already solves the hard parts (a borderless full-screen
        window, the exit affordance, the arm delay), so most of this is the view.

## 3 · Waiting on a decision, not on work

These are not blocked by difficulty. They are blocked because they are somebody's call.

- [ ] **Keep or cut the field's sway.** The Canvas leans 0.6° over 44 seconds and drifts a
      6-point ellipse over 63. It clears Apple's specific caution about slow oscillation, sits
      against its general one about full-field motion, costs a permanent 30fps redraw, and
      diverges from a reference whose field is still. It rests on preference, not principle.
- [ ] **Does this repo take a UI test target?** The command-palette scroll bug reached a
      person because nothing exercises which view a scroll lands in, and it would regress
      silently. There are no UI tests at all today, so this is a question about what the
      project is willing to carry rather than a chore.
- [ ] **"applications" or "Apps" in the week's stat group?** The reference says "Apps" here
      and "application"/"applications" on its own daily memory card, so it disagrees with
      itself. This port is consistent. Worth deciding rather than guessing — see the ledger.

## 4 · Blocked on something outside the code

- [ ] **Signing and notarisation.** Needs a Developer ID. `scripts/make-app.sh` ad-hoc signs,
      which runs locally and cannot be handed to anybody. Everything else here is smaller.
      · **This is now the top item on the whole list**, not just this section. Two of the
        three things in §6 worth building — App Intents and a widget — cannot be installed
        without it, so it stopped being only about distribution and became the thing gating
        the next feature. The CLI in §6 is the one item that does not need it.
- [ ] **PDF export.** Three WebKit routes tried and dead — recorded in the ledger's
      divergences so a fourth person does not repeat them. Reviving it means leaving WebKit
      and drawing the report into a `CGContext` by hand. `L`.
      · **Weightier than it looks.** Six of the 110 prompts that built the Glaze app are
        about the PDF and nothing else — pagination, items overflowing the canvas,
        overwriting an existing file, a footer note. That is more attention than any other
        single feature in that history. It does not change the recommendation, since the
        three WebKit routes really are dead, but "one capped page nobody uses" understates
        what it cost upstream and how much it was wanted.

## 5 · The animation skills, and when to spend them

Installed at `~/.claude/skills/`: `apple-design`, `animation-vocabulary`,
`find-animation-opportunities`, `improve-animations`. All web-oriented — the principles carry,
the implementation guidance does not.

- [x] **`improve-animations` across the app.** Run 2026-07-28. Three of eight categories
      produced nothing; three findings survived vetting and all three are applied. Plans and
      the reasoning — including what was deliberately left alone — are in `plans/`.
- [x] **`apple-design` on Replay Day's scrubbing and the screensaver's drift.** Run
      2026-07-28. The screensaver came back clean. The scrubber answered a drag but never
      said it had been grabbed, and was a 12-point target; both fixed.
- [ ] **Hold `find-animation-opportunities`.** It proposes *new* motion, and the Canvas gained
      four moving things on 27 July that nobody has lived with yet. Revisit once they have
      been used for a while.

---

## 6 · Beyond parity — this port's own ideas

Nothing here exists in the Glaze app, so nothing here can be generated, contract-checked, or
settled by reading the reference. Sized, ordered, and with the real costs named — but none of
it is decided, and the sizes are the least trustworthy in this document because there is no
existing implementation to measure against.

**Both of the first two are gated on signing (§4).** An App Intent nobody can install and a
widget that cannot be registered are each worth zero. That moves signing from "blocked, and
awkward" to the top of the whole list.

**One of these is not like the others.** Multilingual support is larger than everything else
on this page put together, and it is the first item in the project's history that cannot be
checked against anything — see its own note. It sits here rather than in a section of its own
because it is still a product decision nobody has taken.

- [x] **App Intents / Shortcuts support.** Built 2026-07-28. Three read-only intents —
      today's activity, a given day, and time in one application — with Siri phrases, and six
      behaviour cases over the sentences they return. `scripts/make-app.sh` runs
      `appintentsmetadataprocessor` itself, because SwiftPM does not and the failure mode is
      an app that silently has no Shortcuts support. **End-to-end discovery in Shortcuts.app
      is unverified** — see the ledger; it may need a signed build in `/Applications`.

      ~~Was:~~ `M` The best fit and the cheapest. "How long was I
      in Xcode today?", "What did I do on Tuesday?", "Start a reflection." Read-only, needs
      no permission, and reuses `ReplayCore` unchanged — the derivations it would call are
      already pure functions with a contract behind them. It also makes Replay scriptable and
      reachable from Spotlight for free.
      · **Do this one first.** It is the only item here with no architectural cost, and it
        would tell us whether the core's API is actually pleasant to call from outside the
        app, which nothing has tested.

- [ ] **A widget.** `L` Today's total, the application in front, the streak. The right shape
      for this product — it is a glanceable figure the app already computes, and ambient mode
      is evidence somebody wants that figure without opening a window.
      · **The cost is not the view.** Widgets run in a separate process, so the extension
        cannot read `~/Library/Application Support/app.replay.native/activity.db` where the
        database lives today. It needs an **App Group container**, which means migrating the
        database of every existing install.
      · **That is a one-way door**, and the only one on this list. A half-finished migration
        loses somebody's history, which is the one thing this app exists to keep. It wants a
        written plan, a backup taken before the move, and a verified read-back afterwards —
        not an afternoon.
      · Worth checking first whether the widget could read the *daily headlines* only, which
        are small and could be mirrored into the group container rather than moved. That
        would make it additive instead of a migration, and today's total is a headline.

- [ ] **Multilingual support.** `L`+ — **the largest item ever put on this list**, and the
      only one that cannot be finished by the person who starts it.

      The reference is English-only: it reaches for `Intl` to format a date and nothing
      else. So there is no parity to catch up to here, and no contract to generate — which
      makes this the purest §6 item on the page, and the one where being wrong is most
      expensive.

      **What is already done, and it is more than it looks.** Dates, times, durations and
      weekday names all go through `.formatted()` and the calendar's own symbols, so they
      are locale-correct today. The heatmap reads `veryShortStandaloneWeekdaySymbols`; the
      week starts on Monday by rule rather than by locale, which is deliberate and stays.
      Nothing has to be unpicked to begin.

      **What the work actually is**, in rising order of difficulty:
      · **~162 literal strings in views.** Mechanical. A string catalogue and a pass.
      · **28 files pluralise by hand** — `count == 1 ? "session" : "sessions"`. English's
        one-or-many is the exception, not the rule: Russian needs three forms and Arabic
        six. Every one of these becomes a proper plural rule, and a wrong one is not a typo
        but a sentence that reads as broken.
      · **Sentences assembled from clauses.** `Answers`, `DayStory`, `Autobiography`,
        `MorningBriefing` build prose by joining parts. Word order is not universal, so
        each becomes a format string with positional arguments — and some will need
        rewriting rather than translating, because a clause that works appended in English
        may have to be a whole sentence elsewhere.
      · **The layout.** German runs long, and this design uses fixed widths and tracked
        capitals in places. Right-to-left is a second pass again.
      · **The build.** `.xcstrings` are compiled by an Xcode build phase, and this project
        assembles its bundle by hand — the same problem App Intents had. It is solved once
        now, in `make-app.sh`, so the shape is known.

      **The contract is not in the way, and it is worth saying so plainly.**
      `spec/settings-copy.json`, `spec/guide.json` and `spec/narrative-copy.json` pin the
      reference's English character for character. Localising does not weaken that: English
      stays the source language and stays checked. Translations sit beside it, unchecked by
      anything — which is the actual risk, and it is a new category for this project.
      Everything user-facing here has been verifiable against something. Translated copy is
      the first thing that will not be.

      **Do not machine-translate it.** SPEC §8 says the copy *is* the product, and this
      app's voice is unusually deliberate — "nothing set, nothing scheduled", "a day too
      thin to narrate honestly gets no story". A flat translation does not deliver a
      partial version of that; it delivers a different, worse product that happens to be in
      your language. The first non-English language should be one the author actually
      speaks, and it should be treated as rewriting the app in that language rather than
      substituting words.
      · Worth doing **one** language properly first and living with it, rather than three
        at once. The first one will surface every structural assumption; the second will be
        a tenth of the work.

- [ ] **A richer menu bar popover.** `S` The item exists and shows the current app and
      today's total. A small popover — the last few sessions, the goal, a pause control —
      is cheap and does not need signing to try.

- [ ] **A command-line reader.** `S`–`M` `replay today`, `replay export --json`. Falls out of
      `ReplayCore` almost free, is genuinely useful for anyone who scripts, and is the one
      thing here that can be built and used *without* a Developer ID. A reasonable
      consolation while signing is blocked.

### Considered and not proposed

- **Sync between Macs.** It would be the first network code in an app whose entire claim is
  that there is none. Not a feature to weigh against others; a different product.
- **Anything that classifies or scores a day.** SPEC §8 — Replay describes, it does not
  grade. A "productivity score" is the most obvious idea in this space and the most clearly
  against what the app is.
- **Live Activities.** iOS only; there is no Mac equivalent to port.

---

## Done

Kept rather than deleted, so the list shows its own history.

- [x] **Living Home** — Today leads with one card, rotated by day, resume-within-six-hours
      overriding. 2026-07-27.
- [x] **Replay Story** and the five drifted canvas camera values. 2026-07-27.
- [x] **One catalogue for shortcuts**, feeding the View menu, the Settings table and the
      sidebar hints, with `tools/shortcut-audit.mjs` checking both directions. 2026-07-27/28.
- [x] **The contract reaches the views** — Timeline ranges, Search, Today, the canvas field,
      Apps windows, week limits. 696 checks to 761. 2026-07-27/28.
- [x] **`design-audit.mjs` ties `DesignSystem` to the parity mirror**, closing the hole where
      a value could move in the app and the suite would go on agreeing with itself.
- [x] **The Guide's sixteen answers**, generated rather than retyped. 2026-07-28.
- [x] **Settings row labels**, eight of them wrong, now checked against all 36 of the
      reference's. 2026-07-28.
- [x] **Every Settings row explains itself**, all 29 of the reference's descriptions,
      and What's New on the About tab. 2026-07-28.
- [x] **Delete a single day, and Reset Replay** — the last two rows Settings was missing.
      2026-07-28.
- [x] **Memories, Collections and Projects audited** — eight findings, including a heatmap
      that shaded days against the busiest day rather than against fixed amounts of time.
      2026-07-28.
- [x] **The Dock badge shows whole hours**, as the reference does — it had been formatted
      with hours *and* minutes. 2026-07-28.
- [x] **A reopened day's story and chapter context** — found already built while starting to
      rebuild it. The ledger was wrong, not the code. 2026-07-28.
