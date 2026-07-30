# Changelog

What has changed in the native port, newest first.

This is a port, so "added" usually means *reached parity with the Glaze app on*, and the
interesting entries are the ones where the two implementations disagreed. Those are called
out, because a divergence found is worth more than a feature shipped: it is the only thing
that tells you the contract is doing its job.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**This port carries its own version and states which Glaze release it is level with.** The
two are not the same number and should not be: they are different codebases at different
stages, and this one has no 2.3.1 to have shipped. So an entry reads "0.9.0 … level with
Glaze 2.3.2", and the reference's version moves without dragging this one along. (This
paragraph used to say versions *followed* Glaze's, while the entry below was numbered
independently — the document asserted both schemes at once.)

**1.0.0 is reserved for the first build that can be handed to somebody**: signed with a
Developer ID and notarised. Everything before it is a version of the source.

## 0.9.8 — 2026-07-30

### Added

- **The permissions Replay does not use now have rows, in Settings ▸ Privacy and on the welcome
  screen.** Each says where it stands and what it is for; **Reset** takes back anything granted
  earlier, which was previously impossible from inside the app.
  - **Accessibility's button asks macOS to prompt**, which puts Replay *in the list* — so all
    that is left is the switch. The two buttons here before opened System Settings and stopped,
    leaving somebody to press `+` and find Replay in `/Applications` by hand.
  - **App Management has no button of that kind, because macOS offers none.** No app can read
    or request it, so the row says so rather than showing a tick that would be a guess.
  - **Every row offers a way in and, where there is something to undo, a way out** — so a
    permission can be granted, taken back and granted again without leaving Settings. App
    Management always offers **Reset**, precisely because macOS will not say whether it is on:
    hiding the button until a permission "looks" granted would have made the one thing nobody
    can check also the one thing nobody could undo.
  - Nothing here is required and the rows never imply otherwise: no red, no warnings, no
    "action needed". Every row off is the state Replay is built for.
  - No password is ever asked for. macOS collects authorisation in its own window; an app that
    put up a password field to approve a toggle would be collecting a credential it has no
    business seeing, and it would not work anyway.

- **Replay runs on macOS 14 Sonoma.** It required macOS 26 before, which is a version most
  Macs are not on. Exactly two calls in the interface needed something newer — the system's
  glass material (26) and a colour blend (15) — found by building the app against each floor
  in turn rather than by reading the code. Both are guarded, so three OS generations gained
  the app and nothing about it changed on a current Mac.
  - Below macOS 26 the **Surfaces** setting offers Solid and Frosted, and not Glass. A
    setting that silently did nothing would be worse than one that is not there.
  - A `Glass` preference carried over from a newer Mac — in a backup, or across an account —
    draws as Frosted rather than as nothing.
  - macOS 13 is not reachable the same way: the models are built on Observation, which begins
    at 14. That is a rewrite rather than a guard, and it is not planned.

- **A report on a schedule.** Settings ▸ Data writes a report of the period that has just
  *finished* — yesterday, or the week just gone — into a folder you choose, as Markdown or
  HTML, keeping the eight most recent and removing only its own. The sibling of the scheduled
  backup and deliberately the same shape, with one difference worth stating: a backup is
  insurance you hope never to open, and this is the one file in the app meant to be read.
  - Past tense on purpose. A report of a day at two in the afternoon is wrong by six.
  - A period with nothing in it writes no file. A folder that fills with "nothing happened"
    is a folder somebody stops opening.
  - Not PDF: that is one page with a pointer to HTML, which is right for a document somebody
    asked for and wrong for a file that arrives on its own and might cover a busy week.

### Changed

- **The parts of the app you read most are now translated.** A session is called "Late night
  in Terminal" and a gap "8m not recorded" — sentences the app assembles at runtime, which had
  no whole string for a translator to be given and so stayed English in every language. Each
  is now a format string whose pieces a translation can reorder, which matters: in Uzbek the
  application's name comes first and the time of day after it. Session titles, the gaps
  between them, the day's headline figures, the sidebar sections, the resume card, the
  reflection prompt and the relative day and time labels all follow the chosen language.
  Uzbek is complete at 519 strings.
  - Still English everywhere: Story, the autobiography, Memories, the morning briefing,
    Collections and Projects. Those are the same kind of work and are listed as undone in
    `docs/TRANSLATING.md` rather than left to be discovered.

### Fixed

