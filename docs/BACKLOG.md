# Backlog

What is left, in the order it is worth doing. **This is the only list of remaining work** —
[PARITY.md](PARITY.md) records what the port *is*, this records what it is *not yet*. If a
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
- [ ] Story, Chapters, Autobiography
- [ ] Museum · My Story · App history · Relationships
- [ ] Replay Day · Screensaver · Welcome

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

- [ ] **`improve-animations` across the app.** Read-only; produces a prioritised audit and
      plans. Worth running *now* and not before: the canvas camera, both staggers and the
      field constants are contract-checked, so a proposal that moves a pinned value fails
      loudly rather than landing silently.
- [ ] **`apple-design` on Replay Day's scrubbing and the screensaver's drift.** The two
      surfaces with real gesture work that have had none of the treatment the Canvas got.
- [ ] **Hold `find-animation-opportunities`.** It proposes *new* motion, and the Canvas gained
      four moving things on 27 July that nobody has lived with yet. Revisit once they have
      been used for a while.

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
