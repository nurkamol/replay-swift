#!/usr/bin/env node
/**
 * One version, in four places, agreeing.
 *
 *   node tools/version-audit.mjs
 *
 * Why this exists
 * ---------------
 * The version is written down four times and nothing compared them:
 *
 *   1. `scripts/make-app.sh`      — what goes into `CFBundleShortVersionString`
 *   2. `Replay.fallbackVersion`   — what the binary says when there is no bundle
 *   3. `CHANGELOG.md`             — the newest entry
 *   4. `releases` in Changelog.swift — the newest entry of the in-app history
 *
 * Three of those were bumped for 0.9.1, 0.9.2 and 0.9.3. The second was not, and it was the
 * one the *update check* compared against — so a 0.9.2 build believed it was 0.9.0, told its
 * owner "you have 0.9.0", and would have offered an update to the version it was already
 * running. Every test passed. `tools/release-notes.mjs --check` passed, because it compared
 * the tag against `make-app.sh` and the changelog and never looked at the Swift.
 *
 * A version that disagrees with itself is not a cosmetic problem: it is the input to the
 * comparison that decides whether to replace the application.
 */

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => readFileSync(join(ROOT, p), "utf8");

const found = [];

const build = read("scripts/make-app.sh").match(/^VERSION="([^"]+)"/m);
found.push({ where: "scripts/make-app.sh", version: build?.[1] });

const fallback = read("Sources/ReplayCore/Changelog.swift")
  .match(/fallbackVersion\s*=\s*"([^"]+)"/);
found.push({ where: "Replay.fallbackVersion", version: fallback?.[1] });

const changelog = read("CHANGELOG.md").match(/^## (\d+\.\d+\.\d+)\s+—/m);
found.push({ where: "CHANGELOG.md (newest)", version: changelog?.[1] });

/* The Xcode project's copy — three settings that all have to agree with the rest.
 *
 * `project.yml` exists because SwiftPM cannot describe an application bundle, and the price
 * of it is that the version is written down in a second place. That price is only worth
 * paying if the two cannot drift, which is what this checks. Nothing published comes from
 * the project — `make-app.sh` is still what ships — so a disagreement here would show up as
 * an Xcode build reporting a version nobody released, which is the confusing kind of wrong. */
const project = read("project.yml");
for (const [key, label] of [
  ["CFBundleShortVersionString", "project.yml (Info.plist)"],
  ["MARKETING_VERSION", "project.yml (MARKETING_VERSION)"],
]) {
  const match = project.match(new RegExp(`${key}:\\s*"([^"]+)"`));
  found.push({ where: label, version: match?.[1] });
}

/* The first `version:` inside the `releases` array — the in-app history's newest entry. */
const source = read("Sources/ReplayCore/Changelog.swift");
const list = source.slice(source.indexOf("public let releases"));
const inApp = list.match(/version:\s*"([^"]+)"/);
found.push({ where: "releases (in-app, newest)", version: inApp?.[1] });

const missing = found.filter((f) => !f.version);
if (missing.length > 0) {
  console.error("version audit: could not read a version from:\n");
  for (const m of missing) console.error(`  ${m.where}`);
  console.error("\nThe audit's own patterns have gone stale — fix them before trusting it.");
  process.exit(1);
}

const versions = new Set(found.map((f) => f.version));
if (versions.size > 1) {
  console.error("version audit: the version disagrees with itself.\n");
  for (const f of found) console.error(`  ${f.version.padEnd(10)} ${f.where}`);
  console.error(
    `\nAll ${found.length} have to match before a release. \`Replay.fallbackVersion\` is what ` +
      "the update\ncheck compares against, so a stale value there offers an update to the " +
      "version already\nrunning; the two in project.yml only reach Xcode, and a build " +
      "reporting a version nobody\nreleased is the confusing kind of wrong."
  );
  process.exit(1);
}

console.log(`version audit: ${[...versions][0]}, agreed in all ${found.length} places.`);
