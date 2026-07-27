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

- [ ] **Settings rows are labelled differently throughout.** `S`
      "Appearance" against upstream's "Theme", "Open on" against "Open to", "Menu bar only"
      against "Menu bar mode". Every feature exists; the words are not the reference's.
      · Same treatment: into `spec/`, compared directly.

- [ ] **Almost no row says what it does.** `M`
      The reference carries **39** per-row descriptions — "Hide the Dock icon and keep Replay
      running in the menu bar", "Appears once you've been active an hour". This port has 12
      footnotes and tooltips between them. Every control works and most are unexplained.

- [ ] **Delete a specific day, from Settings.** `M`
      `deleteDay` exists in the store and the model and is reachable from exactly one place:
      the Timeline's per-day ⋯ menu. So removing a day means finding it in a list first. The
      reference puts a picker in **Privacy ▸ Your data** listing only days it has a record
      of — read from the durable headlines, with today added from the front because today is
      never summarised while it is still being written — bounded by its own
      `DELETABLE_DAYS_WINDOW = 60`, which is uncontracted.
      · Asked for directly in the Glaze history, prompt 83.
      · This is a missing *route* to an existing capability, not new machinery.

- [ ] **About has no What's New button.** `S`
      Upstream puts one on the About tab; here it is reachable only from the Help menu.
      `WhatsNewView` already exists, so this is wiring rather than building.

## 2 · Surfaces nobody has audited

Five audits so far have each found something real — a stagger three times too slow, Today
stacking six cards where the reference shows one, the canvas dimming drifted, its fade and
label rules missing outright. The later-built surfaces look better than the early ones, so
expect thinner results as this goes on. That is still worth knowing rather than assuming.

Each is `M` and the method is the same: read the upstream view beside ours, compare
behaviour first and constants second, and generate anything that matches-by-luck into `spec/`.

- [ ] Memories · Collections · Projects
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
- [x] **A reopened day's story and chapter context** — found already built while starting to
      rebuild it. The ledger was wrong, not the code. 2026-07-28.