- **The schedules section reported one schedule as if it were both.** Its footer was the
  backup's, so "Nothing has been written yet" sat directly under a line saying a report had
  just been written.

- **A VoiceOver label was built from a malformed format string.** One argument was handed to
  a two-placeholder format on the Chapters screen, mixing positional and non-positional
  specifiers — both undefined behaviour, and the label is read aloud.

## 0.9.7 — 2026-07-29

### Added

- **Replay can be read in another language, and there is now a way to translate it.**
  Settings ▸ General ▸ Language, listing only the languages this build actually carries —
  and the switch takes effect immediately rather than at the next launch.
- **A translation kit**, because the two things that translate text — a person and a service —
  both want a table, and neither wants a `.strings` file. `node tools/translate.mjs new fr`
  writes `translations/fr.csv`, a service or a translator fills the second column, `build fr`
  turns it into the catalogue that ships. Re-running `new` keeps what is already translated
  and adds rows for anything the app has gained since. `status` says how far each language is.
  Instructions, including what a translator needs to know about `%@`, are in
  [docs/TRANSLATING.md](docs/TRANSLATING.md).
- **A language ships only when it is complete.** `build` refuses below 100% unless `--partial`
  is passed: an `.lproj` tells macOS "Replay speaks this", and a Mac set to it would then show
  translated and English lines mixed with no way to tell which is which.
- **Uzbek, complete** — all 423 strings, so it ships without `--partial`. It is machine-made
  and wants a native reader: corrections belong in `translations/uz.csv`, and rebuilding is one
  command. Twelve more languages are scaffolded and empty, ready for a service or a person.

### Fixed

- **Swift unicode escapes were being carried into the table as text.** Three of the longest
  strings in the app contain `\u{2019}` in the source; the extractor took them literally, so
  those keys could never have matched the string the app actually looks up. Found by
  translating them — nothing else would have.
- **The sidebar was never translatable**, and no audit could have said so: its names arrive as
  `Navigation.Surface.rawValue`, and `tools/strings-audit.mjs` looks for literals. The most
  visible column in the app was English in every language while the audit read clean. It goes
  through `Loc` now, and the extractor knows about the helpers that take copy as an argument.

## 0.9.6 — 2026-07-29

### Added

- **A travelling border while an update installs.** The one moving border in the app, on the
  one stretch where Replay is working on something you should not interrupt and cannot be told
  how long it will take. Built here rather than taken from a package — CLAUDE.md forbids
  dependencies, and the effect is thirty lines. Off entirely under Reduce Motion.
- **Pausing can end by itself.** "Pause for…" in the menu bar offers 15 minutes, an hour, or
  until tomorrow, and recording comes back on its own — including after a quit or a night
  asleep, because a timed pause is a promise about a span of time rather than about this
  process. The menu bar and Settings ▸ Privacy both say when it ends. Pausing with no end is
  still there and still indefinite; the problem this fixes is not pausing, it is forgetting.

- **After an update, Replay says what you got.** The updater replaces the bundle and restarts,
  so "after the update" is really *the next launch* — and until now that launch said nothing at
  all. It now compares the version it is running against the one that ran last time and, if it
  is newer, answers in one of two ways.
  - **You pressed Update:** the What's New window opens by itself. You asked a question thirty
    seconds ago, the app disappeared and came back, and this is the answer.
  - **It arrived some other way** — `brew upgrade`, a bundle dragged into place — a banner in
    the same slot the update offer uses: "Updated to Replay 0.9.6", a **What's New** button and
    a dismiss ✕. Nobody is waiting on an answer, so nothing takes the screen. SPEC §8's "never
    interrupt" is exactly this distinction.
  - A **downgrade says nothing**: putting an older copy back is deliberate, and announcing the
    release somebody just escaped would be the app arguing with them.
  - The note is true for one launch and remembers nothing. Read or dismissed, it is gone.

### Fixed

- **Replay Story moved in lurches.** Each stop ran three movements where it should run one: a
  flight that started at full speed, a lean toward the next stop, and another flight that
  started at full speed. It arrived, stopped, crept, stopped and jerked away — two stops and a
  lurch per hop. The lean was this port's own idea and has gone; the dwell is still, and a
  hop now eases at both ends, because it begins from a camera at rest and nobody asked for it
  in the instant it happens. The reference's timings are untouched and still contract-checked.
