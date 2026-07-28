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

- [x] **The field's sway: cut.** Decided 2026-07-28. The Canvas leaned 0.6° over 44 seconds
      and drifted a 6-point ellipse over 63. It rested on preference and preference went the
      other way — it cost a permanent 30fps redraw, sat against Apple's caution about moving
      a whole field, and diverged from a reference whose graph is still. The field is now a
      still picture until you touch it: the `TimelineView` that drove the redraw is gone, and
      with it `sway()` and five motion tokens.
      · Worth remembering *why* `sway()` was a function rather than inline arithmetic: it was
        used by the drawing and the hit test together, so a click always landed where the eye
        had aimed. Removing it had to remove both, or the Canvas would have kept working and
        started missing.
- [x] **A screenshot harness.** Built 2026-07-28, and it answers the question below in a way
      that entry did not anticipate. `./tools/screenshots.sh` drives the app through all
      fourteen surfaces — the nine with a shortcut, Canvas and the two display modes through
      the command palette, Search with a query in it, Settings in its own window — and writes
      a PNG each plus a contact sheet, in under two minutes.
      · **Keyboard only, through the app's own name-based navigation.** Clicking the sidebar
        does not work and that is worth writing down: AppKit reports the row under the
        pointer, `AXPress` returns success, and the selection does not change. Every
        coordinate in the script is a window frame read from the accessibility API rather
        than a guess, because the guesses are what cost four attempts and one stray keypress
        that flipped the user's theme.
      · **Not a UI test, and the distinction is the point.** It makes no assertions. XCUITest
        can say a button exists and is hittable, which is not the question — "does this read
        badly" is, and a person answers it from an image in a second. The bottleneck was
        never whether to check the interface; it was that looking cost a dozen commands of
        window arithmetic each time.

- [x] **A UI test target: no.** Decided 2026-07-28, on evidence rather than taste. Of the
      twelve layout bugs found in a single day, a conventional UI test would have caught
      perhaps three — a focus ring that reads as *armed*, a dead strip under the traffic
      lights, five buttons at five weights and a sentence that reads wrong are all things a
      person sees and an assertion does not. `tools/screenshots.sh` covers the part that was
      actually paying, at a fraction of the maintenance.
      · The original argument still stands on its own terms: the command-palette scroll bug
        reached a person because nothing exercises which view a scroll lands in, and it would
        regress silently. That is one bug's worth of coverage against a permanent burden. If
        this is revisited, revisit it for *that* class — a handful of assertions about
        navigation, not a suite that tries to check appearance.
- [x] **"applications" everywhere.** Decided 2026-07-28, and the interesting part is that
      the project's own rule pointed the other way. CLAUDE.md says Glaze is right when the two
      disagree — but here Glaze disagrees with *itself*, saying "Apps" in the week's stat
      group and "application"/"applications" on its daily memory card. That rule exists to
      stop this port drifting from the reference, not to import the reference's
      inconsistencies, so consistency wins and it is recorded as a deliberate divergence.

## 4 · Blocked on something outside the code

- [ ] **Signing and notarisation.** Needs a Developer ID. `scripts/make-app.sh` ad-hoc signs,
      which runs locally and cannot be handed to anybody. Everything else here is smaller.
      · **This is now the top item on the whole list**, not just this section. Two of the
        three things in §6 worth building — App Intents and a widget — cannot be installed
        without it, so it stopped being only about distribution and became the thing gating
        the next feature. The CLI in §6 is the one item that does not need it.
- [x] **A downloadable build: a signed DMG, released from GitHub.** Built 2026-07-28,
      **and it is waiting on the certificate rather than on any more code.**
      `scripts/make-dmg.sh` builds a real image either way: plain, it makes one for testing
      here and says plainly that Gatekeeper will refuse it anywhere else; `--release` refuses
      to produce anything it cannot sign, notarise and staple, and names the missing variable
      in a second rather than after a full build. `.github/workflows/release.yml` fires on a
      version tag, checks that the tag, `make-app.sh` and the newest changelog entry all say
      the same version, runs every check `parity.yml` runs, and attaches the image with a
      SHA-256. Release notes come from `CHANGELOG.md` via `tools/release-notes.mjs`, so the
      download page and the repository cannot disagree about what shipped.
      · **What remains is six repository secrets and a Developer ID.** The workflow fails at
        a named step until they exist, which is the intended behaviour — see its header for
        the list.
      · **Auto-updates are a separate question, and the answer is currently no.** Sparkle is
        the obvious choice and it is an external dependency, which CLAUDE.md forbids
        outright. That rule has held the project together; it should be changed
        deliberately, in its own decision, rather than sneaked in behind a release process.

