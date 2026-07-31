#!/usr/bin/env node
/**
 * The translation kit: get the words out, get them back in, and know what is missing.
 *
 *   node tools/translate.mjs keys            # every string the app can say, to translations/keys.txt
 *   node tools/translate.mjs new uz          # a CSV to hand to a person or a service
 *   node tools/translate.mjs build uz        # CSV -> Sources/ReplayCore/Resources/uz.lproj
 *   node tools/translate.mjs status          # how far each language has got
 *
 * Why a CSV in the middle
 * -----------------------
 * Because the two things that translate text — a person, and a translation service — both
 * take a table with the source in one column and a blank in the other, and neither takes a
 * `.strings` file without complaining. The CSV is the interchange; `.strings` is the build
 * output and is never edited by hand.
 *
 * The rule that matters
 * ---------------------
 * **A language ships only when it is complete.** An `.lproj` in the bundle is macOS being
 * told "Replay speaks this" — and a Mac set to that language then shows every translated
 * line and every untranslated one in English, mixed, with no way to tell which is which.
 * That is worse than not claiming it. So `build` refuses below 100% unless `--partial` is
 * passed, which is for testing a language before it is finished rather than for shipping it.
 *
 * What is a key
 * -------------
 * The English sentence itself — see `Loc`. Two sources, because the app says words from two
 * places:
 *
 *   1. Views, which wrap their own text: `Loc.t("Pause for…")`.
 *   2. `ReplayCore`, which holds copy as *values* a view then wraps: the Guide's answers, the
 *      Settings explanations, the menu bar's states. Those are literals where they are
 *      defined, and the view does `Text(Loc.t(entry.answer))`, so the sentence is the key
 *      just the same. They are collected from the files named in `CORE` — a list rather than
 *      a heuristic, because "which literals in this module are words" is exactly the judgement
 *      that produces an audit nobody trusts.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "translations");
const LPROJ = join(ROOT, "Sources", "ReplayCore", "Resources");

/** The `ReplayCore` files that hold copy rather than mechanism. */
const CORE = [
  "SettingsCopy.swift", "Guide.swift", "MenuBar.swift", "NarrativeCopy.swift",
  "AutoBackup.swift", "AppWindow.swift", "Pause.swift",
];

/* **What is deliberately not here, and it is a real gap.** `Answers`, `DayStory`,
 * `Autobiography`, `Moments`, `MorningBriefing` and the rest of the narrative surfaces do not
 * hold sentences — they hold *fragments* that are assembled at runtime with the numbers in
 * them: `"\(label), mostly in \(app)"`. There is no whole sentence in the source to be a key,
 * so there is nothing here a translator could be handed, and a table of half-clauses would be
 * untranslatable into any language whose word order differs from English — which is most of
 * them. Making those translatable means rewriting them as format strings with positional
 * arguments, one surface at a time. Until then they stay English, and this says so rather
 * than shipping a translator 200 fragments and calling it coverage. */

const swiftFiles = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.name.endsWith(".swift") ? [path] : [];
  });

/* A Swift string literal, with escapes. Deliberately not multi-line — `"""` blocks are used
   for SQL and for shell scripts here, never for copy. */
const LITERAL = /"((?:[^"\\]|\\.)*)"/g;

/* ── counted nouns ────────────────────────────────────────────────────────────
 *
 * `Loc.count(n, "%@ session", "%@ sessions")`. Both forms are copy and neither was ever
 * collected: the scan above looks for `Loc.t("…")` and these arrive through a different
 * call, so `%@ day`, `%@ visit`, `%@ visits`, `%@ switch` and `%@ switches` were absent
 * from the catalogue entirely and rendered in English in every language. `%@ days` and
 * `%@ session` were present only because the runtime recorder happened to catch them.
 *
 * They also need more than two forms. English has two; Russian has four and Arabic six,
 * and picking by `n == 1` is simply wrong in both — Russian 21 takes the same form as 1,
 * and 11 does not. So each one becomes a row per plural category *of the target language*,
 * written into a `.stringsdict` that Foundation resolves with the locale's own CLDR rules.
 */
const COUNTED =
  /Loc\.count\([^,]+,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)/g;

/** The row a translator fills for one plural category: `plural:few:%@ session`. */
const PLURAL_PREFIX = "plural:";
const pluralRow = (category, singular) => `${PLURAL_PREFIX}${category}:${singular}`;

/**
 * Which plural categories a language actually has, from ICU rather than from a table here.
 *
 * Node ships CLDR, so this is the same data Foundation will use at runtime — no hand-kept
 * list to fall behind, and no chance of inventing a category a language does not have. It
 * is why `ar` gets six rows, `ru` four, and `ja` one.
 */