- **Compacting no longer freezes the window.** `VACUUM` ran on the app's own connection, on
  the main actor, wrapped in `defer { busy = false }` — so "Compacting…" could never draw a
  frame and the window simply stopped answering for the length of a whole-file rewrite. It runs
  on its own connection now, off the main actor, with recording paused around it so no tracker
  write meets an exclusive lock. Importing a backup is still synchronous; it is seconds rather
  than tens of seconds, and it is on the backlog.
- **A pinned ambient screen switched auto-start off.** The idle watch refused to raise anything
  while *any* display was open, so ambient mode left running on a second monitor stopped the
  screensaver ever arriving on the screen you work on. The guard is about the screen now: two
  displays on one screen is what it was for, and two displays on two screens is the setup.
- **The timeline beside the Canvas now travels with the story.** It stayed on whatever was
  selected when the story began, so a story was a camera moving through one memory beside a
  list describing another — the Glaze version keeps the two in step, and now so does this.

## 0.9.5 — 2026-07-29

The update check spending its own attempts badly, and one claim measured rather than
believed.

### Fixed

- **A refused check counted as the day's check.** The "last checked" stamp was written the
  moment a reply arrived, whatever it said — so a rate-limited attempt recorded a check and
  the next one was 24 hours away, while an attempt that failed because the Mac was *offline*
  threw before the stamp and retried freely. Backwards in both directions: the failure that
  clears within the hour burned the day, and the one that might last all day did not. Only a
  `200` or a `304` counts now.

### Added

- **It says when the limit clears.** GitHub names the moment in `x-ratelimit-reset`; the
  message reads "It clears at 6:05 AM" rather than "try again later", and the daily check will
  not ask again before then — an attempt inside a window GitHub has already closed can only be
  refused, and spends one of the sixty an hour that were the problem.
- **The check asks a smaller question.** It sends `If-None-Match` with the tag from the last
  answer, so a day when nothing has changed comes back as an empty `304` rather than a release
  it already had. The release it *did* have is kept between launches, so that empty reply is
  still a complete answer.

### Measured, and it went the other way

**A `304` does not save rate limit on this endpoint.** GitHub documents conditional requests
as exempt, and that is written for *authenticated* ones — on the unauthenticated per-IP cap
this app uses, three requests decremented the counter three times whether they answered `304`
or `200`. The table is in [docs/FINDINGS.md](docs/FINDINGS.md). `If-None-Match` stays for the
two reasons that survived measurement, bytes and clarity, and this entry exists because the
first draft of it claimed the saving.

## 0.9.4 — 2026-07-29

### Added

- **A screen to show them on.** Settings ▸ Display ▸ Show on names which display the
  screensaver and ambient mode take. Replay follows the keyboard unless told otherwise, and a
  named screen that is unplugged falls back to the keyboard's without forgetting the choice.
- **Ambient mode can be left open while you work.** On a screen other than the one Replay's
  window is on, it stops taking the keyboard and stops closing when you type — the second
  monitor the mode was always for. It never applies on the screen you are working in, because
  a display that covers your work and takes no keys is a trap rather than a feature.
- **Quiet hours.** The idle drift can be kept to a span of the day. Spans that run through
  midnight work, which is the case the obvious implementation gets wrong.
- **Backups nobody has to remember.** Settings ▸ Data writes the same full backup every day or
  every week into a folder you choose, atomically, keeping the eight most recent and removing
  only its own older ones. Off until a folder and a schedule are chosen; nothing leaves the Mac.
- **A note and a bookmark on the stretch you are in, from the menu bar** — or ⇧⌘N from
  anywhere. The moment worth marking is the one you are in, and it passes while you are
  finding the session in a window.
- **Ambient mode can drift in on its own.** The idle delay used to have one outcome — the
  screensaver — because that is the only thing the reference's timer raises
  (`openAmbient("screensaver")`, hard-coded). Settings ▸ Display now opens with an **Auto-start**
  section: which of the two displays the delay raises, then the delay itself. The default is
  the screensaver, so an existing install behaves exactly as it did.
- **What starts on its own leaves on its own.** An ambient screen raised by the timer
  dismisses on any key, click or movement. One opened by hand still stays, which is the whole
  point of a display left on a second monitor — upstream says so in as many words, and this is
  the case that comment does not cover.

### Fixed

- **"Theme: Light" left half the app dark.** The appearance was applied by the main window and
  the menu bar panel and by nothing else, so Settings, What's New and the note panel followed
  the system instead of the setting. It is applied once now, where every window picks it up.
  Found by looking at the light-mode screenshots; every check in the suite passed throughout.