- [x] **Homebrew — the other half of "how does anybody get this".** Done 2026-07-28.
      `nurkamol/homebrew-tap` exists with a formula for each: `replay` (the CLI) and
      `replay-app` (the application), both pinned to the current release's tarball with `head` kept so
      `--HEAD` still tracks `main`. The tap's own CI runs `brew test-bot`, which installs and
      tests both for real.
      · **The entry above was wrong about the app, and the correction is the useful part.**
        It said a cask "waits on the same certificate the DMG does". It does not, because the
        app does not need a cask. A cask installs a *prebuilt* binary and therefore needs a
        Developer ID; a **formula builds from source**, and an app compiled on your own
        machine was never downloaded, is never quarantined, and opens with no dialog at all.
        Homebrew prefers casks for GUI apps and is right to — but a cask cannot build, and
        building is precisely what makes this openable. So `--no-quarantine`, argued for at
        length above, turned out to be unnecessary.
      · Two things cost real time. **Homebrew scrubs the environment it hands a build**, so
        `REPLAY_BUILD_FLAGS` never arrived and SwiftPM tried to sandbox inside Homebrew's
        sandbox — `sandbox_apply: Operation not permitted`. `make-app.sh` takes extra flags
        as positional arguments now. And **`brew style` enforces a field order**: `url` and
        `sha256` before `license`. Adding the tagged url below it turned the tap's CI red.
      · Now verified by installing, which the entry above could not be: the CLI installs from
        the tag on this machine.

