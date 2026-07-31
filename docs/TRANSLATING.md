# Translating Replay

Everything the app says, in a table anybody — or any service — can fill in.

```bash
node tools/translate.mjs status          # how far each language has got
node tools/translate.mjs new fr          # create or refresh translations/fr.csv
node tools/translate.mjs build fr        # CSV → Sources/ReplayCore/Resources/fr.lproj
```

## The shape of it

**The English sentence is the key.** `Loc.t("Tracking paused")` looks up that exact sentence
and returns the translation if there is one, or the sentence itself if there is not. So a
missing translation is correct English, never `menubar.paused` — which matters, because
half-translated is the normal state of a translated app.

Three files, and only one of them is edited:

| file | what it is | edited by |
|---|---|---|
| `translations/keys.txt` | every string the app can say | nobody — generated |
| `translations/<code>.csv` | `english,<code>` — the source and a blank | **you, or a service** |
| `Sources/ReplayCore/Resources/<code>.lproj/Replay.strings` | what ships | nobody — generated |

`new` is safe to re-run: it keeps every translation already in the CSV and adds rows for
anything new in the app. Run it after any release and the diff is the work.

## Using a translation service

A CSV with a source column and a target column is what every service takes — DeepL, Google
Cloud Translation, Crowdin, Lokalise, or a person with a spreadsheet. The round trip is:

1. `node tools/translate.mjs new fr` → `translations/fr.csv`
2. Upload, translate, download. **Keep the first column exactly as it is** — it is the lookup
   key, and an "improved" English source silently orphans its own translation.
3. Put the file back at `translations/fr.csv`
4. `node tools/translate.mjs build fr`
5. `swift build && open build/Replay.app`, then Settings ▸ General ▸ Language

## The deep scan: ask the app, do not guess

```bash
REPLAY_LOG_KEYS=/tmp/keys.txt ./tools/screenshots.sh   # drives 21 surfaces, records every lookup
node tools/translate.mjs record /tmp/keys.txt          # merge what it saw into the key list
node tools/translate.mjs keys && node tools/translate.mjs new uz
```

**This is the ground truth, and the source scan is an approximation of it.** Every version of
"find the translatable strings by reading the source" has been wrong differently:

| what was missed | why | how it looked |
|---|---|---|
| the sidebar's names | enum raw values — no literal to find | "Today" translated *by coincidence*, "Collections" never |
| five of seven Settings panes | several `case`s on one line, one regex match per line | "Umumiy" then five English words |
| every Settings row name | `Picker(String)` is SwiftUI's non-localising overload | English labels above translated explanations |
| a footnote | a helper collected the copy and never looked it up | one English paragraph between two Uzbek ones |

The recorder asks the opposite question — what did the app *ask* for while somebody drove it
through every surface — and it cannot be wrong about the surfaces it visited. It is wrong only
about the ones nobody opened, which is why `translations/runtime-keys.txt` is committed and
merged rather than regenerated: it is evidence, and a second run adds to it.

Two things it caught that nothing else would have: a **double translation** — labels that
translate themselves being wrapped again, so the second lookup missed and the recorded set
filled with Uzbek — and a **hybrid key**, where a footnote joined a translated sentence to an
English one and then looked the pair up, matching nothing.

## Rules a translator needs to know

- **Format specifiers are not words.** `%@` is a value the app substitutes — a duration, an
  application's name, a count. Keep every one, and keep them in the same order unless the
  string is numbered (`%1$@`, `%2$@`), which is exactly what numbering is for: `"%1$@ to go of
  %2$@"` may be reordered freely, `"%@ active"` may not.
- **Length is a real constraint** in the sidebar, the menu bar and buttons. A label three times
  longer than the English will be truncated rather than wrap.
- **Sentence case, and no shouting.** Replay describes a day; it does not announce it.
- **Words the app treats as its own** — Replay, Canvas, Timeline, Today, Memories — are the
  names of places in the app. Translate them if your language would; keep them consistent with
  each other, because they appear in the sidebar and in prose about the sidebar.

## A language ships only when it is complete