- **VoiceOver read an unlabelled image before every application name** — three of them per
  session on the Timeline. Application icons are decoration beside a name that is always
  there, and are marked as such.
- **"Exit on mouse movement" had nothing to listen to.** Neither full-screen window set
  `acceptsMouseMovedEvents`, and AppKit does not deliver `.mouseMoved` to a window that has not
  asked for it — so the monitor watching for it could never fire. The switch is off by default,
  which is why a setting that did nothing survived this long.

### Changed

- The line under "Auto-start when idle" now says which display it will raise. The screensaver's
  wording is still the reference's, read from the contract rather than restated.

## 0.9.3 — 2026-07-29

### Added

- **Updates install themselves.** The banner's button was a link to a release page, which
  left somebody to download a zip and drag a bundle over the one they were running. It now
  downloads the zip, fetches the SHA-256 the release publishes beside it, hashes the download
  and compares, extracts with `ditto`, checks the bundle is signed and is *this* application
  and is the version that was advertised, then replaces itself and restarts.
- **What the trust rests on, said out loud:** HTTPS to a repository named in the source, plus
  a checksum published in the same release — the Homebrew-formula model. It proves the bytes
  are the ones that release carries, not that the release is trustworthy. Anyone who can
  publish to the repository can publish an update. A Developer ID would add authorship and is
  still the thing worth buying.
- **It refuses more often than it installs**, which is the design rather than a limitation. A
  Homebrew copy is left to `brew upgrade`, since replacing the bundle would leave `brew`
  believing it has a version it no longer has. A copy running from macOS's read-only
  translocation mount — what an app still sitting in Downloads gets — has nothing to replace.
  A read-only location refuses rather than half-installing.

### Fixed

- **Rate limiting says something useful.** Testing exhausted GitHub's sixty-per-hour
  unauthenticated cap, and "GitHub replied 403" tells nobody anything they can act on.

## 0.9.2 — 2026-07-28

**0.9.1 shipped an app that would not open.** This is that fixed, and the check that should
have caught it.

### Fixed

- **The app died on launch if it could not find its strings catalogue.** `Bundle.module` calls
  `fatalError` when the bundle is missing, and `Loc` reached for it on a path that runs during
  startup. Every other path in `Loc` degrades to English by design — a missing `.lproj`, an
  unreadable table, a key nobody has translated — and missing the whole catalogue should
  degrade the same way rather than take the app down. It resolves the bundle by hand now and
  gives up quietly.
- **How it got through**, because that is the useful part. The resource bundle has two shapes:
  SwiftPM's native build produces a *flat* one with `Info.plist` at the root, Xcode's produces
  a *deep* one with `Contents/Resources/`. Every local build was deep and worked; the release
  was built flat and did not. No test sees either — they run where the bundle is always found.
  951 contract checks, 115 behaviour cases and four audits all passed on a build nobody could
  open.
- **The release workflow now runs the app it is about to publish** and fails if it exits on
  its own. The only way to catch this class of failure is to launch the artefact.

## 0.9.1 — 2026-07-28

Everything below happened after 0.9.0 was tagged the same day. Two of them are the reason to
take this build rather than that one: a data-loss bug, and the last functional gap against
the reference closing.

### Added

- **PDF export**, which the ledger had recorded as a decision rather than an omission after
  three WebKit routes died. The fourth route is not WebKit: `ImageRenderer` returns a
  `CGContext`, a PDF context *is* a `CGContext`, and a SwiftUI view draws straight into a page
  with no browser and nothing to paginate. Every earlier failure was a pagination failure, and
  the reference caps its own PDF at one page — so the honest shape is a summary that counts
  the whole span and names what it left off, rather than the HTML report again.
- **A menu bar popover** in place of the menu. The menu answered two questions well and could
  not answer more, because a menu is rows of text. This adds the day's total, the focus goal
  as a bar, the last three sessions with their applications' icons, and a pause control.
- **`tools/screenshots.sh`** — every surface captured in one command, about two minutes. Not a
  UI test and it makes no assertions: 951 contract checks had never caught a layout bug, and
  the bottleneck was never whether to look but that looking cost a dozen commands each time.
