#!/usr/bin/env node
/**
 * Every word the app says, and whether a translator could reach it.
 *
 *   node tools/strings-audit.mjs           # the inventory, and enforce the migrated files
 *   node tools/strings-audit.mjs --list    # every unreached string, with its file and line
 *
 * Why a ratchet rather than a gate
 * --------------------------------
 * There are several hundred user-facing strings and one language. An audit that failed on
 * all of them would fail from the day it was written until the day the last one moved, which
 * is an audit nobody runs. So it works the other way round: `MIGRATED` lists the files that
 * have been through, and for *those* a bare user-facing literal is an error. Everything else
 * is counted and reported.
 *
 * The property it actually protects is the one that decays silently — a file that was fully
 * localised growing a hard-coded sentence six months later, which nothing else would notice
 * until somebody read the app in another language and found one English line in the middle
 * of a paragraph.
 *
 * What counts as user-facing
 * --------------------------
 * The SwiftUI and AppKit calls that put a string in front of somebody. Deliberately not
 * every literal in the source: an SF Symbol name, a `UserDefaults` key, a table name and a
 * bundle identifier are all strings, none of them are words, and an audit that flags them
 * teaches people to ignore it.
 */

import { readFileSync, readdirSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const LIST = process.argv.includes("--list");

/** Files that have been through, and must stay through. */
const MIGRATED = [];

/* `ReplayCore` holds copy as *keys*, not as text to translate in place — and one rule for
   the whole module rather than a per-file judgement.
 *
 * The reason is the contract. A third of this copy is compared character for character
 * against the reference: the Guide's sixteen answers, the Settings explanations, the
 * narrative surfaces, the report text. `ParityKit` reads those values directly, so if the
 * definition resolved through `Loc` it would return a translation on a translated machine
 * and 200-odd checks would fail for a reason that has nothing to do with the port drifting.
 * CI runs in four timezones today, and would be the last place to notice.
 *
 * So the English stays literal where it is defined, and the *view* wraps it — `Text(Loc.t(
 * entry.answer))`. The exception, and it is a real one, is a function that composes a
 * sentence out of parts: there the format string is the translatable unit and has to go
 * through `Loc` inside the module, which is why `MenuBar.focusedFor` does and
 * `MenuBar.pausedLabel` does not. */
const KEYS_NOT_COPY = "Sources/ReplayCore/";

/* The calls that put words in front of a person. `Text(...)` and friends take a
   `LocalizedStringKey`, but that resolves against the *main* bundle — which for this package
   is the app, not `ReplayCore` where the catalogue lives — so they are wrapped explicitly
   through `Loc.t` rather than left to SwiftUI. */
const CALLS = [
  "Text", "Label", "Button", "Toggle", "Picker", "Link", "TextField", "SecureField",
  "navigationTitle", "help", "accessibilityLabel", "accessibilityHint", "confirmationDialog",
  "alert",
];

/* Strings that are identifiers rather than words. */
const NOT_WORDS = [
  /^[a-z0-9]+([.-][a-z0-9]+)+$/i,      // bundle ids, symbol names, reverse-dns
  /^[a-z]+([A-Z][a-z0-9]*)+$/,          // camelCase keys
  /^[\s\p{P}\p{S}\d]*$/u,               // punctuation, digits, arrows and nothing else
  /^%@?[a-z]?$/i,                        // a bare format specifier
];

const swiftFiles = (dir) =>
  readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return swiftFiles(path);
    return entry.name.endsWith(".swift") ? [path] : [];
  });

/* Interpolations are values, not words. `Text("\(count)")` and `Text("#\(tag)")` have
   nothing in them for a translator, and counting them inflates the inventory with work that
   does not exist. What is left after removing them is the part somebody would translate. */
