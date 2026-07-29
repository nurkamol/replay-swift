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

The narrative surfaces — Story, the autobiography, the day's own sentences, the morning
briefing — do not hold sentences. They hold fragments assembled at runtime with the numbers
inside them: `"\(label), mostly in \(app)"`. There is no whole sentence in the source to be a
key, so there is nothing to hand a translator, and a table of half-clauses cannot be translated
into any language whose word order differs from English — which is most of them.

Making those translatable means rewriting each one as a format string with positional
arguments. It is real work, one surface at a time, and it is on the backlog rather than
pretended away. Until then those surfaces stay English in every language.

## Where each language stands

`node tools/translate.mjs status` is the answer, always. At the time of writing:

- **uz — 468 of 468, complete and shipping.** Machine-made, and it wants a native reader: it
  is fluent-looking Uzbek written by a model, not by an Uzbek speaker, and the difference shows
  up in exactly the places nobody checks. Corrections go in `translations/uz.csv`, not in the
  `.lproj`.
- **es, fr, de, pt-BR, it, ru, tr, ar, zh-Hans, ja, ko, hi** — scaffolded and empty, ready to
  hand to a service or a person. None of them ship until they are finished.