- **Localisation, to the point where it needs a translator rather than a task.** Every string
  a reader sees goes through `Loc`, whose key *is* the English text — so a missing translation
  falls back to correct English rather than a raw identifier, and the contract keeps comparing
  the strings it always did. `tools/strings-audit.mjs` holds it there.
- **A landing page** at `nurkamol.github.io/replay-swift`, and a **v0.9.0 release** with a
  zipped app, since Homebrew and a source build are not routes everyone has.

### Fixed

- **Two copies of Replay could zero each other's live session.** `ActivityStore.open()` closes
  any session left with no end — right after a crash, destructive while another copy is
  running, since it sets `ended_at = started_at, duration = 0` on the first instance's
  in-flight session. Both then wrote to one SQLite file with no busy timeout, so a contended
  write returned `SQLITE_BUSY` and the event was lost with no error anywhere. A second launch
  now hands the front to the first and exits; the store waits five seconds for a lock. **Found
  from a question, not from a check** — whether running the Glaze app alongside this one could
  explain a crash. It could not. This was underneath the question.
- **The menu bar panel opened mid-sentence.** The popover is reused so the button can toggle
  it and remembered its last size, while the content changes height — so taller content was
  clipped off the *top*, taking the header and the day's total with it.
- **The year heatmap's weekday key sat a hundred points from the year it labelled.** The grid
  anchors trailing so it opens on today, which is right; applied unconditionally it also shoves
  a grid that *fits* against the right edge. True at every window from about 1000pt, which is
  every default window, and found by the first light-mode render in the project's history.
- **The week's rhythm strip left a dead gap** before the durations at any wide window. Its
  560pt cap was redundant — the page measure already bounds the row — and was concealing that
  the strip is twenty-four bars that each want to fill, so removing the cap pushed the duration
  column off the edge entirely until it was given layout priority.
- **A page never grew with its window**: every surface was capped at the *prose* measure and
  pinned left, so widening the window grew a dead column against the scroll bar.
- **The Canvas field is still.** Its sway was this port's own, cost a permanent 30fps redraw,
  and diverged from a reference whose graph does not move.

### Known gaps

- **Still not signed.** The download is a zip and macOS will refuse it once; the release notes
  say why and how. Homebrew and a source build avoid it entirely.
- **One language.** The mechanism is built and every string goes through it; nobody has
  translated anything. `Loc.count` has two plural forms, which is English — Russian needs
  three, Arabic six. A `.stringsdict` is the seam waiting for a language to be chosen.

## 0.9.0 — 2026-07-28

Feature-complete: every route the reference has, both of its display modes, and the whole of
its Settings. Nine rather than one because nothing is missing against the reference, and not
ten because it still cannot be handed to somebody as a finished application. Level with
**Glaze 2.3.2** (`d355ba2`), verified by **951 contract checks and 74 behaviour cases**.

**A source release, and the distinction is the honest one.** There is no disk image on the
release page. `scripts/make-app.sh` signs ad-hoc, which runs on the machine that built it and
nowhere else, and macOS refuses a *downloaded* app with no Developer ID — so an unsigned
image would look like a download and behave like a broken app. What this release is instead
is a **version**: something Homebrew can build from and something the update check can see,
neither of which needs a certificate. Install it with `brew install nurkamol/tap/replay-app`
or from the source tarball; both compile locally, are never quarantined, and open with no
warning. Signing remains the only thing between this and 1.0.0, and it needs a Developer ID
rather than any more code.

### Added

- **Recording.** A menu bar item that records all day, with the current app, today's total,
  pause/resume, and the surfaces behind it. No Accessibility, Automation, or Screen
  Recording permission — that property is the product.
- **Today.** The day's headline, its top app, an optional focus goal, a reflection, and the
  sessions and gaps that made it up.
- **Timeline.** Recent days newest-first with day-part dividers, a range picker, and a
  per-day menu to open, export, or delete.
- **A past day, reopened**, filtered to the runs that *began* that day.
- **Notes, tags and bookmarks** on a session, with marks visible on a collapsed card.
- **Reflections** — a line you write for a day, on Today and on any day you reopen.
- **Search** by session name, note, tag or application, plus a few phrases ("morning",
  "longest", "bookmarked") that go to a slice rather than matching literally.
- **Settings** — General, Privacy, Data, Guide, About — with excluded applications,
  retention, database compaction, and menu-bar-only mode.
- **Export.** A day, a session, or a scope (this week, this month, bookmarks, notes) as
  Markdown, CSV, JSON or HTML; and a full backup in the format both implementations read.
