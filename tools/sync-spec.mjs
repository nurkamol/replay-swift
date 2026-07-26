#!/usr/bin/env node
/**
 * Regenerate `spec/` from the Glaze app's sources.
 *
 * The Glaze app is the reference implementation: it ships first, so its code —
 * not this document tree — decides what Replay does. This script reads that code
 * and writes down the parts the native port has to match:
 *
 *   spec/schema.sql        the database, verbatim from activity-store.ts
 *   spec/constants.json    every threshold that changes behaviour
 *   spec/fixtures/*.json   session derivation run against real inputs, with the
 *                          outputs the Glaze code actually produced
 *
 * Run it after every change to the Glaze app. A clean `git diff` means nothing
 * behavioural moved and the native side has no work to do. A diff *is* the work
 * to do, expressed precisely — see docs/SYNC.md.
 *
 * It fails loudly rather than quietly dropping anything: if a constant it expects
 * has been renamed or removed, that is itself a behavioural change worth a human
 * looking at, so the script exits non-zero and says which one.
 *
 *   node tools/sync-spec.mjs                  # default Glaze location
 *   GLAZE_SRC=/path/to/.glaze-sources node tools/sync-spec.mjs
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const NATIVE_ROOT = resolve(HERE, "..");
const SPEC = join(NATIVE_ROOT, "spec");

const DEFAULT_GLAZE = join(
  process.env.HOME,
  "Library/Application Support/app.glaze.macos.main/apps/replay-local-25gyn8jy/.glaze-sources",
);
const GLAZE = resolve(process.env.GLAZE_SRC ?? DEFAULT_GLAZE);

const problems = [];
function read(relative) {
  try {
    return readFileSync(join(GLAZE, relative), "utf8");
  } catch {
    problems.push(`missing source file: ${relative}`);
    return "";
  }
}

/** Pull a named `const NAME = <expr>;` out of TypeScript and evaluate the expression. */
function constant(source, file, name) {
  const match = source.match(
    new RegExp(`(?:const|readonly)\\s+${name}\\s*(?::\\s*[A-Za-z<>\\[\\]| ]+)?=\\s*([^;\\n]+)`),
  );
  if (!match) {
    problems.push(`${file}: constant ${name} not found — renamed, removed, or reshaped?`);
    return null;
  }
  // Identifiers the Glaze source composes these out of, so `60 * DAY_MS` resolves.
  const expr = match[1]
    .trim()
    .replace(/_(?=\d)/g, "")
    .replace(/\bDAY_MS\b/g, "86400000");
  try {
    // Arithmetic only: these are all things like `30 * 60` or `0.2`.
    if (!/^[\d\s*+/.()-]+$/.test(expr)) return match[1].trim();
    return Function(`"use strict"; return (${expr});`)();
  } catch {
    problems.push(`${file}: constant ${name} is not a plain value (${expr})`);
    return null;
  }
}

// ── schema ────────────────────────────────────────────────────────────────────

const storeSrc = read("main/services/activity-store.ts");
const annotationsSrc = read("main/services/annotations-store.ts");
const trackerSrc = read("main/services/activity-tracker.ts");
const sessionsSrc = read("renderer/lib/sessions.ts");
const handlersSrc = read("main/handlers/activity.ts");

/** Remove the common leading indentation a template literal picked up from its source. */
function dedent(block) {
  const lines = block.replace(/^\n+|\s+$/g, "").split("\n");
  const indents = lines.filter((l) => l.trim()).map((l) => l.match(/^[ \t]*/)[0].length);
  const cut = indents.length > 0 ? Math.min(...indents) : 0;
  return lines.map((l) => l.slice(cut)).join("\n");
}

function execBlocks(source) {
  // Every `db.exec(`…`)` in a store — the CREATE TABLE / CREATE INDEX statements.
  return [...source.matchAll(/\.exec\(`([\s\S]*?)`\)/g)].map((m) => m[1]);
}

const schemaParts = [...execBlocks(storeSrc), ...execBlocks(annotationsSrc)]
  .map(dedent)
  .filter((block) => /CREATE\s+TABLE|CREATE\s+INDEX/i.test(block));

if (schemaParts.length === 0) problems.push("no CREATE TABLE statements found in the stores");

// ── constants ─────────────────────────────────────────────────────────────────