function pluralCategories(language) {
  try {
    const found = new Intl.PluralRules(language).resolvedOptions().pluralCategories;
    // CLDR's own order, so the rows read predictably rather than alphabetically.
    return ["zero", "one", "two", "few", "many", "other"].filter((c) => found.includes(c));
  } catch {
    return ["one", "other"];
  }
}

/** Every `(singular, plural)` pair the app counts with, sorted and deduplicated. */
function collectCounted() {
  const pairs = new Map();
  for (const dir of ["Sources/ReplayUI", "Sources/ReplayApp", "Sources/ReplayCore"]) {
    for (const file of swiftFiles(join(ROOT, dir))) {
      const source = joinConcatenations(readFileSync(file, "utf8"));
      for (const match of source.matchAll(COUNTED)) {
        pairs.set(unescape(match[1]), unescape(match[2]));
      }
    }
  }
  return [...pairs.entries()]
    .map(([singular, plural]) => ({ singular, plural }))
    .sort((a, b) => a.singular.localeCompare(b.singular, "en"));
}

/* `\u{2019}` is a Swift escape, and the *runtime* string has the character in it — so a key
   left escaped is a key that can never match anything. Found by translating: three of the
   longest strings in the app carried a literal `\u{2019}` into the table. */
const unescape = (s) =>
  s
    .replace(/\\u\{([0-9a-fA-F]+)\}/g, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/\\n/g, "\n")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, "\\");

/** Is this a sentence somebody reads, or an identifier that happens to be letters? */
const isCopy = (s) => {
  if (s.length < 2) return false;
  if (!/\p{L}/u.test(s)) return false;
  if (/^[a-z0-9]+([.-][a-z0-9]+)+$/i.test(s)) return false;   // bundle ids, symbol names
  if (/^[a-z]+([A-Z][a-z0-9]*)+$/.test(s)) return false;       // camelCase keys
  if (/^%@?[a-z]?$/i.test(s)) return false;                     // a bare format specifier
  if (/^(SELECT|INSERT|UPDATE|DELETE|CREATE|PRAGMA|VACUUM)\b/i.test(s)) return false;
  // Not words: a file extension, a locale identifier, a filename this app builds.
  if (/^\.[a-z]+$/i.test(s)) return false;
  if (/^[a-z]{2}_[A-Z]{2}(_[A-Z]+)?$/.test(s)) return false;
  if (/^Replay backup $/.test(s)) return false;
  return true;
};

/* `"a " + "b"` across lines is one sentence. Joining them is not cosmetic: the app looks up
   the *whole* sentence, so a table of halves would never match anything. */
function joinConcatenations(source) {
  return source.replace(/"\s*\n\s*\+\s*"/g, "").replace(/"\s*\+\s*"/g, "");
}