- **Backup import**, verified against a real 3,084-row export from the Glaze app.
- **An application menu**, without which ⌘, ⌘W and — the one that bit — ⌘C and ⌘V in a note
  field did nothing.
- **Memories** — what you were doing on this date a week, a month, or up to two years ago,
  read from the durable daily headlines so a memory outlives the day's raw events.
- **Collections** — every session of one kind, with its running totals and the apps that
  defined it. Derived from the category a session already has, so there is nothing to file.
- **Story Mode** — a reopened day told back in a few plain sentences, every clause filled
  from recorded activity. A day too thin to narrate honestly gets no story rather than a
  padded one.
- **A design system.** Every visual constant — radii, spacing, typography, motion, springs,
  materials, elevation, shadows, colour, icon sizes, window and sheet metrics, card chrome —
  in one file, with every view reading from it. `node tools/design-audit.mjs` fails the
  build if a view hard-codes a value, so the system cannot rot one plausible number at a
  time. The motion tokens are the reference's own, extracted into the generated contract and
  checked by the parity suite.
- **CI** running the parity suite on every push, in four timezones, plus the design audit.

### Added — the rest of the surfaces

- **Projects** — the app combinations that keep coming back, named descriptively and
  renameable, with a page each.
- **Canvas** — the whole history as a field you can fly through, and **Replay Story**, a
  camera tour that narrates a memory by moving rather than by writing.
- **Story, Chapters, Autobiography, Museum and My Story** — the long view: your history
  divided into eras, told back to you a month at a time, and the best of it curated.
- **Relationships and an application's own page** — what two apps do together, and what one
  app has done across the record.
- **This Week**, **Replay Day** (scrub a day back at 1×, 2× or 5×), and a **screensaver**.
- **Ambient mode** — a distraction-free full-screen clock for a second monitor, the second
  of the reference's two display modes.
- **A welcome screen**, a **Dock badge** showing whole active hours, and a **command
  palette** that reaches every surface, application and project by name.
- **One catalogue for keyboard shortcuts**, feeding the View menu, the Settings table and
  the sidebar hints, with `tools/shortcut-audit.mjs` checking all three agree.
- **A Display pane in Settings** for the screensaver and ambient mode — the reference's own
  grouping for the pair.

### Fixed — differences found between the two implementations

These are the ones worth reading. Each was invisible until something checked it.

- **A backup this app wrote, this app could not read.** The writer named its JSON keys after
  Swift properties (`applicationName`) where a backup carries SQLite column names
  (`application_name`). Every row failed the reader's guard and was counted as skipped, so a
  file full of malformed rows parsed as a valid, empty backup. Caught by a round-trip check,
  not by reading the output.
- **The parity suite only passed in one timezone.** Session titles are named after the local
  day part, so the derivation fixtures had quietly recorded the machine that generated them.
  The suite would have failed the first time it ran anywhere else.
- **Five divergences in the report formats**, none of which reading the reference had found:
  an abbreviated timestamp where the reference uses `toLocaleString()`; a two-digit year
  where JavaScript renders four; a time range that collapsed its shared meridiem, which is
  right on a card and wrong in a document; a missing `scope` field in the JSON; and an
  `exportedAt` without the milliseconds `toISOString()` writes.
- **Two application-matching predicates collapsed into one.** The reference keeps an exact
  match (for an app you chose) apart from a substring match (for discovering one by typing).
  Merging them is invisible until an app's name is a prefix of another's.
- **Today's figures went stale** while the window sat open, because the day was only
  re-derived when the tracker recorded a switch. It now re-derives on the reference's 30s
  interval.
- **Away time was being dropped on import** by the Glaze app itself, which omitted `idle`
  from its accepted row types — relabelling every away stretch as "Replay wasn't running".
  Fixed upstream; the accepted set is now pinned in the generated contract so neither
  implementation can lose one silently again.
- **Calendar arithmetic clamped where the reference overflows.** 31 March minus one month is
  3 March in JavaScript and 28 February with Swift's `date(byAdding:)`. A memory labelled
  "one month ago" has to mean the same day in both apps.
- **The About panel claimed Apache 2.0** after the port was relicensed under MIT.

### Fixed — bugs in this port

- **An HTML report weighed 89 MB.** `NSImage.size` sets the point size and nothing about the
  pixels, so every icon tile carried the 1024px master from the iconset. Redrawn into a
  64×64 bitmap: 482 KB, identical on screen.