- [x] **PDF export.** Built 2026-07-28. Not WebKit — `ImageRenderer` returns a `CGContext`
      and a PDF context *is* a `CGContext`, so a SwiftUI view draws straight into a page with
      no browser and nothing to paginate. Every one of the three dead routes died on
      pagination; a single fixed page needs none of it, and one page is what the reference
      caps its own at.
      · **The page is a summary, not the report again.** That answers the objection that
        stopped this before — that a PDF would be a second document to keep in step with the
        HTML one. It counts the whole span in its header and names what it left off ("17 more
        sessions not shown — export as HTML for the whole span"), so the two formats of one
        slice cannot quietly disagree about totals.
      · Times use `timeLabel` twice rather than `formatRange`, which collapses a shared
        meridiem — right on a card, wrong in a document, and already one of the five report
        divergences this port found against the reference.
      · Fonts are fixed points rather than the app's semantic styles: `Font.body` follows
        Dynamic Type, which is right in a window and wrong in a file somebody prints, where
        it would come out a different size on every Mac.
      · 17 behaviour cases, five of which write a real file and read it back with Core
        Graphics — one page, right media box, more than two kilobytes. A PDF export that
        writes a blank or a zero-byte file succeeds from the caller's side, which is exactly
        how the `dataWithPDF` attempt looked until somebody opened the result.

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

- [x] **Auto-start could raise either display, not only the screensaver.** Built 2026-07-29.
      `IdleDisplay` in `Preferences.swift`, a picker at the head of Settings ▸ Display, and the
      idle watch in `main.swift` switching on it. The reference hard-codes
      `openAmbient("screensaver")` in `useScreensaverAutoStart`, so this is additive and
      defaults to its behaviour. An auto-started ambient screen dismisses on any input; a
      hand-started one does not, which is the distinction upstream's "never auto-dismisses"
      comment is really making. Found `acceptsMouseMovedEvents` unset on both full-screen
      windows on the way through — "Exit on mouse movement" had never worked.

- [x] **Which screen a display opens on, and ambient mode left open on it.** Built 2026-07-29.
      `Show on` names the screen; ambient mode on a screen other than the window's becomes a
      non-activating window that stays up while you work. Verified on a two-display desk: the
      main window kept the keyboard with ambient mode up on the other screen.

- [x] **Quiet hours for the idle drift.** Built 2026-07-29. `IdleWindow` in the core, five
      behaviour cases, the midnight-wrapping span among them.

- [x] **Scheduled backups.** Built 2026-07-29. `AutoBackup` decides when one is due, what it
      is called and which old ones go; `AutoBackupModel` writes it. Verified end to end: a
      4,616-row file written unattended at launch, and a ninth copy pruning the oldest while
      an unrelated `taxes.json` in the same folder was left alone.

- [x] **A note and a bookmark from the menu bar.** Built 2026-07-29. The bookmark is a row in
      the panel; the note opens a small panel of its own, because an `NSPopover` never becomes
      key and a text field in one eats its first keystroke and then dismisses the panel. That
      cost an hour and is written down in `PARITY.md` so it costs nobody else one.

- [x] **The light-mode pass.** Run 2026-07-29 with `./tools/screenshots.sh --appearance light`.
      It found the appearance setting reaching two windows out of six — see the ledger. The
      surfaces themselves came back clean.

- [ ] **A border beam, in the one place it would be information.** `S` for the effect, and the
      decision is the whole of the work. `border-beam` (jakubantalik) ships a SwiftUI package —
      `.package(url: "https://github.com/Jakubantalik/border-beam.git", from: "1.4.0")`,
      `import BorderBeamKit`, `BorderBeam(size: .md) { … }` or `.borderBeam(.md, colorVariant:
      .ocean)`. A light travelling around a rounded border.
      · **Taking the package means changing a rule.** CLAUDE.md says no external dependencies,
        and that rule is why this project has nothing to resolve and nothing to vendor. The
        package also advertises iOS 17+, so its macOS support would have to be established
        before it could build here at all. The effect itself is an `AngularGradient` rotated
        by a `phaseAnimator` and masked to a rounded-rect stroke — about thirty lines, with
        its values in `DesignSystem.swift` where the design audit can see them. Reimplementing
        is almost certainly the right call; adopting is a decision somebody should take
        deliberately rather than by `swift package add`.
      · **Where it fits is the narrow part.** SPEC §8 — never gamify, never celebrate, nothing
        asks for attention — rules out the goal card when a goal is met, streaks, session
        cards, and ambient mode, which has exactly one moving thing on purpose. The honest use
        is *work in progress with no known length*: the update banner while it downloads,
        checks and installs.
      · **Do the thing underneath it first.** `SettingsModel.compact()` sets `busy = true` and
        runs `compactSafely()` synchronously on the main actor with `defer { busy = false }`,
        so the flag is never true for a drawn frame — "Compacting…" on that button cannot
        appear, and the window simply freezes for the length of a `VACUUM`. Backup import has
        the same shape. No indicator of any kind, beam or spinner, can help until that work
        moves off the main actor.

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

- [ ] **Multilingual support.** **The groundwork is built (2026-07-28); the translating is
      not, and needs a language and a person before it can start.** What exists now:
      · `Loc` in `ReplayCore` — one table, one bundle, and **the English text is the key**.
        A missing translation therefore falls back to correct English rather than to a raw
        identifier, which matters because half-translated is the normal state of a translated
        app. It also keeps the contract working untouched: the value a parity check sees is
        the same string it always was, and `Loc.base` makes that true on any machine, the same
        seam and the same reason as `Report.Environment` injecting a locale.
      · **Language resolution is explicit**, not left to `Bundle.localizedString`. Measured,
        not assumed: the implicit path did not follow `-AppleLanguages` for a SwiftPM resource
        bundle at all, and could not be tested without relaunching a process. `Loc.string(_:in:)`
        is one function anybody can call with any language, and is the seam a language picker
        in Settings would need.
      · `tools/strings-audit.mjs`, in CI. **270-odd strings across 39 files** is the real size
        of the job — and it is a ratchet rather than a gate, because an audit that failed on
        all of them from the day it was written is an audit nobody runs. Files on its migrated
        list fail on a bare literal; the rest are counted so the number is visible.
      · `MenuBar.swift` is migrated end to end as the worked example, and eight behaviour
        cases cover the mechanism — including that a translation genuinely resolves from a
        `.lproj`, proved against a probe catalogue that lives in the **test** bundle. It is not
        shipped: a `uz.lproj` in `ReplayCore` would make macOS believe Replay supports Uzbek,
        and one translated line among four hundred English ones is worse than no claim.
      · **Done 2026-07-28: every string a reader sees now goes through `Loc`.** The audit
        reports zero. The real number was never 279 — teaching it the shapes it could not see
        (constructor arguments, switch-case returns, multi-line concatenations) put it at
        **664**, of which 408 are `ReplayCore` copy that stays literal on purpose.
      · **One rule, and the contract decides it.** `ReplayCore` holds copy as *keys*; the view
        translates at the point of display. A third of that copy is compared character for
        character against the reference, and `ParityKit` reads the values directly — so a
        definition that resolved through `Loc` would return a translation on a translated
        machine and fail 200-odd checks for a reason unrelated to drift. The exception is a
        function that *composes* a sentence, where the format string is the translatable unit
        and has to go through `Loc` inside the module.
      · Counted nouns go through `Loc.count`, which has two forms — and the limit is written
        down rather than discovered later: Russian has three, Arabic six, Japanese none. A
        `.stringsdict` is the real answer and this is the seam it goes behind.
      · **It crashed the app, and that is the part worth keeping.** Six generated calls had a
        format wanting two or three arguments and were handed one; `String(format:)` then
        reads past its arguments and segfaults. It built, the tests passed, every audit
        passed, and the app died the moment a view drew. Only `tools/screenshots.sh` caught
        it — by failing to find a window. The audit counts specifiers against arguments now.
      · What is left is a translator, and the argument below is why that is a person rather
        than a task.

       `L`+ — **the largest item ever put on this list**, and the
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

- [x] **In-app updates from GitHub releases.** Built 2026-07-28, in the shape this entry
      argued for: **opt-in, off by default, and checking only.** Once a day at most, and only
      while the app is running, it asks GitHub's public releases API whether a newer tag
      exists; if one does, a dismissible bar offers the notes and a link. It downloads
      nothing and replaces nothing.
      · **The decision is in `ReplayCore`, the request is not.** `Updates` parses a version,
        compares two, reads a release out of GitHub's JSON and decides whether a check is
        due — all pure, all tested (74 behaviour cases). `UpdateModel` in `ReplayApp` owns
        the one `URLSession` call. Version parsing is deliberately strict and fails closed:
        anything it cannot read is "no update", because nagging about a release that does
        not exist is worse than being quietly out of date.
      · **Self-update built 2026-07-29.** The banner's button installs rather than opening a
        page. Download the zip, fetch the SHA-256 the release publishes beside it, hash the
        download and compare, extract with `ditto`, check the bundle is signed, is *this*
        application, and is the version that was advertised — then replace and relaunch.
        Staged beside the app rather than in `/tmp`, because `replaceItemAt` needs one volume.
      · **What the trust actually rests on, stated plainly:** HTTPS to a repository named in
        the source, and a checksum published in the same release. That is the Homebrew-formula
        model, and it is weaker than notarisation — it proves the bytes are the ones that
        release carries, not that the release is trustworthy. Anyone who can publish to the
        repository can publish an update. A Developer ID would add authorship; it is still the
        thing worth buying.
      · **It refuses more often than it installs, and that is the design.** A Homebrew copy is
        left to Homebrew, since replacing the bundle would leave `brew` believing it has a
        version it no longer has. A translocated copy has nothing to replace. A read-only
        location refuses rather than half-installing. Eleven behaviour cases cover the
        refusals and the checksum parsing, because the alternative to a correct refusal is
        overwriting somebody's application with a file off the internet.
      · **The claim was amended rather than defended.** README said "no networking code in
        the app at all" and SPEC said "no network of any kind". Both were true and are not,
        so both now say what is actually true: *nothing recorded ever leaves the machine,
        under any setting* — which is the invariant worth having, and the one this feature
        does not touch. The Guide could not be edited the same way, because its sixteen
        answers are compared word for word against the reference and the reference genuinely
        has no network — so `Guide.ownEntries` states the exception alongside them, checked
        in the opposite direction like `OwnSettingsRow`.
      · Still true, and still the better route: **anyone who installed with Homebrew already
        has updates** via `brew upgrade`, with no network code in the app at all.

- [ ] **iCloud, as an option and only ever as an option.** `L` — and the size is the least
      of it. Asked for on 2026-07-28 as a way to keep the record safe rather than to sync it,
      and those are two features with very different costs.
      · **It runs straight into the one invariant this app has left.** SPEC §1 now says
        *nothing recorded is ever transmitted anywhere, under any setting* — the claim that
        survived adding an update check, precisely because the check sends nothing. iCloud
        would be the first thing to send the record itself. That does not make it wrong, but
        it makes it a change to what Replay *is*, not a feature to slot in: it would have to
        be off by default, explained before it is switched on, and stated plainly in the
        README, the Guide and SPEC on the same day the code lands. A switch that quietly
        makes an old promise false is the one failure this project cannot afford.
      · **Backup is much smaller than sync, and is probably the real ask.** The app already
        writes a full backup and already imports one by merging rather than overwriting.
        Dropping that file into `~/Library/Mobile Documents/` on a schedule is a day's work
        and gives you the whole of the safety with none of the hard part. It is one
        direction, it has no conflicts, and a second Mac restores from it by hand.
      · **Sync is the hard part and it is genuinely hard.** Two Macs both recording produce
        two overlapping event streams for the same wall-clock hours, and there is no correct
        merge — you were in front of one of them, and the record cannot say which. Sessions
        are *derived*, so a merge has to happen on raw events and re-derive, and the derived
        titles, notes, tags and bookmarks then have to be reconciled on top. CloudKit gives
        you transport and conflict *detection*; the resolution is a product decision nobody
        has made. Do not start here.
      · **Never put the live SQLite file in iCloud Drive.** A file-sync layer copying a
        database out from under an open connection is how a record gets truncated, and this
        app holds its connection open all day. Export a backup; do not sync the store.
      · **Blocked on the same thing as everything else.** A CloudKit container needs a paid
        Apple Developer account and an entitlement, which is the same certificate §4 is
        waiting on. iCloud Drive via the ubiquity container needs the account too. So this
        cannot even be prototyped until signing is solved.

- [x] **A richer menu bar popover.** Built 2026-07-28. The status item now opens an
      `NSPopover` instead of an `NSMenu`: what you are in and for how long, the day's total
      and session count, the focus goal as a bar, the last three sessions with the icons of
      the applications in them, and a list of actions.
      · **The menu and the popover cannot coexist.** Setting `item.menu` makes AppKit open it
        on mouse-down and the button's own action never fires, so there is no right-click
        fallback — everything the menu held is a row in the popover, and 61 lines of menu
        building went with it.
      · **Buttons were the wrong shape and the render said so.** The first version had five
        controls at five weights — a saturated blue pill, two bordered capsules of different
        widths, two icon squares floated right — in a panel 300 points wide, and the eye went
        to the blue first, which is backwards: the figures are the content and the actions
        are the exits. Rebuilt as equal, quiet rows that highlight under the pointer and run
        edge to edge. Calmer to read and easier to hit, since the target is the full width.
      · Two things only a screenshot could have caught. `focusedFor` produced **"Focused for
        just now"** — fine as a standalone menu row, not a sentence once it sat under an
        application's name; the copy never changed, the context did. And the first row took
        keyboard focus as the panel opened and wore a **focus ring**, which reads as "armed,
        press Return" on a control that pauses recording.
      · Pausing deliberately does *not* close the panel: watching the line change to
        "Tracking paused" is the confirmation, and a panel that vanishes leaves you wondering
        whether the click landed. Everything that opens a window closes it first, so the
        window does not appear underneath.
      · The decisions are in `MenuBar.Popover` with 20 behaviour cases over them. The
        reference has no menu bar at all — it runs inside the Glaze shell — so this surface
        can never be contract-checked, which is the argument for testing what can be tested.

- [x] **A command-line reader.** Built 2026-07-28. `replay today`, `day`, `app`, `export`,
      with `--json` everywhere and `--database` for reading another file. Read-only except
      `export --output`, which writes only where you point it. `tools/cli-audit.sh` checks
      the three things that make a CLI different from a function — exit codes, stream
      discipline, and the shape of `--json` — because all three break somebody's automation
      silently while every sentence still reads correctly by eye.

### Considered and not proposed

- **Sync between Macs.** Kept here, but the reason has changed and the old wording was
  overtaken by events: it used to say sync "would be the first network code in an app whose
  entire claim is that there is none", and as of 2026-07-28 the app has network code — an
  opt-in update check. That check sends *nothing*, which is why the claim that matters
  survived it. Sync would send the record, and that is the actual objection. See the iCloud
  entry in §6, which is where the version of this worth considering lives.
- **Anything that classifies or scores a day.** SPEC §8 — Replay describes, it does not
  grade. A "productivity score" is the most obvious idea in this space and the most clearly
  against what the app is.
- **Live Activities.** iOS only; there is no Mac equivalent to port.

---

## Done

Kept rather than deleted, so the list shows its own history.

- [x] **A landing page**, at `nurkamol.github.io/replay-swift`, published from `website/` by
      a Pages workflow. One hand-written HTML file, CSS inline, no build step — the same rule
      the app is built under. Fifteen screenshots of the app running against a real record,
      each opening full screen, and the Gatekeeper warning on the download rather than behind
      it. Never on the backlog; asked for on 2026-07-28 and built the same day.
- [x] **v0.9.0 released.** 2026-07-28. A source release plus a zipped app, since there is no
      Developer ID and the workflow refuses to attach an unsigned disk image. It publishes a
      *version*, which is what Homebrew builds from and what the in-app update check looks
      for — neither of which needs a certificate.

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