function collectKeys() {
  const keys = new Set();

  // 1. Anything a view wraps itself.
  for (const dir of ["Sources/ReplayUI", "Sources/ReplayApp", "Sources/ReplayCore"]) {
    for (const file of swiftFiles(join(ROOT, dir))) {
      const source = joinConcatenations(readFileSync(file, "utf8"));
      for (const match of source.matchAll(/Loc\.t\(\s*"((?:[^"\\]|\\.)*)"/g)) {
        const text = unescape(match[1]);
        if (isCopy(text)) keys.add(text);
      }
      // Enum raw values that are read to a person: the sidebar's surface names and the
      // Settings panes. They reach `Loc.t` as a variable, so nothing that scans for literals
      // could find them — "Collections", "Story" and "Settings" were missing from the table
      // entirely, while "Today" and "Search" were in it *by coincidence*, because other files
      // happen to say `Loc.t("Today")`. A translated sidebar with two English rows in it was
      // the visible half of that.
      if (/enum (Surface|Pane)\b/.test(source)) {
        // Every raw value on the line, not the first. Swift allows several cases per line —
        // `case general = "General", privacy = "Privacy"` — and a regex anchored on `case`
        // finds one of them. That is why the Settings sidebar came out half translated:
        // "Umumiy" and then five English words under it.
        for (const line of source.split("\n")) {
          if (!/^\s*case\s/.test(line)) continue;
          for (const match of line.matchAll(/=\s*"((?:[^"\\]|\\.)*)"/g)) {
            const text = unescape(match[1]);
            if (isCopy(text)) keys.add(text);
          }
        }
      }
      // Helpers whose first argument is copy, which then wrap it in `Loc.t` themselves.
      // Without these the sidebar's own names were missing from the table while every audit
      // read clean: they reach `Loc.t` as a *variable*, so no scan for literals can see them.
      for (const match of source.matchAll(
        /\b(?:sidebarLabel|footerRow|panelNote|Footnote|MenuBarRow)\(\s*(?:glyph:\s*"[^"]*",\s*title:\s*)?"((?:[^"\\]|\\.)*)"/g
      )) {
        const text = unescape(match[1]);
        if (isCopy(text)) keys.add(text);
      }
    }
  }

  // 2. The copy `ReplayCore` holds as values.
  for (const name of CORE) {
    const path = join(ROOT, "Sources", "ReplayCore", name);
    if (!existsSync(path)) continue;
    const source = joinConcatenations(readFileSync(path, "utf8"));
    for (const line of source.split("\n")) {
      const code = line.trim();
      if (code.startsWith("//") || code.startsWith("///")) continue;
      for (const match of code.matchAll(LITERAL)) {
        const text = unescape(match[1]);
        // A literal with an interpolation in it is part of a sentence built at runtime, and
        // the app never looks that up as a whole. Anything ending mid-clause is the same
        // thing seen from the other side.
        if (text.includes("\\(")) continue;
        if (isCopy(text)) keys.add(text);
      }
    }
  }

  // 3. And everything the running app actually asked for.
  //
  // **This is the ground truth and the other two are approximations of it.** A scan of the
  // source guesses which strings will reach a person, and every version of that guess has been
  // wrong differently: enum raw values are invisible to it, several `case`s on one line hid
  // half a sidebar, a helper that collected copy and never looked it up read as complete.
  // `REPLAY_LOG_KEYS=<file> ./tools/screenshots.sh` drives every surface with `Loc` recording
  // what it is asked for, and `translate.mjs record <file>` merges the result here.
  //
  // Committed rather than regenerated on demand, because it is evidence: it says which strings
  // this app was seen to ask for, on a day somebody drove it through everything.
  const recorded = join(OUT, "runtime-keys.txt");
  if (existsSync(recorded)) {
    for (const line of readFileSync(recorded, "utf8").split("\n")) {
      const text = line.trim();
      if (text && isCopy(text)) keys.add(text);
    }
  }

  // 4. Both forms of every counted noun. They reach `Loc` through `Loc.count` rather than
  //    `Loc.t`, so no scan above could see them, and five of the eleven were missing.
  for (const { singular, plural } of collectCounted()) {
    keys.add(singular);
    keys.add(plural);
  }

  return [...keys].sort((a, b) => a.localeCompare(b, "en"));
}

// ── the CSV in the middle ─────────────────────────────────────────────────────

const csvCell = (s) => `"${s.replace(/"/g, '""')}"`;

function parseCSV(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') quoted = false;
      else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (c !== "\r") cell += c;
  }
  if (cell.length || row.length) { row.push(cell); rows.push(row); }
  return rows.filter((r) => r.some((c) => c.length));
}

const stringsEscape = (s) =>
  s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");

const xmlEscape = (s) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/**
 * The `.stringsdict` — one entry per counted noun, one form per plural category.
 *
 * Foundation reads this *before* `Replay.strings` for the same table, hands back the
 * `%#@n@` reference, and resolves it against the locale's CLDR rules when the format is
 * applied. That is what makes 21 take Russian's `one` form and 11 its `many` form, which no
 * amount of `n == 1` can do.
 *
 * `%@` becomes `%d` on the way in. The CSV says `%@` everywhere, because to a translator it
 * is simply "the value goes here" — but a plural rule has to be given a *number* to reason
 * about, so the specifier type is `d` and the forms have to match it.
 */
function stringsdict(language, entries) {
  const body = entries
    .map(({ singular, forms }) => {
      const cases = Object.entries(forms)
        .map(([category, text]) =>
          `      <key>${category}</key>\n` +
          `      <string>${xmlEscape(text.replace("%@", "%d"))}</string>`
        )
        .join("\n");
      return (
        `  <key>${xmlEscape(singular)}</key>\n` +
        `  <dict>\n` +
        `    <key>NSStringLocalizedFormatKey</key>\n    <string>%#@n@</string>\n` +
        `    <key>n</key>\n` +
        `    <dict>\n` +
        `      <key>NSStringFormatSpecTypeKey</key>\n      <string>NSStringPluralRuleType</string>\n` +
        `      <key>NSStringFormatValueTypeKey</key>\n      <string>d</string>\n` +
        `${cases}\n` +
        `    </dict>\n  </dict>`
      );
    })
    .join("\n");
  return (
    `<?xml version="1.0" encoding="UTF-8"?>\n` +
    `<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ` +
    `"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n` +
    `<!-- Replay — ${language}. Generated by tools/translate.mjs from ` +
    `translations/${language}.csv.\n` +
    `     Do not edit by hand: edit the CSV and rebuild. -->\n` +
    `<plist version="1.0">\n<dict>\n${body}\n</dict>\n</plist>\n`
  );
}

