#!/usr/bin/env node
/**
 * Pull one version's section out of CHANGELOG.md.
 *
 * The release notes on a GitHub release and the entry in the changelog are the same text,
 * so only one of them is written. Two copies of a release's description is how the download
 * page and the repository end up disagreeing about what shipped — and the copy people read
 * is the one nobody maintains.
 *
 * It also checks, and this is most of the value: the version asked for must be the *newest*
 * entry. Tagging v0.9.0 while the changelog has already moved to 0.10.0 means the tag is
 * describing something other than what is being built, and that is worth stopping for.
 *
 *   node tools/release-notes.mjs 0.9.0
 *   node tools/release-notes.mjs 0.9.0 --check   # say nothing, just verify
 */

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const CHANGELOG = join(resolve(HERE, ".."), "CHANGELOG.md");

const wanted = (process.argv[2] ?? "").replace(/^v/, "");
const checkOnly = process.argv.includes("--check");

if (!wanted) {
  console.error("usage: release-notes.mjs <version> [--check]");
  process.exit(1);
}

const lines = readFileSync(CHANGELOG, "utf8").split("\n");

/* Headings look like `## 0.9.0 — 2026-07-28`, and older ones may still say `## Unreleased
   — 0.1.0`. Only the released form counts: an unreleased entry is not something to tag. */
const headings = [];
lines.forEach((line, index) => {
  const match = line.match(/^## (\d+\.\d+\.\d+)\s+—/);
  if (match) headings.push({ version: match[1], index });
});

if (headings.length === 0) {
  console.error("release-notes: no released version headings in CHANGELOG.md");
  process.exit(1);
}

const newest = headings[0].version;
if (newest !== wanted) {
  console.error(
    `release-notes: asked for ${wanted}, but the newest entry in CHANGELOG.md is ${newest}.\n` +
      `               A tag that does not match the changelog describes something other\n` +
      `               than what is being built. Fix one of them before releasing.`,
  );
  process.exit(1);
}

if (checkOnly) process.exit(0);

const start = headings[0].index;
const end = headings[1]?.index ?? lines.length;
const body = lines.slice(start + 1, end).join("\n").trim();

if (!body) {
  console.error(`release-notes: ${wanted} has a heading and no body.`);
  process.exit(1);
}

process.stdout.write(body + "\n");