const withoutInterpolation = (s) => {
  // Balance-aware, because interpolations nest: `\(Int((fraction * 100).rounded()))` has
  // three levels, and a `[^)]*` regex stops at the first `)` and leaves the tail behind —
  // which made a bare percentage look like a sentence.
  let out = "";
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "\\" && s[i + 1] === "(") {
      let depth = 1;
      i += 2;
      while (i < s.length && depth > 0) {
        if (s[i] === "(") depth++;
        else if (s[i] === ")") depth--;
        i++;
      }
      i--;
      continue;
    }
    out += s[i];
  }
  return out;
};

const isWord = (s) => {
  const text = withoutInterpolation(s);
  return text.length > 1 && /\p{L}/u.test(text) && !NOT_WORDS.some((re) => re.test(text));
};

/* A string that is *only* interpolation is a value, not a sentence. `Text("\(percent)")`
   has nothing in it for a translator, and wrapping one made the rendered number its own
   lookup key — a new key on every repaint. */
const isOnlyInterpolation = (s) => withoutInterpolation(s).trim().length === 0;

const findings = [];
const counts = new Map();

/* The mechanism is not copy. `Loc.table` is an identifier that happens to be a word. */
const SKIP = ["Sources/ReplayCore/Localization.swift"];

for (const file of ["Sources/ReplayCore", "Sources/ReplayUI", "Sources/ReplayApp"].flatMap((d) =>
  swiftFiles(join(ROOT, d))
)) {
  const rel = relative(ROOT, file);
  if (SKIP.includes(rel)) continue;
  const lines = readFileSync(file, "utf8").split("\n");

  lines.forEach((line, index) => {
    // Comments and doc comments are not shipped copy.
    if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;

    /* `ReplayCore` holds its copy as constants rather than in view calls: the sixteen
       Guide answers, the Settings explanations, the narrative surfaces, the menu bar's
       labels. That is the larger body of words in the app, and an audit that only read
       view call sites would report the interface as nearly done while the prose was
       untouched. */
    if (rel.startsWith("Sources/ReplayCore/")) {
      /* Three shapes, because the copy is written three ways and an audit that saw only
         one reported the largest body of prose in the app as absent. `Guide`'s sixteen
         answers are constructor arguments; `SettingsCopy`'s explanations are the return
         value of a switch case; the rest are plain constants. All three continue across
         lines with `+`, so a bare quoted string on its own line counts too. */
      const shapes = [
        /\b(?:let|var)\s+\w+(?::\s*[\w<>\[\]?]+)?\s*=\s*"((?:[^"\\]|\\.)*)"/g,  // constant
        /\b\w+:\s*"((?:[^"\\]|\\.)*)"/g,                                            // argument
        /^\s*(?:case\s+[^:]+:\s*)?"((?:[^"\\]|\\.)*)"\s*$/g,                        // switch return
        /^\s*\+\s*"((?:[^"\\]|\\.)*)"/g,                                            // continuation
      ];
      for (const shape of shapes) {
        for (const match of line.matchAll(shape)) {
          const text = match[1];
          if (!isWord(text)) continue;
          findings.push({ file: rel, line: index + 1, call: "copy", text });
          counts.set(rel, (counts.get(rel) ?? 0) + 1);
          break; // one finding per line, however many shapes match it
        }
      }
    }

    for (const call of CALLS) {
      // The literal has to be the *first* argument and not already wrapped.
      const re = new RegExp(`\\b${call}\\(\\s*"((?:[^"\\\\]|\\\\.)*)"`, "g");
      for (const match of line.matchAll(re)) {
        const text = match[1];
        if (!isWord(text) || isOnlyInterpolation(text)) continue;
        findings.push({ file: rel, line: index + 1, call, text });
        counts.set(rel, (counts.get(rel) ?? 0) + 1);
      }
    }
  });
}