// ── commands ──────────────────────────────────────────────────────────────────

const [command, argument] = process.argv.slice(2);
const partial = process.argv.includes("--partial");

if (command === "keys") {
  const keys = collectKeys();
  mkdirSync(OUT, { recursive: true });
  writeFileSync(join(OUT, "keys.txt"), keys.join("\n") + "\n");
  console.log(`${keys.length} strings → translations/keys.txt`);
} else if (command === "new") {
  if (!argument) { console.error("usage: translate.mjs new <language-code>"); process.exit(2); }
  const keys = collectKeys();
  const path = join(OUT, `${argument}.csv`);
  const existing = existsSync(path)
    ? new Map(parseCSV(readFileSync(path, "utf8")).slice(1).map((r) => [r[0], r[1] ?? ""]))
    : new Map();
  mkdirSync(OUT, { recursive: true });

  // One row per plural category of *this* language, seeded from the two-form translation
  // that is already there. A two-category language therefore arrives fully filled and its
  // translator has nothing extra to do; Russian gets four rows with `one` and `other` filled
  // and `few`/`many` blank, which is exactly the work that is genuinely new.
  const pluralRows = [];
  for (const { singular, plural } of collectCounted()) {
    for (const category of pluralCategories(argument)) {
      const key = pluralRow(category, singular);
      const seed = category === "one" ? existing.get(singular) : existing.get(plural);
      pluralRows.push([key, existing.get(key) || seed || ""]);
    }
  }

  const rows = [["english", argument]]
    .concat(keys.map((key) => [key, existing.get(key) ?? ""]))
    .concat(pluralRows);
  writeFileSync(path, rows.map((r) => r.map(csvCell).join(",")).join("\n") + "\n");
  const kept = keys.filter((k) => existing.get(k)).length;
  console.log(
    `translations/${argument}.csv — ${keys.length} rows, ${kept} already translated. ` +
      `Fill the second column and run: node tools/translate.mjs build ${argument}`
  );
} else if (command === "build") {
  if (!argument) { console.error("usage: translate.mjs build <language-code>"); process.exit(2); }
  const path = join(OUT, `${argument}.csv`);
  if (!existsSync(path)) { console.error(`no translations/${argument}.csv — run: new ${argument}`); process.exit(1); }
  const rows = parseCSV(readFileSync(path, "utf8")).slice(1);
  const done = rows.filter(([, value]) => value && value.trim().length);
  const missing = rows.length - done.length;
  if (missing > 0 && !partial) {
    console.error(
      `${argument}: ${done.length} of ${rows.length} translated, ${missing} missing.\n\n` +
        "A language ships complete or not at all: an .lproj tells macOS \"Replay speaks this\",\n" +
        "and a Mac set to it would show translated and English lines mixed together with no way\n" +
        "to tell which is which. Pass --partial to build it anyway for testing."
    );
    process.exit(1);
  }
  const dir = join(LPROJ, `${argument}.lproj`);
  mkdirSync(dir, { recursive: true });
  // Plural rows go to the .stringsdict, everything else to the .strings. The two-form keys
  // stay in the .strings as well, and deliberately: they are what `Loc.count` falls back to
  // when a language has no plural entry for a noun, and a half-filled .stringsdict should
  // degrade to the old behaviour rather than to nothing.
  const plain = done.filter(([key]) => !key.startsWith(PLURAL_PREFIX));
  const plurals = done.filter(([key]) => key.startsWith(PLURAL_PREFIX));

  const body = plain
    .map(([key, value]) => `"${stringsEscape(key)}" = "${stringsEscape(value)}";`)
    .join("\n");
  writeFileSync(
    join(dir, "Replay.strings"),
    `/* Replay — ${argument}. Generated by tools/translate.mjs from translations/${argument}.csv.\n` +
      ` * Do not edit by hand: edit the CSV and rebuild, or the next build will overwrite you. */\n\n` +
      body + "\n"
  );

  // Grouped back into one entry per noun. A noun with no filled categories is left out
  // entirely rather than written half-empty: a `.stringsdict` entry missing the category a
  // number lands in returns nothing at all, which would be worse than the two-form fallback.
  const grouped = new Map();
  for (const [key, value] of plurals) {
    const rest = key.slice(PLURAL_PREFIX.length);
    const split = rest.indexOf(":");
    const category = rest.slice(0, split);
    const singular = rest.slice(split + 1);
    if (!grouped.has(singular)) grouped.set(singular, {});
    grouped.get(singular)[category] = value;
  }
  const wanted = pluralCategories(argument);
  const entries = [...grouped.entries()]
    .filter(([, forms]) => wanted.every((c) => forms[c]))
    .map(([singular, forms]) => ({ singular, forms }));
  const dropped = grouped.size - entries.length;

  if (entries.length > 0) {
    writeFileSync(join(dir, "Replay.stringsdict"), stringsdict(argument, entries));
  }

  console.log(
    `${argument}.lproj — ${plain.length} strings${missing ? `, ${missing} still English` : ""}` +
      `; ${entries.length} counted nouns across ${wanted.length} plural ` +
      `${wanted.length === 1 ? "category" : "categories"} (${wanted.join(", ")})` +
      `${dropped ? `, ${dropped} incomplete and left to the two-form fallback` : ""}`
  );
} else if (command === "record") {
  // Merge a run's log into the recorded set. Union rather than replace: one run visits the
  // surfaces that run visited, and nothing else — a missing key is evidence of a gap in the
  // *drive*, not evidence the string is gone.
  if (!argument) { console.error("usage: translate.mjs record <log-file>"); process.exit(2); }
  if (!existsSync(argument)) { console.error(`no such file: ${argument}`); process.exit(1); }
  mkdirSync(OUT, { recursive: true });
  const path = join(OUT, "runtime-keys.txt");
  const before = existsSync(path)
    ? new Set(readFileSync(path, "utf8").split("\n").map((l) => l.trim()).filter(Boolean))
    : new Set();
  const size = before.size;
  for (const line of readFileSync(argument, "utf8").split("\n")) {
    const text = line.trim();
    if (text && isCopy(text)) before.add(text);
  }
  const all = [...before].sort((a, b) => a.localeCompare(b, "en"));
  writeFileSync(path, all.join("\n") + "\n");
  console.log(`recorded ${all.length} keys (${all.length - size} new) → translations/runtime-keys.txt`);
} else if (command === "status") {
  const keys = collectKeys();
  const languages = existsSync(OUT)
    ? readdirSync(OUT).filter((f) => f.endsWith(".csv")).map((f) => f.replace(/\.csv$/, ""))
    : [];
  console.log(`${keys.length} strings in the app.\n`);
  if (!languages.length) console.log("No translations yet. Start one: node tools/translate.mjs new <code>");
  for (const language of languages) {
    const rows = parseCSV(readFileSync(join(OUT, `${language}.csv`), "utf8")).slice(1);
    const done = rows.filter(([, v]) => v && v.trim().length).length;
    // A `plural:` row is not a key and never will be — it is one form of a counted noun,
    // and the key it belongs to is the singular after the second colon. Counting them as
    // orphans would be a lie with teeth: this file's own warning is that somebody sweeping
    // "orphans" in bulk has already deleted correct translations here once, and twelve rows
    // per language reported as dead is exactly the invitation to do it again.
    const known = new Set(keys);
    const counted = new Set(collectCounted().map(({ singular }) => singular));
    const stale = rows.filter(([k]) => {
      if (!k.startsWith(PLURAL_PREFIX)) return !known.has(k);
      const rest = k.slice(PLURAL_PREFIX.length);
      const singular = rest.slice(rest.indexOf(":") + 1);
      // Orphaned only if the app stopped counting that noun, or the language stopped
      // having that category — both real, and both worth removing.
      const category = rest.slice(0, rest.indexOf(":"));
      return !counted.has(singular) || !pluralCategories(language).includes(category);
    }).length;
    const shipped = existsSync(join(LPROJ, `${language}.lproj`)) ? "shipped" : "not shipped";
    const percent = rows.length ? Math.round((done / rows.length) * 100) : 0;
    console.log(
      `  ${language.padEnd(6)} ${String(percent).padStart(3)}%  ` +
        `${done}/${rows.length}${stale ? `, ${stale} orphaned` : ""} · ${shipped}`
    );
  }
} else {
  console.error(
    "usage: translate.mjs keys | new <code> | build <code> [--partial] | record <log> | status"
  );
  process.exit(2);
}