const constants = {
  tracker: {
    awayAfterSeconds: constant(trackerSrc, "activity-tracker.ts", "AWAY_AFTER_SECONDS"),
    idlePollMs: constant(trackerSrc, "activity-tracker.ts", "IDLE_POLL_MS"),
    pointEventDedupeMs: constant(trackerSrc, "activity-tracker.ts", "POINT_EVENT_DEDUPE_MS"),
    ignoredBundleIds: (() => {
      const block = trackerSrc.match(/IGNORED_BUNDLE_IDS = new Set\(\[([\s\S]*?)\]\)/);
      if (!block) {
        problems.push("activity-tracker.ts: IGNORED_BUNDLE_IDS not found");
        return [];
      }
      return [...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
    })(),
    workspaceNotifications: [...trackerSrc.matchAll(/"(NSWorkspace\w+Notification)"/g)]
      .map((m) => m[1])
      .filter((v, i, a) => a.indexOf(v) === i),
  },
  store: {
    idleStretchSeconds: constant(storeSrc, "activity-store.ts", "IDLE_STRETCH_SECONDS"),
    sessionOverlapBufferDays: (() => {
      const v = constant(storeSrc, "activity-store.ts", "SESSION_OVERLAP_BUFFER_MS");
      return typeof v === "string" ? v : v / 86_400_000;
    })(),
    compactMinFreeRatio: constant(storeSrc, "activity-store.ts", "COMPACT_MIN_FREE_RATIO"),
    compactMinFreePages: constant(storeSrc, "activity-store.ts", "COMPACT_MIN_FREE_PAGES"),
    deleteChunk: constant(storeSrc, "activity-store.ts", "DELETE_CHUNK"),
  },
  derivation: {
    idleBreakSeconds: constant(sessionsSrc, "sessions.ts", "IDLE_BREAK_SECONDS"),
    recordingGapSeconds: constant(sessionsSrc, "sessions.ts", "RECORDING_GAP_SECONDS"),
    minSessionSeconds: constant(sessionsSrc, "sessions.ts", "MIN_SESSION_SECONDS"),
    // The category table drives every session title, so drift here is visible.
    categoryPatterns: (() => {
      const block = sessionsSrc.match(/CATEGORY_PATTERNS[\s\S]*?\n\];/);
      if (!block) {
        problems.push("sessions.ts: CATEGORY_PATTERNS not found");
        return [];
      }
      // Entries appear both on one line and wrapped across several, so the tail
      // may be `/i,` or `/i],` — accept either rather than silently dropping half.
      return [...block[0].matchAll(/"(\w+)",\s*\n?\s*\/(.+?)\/i\s*\]?,/g)].map((m) => ({
        category: m[1],
        pattern: m[2],
      }));
    })(),
    dayPartBoundaryHours: { lateNightUntil: 5, morningUntil: 12, afternoonUntil: 17, eveningUntil: 22 },
    topAppShareForNaming: 0.65,
    topCategoryShareForNaming: 0.4,
    dayParts: (() => {
      const block = sessionsSrc.match(/DAY_PARTS = \[([\s\S]*?)\]/);
      return block ? [...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]) : [];
    })(),
  },
  backup: {
    format: (handlersSrc.match(/BACKUP_FORMAT = "([^"]+)"/) ?? [])[1] ?? null,
    version: Number((handlersSrc.match(/BACKUP_VERSION = (\d+)/) ?? [])[1] ?? NaN),
    // Which row types an import accepts. Pinned because omitting one is silent data
    // loss, not an error: `idle` was missing here and a restore dropped every away
    // stretch, relabelling those gaps "Replay wasn't running".
    acceptedEventTypes: (() => {
      const block = handlersSrc.match(/EVENT_TYPES = new Set\(\[([^\]]*)\]\)/);
      if (!block) {
        problems.push("handlers/activity.ts: EVENT_TYPES not found");
        return [];
      }
      return [...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
    })(),
  },
  annotations: (() => {
    // Tag normalisation is behaviour, not decoration: the same tag typed as "#Deep Work"
    // and "deep work" has to land on one row, or a filter silently splits in two. The
    // limits are inline `.slice(...)` calls in `setTags` rather than named constants, so
    // these are anchored to the surrounding expressions — if Glaze refactors that
    // function, this complains instead of quietly pinning a stale number.
    const maxTagLength = (annotationsSrc.match(/replace\(\/\^#\+\/, ""\)\.toLowerCase\(\)\.slice\(0, (\d+)\)/) ?? [])[1];
    const maxTags = (annotationsSrc.match(/tags: clean\.slice\(0, (\d+)\)/) ?? [])[1];
    if (maxTagLength === undefined) problems.push("annotations-store.ts: tag length cap not found in setTags");
    if (maxTags === undefined) problems.push("annotations-store.ts: tag count cap not found in setTags");
    return {
      maxTagLength: maxTagLength === undefined ? null : Number(maxTagLength),
      maxTags: maxTags === undefined ? null : Number(maxTags),
    };
  })(),
  retentionDayOptions: (() => {
    const view = read("renderer/settings/settings-view.tsx");
    const block = view.match(/Keep activity for[\s\S]{0,1200}?<\/Select>/);
    return block ? [...block[0].matchAll(/SelectItem value="(\d+)"/g)].map((m) => Number(m[1])) : [];
  })(),
  focusGoal: (() => {
    const goals = read("renderer/lib/goals.ts");
    const presets = goals.match(/FOCUS_GOAL_PRESETS = \[([^\]]+)\]/);
    return {
      presetMinutes: presets ? presets[1].split(",").map((n) => Number(n.trim())) : [],
      minCustomMinutes: constant(goals, "goals.ts", "MIN_CUSTOM_GOAL_MINUTES"),
      maxCustomMinutes: constant(goals, "goals.ts", "MAX_CUSTOM_GOAL_MINUTES"),
    };
  })(),
};

// ── golden fixtures for session derivation ────────────────────────────────────
//
// The derivation is the one piece of logic a port is most likely to get subtly
// wrong, so rather than describing it in prose we run the real implementation and
// record what it produced. The Swift port's tests replay these.

const T0 = 1_770_000_000_000; // fixed, so regenerating produces no spurious diff
const ev = (id, name, bundle, startedAt, seconds, type = "activated") => ({
  id,
  type,
  applicationName: name,
  bundleIdentifier: bundle,
  appPath: null,
  startedAt,
  endedAt: startedAt + seconds * 1000,
  duration: seconds,
});
const min = (n) => n * 60_000;

const SCENARIOS = [
  {
    name: "one-session-two-apps",
    description: "Consecutive rows with no gap form a single session; apps sort by time.",
    now: T0 + min(60),
    events: [
      ev(1, "Code", "com.microsoft.VSCode", T0, 600),
      ev(2, "Safari", "com.apple.Safari", T0 + min(10), 300),
      ev(3, "Code", "com.microsoft.VSCode", T0 + min(15), 900),
    ],
  },
  {
    name: "away-row-splits-session",
    description: "A measured idle row is a break, and splits the run either side of it.",
    now: T0 + min(120),
    events: [
      ev(1, "Code", "com.microsoft.VSCode", T0, 900),
      ev(2, "Away", null, T0 + min(15), 1800, "idle"),
      ev(3, "Code", "com.microsoft.VSCode", T0 + min(45), 900),
    ],
  },
  {
    name: "recording-gap-splits-session",
    description:
      "A hole of RECORDING_GAP_SECONDS or more means Replay was not running: an 'unrecorded' break.",
    now: T0 + min(120),
    events: [
      ev(1, "Code", "com.microsoft.VSCode", T0, 600),
      ev(2, "Code", "com.microsoft.VSCode", T0 + min(30), 600),
    ],
  },
  {
    name: "long-row-is-a-break-not-focus",
    description:
      "One app holding focus for IDLE_BREAK_SECONDS or more is absence, not concentration.",
    now: T0 + min(240),
    events: [
      ev(1, "Code", "com.microsoft.VSCode", T0, 300),
      ev(2, "Finder", "com.apple.finder", T0 + min(5), 3 * 3600),
      ev(3, "Code", "com.microsoft.VSCode", T0 + min(190), 600),
    ],
  },
  {
    name: "stray-switch-is-dropped",
    description:
      "A run under MIN_SESSION_SECONDS with fewer than 3 rows is noise and produces no session.",
    now: T0 + min(120),
    events: [
      ev(1, "Code", "com.microsoft.VSCode", T0, 1200),
      ev(2, "Away", null, T0 + min(20), 1800, "idle"),
      ev(3, "Dock", "com.apple.dock", T0 + min(50), 5),
    ],
  },
  {
    name: "open-session-uses-now",
    description: "A row with no end (the session in progress) is measured against `now`.",
    now: T0 + min(30),
    events: [
      { ...ev(1, "Code", "com.microsoft.VSCode", T0, 0), endedAt: null, duration: 0 },
    ],
  },
  {
    name: "leading-and-trailing-breaks-trimmed",
    description: "Breaks at either end say nothing about the day's shape and are removed.",
    now: T0 + min(240),
    events: [
      ev(1, "Away", null, T0, 1800, "idle"),
      ev(2, "Code", "com.microsoft.VSCode", T0 + min(30), 1200),
      ev(3, "Away", null, T0 + min(50), 1800, "idle"),
    ],
  },
  {
    name: "unordered-input-is-sorted",
    description: "Input order does not matter; rows are sorted by start before grouping.",
    now: T0 + min(60),
    events: [
      ev(2, "Safari", "com.apple.Safari", T0 + min(10), 300),
      ev(1, "Code", "com.microsoft.VSCode", T0, 600),
    ],
  },
];

function buildFixtures() {
  const tmp = mkdtempSync(join(tmpdir(), "replay-spec-"));
  try {
    const bundle = join(tmp, "sessions.mjs");
    execFileSync(
      "npx",
      [
        "esbuild",
        "renderer/lib/sessions.ts",
        "--bundle",
        "--format=esm",
        "--platform=node",
        `--outfile=${bundle}`,
      ],
      { cwd: GLAZE, stdio: "pipe" },
    );

    const runner = join(tmp, "run.mjs");
    writeFileSync(
      runner,
      `import { buildTimeline, computeDaySummary } from ${JSON.stringify(bundle)};
       const scenarios = JSON.parse(process.argv[2]);
       const out = scenarios.map((s) => ({
         name: s.name,
         description: s.description,
         now: s.now,
         events: s.events,
         summary: (() => {
           const tl = buildTimeline(s.events, s.now);
           const d = computeDaySummary(s.events, tl, s.now);
           return {
             activeSeconds: d.activeSeconds,
             activeLabel: d.activeLabel,
             appsUsed: d.appsUsed,
             sessionCount: d.sessionCount,
             switches: d.switches,
             focus: d.focus ? { averageStretchSeconds: d.focus.averageStretchSeconds, quality: d.focus.quality } : null,
             mostUsed: d.mostUsed ? { applicationName: d.mostUsed.applicationName, seconds: d.mostUsed.seconds } : null,
             longestSessionSeconds: d.longestSession ? d.longestSession.seconds : null,
           };
         })(),
         expected: buildTimeline(s.events, s.now).map((item) =>
           item.kind === "session"
             ? {
                 kind: "session",
                 title: item.title,
                 category: item.category,
                 startedAt: item.startedAt,
                 endedAt: item.endedAt,
                 spanSeconds: item.spanSeconds,
                 activeSeconds: item.activeSeconds,
                 switches: item.switches,
                 eventIds: item.events.map((e) => e.id),
                 apps: item.apps.map((a) => ({
                   applicationName: a.applicationName,
                   bundleIdentifier: a.bundleIdentifier,
                   seconds: a.seconds,
                   switches: a.switches,
                   share: Math.round(a.share * 1e6) / 1e6,
                 })),
               }
             : {
                 kind: "break",
                 reason: item.reason,
                 startedAt: item.startedAt,
                 endedAt: item.endedAt,
                 seconds: item.seconds,
                 applicationName: item.applicationName,
               },
         ),
       }));
       process.stdout.write(JSON.stringify(out));`,
    );

    const json = execFileSync("node", [runner, JSON.stringify(SCENARIOS)], {
      cwd: GLAZE,
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
    });
    return JSON.parse(json);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

// ── write ─────────────────────────────────────────────────────────────────────

let glazeCommit = "unknown";
let glazeVersion = "unknown";
try {
  glazeCommit = execFileSync("git", ["-C", GLAZE, "rev-parse", "--short", "HEAD"], {
    encoding: "utf8",
  }).trim();
  glazeVersion = JSON.parse(readFileSync(join(GLAZE, "package.json"), "utf8")).version;
} catch {
  problems.push("could not read the Glaze app's git commit / version");
}

let fixtures = [];
try {
  fixtures = buildFixtures();
} catch (error) {
  problems.push(`could not run the Glaze derivation code: ${error.message.split("\n")[0]}`);
}

if (problems.length > 0) {
  console.error("sync-spec failed:\n" + problems.map((p) => `  · ${p}`).join("\n"));
  console.error(`\nGlaze sources: ${GLAZE}`);
  process.exit(1);
}

const provenance = `Generated by tools/sync-spec.mjs — do not edit by hand.
Glaze app version ${glazeVersion}, commit ${glazeCommit}.`;

mkdirSync(join(SPEC, "fixtures"), { recursive: true });

writeFileSync(
  join(SPEC, "schema.sql"),
  `-- ${provenance.split("\n").join("\n-- ")}\n--\n` +
    `-- The one file both implementations must agree on byte for byte: a database\n` +
    `-- written by one has to be readable by the other.\n\n` +
    schemaParts.join("\n\n") +
    "\n",
);

writeFileSync(
  join(SPEC, "constants.json"),
  JSON.stringify({ _generated: provenance, glazeVersion, glazeCommit, ...constants }, null, 2) + "\n",
);

for (const fixture of fixtures) {
  writeFileSync(
    join(SPEC, "fixtures", `${fixture.name}.json`),
    JSON.stringify({ _generated: provenance, ...fixture }, null, 2) + "\n",
  );
}

writeFileSync(
  join(SPEC, "fixtures", "index.json"),
  JSON.stringify(
    { _generated: provenance, fixtures: fixtures.map((f) => f.name) },
    null,
    2,
  ) + "\n",
);

console.log(`spec/ regenerated from Glaze ${glazeVersion} (${glazeCommit})`);
console.log(`  schema.sql        ${schemaParts.length} statement blocks`);
console.log(`  constants.json    ${Object.keys(constants).length} groups`);
console.log(`  fixtures/         ${fixtures.length} scenarios`);
console.log(`\nReview 'git diff spec/' — anything that changed is work for the native port.`);