/* A format string and its arguments, counted.
 *
 * This is here because it crashed the app. Wrapping the interface produced six calls whose
 * format wanted two or three arguments and was handed one — `String(format:)` then reads
 * whatever is next on the stack and segfaults. Nothing else caught it: it builds, the tests
 * pass, the audits pass, and the app dies the moment the view draws. The screenshot harness
 * found it only because the app failed to open a window at all.
 *
 * Counts across lines, since a wrapped call is usually written over several. */
const mismatches = [];
for (const file of ["Sources/ReplayCore", "Sources/ReplayUI", "Sources/ReplayApp"].flatMap((d) =>
  swiftFiles(join(ROOT, d))
)) {
  const rel = relative(ROOT, file);
  const text = readFileSync(file, "utf8");
  const call = /String\(\s*format:\s*Loc\.t\("((?:[^"\\]|\\.)*)"\)\s*,/g;
  for (const match of text.matchAll(call)) {
    const specifiers = new Set((match[1].match(/%(\d+)\$@/g) ?? []).map((s) => s));
    const positional = specifiers.size;
    const plain = (match[1].match(/%@/g) ?? []).length;
    const wanted = positional > 0 ? positional : plain;

    // Walk the argument list to its closing paren, counting top-level commas.
    let depth = 0, args = 1, i = match.index + match[0].length;
    for (; i < text.length; i++) {
      const c = text[i];
      if (c === "(" || c === "[") depth++;
      else if (c === "]") depth--;
      else if (c === ")") { if (depth === 0) break; depth--; }
      else if (c === "," && depth === 0) args++;
      else if (c === '"') { i++; while (i < text.length && (text[i] !== '"' || text[i - 1] === "\\")) i++; }
    }
    const line = text.slice(0, match.index).split("\n").length;
    if (wanted !== args) {
      mismatches.push({ file: rel, line, wanted, args, fmt: match[1] });
    }
  }
}

if (mismatches.length > 0) {
  console.error("strings audit: a format string does not match its arguments.\n");
  for (const m of mismatches) {
    console.error(`  ${m.file}:${m.line}  "${m.fmt}" wants ${m.wanted}, given ${m.args}`);
  }
  console.error("\nString(format:) reads past its arguments and crashes. Fix before shipping.");
  process.exit(1);
}

const reached = findings.filter((f) => MIGRATED.includes(f.file));
/* Core copy is counted separately: it is not *missing* localisation, it is the key side of
   it. What matters for those is that the view displaying them wraps them, which no static
   check here can see — it is covered by the app-side count instead. */
const keys = findings.filter((f) => f.file.startsWith(KEYS_NOT_COPY));
const app = findings.filter((f) => !f.file.startsWith(KEYS_NOT_COPY));
const total = findings.length;

if (LIST) {
  for (const f of findings.sort((a, b) => a.file.localeCompare(b.file) || a.line - b.line)) {
    console.log(`${f.file}:${f.line}  ${f.call}("${f.text}")`);
  }
  console.log("");
}

if (reached.length > 0) {
  console.error("strings audit: a migrated file grew a hard-coded string.\n");
  for (const f of reached) {
    console.error(`  ${f.file}:${f.line}  ${f.call}("${f.text}")`);
  }
  console.error("\nWrap it in Loc.t(…) so a translator can reach it.");
  process.exit(1);
}

const byFile = [...counts.entries()]
  .filter(([f]) => !f.startsWith(KEYS_NOT_COPY))
  .sort((a, b) => b[1] - a[1]);

console.log(
  `strings audit: ${app.length} string${app.length === 1 ? "" : "s"} in the interface still ` +
    `hard-coded across ${byFile.length} files; ${keys.length} in ReplayCore are keys the ` +
    `views translate.`
);
if (byFile.length > 0 && !LIST) {
  const top = byFile.slice(0, 5).map(([f, n]) => `${n} in ${f.split("/").pop()}`);
  console.log(`  most of them: ${top.join(", ")} — \`--list\` for all of them.`);
} else if (byFile.length === 0) {
  console.log("  every string a reader sees goes through Loc.");
}
