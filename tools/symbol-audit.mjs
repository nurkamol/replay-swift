#!/usr/bin/env node
/* Every SF Symbol the interface uses exists on the oldest macOS this app supports.
 *
 * **A symbol that is too new does not fail — it draws nothing.** No crash, no warning, no
 * fallback: an empty space where an icon should be, on somebody else's Mac, in a build that
 * looked perfect here. That is the worst shape a bug can have, and this project has now
 * lowered its floor to macOS 14 while developing on 27, which is exactly the gap where it
 * happens.
 *
 * The answer is not to guess. macOS ships the manifest itself —
 * `CoreGlyphs.bundle/Contents/Resources/name_availability.plist` maps every symbol to the
 * release that introduced it — so this reads Apple's own record rather than a list somebody
 * maintained by hand and stopped updating.
 *
 *   node tools/symbol-audit.mjs           # fails if any symbol is newer than the floor
 *   node tools/symbol-audit.mjs --list    # every symbol and the release it arrived in
 *
 * The floor is read from `Package.swift`, so raising or lowering the deployment target moves
 * this check with it and cannot be forgotten.
 */
import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { readdirSync, statSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "..");
const LIST = process.argv.includes("--list");

const MANIFEST =
  "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist";

/* The deployment target, from the one place it is declared. */
function floor() {
  const manifest = readFileSync(join(ROOT, "Package.swift"), "utf8");
  const match = manifest.match(/\.macOS\(\.v(\d+)\)/);
  if (!match) {
    console.error("symbol audit: could not read the deployment target from Package.swift.");
    process.exit(1);
  }
  return Number(match[1]);
}

function swiftFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) out.push(...swiftFiles(path));
    else if (entry.endsWith(".swift")) out.push(path);
  }
  return out;
}

if (!existsSync(MANIFEST)) {
  // Not a failure: a machine without the manifest cannot answer, and inventing an answer
  // would be worse than saying so. CI runs on macOS and will have it.
  console.log("symbol audit: skipped — macOS's symbol manifest is not on this machine.");
  process.exit(0);
}

const raw = execFileSync("plutil", ["-convert", "json", "-o", "-", MANIFEST], {
  maxBuffer: 64 * 1024 * 1024,
});
const { symbols, year_to_release: releases } = JSON.parse(raw.toString());

const target = floor();
const used = new Map(); // symbol → [where it is used]

for (const dir of ["Sources/ReplayUI", "Sources/ReplayApp"]) {
  const full = join(ROOT, dir);
  if (!existsSync(full)) continue;
  for (const file of swiftFiles(full)) {
    const rel = relative(ROOT, file);
    readFileSync(file, "utf8").split("\n").forEach((line, index) => {
      if (/^\s*(\/\/|\*|\/\*)/.test(line)) return;
      for (const match of line.matchAll(/(?:systemName|systemImage):\s*"([^"]+)"/g)) {
        const list = used.get(match[1]) ?? [];
        list.push(`${rel}:${index + 1}`);
        used.set(match[1], list);
      }
    });
  }
}

const tooNew = [];
const unknown = [];
const rows = [];

for (const [symbol, where] of [...used.entries()].sort()) {
  const year = symbols[symbol];
  const introduced = year ? releases[year]?.macOS : undefined;
  if (!introduced) {
    unknown.push({ symbol, where });
    continue;
  }
  rows.push({ symbol, introduced });
  if (Number(introduced.split(".")[0]) > target) tooNew.push({ symbol, introduced, where });
}

if (LIST) {
  for (const r of rows.sort((a, b) => a.symbol.localeCompare(b.symbol))) {
    console.log(`  ${r.symbol.padEnd(34)} macOS ${r.introduced}`);
  }
  console.log("");
}

/* A name macOS has never heard of draws nothing too, so a typo is the same bug by another
   route — and it is the more likely one. */
if (unknown.length > 0) {
  console.error("symbol audit: a symbol name macOS does not know.\n");
  for (const u of unknown) console.error(`  ${u.symbol}  at ${u.where.join(", ")}`);
  console.error("\nIt will draw nothing. Check the spelling against the SF Symbols app.");
  process.exit(1);
}

if (tooNew.length > 0) {
  console.error(
    `symbol audit: ${tooNew.length} symbol${tooNew.length === 1 ? "" : "s"} newer than ` +
      `macOS ${target}, the deployment target.\n`
  );
  for (const t of tooNew) {
    console.error(`  ${t.symbol}  needs macOS ${t.introduced}  at ${t.where.join(", ")}`);
  }
  console.error(
    "\nThese draw *nothing* on an older Mac — no crash and no warning, just a gap where the\n" +
      "icon should be. Choose an older symbol, or ship a custom asset for it."
  );
  process.exit(1);
}

console.log(
  `symbol audit: ${used.size} SF Symbols, all available on macOS ${target} — the deployment ` +
    `target — or earlier.`
);