`build` refuses below 100% unless you pass `--partial`. That is not fussiness. An `.lproj` in
the bundle tells macOS "Replay speaks this", and a Mac set to that language then shows
translated and untranslated lines mixed together with no way to tell which is which — worse
than not claiming the language at all. `--partial` exists so you can *see* a language running
before it is finished; it is not a way to ship one.

## Dates and numbers are a different system

The picker chooses which strings table is read. It has no effect on Foundation, which formats
"Wednesday, July 29" from the *system* locale — so an app could be, and was, entirely
translated with an English date across the top of it.

`Loc.locale` is the seam: a `Locale` built from the chosen language, or `.current` when the
picker is on Match System, because a Mac that is set to a language has already been told. Every
formatter a reader sees goes through it, and `Report.Environment.current` reads it too, so
exports follow the same rule. When you add a date to a view, `.locale(Loc.locale)` on the format
style is the whole of the work.

## What is not translatable yet, and why

Some copy is not a whole string in the source. It is fragments assembled at runtime with the
numbers inside them — `"\(part) in \(app)"` — so there is no sentence to hand a translator,
and a table of half-clauses cannot be assembled into a language whose word order differs from
English. Which is most of them: in Uzbek the app name takes a locative and the time-of-day
leads, and no amount of translating "in" separately produces that.

The fix is one format string per sentence, with positional arguments (`%1$@`, `%2$@`), so a
translator can reorder the pieces and the whole sentence is one row in the catalogue.
`Sources/ReplayCore/RuntimeCopy.swift` is where those live. **The English never moves**: every
one has a counterpart that renders the contract — `SessionTitle.english`, `describeBreak` —
and those are what the parity suite compares against `spec/`.

**Done (2026-07-29):** session titles, the gaps between sessions, the day's headline figures,
the sidebar sections, the resume card, the reflection prompt, the relative day and time labels,
and the session card's VoiceOver sentence.

**Done (2026-07-30):** Memories, in full — its seven moment cards, the on-this-day range names,
the heatmap's months and weekday initials, and the update messages that appear when a check or
an install fails. `Moment` carries a `facts` payload so the sentence can be assembled again in
another language; the English on it is untouched.

**Not done:** the rest of the narrative surfaces — Story, the autobiography, the morning
briefing, Collections and Projects. Roughly sixty assembled sentences across `Moments`,
`Autobiography`, `DayStory`, `Canvas` and `Resume`. One surface at a time, when that surface is
being touched anyway.

### Two traps, both of which have already happened here

**Do not translate an already-translated string.** `Loc.t` falls back to its input, so a double
lookup looks harmless — the words on screen are right. What breaks is the key recorder: it
writes down what was asked for, and it will happily record a *translated* sentence as though it
were a key. Three Uzbek sentences reached `translations/keys.txt` that way. The rule is that a
value is translated exactly once, at one end or the other, and helpers that compose from parts
take them verbatim.

**Never sweep orphans in bulk.** `status` calls a row "orphaned" when the key list does not
contain it — and the key list is built by scanning for `Loc.t("…")` literals, which cannot see
a lookup written as `Loc.t(someVariable)`. So a *correct, used* translation can look orphaned.
This has already happened: the day parts "morning", "afternoon" and "evening" were asked for
through a variable, never appeared as keys, and a tidy-up deleted them — after which a day's
story read "…that evening" in the middle of an Uzbek sentence. Remove a row only when you know
which call site you deleted, and prefer fixing the lookup so the scanner can see it.

**A count is not proof.** `translate.mjs status` counts the keys that exist. Copy that never
reaches `Loc` at all is not a key, so it is not counted, and a language can report 100% while a
whole surface is in English. Two things find that: the runtime recorder — which sees only what
the running app asked for — and running the app in another language and *looking*. The second
one is the one that found the sidebar headers.

## Where each language stands

`node tools/translate.mjs status` is the answer, always. At the time of writing:

- **uz — 468 of 468, complete and shipping.** Machine-made, and it wants a native reader: it
  is fluent-looking Uzbek written by a model, not by an Uzbek speaker, and the difference shows
  up in exactly the places nobody checks. Corrections go in `translations/uz.csv`, not in the
  `.lproj`.
- **es, fr, de, pt-BR, it, ru, tr, ar, zh-Hans, ja, ko, hi** — scaffolded and empty, ready to
  hand to a service or a person. None of them ship until they are finished.
