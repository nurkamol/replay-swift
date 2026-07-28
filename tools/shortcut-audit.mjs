#!/usr/bin/env node
/**
 * Check that the shortcut catalogue and the app agree.
 *
 * `Sources/ReplayApp/Shortcuts.swift` is the single list the View menu is built from and the
 * Settings table renders. That covers the shortcuts a menu owns: change one and both move.
 *
 * It cannot cover the ones a SwiftUI view binds. `.keyboardShortcut` is a view modifier and
 * there is no way to tell AppKit about it from a catalogue, so those are declared in the
 * catalogue *and* bound in the view, which is two places again — exactly the arrangement
 * that let the old hand-written table drift.
 *
 * So this closes it from the other end, and in both directions:
 *
 *   · every entry with `boundInView:` must really be bound, in the file it names
 *   · every `.keyboardShortcut` in a view must be in the catalogue
 *
 * The second direction is the one that matters most. A shortcut added to a view and never
 * written down is invisible: it works, and the only place a person could have learned about
 * it says nothing. That is not a stale document, it is an undiscoverable feature.
 *
 *   node tools/shortcut-audit.mjs
 */

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const VIEWS = resolve(HERE, "..", "Sources", "ReplayApp");
const CATALOGUE = join(VIEWS, "Shortcuts.swift");

const problems = [];
const catalogue = readFileSync(CATALOGUE, "utf8");

/*
 * Bindings the catalogue deliberately does not claim, because no `keyboardShortcut` creates
 * them. `.defaultAction` is the Return key on a sheet's confirming button and `.cancelAction`
 * its Escape — the system's own behaviour, present on every dialog and worth nobody's table.
 * Escape and Space are bound by views for the surface they are in (leave the screensaver,
 * pause a playback) and appear in the catalogue under "Anywhere" as a description rather than
 * as one binding.
 */
const NOT_CLAIMED = new Set([".defaultAction", ".cancelAction", ".escape", ".space"]);

/**
 * Every `Entry(...)` in the catalogue, as a flat record.
 *
 * Parens are counted rather than matched with a regex. The first version used a non-greedy
 * `Entry\(([\s\S]*?)\n\s*\)`, which is right for the entries written across several lines
 * and silently wrong for the ones written on one: with no closing paren on its own line the
 * match ran on into the following entries and merged them, so a field belonging to one
 * shortcut was read as another's. It reported seven disagreements, six of them its own.
 */
function entries() {
  const out = [];
  for (let i = catalogue.indexOf("Entry("); i !== -1; i = catalogue.indexOf("Entry(", i + 1)) {
    let depth = 0;
    let end = i + "Entry".length;
    for (; end < catalogue.length; end += 1) {
      const c = catalogue[end];
      if (c === "(") depth += 1;
      else if (c === ")") {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    const body = catalogue.slice(i + "Entry(".length, end);
    const field = (name) => {
      const m = body.match(new RegExp(`${name}:\\s*"((?:[^"\\\\]|\\\\.)*)"`));
      return m ? m[1] : null;
    };
    const modifiers = body.match(/modifiers:\s*\[([^\]]*)\]/);
    out.push({
      label: field("label"),
      key: field("key"),
      boundInView: field("boundInView"),
      // Absent means the default, which the catalogue declares as `[.command]`.
      modifiers: modifiers
        ? modifiers[1].split(",").map((m) => m.trim()).filter(Boolean)
        : [".command"],
    });
  }
  return out;
}

const declared = entries();
if (declared.length === 0) problems.push("no Entry(...) found — has Shortcuts.swift moved?");

// ── direction one: what the catalogue claims a view binds, the view must bind ──

for (const entry of declared) {
  if (!entry.boundInView) continue;
  let source;
  try {
    source = readFileSync(join(VIEWS, entry.boundInView), "utf8");
  } catch {
    problems.push(`${entry.label}: names ${entry.boundInView}, which does not exist`);
    continue;
  }
  // `⌘−` is written "-" in the catalogue and bound as "-", but a keyboard also sends "=" for
  // an unshifted "+", which the Canvas binds as a second alias. Either spelling satisfies it.
  const aliases = entry.key === "+" ? ["+", "="] : [entry.key];
  const bound = aliases.some((key) => {
    const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(`keyboardShortcut\\("${escaped}"`).test(source);
  });
  if (!bound) {
    problems.push(
      `${entry.label}: the catalogue says ${entry.boundInView} binds "${entry.key}", ` +
        "and it does not",
    );
  }
}

// ── direction two: what a view binds, the catalogue must know about ────────────

const claimedKeys = new Set(declared.map((e) => e.key));
for (const file of readdirSync(VIEWS).filter((f) => f.endsWith(".swift"))) {
  if (file === "Shortcuts.swift") continue;
  const source = readFileSync(join(VIEWS, file), "utf8");
  for (const match of source.matchAll(/keyboardShortcut\(\s*("(?:[^"\\]|\\.)*"|\.\w+)/g)) {
    const bound = match[1].trim();
    if (NOT_CLAIMED.has(bound)) continue;
    const key = bound.startsWith('"') ? bound.slice(1, -1) : bound;
    // "=" is the Canvas's alias for "+", declared as "+".
    if (claimedKeys.has(key) || (key === "=" && claimedKeys.has("+"))) continue;
    problems.push(
      `${file} binds ${bound}, which is in no Shortcuts entry — so it works and nothing ` +
        "in the app tells anybody it exists",
    );
  }
}

if (problems.length === 0) {
  console.log(
    `shortcut audit: ${declared.length} shortcuts, and the catalogue matches what is bound.`,
  );
  process.exit(0);
}

console.error(`shortcut audit: ${problems.length} disagreement(s)\n`);
for (const problem of problems) console.error(`  ${problem}`);
console.error(
  "\nShortcuts.swift is the list the View menu and Settings are both built from. Add the" +
    "\nbinding to it, or bind what it already promises.",
);
process.exit(1);