- **The same icons were inlined once per use** — fifty-odd icons appearing three hundred
  times in one document. Defined once as CSS classes and referenced by name.

### Added — beyond the reference

The first things Replay does that the Glaze app does not.

- **App Intents.** Three read-only intents — today's activity, a given day, and time in one
  application — with Siri phrases, so the record is reachable from Shortcuts and Spotlight.
- **`replay`, a command-line reader.** `replay today`, `replay day yesterday`,
  `replay app Xcode`, `replay export --format json`. Everything supports `--json`, nothing
  can change the record, and exit codes distinguish "you asked wrongly" from "I could not
  answer" so a script can branch on them.

### Fixed — divergences the audits found

Seven surface audits, each comparing a view against its reference beside it. Every one found
something; these are the ones worth naming.

- **The memory heatmap shaded days against the busiest day in view**, not against fixed
  amounts of time — so a quiet month and a heavy one looked identical, and a square's
  darkness meant nothing you could compare across a year.
- **Today was missing from its own year.** The reference builds the grid forwards from 370
  days ago; 53 weeks is 371 days, so it ends between today and six days before it.
- **The narrative surfaces were entirely paraphrase** — every subtitle and empty state on
  Story, Chapters and Autobiography, with both footnotes missing outright.
- **My Story was missing a section** the reference has, found by diffing section labels.
- **The screensaver's close button and exit hint had never been visible**, pushed off-screen
  by a `ZStack` sizing to its drifting column.
- **The Timeline built every row before showing one**, which read as a slow query and was
  not: the data is 22ms.

### Added — getting it to somebody else

- **An update check**, opt-in and off by default: at most one `GET` a day to GitHub's public
  releases API, no body and no identifier, and a bar with the notes if a newer tag exists. It
  downloads nothing and replaces nothing — a self-updater has to verify a signature and swap
  a running bundle, and until there is a Developer ID it would be trading a working app for
  one Gatekeeper refuses. `Check for Updates…` sits under About Replay where every Mac app
  puts it. **This is the first network code the app has ever had**, which cost more in prose
  than in Swift: README and SPEC both claimed there was none, both were true and are not, and
  both were rewritten around the claim that survives — *nothing recorded ever leaves the
  machine, under any setting*. The Guide could not be edited to match, because its sixteen
  answers are compared character for character against the reference and the reference
  genuinely has no network, so `Guide.ownEntries` states the exception beside them.
- **A release pipeline.** `scripts/make-dmg.sh`, a tagged workflow that runs the whole suite
  before it publishes, and `tools/release-notes.mjs` so the changelog and the release page
  cannot disagree. It refuses to attach an unsigned image and publishes a source release
  instead.
- **A Homebrew tap** — `nurkamol/tap`, with a formula for the application and one for the
  CLI. Formulae rather than casks, which is the whole trick: a cask installs a prebuilt
  binary and needs a certificate, a formula *builds*, and an app built on your own machine
  was never downloaded and is never quarantined.

### Fixed — found by looking at it

- **The menu bar item answered the wrong questions**, showing the day's total and top app —
  things the window is for — where the reference answers *what am I in now, and what was I
  just in*. It also wore `clock.arrow.circlepath`, which in the menu bar is Time Machine's
  icon, so the status item read as a system backup service.
- **A page never grew with its window.** Every surface was capped at 760pt — the measure for
  prose — and pinned left, so widening the window grew a dead column against the scroll bar
  and the page read as content that had failed to load. Pages now grow to 1080 and centre
  the remainder; `readableWidth` moved to where it belongs, on the paragraph rather than the
  page, so a card is as wide as its page and the sentence inside it is not.

### Known gaps

- **No PDF export.** Three WebKit routes tried and dead. Reviving it means leaving WebKit
  and drawing the report into a `CGContext` by hand. See `docs/PARITY.md`.
- **The app is not signed for distribution.**
- **The suite covers the core, not the interface.** Every UI behaviour above was verified by
  running the app against real data, which is weaker than a fixture and is recorded as such
  in the ledger. Three bugs this release were invisible to every automated check and were
  found only by looking: a Settings toggle bound to the wrong `Bool`, chrome laid out
  off-screen, and a test suite leaking a `UserDefaults` domain per fixture. That is the
  argument for a UI test target, which is an open decision in `docs/BACKLOG.md`.
