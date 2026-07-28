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
const MIGRATED = [
  "Sources/ReplayCore/MenuBar.swift",
];

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
const withoutInterpolation = (s) => s.replace(/\\\([^)]*\)/g, "");

const isWord = (s) => {
  const text = withoutInterpolation(s);
  return text.length > 1 && /\p{L}/u.test(text) && !NOT_WORDS.some((re) => re.test(text));
};

const findings = [];
const counts = new Map();

for (const file of ["Sources/ReplayCore", "Sources/ReplayApp"].flatMap((d) =>
  swiftFiles(join(ROOT, d))
)) {
  const rel = relative(ROOT, file);
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
      const constant = /\b(?:let|var)\s+\w+(?::\s*String)?\s*=\s*"((?:[^"\\]|\\.)*)"/g;
      for (const match of line.matchAll(constant)) {
        const text = match[1];
        if (!isWord(text)) continue;
        findings.push({ file: rel, line: index + 1, call: "constant", text });
        counts.set(rel, (counts.get(rel) ?? 0) + 1);
      }
    }

    for (const call of CALLS) {
      // The literal has to be the *first* argument and not already wrapped.
      const re = new RegExp(`\\b${call}\\(\\s*"((?:[^"\\\\]|\\\\.)*)"`, "g");
      for (const match of line.matchAll(re)) {
        const text = match[1];
        if (!isWord(text)) continue;
        findings.push({ file: rel, line: index + 1, call, text });
        counts.set(rel, (counts.get(rel) ?? 0) + 1);
      }
    }
  });
}

const reached = findings.filter((f) => MIGRATED.includes(f.file));
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

const byFile = [...counts.entries()].sort((a, b) => b[1] - a[1]);
console.log(
  `strings audit: ${MIGRATED.length} file${MIGRATED.length === 1 ? "" : "s"} localised and holding; ` +
    `${total} string${total === 1 ? "" : "s"} still hard-coded across ${byFile.length} files.`
);
if (byFile.length > 0 && !LIST) {
  const top = byFile.slice(0, 5).map(([f, n]) => `${n} in ${f.split("/").pop()}`);
  console.log(`  most of them: ${top.join(", ")} — \`--list\` for all of them.`);
}
