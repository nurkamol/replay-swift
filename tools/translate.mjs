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
  for (const dir of ["Sources/ReplayApp", "Sources/ReplayCore"]) {
    for (const file of swiftFiles(join(ROOT, dir))) {
      const source = joinConcatenations(readFileSync(file, "utf8"));
      for (const match of source.matchAll(/Loc\.t\(\s*"((?:[^"\\]|\\.)*)"/g)) {
        const text = unescape(match[1]);
        if (isCopy(text)) keys.add(text);
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
  const rows = [["english", argument]].concat(
    keys.map((key) => [key, existing.get(key) ?? ""])
  );
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
  const body = done
    .map(([key, value]) => `"${stringsEscape(key)}" = "${stringsEscape(value)}";`)
    .join("\n");
  writeFileSync(
    join(dir, "Replay.strings"),
    `/* Replay — ${argument}. Generated by tools/translate.mjs from translations/${argument}.csv.\n` +
      ` * Do not edit by hand: edit the CSV and rebuild, or the next build will overwrite you. */\n\n` +
      body + "\n"
  );
  console.log(`${argument}.lproj — ${done.length} strings${missing ? `, ${missing} still English` : ""}`);
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
    const stale = rows.filter(([k]) => !keys.includes(k)).length;
    const shipped = existsSync(join(LPROJ, `${language}.lproj`)) ? "shipped" : "not shipped";
    const percent = rows.length ? Math.round((done / rows.length) * 100) : 0;
    console.log(
      `  ${language.padEnd(6)} ${String(percent).padStart(3)}%  ` +
        `${done}/${rows.length}${stale ? `, ${stale} orphaned` : ""} · ${shipped}`
    );
  }
} else {
  console.error(
    "usage: translate.mjs keys | new <code> | build <code> [--partial] | status"
  );
  process.exit(2);
}
