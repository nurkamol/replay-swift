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
  motion: (() => {
    /*
     * The motion system, from the reference's own stylesheet and page shell.
     *
     * Extracted rather than eyeballed because these are the numbers that make two
     * implementations feel like one product. A port that guesses 0.2s where the
     * reference says 180ms is not visibly wrong in a screenshot and is wrong every
     * time anyone uses it.
     */
    const css = read("renderer/styles.css");
    const page = read("renderer/components/page.tsx");
    const duration = (name) => {
      const match = css.match(new RegExp(`--replay-duration-${name}:\\s*(\\d+)ms`));
      if (!match) problems.push(`styles.css: --replay-duration-${name} not found`);
      return match ? Number(match[1]) : null;
    };
    const curve = (name) => {
      const match = css.match(
        new RegExp(`--replay-ease-${name}:\\s*cubic-bezier\\(([^)]+)\\)`),
      );
      if (!match) {
        problems.push(`styles.css: --replay-ease-${name} not found`);
        return null;
      }
      return match[1].split(",").map((n) => Number(n.trim()));
    };
    return {
      pressMs: duration("press"),
      hoverMs: duration("hover"),
      enterMs: duration("enter"),
      easeSoft: curve("soft"),
      easeStandard: curve("standard"),
      enterStepMs: constant(page, "page.tsx", "ENTER_STEP_MS"),
      enterCapMs: constant(page, "page.tsx", "ENTER_CAP_MS"),
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

/*
 * Session titles are named after the *local* day part ("Morning in Code"), so a
 * fixture generated without a pinned timezone records the machine that produced
 * it: the same code in UTC would call that session "Late night in Code" and the
 * committed fixture would fail. Everything the tool runs is pinned to one
 * timezone and locale, and every fixture records which, so the checks can derive
 * under the same calendar rather than the runner's.
 */
const FIXTURE_TZ = "UTC";
const FIXTURE_LOCALE = "en-US";
const FIXTURE_ENV = { TZ: FIXTURE_TZ, LC_ALL: FIXTURE_LOCALE.replace("-", "_") + ".UTF-8" };

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
      env: { ...process.env, ...FIXTURE_ENV },
    });
    return JSON.parse(json).map((fixture) => ({ timeZone: FIXTURE_TZ, ...fixture }));
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

/*
 * Day grouping and report export, run against the real Glaze code.
 *
 * Both were previously "verified by reading the reference", which is the weakest
 * kind of verification this project has and the kind that quietly rots. They are
 * generated together because they need the same thing the session fixtures don't:
 * a **pinned clock, timezone and locale**.
 *
 *   · `groupByDay` buckets by *local* midnight, so its answer depends on TZ.
 *   · A report prints dates, times and an "exported" stamp, so its text depends
 *     on TZ, on the locale, and on the wall clock at the moment it ran.
 *
 * The runner therefore fixes `Date` to one instant and runs under a fixed TZ and
 * locale, and the fixture records which — so the Swift side can format under the
 * same and compare like for like. Without that, the fixture would encode
 * whichever machine last ran the tool.
 */
/** The instant a report claims it was exported at. Arbitrary, but fixed. */
const FIXTURE_NOW = 1_770_000_000_000;

function buildExportFixtures() {
  const tmp = mkdtempSync(join(tmpdir(), "replay-spec-export-"));
  try {
    const bundle = join(tmp, "reference.mjs");
    // One bundle with both entry points, so the two fixtures cannot be generated
    // from different versions of the same helpers.
    const entry = join(tmp, "entry.ts");
    writeFileSync(
      entry,
      `export { groupByDay, computeAppStats } from ${JSON.stringify(join(GLAZE, "renderer/lib/activity.ts"))};
       export { buildDayStory } from ${JSON.stringify(join(GLAZE, "renderer/lib/day-story.ts"))};
       export { computeCollections, COLLECTION_CATEGORIES } from ${JSON.stringify(join(GLAZE, "renderer/lib/collections.ts"))};
       export { detectWorkflows, detectProjects, computeWorkflowPartners, computeRelationship } from ${JSON.stringify(join(GLAZE, "renderer/lib/workflows.ts"))};
       export { projectDefaultName } from ${JSON.stringify(join(GLAZE, "renderer/lib/projects.ts"))};
       export { detectRituals } from ${JSON.stringify(join(GLAZE, "renderer/lib/rituals.ts"))};
       export { detectChapters, chapterDefaultName } from ${JSON.stringify(join(GLAZE, "renderer/lib/chapters.ts"))};
       export { listPeriods, summarizePeriod } from ${JSON.stringify(join(GLAZE, "renderer/lib/autobiography.ts"))};
       export { detectMoments, pickDailyQuote } from ${JSON.stringify(join(GLAZE, "renderer/lib/moments.ts"))};
       export { clamp01, ramp, freshness, blendConfidence, daysBetween, sessionMeaning,
                projectMeaning, eligibleMemories, selectLivingMemory,
                confidenceThresholdLabel } from ${JSON.stringify(join(GLAZE, "renderer/lib/memory-intelligence.ts"))};
       export { detectRightTime } from ${JSON.stringify(join(GLAZE, "renderer/lib/right-time.ts"))};
       export { detectThreadUpdate } from ${JSON.stringify(join(GLAZE, "renderer/lib/threads.ts"))};
       export { detectEcho } from ${JSON.stringify(join(GLAZE, "renderer/lib/echoes.ts"))};
       export { detectAnniversaries } from ${JSON.stringify(join(GLAZE, "renderer/lib/anniversaries.ts"))};
       export { detectForgotten } from ${JSON.stringify(join(GLAZE, "renderer/lib/forgotten.ts"))};
       // The pool is built inside a hook upstream, so its body is re-declared here, as
       // sessionMatches and computeLegacy and the briefing are. Fourth time; each is on
       // the ledger. (No backticks in this comment: it is inside a template literal.)
       export function surprisePool(moments, summaries, bookmarkStarts, now) {
         const startOfLocalDay = (ts) => { const d = new Date(ts); d.setHours(0,0,0,0); return d.getTime(); };
         const today = startOfLocalDay(now);
         const pool = new Set();
         for (const moment of moments) {
           if (moment.dayStart !== undefined && moment.dayStart !== today) pool.add(moment.dayStart);
         }
         for (const summary of summaries) {
           if (summary.activeSeconds >= 20 * 60 && summary.dayStart !== today) pool.add(summary.dayStart);
         }
         for (const start of bookmarkStarts) {
           const day = startOfLocalDay(start);
           if (day !== today) pool.add(day);
         }
         return [...pool];
       }
       // The briefing is assembled inside a hook upstream, so like sessionMatches and
       // computeLegacy above, its body is re-declared here character for character. Same
       // known risk, same reason: nothing would check it otherwise.
       // (No backticks in this comment: it lives inside a template literal.)
       import { buildTimeline as bt_ } from ${JSON.stringify(join(GLAZE, "renderer/lib/sessions.ts"))};
       import { projectMeaning as pm_ } from ${JSON.stringify(join(GLAZE, "renderer/lib/memory-intelligence.ts"))};
       export function buildMorningBriefing(now, yesterdayEvents, summaries, projects, monthAgo, bookmarkStarts) {
         const DAY = 86400000;
         const startOfLocalDay = (ts) => { const d = new Date(ts); d.setHours(0,0,0,0); return d.getTime(); };
         const todayStart = startOfLocalDay(now);
         const yesterdayStart = todayStart - DAY;
         if (new Date(now).getHours() >= 12) return null;
         const yesterdaySummary = summaries.find((s) => s.dayStart === yesterdayStart) ?? null;
         const sessions = bt_(yesterdayEvents, now).filter((i) => i.kind === "session");
         const activeSeconds = yesterdaySummary?.activeSeconds ?? 0;
         if (activeSeconds <= 0 && sessions.length === 0) return null;
         const longest = sessions.reduce((best, s) => (best === null || s.activeSeconds > best.activeSeconds ? s : best), null);
         const continued = projects
           .filter((p) => p.sessionCount >= 2 && p.sessions.some((s) => s.startedAt >= yesterdayStart && s.startedAt < todayStart))
           .sort((a, b) => pm_(b) - pm_(a))[0];
         const oldestBookmark = bookmarkStarts.slice().sort((a, b) => a - b)[0];
         return {
           dayStart: todayStart,
           yesterdayActiveSeconds: activeSeconds,
           yesterdayTopApp: yesterdaySummary?.topAppName ?? null,
           longestFocusSeconds: longest?.activeSeconds ?? null,
           continuedProject: continued ? { id: continued.id, name: continued.name } : null,
           monthAgo,
           pendingBookmark: oldestBookmark !== undefined ? startOfLocalDay(oldestBookmark) : null,
         };
       }
       export { buildConstellation } from ${JSON.stringify(join(GLAZE, "renderer/lib/constellation.ts"))};
       export { buildCanvas } from ${JSON.stringify(join(GLAZE, "renderer/lib/canvas.ts"))};
       export { historyTargets, findMemories, relativeDayLabel, shortDateLabel } from ${JSON.stringify(join(GLAZE, "renderer/lib/history.ts"))};
       export { buildExport, selectScope, EXPORT_SCOPES } from ${JSON.stringify(join(GLAZE, "renderer/lib/export.ts"))};
       export { buildTimeline, groupSessionsForWeek, sessionUsesApp, describeBreak, FILTER_CATEGORIES, sessionFilterCategory, computeWeekSummary, describePeak, findResumeTarget, formatWhen, excludeIdleStretches } from ${JSON.stringify(join(GLAZE, "renderer/lib/sessions.ts"))};
       // sessionMatches is module-private in the view, so the predicate is
       // re-declared here character for character. If it drifts upstream this
       // fixture keeps asserting the old rule — the one risk in extracting it,
       // and the reason it is copied rather than approximated.
       // The archive's figures are computed inside the legacy view upstream, not in a
       // lib module, so like sessionMatches above they are re-declared here character
       // for character. Same risk, same reason: without this nothing checks them.
       // (No backticks in this comment: it lives inside a template literal.)
       export function computeLegacy(summaries, directory) {
         const active = summaries.filter((s) => s.activeSeconds > 0);
         if (active.length === 0) return null;
         const firstDay = Math.min(...active.map((s) => s.dayStart));
         const lastDay = Math.max(...active.map((s) => s.dayStart));
         const totalSeconds = active.reduce((sum, s) => sum + s.activeSeconds, 0);
         const years = [...new Set(active.map((s) => new Date(s.dayStart).getFullYear()))].sort((a, b) => b - a);
         const appAgg = new Map();
         for (const s of active) {
           const key = s.topBundleId ?? s.topAppName ?? "unknown";
           const entry = appAgg.get(key);
           if (entry) {
             entry.seconds += s.topSeconds;
             entry.days += 1;
           } else {
             appAgg.set(key, {
               name: s.topAppName ?? key,
               appPath: s.topBundleId ? directory.get(s.topBundleId)?.appPath ?? null : null,
               seconds: s.topSeconds,
               days: 1,
             });
           }
         }
         const favorites = [...appAgg.entries()]
           .map(([bundleId, v]) => ({ bundleId, ...v }))
           .sort((a, b) => b.seconds - a.seconds)
           .slice(0, 6);
         return { firstDay, lastDay, totalSeconds, activeDays: active.length, years, favorites };
       }

       export function sessionMatches(session, annotation, query) {
         const q = query.replace(/^#/, "").toLowerCase();
         if (session.title.toLowerCase().includes(q)) return true;
         if (annotation) {
           if (annotation.note.toLowerCase().includes(q)) return true;
           if (annotation.tags.some((tag) => tag.includes(q))) return true;
         }
         return false;
       }`,
    );
    execFileSync(
      "npx",
      ["esbuild", entry, "--bundle", "--format=esm", "--platform=node", `--outfile=${bundle}`],
      { cwd: GLAZE, stdio: "pipe" },
    );

    const runner = join(tmp, "run-export.mjs");
    writeFileSync(
      runner,
      `// Freeze the clock before the reference code can read it, so "exported at"
       // and any relative reasoning are the same on every run.
       const FIXED = ${FIXTURE_NOW};
       const RealDate = Date;
       class FrozenDate extends RealDate {
         constructor(...args) { super(...(args.length ? args : [FIXED])); }
         static now() { return FIXED; }
       }
       globalThis.Date = FrozenDate;

       const { groupByDay, buildExport, selectScope, EXPORT_SCOPES, buildTimeline,
               groupSessionsForWeek, sessionUsesApp, sessionMatches,
               historyTargets, findMemories, describeBreak,
               FILTER_CATEGORIES, sessionFilterCategory,
               computeWeekSummary, describePeak, detectWorkflows, detectProjects,
               projectDefaultName, relativeDayLabel, shortDateLabel, detectRituals,
               detectChapters, chapterDefaultName, listPeriods, summarizePeriod,
               computeLegacy, computeWorkflowPartners, computeRelationship,
               detectMoments, pickDailyQuote, buildConstellation, buildCanvas,
               buildMorningBriefing,
               clamp01, ramp, freshness, blendConfidence, daysBetween, sessionMeaning,
               projectMeaning, eligibleMemories, selectLivingMemory,
               confidenceThresholdLabel, detectRightTime, detectThreadUpdate, detectEcho,
               detectAnniversaries, detectForgotten, surprisePool,
               findResumeTarget, formatWhen, computeAppStats, excludeIdleStretches,
               computeCollections, COLLECTION_CATEGORIES,
               buildDayStory } = await import(${JSON.stringify(bundle)});
       const input = JSON.parse(process.argv[2]);

       // Day grouping: record the bucketing only. The label is a locale rendering
       // of "today", which is not a property of the grouping and would make the
       // fixture expire overnight.
       const grouping = groupByDay(input.groupingEvents).map((group) => ({
         dayStart: Number(group.key),
         eventIds: group.events.map((e) => e.id),
       }));

       // How a gap is named. Pure copy, and copy is where a port drifts without
       // anything failing: the words are the product (SPEC §8), and nothing else
       // in this contract covers them.
       const breaks = input.breakCases.map((c) => ({ ...c, ...describeBreak(c) }));

       // A week: seven days of figures, a weekday x hour rhythm grid, and the
       // plain-language read of its busiest cell.
       const weekSummary = computeWeekSummary(input.weekEvents, input.weekDayStarts, input.weekNow);
       const week = {
         ...weekSummary,
         peakLabel: weekSummary.peak ? describePeak(weekSummary.peak) : null,
       };
       // Per-application usage. Idle stretches are excluded first, as at every call
       // site upstream — "how long in this app" means time at the keyboard.
       const appStats = computeAppStats(
         excludeIdleStretches(input.appStatEvents, input.appStatNow),
         input.appStatNow,
       );

       // Recurring application combinations.
       const workflowSessions = groupSessionsForWeek(input.workflowEvents, input.workflowNow);
       const workflows = detectWorkflows(workflowSessions);

       // What to offer picking back up, and how each case reads.
       const resume = input.resumeCases.map((c) => {
         const target = findResumeTarget(buildTimeline(c.events, c.now), c.now);
         return {
           name: c.name,
           target: target && {
             sessionStart: target.session.startedAt,
             sessionTitle: target.session.title,
             applicationName: target.app.applicationName,
             isEarlierDay: target.isEarlierDay,
             when: formatWhen(target.session.endedAt, c.now),
           },
         };
       });
       const whenLabels = input.whenCases.map((c) => ({ ...c, label: formatWhen(c.at, c.now) }));
       // How long ago a day was, and a short absolute date. Both are locale renderings,
       // so both are recorded rather than assumed.
       const dayLabels = input.whenCases.map((c) => ({
         at: c.at,
         now: c.now,
         relative: relativeDayLabel(c.at, c.now),
         short: shortDateLabel(c.at),
       }));

       // The same signature grouping, keeping the whole span. Session lists are
       // recorded by start rather than in full: the sessions themselves are already
       // pinned by the derivation fixtures, and repeating them here would make this
       // file enormous for no extra assurance.
       const projects = detectProjects(workflowSessions).map((p) => ({
         id: p.id,
         category: p.category,
         apps: p.apps,
         totalSeconds: p.totalSeconds,
         sessionCount: p.sessionCount,
         firstSeen: p.firstSeen,
         lastActive: p.lastActive,
         sessionStarts: p.sessions.map((s) => s.startedAt),
         defaultName: projectDefaultName(p),
       }));

       // The shape a run of days settles into.
       const rituals = detectRituals(
         groupSessionsForWeek(input.ritualEvents, input.ritualNow),
         input.ritualEvents,
       );

       // Eras, read from the durable daily headlines.
       const chapters = detectChapters(input.chapterSummaries, new Map()).map((c) => ({
         ...c,
         defaultName: chapterDefaultName(c),
       }));

       // The history told back, a period at a time. Prose is the whole feature, so the
       // sentences are compared as text.
       const periods = listPeriods(input.chapterSummaries);
       const autobiography = periods.map((period) => ({
         key: period.key,
         kind: period.kind,
         start: period.start,
         end: period.end,
         label: period.label,
         ...summarizePeriod(period, input.chapterSummaries, new Map(), input.reflectionCounts[period.key] ?? 0),
       }));

       const legacy = computeLegacy(input.chapterSummaries, new Map());

       // The coarse buckets the Timeline filters by, and which one every session
       // category falls into — including the two that have no bucket of their own.
       const filters = {
         categories: FILTER_CATEGORIES,
         mapped: input.filterCases.map((category) => ({
           category,
           bucket: sessionFilterCategory({ category }),
         })),
       };

       // The confidence primitives. Every producer scores in this vocabulary, so if the
       // arithmetic drifts every memory in the app drifts with it.
       const scoring = {
         clamp: input.scoringCases.clamp.map(clamp01),
         ramps: input.scoringCases.ramps.map(([v, z, f]) => ramp(v, z, f)),
         freshness: input.scoringCases.freshness.map(([age, half]) => freshness(age, half)),
         blends: input.scoringCases.blends.map((parts) => blendConfidence(parts)),
         days: input.scoringCases.days.map(([a, b]) => daysBetween(a, b)),
         sessions: input.scoringCases.sessions.map(sessionMeaning),
         projects: input.scoringCases.projects.map(projectMeaning),
         labels: input.scoringCases.thresholds.map(confidenceThresholdLabel),
       };

       // Selection, including the case that matters most: nothing clears the bar.
       const selection = input.selectionCases.map((c) => ({
         name: c.name,
         eligible: eligibleMemories(c.candidates, c.options).map((m) => m.id),
         chosen: selectLivingMemory(c.candidates, c.options)?.id ?? null,
       }));

       // The producers, each over a case built to make it speak.
       const memoryProjects = detectProjects(workflowSessions).map((p) => ({
         ...p,
         name: projectDefaultName(p),
         named: false,
       }));
       const briefings = input.briefingCases.map((c) => ({
         name: c.name,
         result: buildMorningBriefing(
           c.now, c.yesterdayEvents, input.briefingSummaries, input.memoryProjects,
           c.monthAgo ?? null, c.bookmarkStarts ?? [],
         ),
       }));

       const anniversaries = detectAnniversaries(
         {
           seed: input.anniversarySeed,
           projects: input.memoryProjects,
           bookmarks: input.memoryBookmarks,
           reflections: input.memoryReflections,
         },
         input.anniversaryNow,
       );
       const forgotten = detectForgotten(
         {
           projects: input.memoryProjects,
           bookmarks: input.memoryBookmarks,
           reflections: input.memoryReflections,
         },
         input.memoryNow,
       );

       const producers = {
         rightTime: detectRightTime(input.rightTimeEvents, input.memoryProjects, input.memoryNow),
         thread: detectThreadUpdate(input.memoryProjects, input.memoryNow),
         echo: detectEcho(input.echoEvents, input.memoryProjects, input.memoryNow),
         projectCount: memoryProjects.length,
       };

       // The memories worth rediscovering. Prose again, so compared as text.
       const moments = detectMoments(
         input.momentSeed, input.chapterSummaries, input.momentEvents, input.momentNow,
       );
       const quote = pickDailyQuote(moments, input.momentNow);
       // The days worth arriving on, from the moments, the fuller days and the marks.
       const surprise = surprisePool(
         moments, input.chapterSummaries, input.memoryBookmarks.map((b) => b.sessionStart),
         input.momentNow,
       );

       // The graph behind the canvas, over the workflow fixture's sessions — small
       // enough to record in full, and it already has two projects and repeated
       // switching between the same pairs.
       const constellation = buildConstellation(workflowSessions, 16);
       const canvasProjects = detectProjects(workflowSessions).map((p) => ({
         ...p,
         name: projectDefaultName(p),
         named: false,
       }));
       const canvasChapters = detectChapters(input.chapterSummaries, new Map()).map((c) => ({
         ...c,
         name: chapterDefaultName(c),
         named: false,
       }));
       const canvas = buildCanvas(workflowSessions, canvasProjects, canvasChapters, moments);

       // How two applications are used together. The anchor is the app that appears in
       // every session of the workflow fixture, so partners exist to be ranked at all.
       const partners = computeWorkflowPartners(workflowSessions, input.anchorKey);
       const relationship = computeRelationship(
         workflowSessions, input.anchorKey, input.partnerKey,
       );
       const noRelationship = computeRelationship(workflowSessions, input.anchorKey, "com.example.never");

       // Every branch of describePeak, so the boundary hours are pinned rather
       // than sampled by whatever the week fixture happened to land on.
       const peakLabels = input.peakCases.map((p) => ({ ...p, label: describePeak(p) }));

       const sessions = buildTimeline(input.reportEvents, input.reportNow)
         .filter((item) => item.kind === "session");
       const entries = sessions.map((session, index) => ({
         session,
         annotation: input.annotations[index] ?? undefined,
       }));

       const reports = {};
       for (const format of ["markdown", "csv", "json"]) {
         reports[format] = buildExport(format, { label: input.label }, entries).content;
       }

       // Scope selection, over a month of events with marks scattered through it.
       // Recorded as the session starts each scope picks: the identity that survives,
       // and the one an annotation is keyed to.
       const scopeSessions = groupSessionsForWeek(input.scopeEvents, input.scopeNow)
         .sort((a, b) => b.startedAt - a.startedAt);
       const scopeAnnotations = new Map(
         input.scopeAnnotations.map((a) => [a.sessionStart, a]),
       );
       const scopes = {};
       for (const { value } of EXPORT_SCOPES) {
         scopes[value] = selectScope(scopeSessions, scopeAnnotations, value, input.todayStart)
           .map((entry) => entry.session.startedAt);
       }

       // Search: which sessions each query finds, by session start.
       const searchResults = {};
       for (const query of input.searchQueries) {
         searchResults[query] = {
           matches: scopeSessions
             .filter((s) => sessionMatches(s, scopeAnnotations.get(s.startedAt), query))
             .map((s) => s.startedAt),
           usesApp: scopeSessions.filter((s) => sessionUsesApp(s, query)).map((s) => s.startedAt),
         };
       }

       // Looking back: which calendar day each offset lands on, and which of them
       // actually hold activity. The month-end cases are the point — see the note
       // beside the inputs.
       const history = input.historyNows.map((now) => ({
         now,
         targets: historyTargets(now).map((t) => ({ key: t.key, label: t.label, dayStart: t.dayStart })),
         found: findMemories(input.historySummaries, now).map((m) => ({
           key: m.range.key,
           dayStart: m.summary.dayStart,
           activeSeconds: m.summary.activeSeconds,
         })),
       }));

       // Collections, over sessions built so two categories tie on total time — the
       // case where JavaScript's stable sort quietly decides the order and Swift's
       // does not.
       const collectionSessions = buildTimeline(input.collectionEvents, input.collectionNow)
         .filter((item) => item.kind === "session");
       const collections = computeCollections(collectionSessions).map((c) => ({
         category: c.category,
         label: c.label,
         sessionCount: c.sessionCount,
         totalSeconds: c.totalSeconds,
         apps: c.apps.map((a) => ({ applicationName: a.applicationName, seconds: a.seconds })),
       }));

       // Story Mode, over several day shapes — including one whose two longest
       // stretches tie, and one too thin to narrate at all.
       const stories = input.storyCases.map((c) => {
         const sessions = buildTimeline(c.events, c.now).filter((i) => i.kind === "session");
         return {
           name: c.name,
           sessionCount: sessions.length,
           sentences: buildDayStory(sessions),
         };
       });

       process.stdout.write(JSON.stringify({
         stories,
         collections: {
           definitions: COLLECTION_CATEGORIES,
           sessionCount: collectionSessions.length,
           expected: collections,
         },
         history,
         grouping,
         breaks,
         week,
         peakLabels,
         workflows,
         projects,
         rituals,
         chapters,
         autobiography,
         legacy,
         filters,
         scoring,
         selection,
         producers,
         anniversaries,
         forgotten,
         surprise,
         briefings,
         moments,
         quoteKey: quote ? quote.key : null,
         constellation,
         canvas,
         partners,
         relationship: relationship && {
           ...relationship,
           sessionStarts: relationship.sessions.map((s) => s.startedAt),
           sessions: undefined,
         },
         hasNoRelationship: noRelationship === null,
         workflowSessionCount: workflowSessions.length,
         resume,
         whenLabels,
         dayLabels,
         appStats,
         reports,
         sessionCount: sessions.length,
         searchResults,
         scopes,
         scopeSessionStarts: scopeSessions.map((s) => s.startedAt),
         scopeLabels: EXPORT_SCOPES,
       }));`,
    );

    // Events either side of two local midnights, plus one out of order, so the
    // fixture pins both the bucketing and the sort within a day.
    const DAY = 86_400_000;
    const midnight = 1_770_076_800_000; // 2026-02-03T00:00:00Z
    const groupingEvents = [
      ev(1, "Code", "com.microsoft.VSCode", midnight - min(20), 600),
      ev(2, "Safari", "com.apple.Safari", midnight + min(10), 600),
      ev(3, "Code", "com.microsoft.VSCode", midnight + min(5), 120),
      ev(4, "Mail", "com.apple.mail", midnight + DAY + min(30), 300),
    ];

    const reportNow = FIXTURE_NOW;
    const reportStart = FIXTURE_NOW - min(120);
    // Two runs with a recording gap between them, so the report covers more than one
    // session. Each run is kept under `idleBreakSeconds` — a row that long is absence
    // rather than focus, and would be dropped from the report as a break.
    const reportEvents = [
      ev(1, "Code", "com.microsoft.VSCode", reportStart, 1200),
      ev(2, "Safari", "com.apple.Safari", reportStart + min(35), 900),
    ];
    // One annotated session and one bare, so a report is checked with and without
    // the parts a note contributes. The comma and quote are deliberate: CSV
    // quoting is a rule, not a formatting preference.
    const annotations = [
      {
        sessionStart: reportStart,
        note: 'shipped it, and said "done"',
        bookmarked: true,
        tags: ["deep work", "shipping"],
        updatedAt: reportNow,
      },
    ];

    /*
     * A month of history for the scopes: one run a day at noon, going back far
     * enough that `month` holds days `week` does not. Marks are scattered rather
     * than clustered, so `bookmarks` and `notes` cannot accidentally agree with a
     * date range — the whole point of those two is that they cut across time.
     */
    const todayStart = 1_770_076_800_000; // 2026-02-03T00:00:00Z, a local midnight in UTC
    const scopeNow = todayStart + min(13 * 60);
    const scopeEvents = [];
    for (let dayBack = 0; dayBack < 20; dayBack += 1) {
      const start = todayStart - dayBack * DAY + min(12 * 60);
      scopeEvents.push(
        ev(100 + dayBack * 2, "Code", "com.microsoft.VSCode", start, 900),
        ev(101 + dayBack * 2, "Safari", "com.apple.Safari", start + min(15), 600),
      );
    }
    const scopeAnnotations = [
      // Today: bookmarked, no note.
      { sessionStart: todayStart + min(12 * 60), note: "", bookmarked: true, tags: [] },
      // Eight days back — outside the week, inside the month — with a note only.
      { sessionStart: todayStart - 8 * DAY + min(12 * 60), note: "worth remembering", bookmarked: false, tags: [] },
      // Fifteen days back, carrying both.
      { sessionStart: todayStart - 15 * DAY + min(12 * 60), note: "both", bookmarked: true, tags: ["deep work"] },
      // A note that is only whitespace must not count as a note.
      { sessionStart: todayStart - 3 * DAY + min(12 * 60), note: "   ", bookmarked: false, tags: [] },
    ];

    /*
     * Queries chosen for the rules they exercise, not for looking realistic:
     * a title word, a note word, a tag with and without its hash, a prefix of a
     * tag (tags match on substring like everything else), an application name
     * that appears in sessions named after a *different* app, and a query that
     * finds nothing.
     */
    const input_searchQueries = [
      "code",       // a title word, and an app name — the two predicates disagree here
      "remembering",// a word only in a note
      "#deep work", // a tag typed with its hash
      "deep",       // a prefix of that tag
      "safari",     // lowercase: the app predicate is exact, so this must find nothing
      "Code",       // exact application name — what clicking an app sends
      "Safari",
      "nothingatall",
    ];

    /*
     * Month-end is where the two runtimes disagree, so it is what the fixture is
     * built around. JavaScript's Date *overflows* — 31 March minus one month is
     * `new Date(y, 2, 31)`, which is 3 March, not 28 February. Swift's Calendar
     * clamps to the last valid day instead. Both are defensible; only one matches
     * the app people already use, and without this fixture the port would have
     * silently picked the other.
     */
    const historyNows = [
      Date.UTC(2026, 2, 31, 12),  // 31 March — one month back overflows
      Date.UTC(2026, 4, 31, 12),  // 31 May — same, and three months back too
      Date.UTC(2024, 1, 29, 12),  // 29 February, a leap day: one year back has no such date
      Date.UTC(2026, 5, 15, 12),  // an ordinary day, as a control
    ];
    // A headline on every day any offset could reach, so "found" is decided by the
    // date arithmetic rather than by which days happen to exist.
    const historySummaries = [];
    for (const now of historyNows) {
      for (const back of [1, 7, 30, 31, 32, 90, 91, 92, 180, 181, 182, 365, 366, 730, 731]) {
        const day = Date.UTC(
          new Date(now).getUTCFullYear(),
          new Date(now).getUTCMonth(),
          new Date(now).getUTCDate() - back,
        );
        historySummaries.push({ dayStart: day, activeSeconds: 3600, topBundleID: null, topAppName: "Code", topSeconds: 1800 });
      }
    }

    /*
     * Two runs of equal length in different categories, so Development and Research
     * tie on total seconds and the order is decided by the tiebreak rather than by
     * the data. Plus a Communication run of its own, and a session that lands in
     * "Other" — which must not become a collection.
     */
    const collectionNow = FIXTURE_NOW;
    const collectionBase = FIXTURE_NOW - min(600);
    const collectionEvents = [
      // Development, 20 minutes.
      ev(200, "Code", "com.microsoft.VSCode", collectionBase, 1200),
      // Research, also 20 minutes — the tie.
      ev(201, "Safari", "com.apple.Safari", collectionBase + min(30), 1200),
      // Communication, also 20 minutes: Research and Communication tie on total, and
      // their order can only come from the declared category order.
      ev(202, "Slack", "com.tinyspeck.slackmacgap", collectionBase + min(60), 1200),
      // Two apps sharing a category, to exercise the per-app fold and its own tie.
      ev(203, "Terminal", "com.apple.Terminal", collectionBase + min(90), 900),
      ev(204, "Xcode", "com.apple.dt.Xcode", collectionBase + min(110), 900),
      // Something the category table does not name, which must stay out.
      ev(205, "SomeUnknownApp", "com.example.unknown", collectionBase + min(140), 1200),
    ];

    /*
     * Story Mode is prose assembled from thresholds, so each case exists to make
     * one clause appear or not appear. The tie case matters most: the reference
     * picks the *first* of two equally long stretches (its reduce keeps `best`),
     * while Swift's `max(by:)` would pick the last and narrate a different app.
     */
    const storyDay = 1_770_076_800_000; // a local midnight in UTC
    const hour = (h) => storyDay + h * 3_600_000;
    // Every row is kept under idleBreakSeconds (1800): a stretch that long is
    // absence rather than focus and is dropped from the timeline entirely, which
    // silently emptied the first version of these cases.
    const storyCases = [
      {
        name: "a full day",
        now: hour(23),
        events: [
          ev(300, "Code", "com.microsoft.VSCode", hour(9), 900),
          ev(301, "Terminal", "com.apple.Terminal", hour(9) + 900_000, 600),
          ev(302, "Safari", "com.apple.Safari", hour(13), 1500),
          ev(303, "Slack", "com.tinyspeck.slackmacgap", hour(16), 900),
          ev(304, "Mail", "com.apple.mail", hour(20), 600),
        ],
      },
      {
        name: "two stretches tie for longest",
        now: hour(23),
        events: [
          ev(310, "Code", "com.microsoft.VSCode", hour(9), 600),
          ev(311, "Safari", "com.apple.Safari", hour(13), 1500),
          ev(312, "Terminal", "com.apple.Terminal", hour(17), 1500),
        ],
      },
      {
        name: "one short session, nothing to narrate beyond the opening",
        now: hour(12),
        events: [
          ev(320, "Code", "com.microsoft.VSCode", hour(9), 300),
          ev(321, "Safari", "com.apple.Safari", hour(9) + 300_000, 200),
        ],
      },
      {
        name: "a day that never left the morning",
        now: hour(12),
        events: [
          ev(330, "Code", "com.microsoft.VSCode", hour(8), 1500),
          ev(331, "Safari", "com.apple.Safari", hour(10), 900),
        ],
      },
      { name: "nothing at all", now: hour(12), events: [] },
    ];

    /*
     * One case per branch of `describeBreak`, including both idle shapes. The
     * durations differ so a swapped-in wrong formatter cannot pass by accident,
     * and 90 seconds is there because it is where the short formatter rounds.
     */
    const breakCases = [
      { kind: "break", reason: "unrecorded", seconds: 480, startedAt: 0, endedAt: 0 },
      { kind: "break", reason: "away", seconds: 3_600, startedAt: 0, endedAt: 0 },
      { kind: "break", reason: "idle", seconds: 90, startedAt: 0, endedAt: 0, applicationName: "Safari" },
      { kind: "break", reason: "idle", seconds: 5_400, startedAt: 0, endedAt: 0 },
    ];

    /*
     * A week with something to say in every field: two days with real work, one
     * empty (rest is a legitimate day, not a hole), an app used across several
     * days so `daysUsed` is not just 1, two apps tied on seconds so the stable
     * sort is pinned, and a stretch crossing an hour boundary so the rhythm
     * grid has to split it rather than drop it in one cell.
     */
    const weekDayStart = 1_769_990_400_000; // a local midnight under the pinned TZ
    const weekDayStarts = Array.from({ length: 7 }, (_, i) => weekDayStart + i * DAY);
    const wd = (day, h, m = 0) => weekDayStarts[day] + h * 3_600_000 + m * 60_000;
    const weekEvents = [
      ev(400, "Code", "com.microsoft.VSCode", wd(0, 9), 1200),
      ev(401, "Safari", "com.apple.Safari", wd(0, 9, 20), 600),
      // Starts 20 minutes before the hour and runs 25, so it lands in two rhythm
      // cells. Kept under idleStretchSeconds (1800) or the derivation drops it as
      // absence and the case silently tests nothing.
      ev(402, "Code", "com.microsoft.VSCode", wd(1, 10, 40), 1500),
      ev(403, "Terminal", "com.apple.Terminal", wd(3, 14), 900),
      // Ties with Terminal on seconds; whichever was seen first must sort first.
      ev(404, "Mail", "com.apple.mail", wd(3, 15), 900),
      ev(405, "Code", "com.microsoft.VSCode", wd(5, 21), 1500),
      // Day 6 is deliberately empty.
    ];
    const weekNow = wd(6, 12);

    /*
     * Workflows need their own events: the week fixture's sessions never repeat a
     * combination, which is the whole point of the detection. Five days, one session
     * each — two that share an editor-and-terminal signature, two that share a
     * browser-and-mail one, and one single-app session that must be skipped because a
     * workflow is a combination rather than an app. The two recurring signatures are
     * built to total exactly the same time, so the fixture pins the tie-break: they can
     * only be ordered by which was seen first, and days arrive newest first.
     */
    const workflowDay = 1_769_990_400_000;
    const wf = (day, h, m = 0, sec = 0) =>
      workflowDay + day * DAY + h * 3_600_000 + m * 60_000 + sec * 1000;
    const workflowEvents = [
      ev(500, "Code", "com.microsoft.VSCode", wf(0, 9), 600),
      ev(501, "Terminal", "com.apple.Terminal", wf(0, 9, 10), 400),
      ev(502, "Code", "com.microsoft.VSCode", wf(1, 9), 500),
      ev(503, "Terminal", "com.apple.Terminal", wf(1, 9, 8, 20), 300),
      ev(504, "Safari", "com.apple.Safari", wf(2, 9), 700),
      ev(505, "Mail", "com.apple.mail", wf(2, 9, 11, 40), 300),
      ev(506, "Safari", "com.apple.Safari", wf(3, 9), 500),
      ev(507, "Mail", "com.apple.mail", wf(3, 9, 8, 20), 300),
      // One app on its own: a session, but never a workflow.
      ev(508, "Notes", "com.apple.Notes", wf(4, 9), 600),
    ];
    const workflowNow = wf(4, 12);

    /*
     * Per-application totals. Two apps are built to tie on seconds so the stable sort is
     * pinned, one row is left open so `effectiveDuration` has to measure it against `now`,
     * one app has no bundle identifier so the fallback key is exercised, and one row is
     * long enough to be dropped as absence rather than counted as use.
     */
    const appStatDay = 1_769_990_400_000;
    const as = (h, m = 0) => appStatDay + h * 3_600_000 + m * 60_000;
    const appStatEvents = [
      ev(700, "Code", "com.microsoft.VSCode", as(9), 900),
      ev(701, "Safari", "com.apple.Safari", as(9, 15), 600),
      ev(702, "Code", "com.microsoft.VSCode", as(10), 300),
      // Ties with Safari at 1200s total once its second row lands.
      ev(703, "Terminal", "com.apple.Terminal", as(11), 1200),
      ev(704, "Safari", "com.apple.Safari", as(12), 600),
      // No bundle identifier: counted under its name instead.
      { ...ev(705, "Some Script", null, as(13), 400), bundleIdentifier: null },
      // Longer than idleStretchSeconds: absence, not use, and excluded before counting.
      ev(706, "Preview", "com.apple.Preview", as(14), 4000),
      // Still open, so its length is measured against `now` rather than read off the row.
      { ...ev(707, "Mail", "com.apple.mail", as(16), 0), endedAt: null, duration: 0 },
    ];
    const appStatNow = as(16, 5);

    /*
     * Resume: the point is that the session you are *in* is not the one to offer, so the
     * cases turn on where `now` sits relative to the last row's end. The 180-second
     * in-progress window is the hinge, tested from both sides.
     */
    const resumeDay = 1_769_990_400_000;
    const rt = (h, m = 0) => resumeDay + h * 3_600_000 + m * 60_000;
    const resumeEvents = [
      ev(600, "Code", "com.microsoft.VSCode", rt(9), 900),
      ev(601, "Terminal", "com.apple.Terminal", rt(9, 15), 300),
      // A gap, then a second session.
      ev(602, "Safari", "com.apple.Safari", rt(14), 600),
      ev(603, "Mail", "com.apple.mail", rt(14, 10), 300),
    ];
    const resumeCases = [
      // Still in the afternoon session: offer the morning's, not the one in progress.
      { name: "the newest session is still running", events: resumeEvents, now: rt(14, 16) },
      // Stepped away: the afternoon session is now the thing to pick up.
      { name: "stepped away from the newest", events: resumeEvents, now: rt(15) },
      // Tomorrow morning: yesterday's last session, and it knows it was another day.
      { name: "the next morning", events: resumeEvents, now: rt(33) },
      // One session, and it is live: nothing to offer rather than the current one.
      {
        name: "only one session, still in it",
        events: [ev(610, "Code", "com.microsoft.VSCode", rt(9), 900)],
        now: rt(9, 16),
      },
      { name: "nothing recorded", events: [], now: rt(12) },
    ];

    /** Every branch of formatWhen, including the seven-day edge from both sides. */
    const whenNow = rt(240) + 45 * 60_000; // ten days on, at a fixed time of day
    const whenCases = [
      { at: whenNow - 2 * 3_600_000, now: whenNow },
      { at: whenNow - DAY, now: whenNow },
      { at: whenNow - 3 * DAY, now: whenNow },
      { at: whenNow - 6 * DAY, now: whenNow },
      { at: whenNow - 7 * DAY, now: whenNow },
      { at: whenNow - 40 * DAY, now: whenNow },
      // Midnight and noon, where the twelve-hour clock wraps.
      { at: resumeDay, now: resumeDay + 5 * DAY },
      { at: resumeDay + 12 * 3_600_000, now: resumeDay + 5 * DAY },
    ];

    /*
     * The confidence primitives, sampled at every boundary that matters: a ramp below
     * its zero, at both ends and between; a reversed ramp; a blend where one signal is
     * absent (weight 0) rather than zero, which is the distinction the whole design
     * rests on; and every band of the threshold label.
     */
    const scoringCases = {
      clamp: [-0.5, 0, 0.25, 1, 1.5],
      ramps: [[0, 10, 20], [10, 10, 20], [15, 10, 20], [20, 10, 20], [30, 10, 20],
              [5, 20, 10], [15, 20, 10], [7, 5, 5]],
      freshness: [[0, 30], [30, 30], [60, 30], [-1, 30], [10, 0]],
      blends: [
        [{ signal: 1, weight: 1 }, { signal: 0, weight: 0 }],
        [{ signal: 0.5, weight: 1 }, { signal: 1, weight: 1.4 }],
        [{ signal: 2, weight: 1 }],
        [{ signal: 1, weight: 0 }],
        [],
      ],
      days: [[0, 86_400_000], [86_400_000, 0], [0, 0]],
      sessions: [
        { activeSeconds: 60 },
        { activeSeconds: 3600 },
        { activeSeconds: 3600, bookmarked: true },
        { activeSeconds: 600, hasNote: true },
        { activeSeconds: 7200, bookmarked: true, hasNote: true },
      ],
      projects: [
        { totalSeconds: 600, sessionCount: 1 },
        { totalSeconds: 3600, sessionCount: 2 },
        { totalSeconds: 36_000, sessionCount: 8 },
      ],
      thresholds: [0, 0.34, 0.35, 0.54, 0.55, 0.74, 0.75, 1],
    };

    /*
     * Selection. The important case is the last one: nothing clears the bar, and the
     * answer is nothing rather than the best of a bad lot.
     */
    const candidate = (id, confidence) => ({ id, kind: "echo", confidence, headline: id });
    const selectionCases = [
      {
        name: "the most confident wins",
        candidates: [candidate("b", 0.6), candidate("a", 0.9)],
        options: { threshold: 0.5 },
      },
      {
        name: "a tie is broken by id, so the choice is stable",
        candidates: [candidate("b", 0.7), candidate("a", 0.7)],
        options: { threshold: 0.5 },
      },
      {
        name: "dismissed is gone entirely",
        candidates: [candidate("a", 0.9), candidate("b", 0.6)],
        options: { threshold: 0.5, dismissed: ["a"] },
      },
      {
        name: "archived too",
        candidates: [candidate("a", 0.9), candidate("b", 0.6)],
        options: { threshold: 0.5, archived: ["a"] },
      },
      {
        name: "nothing clears the bar, so nothing is shown",
        candidates: [candidate("a", 0.4), candidate("b", 0.3)],
        options: { threshold: 0.8 },
      },
    ];

    /*
     * The producers. `memoryNow` sits on a day whose events make right-time and echo
     * fire; the projects are hand-built so their weight and dormancy are exact rather
     * than whatever the derivation happens to produce.
     */
    const memoryDay = 1_770_076_800_000;
    const md = (h, m = 0) => memoryDay + h * 3_600_000 + m * 60_000;
    const memoryNow = md(15);
    const app = (name, bundle, seconds) => ({
      applicationName: name, bundleIdentifier: bundle, appPath: null, seconds,
    });
    const memoryProjects = [
      {
        id: "proj-editor",
        name: "Development · Code",
        category: "Development",
        apps: [app("Code", "com.microsoft.VSCode", 20_000), app("Terminal", "com.apple.Terminal", 9_000)],
        totalSeconds: 29_000,
        sessionCount: 9,
        firstSeen: memoryDay - 200 * DAY,
        // Dormant for forty days: past the twelve that make a return an echo.
        lastActive: memoryDay - 40 * DAY,
        sessions: [
          { startedAt: memoryDay - 40 * DAY },
          { startedAt: memoryDay - 44 * DAY },
        ],
      },
      {
        // Touched today after a long gap: a thread that resumed.
        id: "proj-writing",
        name: "Writing · Notes",
        category: "Writing",
        apps: [app("Notes", "com.apple.Notes", 8_000), app("Safari", "com.apple.Safari", 4_000)],
        totalSeconds: 12_000,
        sessionCount: 5,
        firstSeen: memoryDay - 150 * DAY,
        lastActive: md(11),
        sessions: [{ startedAt: md(11) }, { startedAt: memoryDay - 21 * DAY }],
      },
    ];
    // Today: mostly the editor project's tools, so it echoes them.
    const rightTimeEvents = [
      // A use 30 days ago, then today — a real gap for the right-time note.
      ev(1000, "Code", "com.microsoft.VSCode", memoryDay - 30 * DAY + 9 * 3_600_000, 1500),
      ev(1001, "Code", "com.microsoft.VSCode", md(14), 900),
    ];
    const echoEvents = [
      ev(1010, "Code", "com.microsoft.VSCode", md(9), 1500),
      ev(1011, "Terminal", "com.apple.Terminal", md(10), 1200),
    ];

    /*
     * Anniversaries only fire on an exact date, so `anniversaryNow` is built to *be*
     * one: a year to the day after the seed's first event, and six months after a
     * project began. Bookmarks and reflections are aged past each producer's floor so
     * the forgotten cases fire on the ordinary clock.
     */
    const anniversaryNow = 1_770_076_800_000 + 10 * 3_600_000;
    const yearBefore = new Date(anniversaryNow);
    yearBefore.setFullYear(yearBefore.getFullYear() - 1);
    const sixMonthsBefore = new Date(anniversaryNow);
    sixMonthsBefore.setMonth(sixMonthsBefore.getMonth() - 6);
    const anniversarySeed = {
      firstEventAt: yearBefore.getTime(),
      appCount: 3,
      appFirstSeen: [
        { applicationName: "Code", bundleIdentifier: "com.microsoft.VSCode", appPath: null, firstAt: yearBefore.getTime() },
      ],
    };
    const memoryBookmarks = [
      // Older than the 45-day floor, with a note, so the excerpt is exercised.
      { sessionStart: memoryDay - 90 * DAY, note: "  the migration   spike, and what it cost  ", bookmarked: true, tags: [], updatedAt: yearBefore.getTime() },
      // Inside the floor: must not appear.
      { sessionStart: memoryDay - 10 * DAY, note: "", bookmarked: true, tags: [], updatedAt: memoryDay - 10 * DAY },
    ];
    const memoryReflections = [
      { dayStart: memoryDay - 200 * DAY, text: "A long line about what mattered that week, written down so it would not be lost." },
      { dayStart: memoryDay - 5 * DAY, text: "Too recent to have been forgotten." },
      { dayStart: memoryDay - 3 * DAY, text: "   " },
    ];

    /*
     * The morning briefing. Four cases, one per reason it stays quiet: the afternoon,
     * a yesterday with nothing in it, and the two shapes of a day worth mentioning.
     */
    const briefingToday = 1_770_076_800_000;
    const bt = (h, m = 0) => briefingToday + h * 3_600_000 + m * 60_000;
    const briefingSummaries = [
      { dayStart: briefingToday - DAY, activeSeconds: 7200, topBundleId: "com.microsoft.VSCode", topAppName: "Code", topSeconds: 5000 },
    ];
    const yesterdayEvents = [
      ev(1100, "Code", "com.microsoft.VSCode", briefingToday - DAY + 9 * 3_600_000, 1500),
      ev(1101, "Terminal", "com.apple.Terminal", briefingToday - DAY + 9 * 3_600_000 + 1_500_000, 600),
    ];
    const briefingCases = [
      {
        name: "a morning with something to say",
        now: bt(8),
        yesterdayEvents,
        monthAgo: { dayStart: briefingToday - 30 * DAY, topApp: "Safari" },
        bookmarkStarts: [briefingToday - 12 * DAY, briefingToday - 40 * DAY],
      },
      { name: "the afternoon, when the day is underway", now: bt(14), yesterdayEvents },
      { name: "a yesterday with nothing in it", now: bt(8), yesterdayEvents: [] },
      { name: "no memory and no bookmark", now: bt(9), yesterdayEvents },
    ];

    /*
     * Moments. Each kind has a threshold, and the fixture crosses every one it can with
     * a single day of rows: a stretch past twenty minutes, eight distinct applications,
     * and something at 2 AM. The streak and the peak day come from the chapter summaries
     * this shares, which already hold a run of consecutive days.
     */
    const momentDay = 1_770_076_800_000;
    const mt = (h, m = 0) => momentDay + h * 3_600_000 + m * 60_000;
    const momentEvents = [
      // 25 minutes on one app: past the twenty-minute bar for a longest focus.
      ev(900, "Code", "com.microsoft.VSCode", mt(9), 1500),
      ev(901, "Terminal", "com.apple.Terminal", mt(9, 25), 300),
      // Eight distinct bundles in the day, for the busiest mix.
      ev(902, "Safari", "com.apple.Safari", mt(11), 300),
      ev(903, "Mail", "com.apple.mail", mt(11, 10), 300),
      ev(904, "Slack", "com.tinyspeck.slackmacgap", mt(11, 20), 300),
      ev(905, "Notes", "com.apple.Notes", mt(11, 30), 300),
      ev(906, "Music", "com.apple.Music", mt(11, 40), 300),
      ev(907, "Finder", "com.apple.finder", mt(11, 50), 300),
      // 2:14 AM the next day: inside the 1–5 window, so a late night.
      ev(908, "Code", "com.microsoft.VSCode", mt(26, 14), 600),
    ];
    const momentNow = mt(30);
    const momentSeed = {
      // Well past the three days that make a newly-tried app notable.
      firstEventAt: momentDay - 40 * DAY,
      appCount: 8,
      appFirstSeen: [
        // Inside seven days: a first-time-in moment.
        { applicationName: "Notes", bundleIdentifier: "com.apple.Notes", appPath: null, firstAt: momentDay - 2 * DAY },
        // Outside it: must not appear.
        { applicationName: "Music", bundleIdentifier: "com.apple.Music", appPath: null, firstAt: momentDay - 30 * DAY },
      ],
    };

    /*
     * Chapters, from daily headlines rather than from rows. Four runs, each testing one
     * rule: a character change splits, a gap longer than 16 days splits even when the
     * character is unchanged, a day under five minutes is too quiet to anchor anything,
     * and a run crossing a month boundary must name itself with a range.
     */
    const chapterDay = 1_767_225_600_000; // a local midnight, New Year's Day 2026
    const summary = (dayOffset, app, bundle, seconds, topSeconds) => ({
      dayStart: chapterDay + dayOffset * DAY,
      activeSeconds: seconds,
      topBundleId: bundle,
      topAppName: app,
      topSeconds: topSeconds ?? seconds,
    });
    const chapterSummaries = [
      // Five development days, then one that leans elsewhere: a split on character.
      summary(0, "Code", "com.microsoft.VSCode", 3600),
      summary(1, "Code", "com.microsoft.VSCode", 7200),
      summary(2, "Terminal", "com.apple.Terminal", 3600),
      summary(3, "Code", "com.microsoft.VSCode", 1800),
      summary(4, "Code", "com.microsoft.VSCode", 3600),
      summary(5, "Safari", "com.apple.Safari", 3600),
      summary(6, "Safari", "com.apple.Safari", 5400),
      // Too quiet to anchor anything, and it must not split the run either.
      summary(7, "Safari", "com.apple.Safari", 60),
      summary(8, "Safari", "com.apple.Safari", 3600),
      // A twenty-day gap: same character, new chapter.
      summary(28, "Safari", "com.apple.Safari", 3600),
      summary(29, "Safari", "com.apple.Safari", 3600),
      // And a run that crosses into the next month, so the name has to be a range.
      summary(58, "Code", "com.microsoft.VSCode", 3600),
      summary(59, "Code", "com.microsoft.VSCode", 3600),
      summary(62, "Code", "com.microsoft.VSCode", 3600),
    ];

    /*
     * Rituals: a part of the day only counts once the same app has led it on more than
     * one day. Three mornings led by the same app clears that; one afternoon does not,
     * and must produce no slot at all. The first app of each day is tallied separately
     * from the leaders, so one day starts on something that leads nothing.
     */
    const ritualDay = 1_769_990_400_000;
    const rt2 = (day, h, m = 0) => ritualDay + day * DAY + h * 3_600_000 + m * 60_000;
    const ritualEvents = [
      // Three mornings led by Code — a ritual.
      ev(800, "Code", "com.microsoft.VSCode", rt2(0, 9), 900),
      ev(801, "Terminal", "com.apple.Terminal", rt2(0, 9, 15), 300),
      ev(802, "Code", "com.microsoft.VSCode", rt2(1, 9), 900),
      ev(803, "Terminal", "com.apple.Terminal", rt2(1, 9, 15), 300),
      ev(804, "Code", "com.microsoft.VSCode", rt2(2, 9), 900),
      ev(805, "Terminal", "com.apple.Terminal", rt2(2, 9, 15), 300),
      // One afternoon led by Safari — not enough days to be a ritual.
      ev(806, "Safari", "com.apple.Safari", rt2(0, 14), 900),
      ev(807, "Mail", "com.apple.mail", rt2(0, 14, 15), 300),
      // Two evenings led by Mail — a ritual, and a different app from the mornings'.
      ev(808, "Mail", "com.apple.mail", rt2(1, 19), 900),
      ev(809, "Safari", "com.apple.Safari", rt2(1, 19, 15), 300),
      ev(810, "Mail", "com.apple.mail", rt2(2, 19), 900),
      ev(811, "Safari", "com.apple.Safari", rt2(2, 19, 15), 300),
      // A fourth day that begins on something else entirely, so the first-app tally and
      // the part leaders cannot be the same computation by accident.
      ev(812, "Music", "com.apple.Music", rt2(3, 7), 600),
      ev(813, "Code", "com.microsoft.VSCode", rt2(3, 9), 900),
      ev(814, "Terminal", "com.apple.Terminal", rt2(3, 9, 15), 300),
    ];
    const ritualNow = rt2(4, 12);

    /** The hour boundaries in `describePeak`, from each side. */
    const peakCases = [
      { weekday: 0, hour: 0, seconds: 1 },
      { weekday: 1, hour: 4, seconds: 1 },
      { weekday: 2, hour: 5, seconds: 1 },
      { weekday: 3, hour: 11, seconds: 1 },
      { weekday: 4, hour: 12, seconds: 1 },
      { weekday: 5, hour: 16, seconds: 1 },
      { weekday: 6, hour: 17, seconds: 1 },
      { weekday: 0, hour: 21, seconds: 1 },
      { weekday: 1, hour: 22, seconds: 1 },
      { weekday: 2, hour: 23, seconds: 1 },
    ];

    const json = execFileSync(
      "node",
      [runner, JSON.stringify({
        // Every session category, so the two that fall through to Other are pinned.
        filterCases: ["Development", "Research", "Communication", "Writing", "Design", "Media", "Admin", "Other"],
        anniversaryNow,
        anniversarySeed,
        memoryBookmarks,
        memoryReflections,
        briefingCases,
        briefingSummaries,
        scoringCases,
        selectionCases,
        memoryProjects,
        memoryNow,
        rightTimeEvents,
        echoEvents,
        momentEvents,
        momentNow,
        momentSeed,
        // Terminal is in both editor sessions; Code is the other half of that pair.
        anchorKey: "com.apple.Terminal",
        partnerKey: "com.microsoft.VSCode",
        chapterSummaries,
        // Reflections live in their own table, so the count is supplied. Two periods get
        // one, so the singular and the plural are both exercised, and the rest get none
        // so the sentence has to be absent rather than say "0 reflections".
        reflectionCounts: { "m-2026-0": 3, "y-2026": 1 },
        ritualEvents,
        ritualNow,
        appStatEvents,
        appStatNow,
        resumeCases,
        whenCases,
        workflowEvents,
        workflowNow,
        weekEvents,
        weekDayStarts,
        weekNow,
        peakCases,
        breakCases,
        groupingEvents,
        reportEvents,
        reportNow,
        annotations,
        label: "This Week",
        scopeEvents,
        scopeNow,
        scopeAnnotations,
        todayStart,
        searchQueries: input_searchQueries,
        historyNows,
        historySummaries,
        collectionEvents,
        collectionNow,
        storyCases,
      })],
      {
        cwd: GLAZE,
        encoding: "utf8",
        maxBuffer: 32 * 1024 * 1024,
        env: { ...process.env, ...FIXTURE_ENV },
      },
    );

    const result = JSON.parse(json);
    if (result.sessionCount === 0) {
      problems.push("export fixture produced no sessions — the derivation input is wrong");
    }
    return {
      timeZone: FIXTURE_TZ,
      locale: FIXTURE_LOCALE,
      exportedAtMillis: FIXTURE_NOW,
      grouping: { events: groupingEvents, expected: result.grouping },
      breaks: result.breaks,
      week: {
        events: weekEvents,
        dayStarts: weekDayStarts,
        now: weekNow,
        expected: result.week,
        peakCases: result.peakLabels,
      },
      appStats: {
        events: appStatEvents,
        now: appStatNow,
        expected: result.appStats,
      },
      resume: {
        cases: resumeCases,
        expected: result.resume,
        whenCases: result.whenLabels,
        dayLabels: result.dayLabels,
      },
      autobiography: {
        expected: result.autobiography,
      },
      legacy: { expected: result.legacy },
      filters: result.filters,
      canvas: {
        constellation: result.constellation,
        expected: result.canvas,
      },
      briefings: {
        cases: briefingCases,
        summaries: briefingSummaries,
        expected: result.briefings,
      },
      memory: {
        scoringCases,
        scoring: result.scoring,
        selectionCases: selectionCases.map((c) => ({ name: c.name, ...c })),
        selection: result.selection,
        projects: memoryProjects,
        now: memoryNow,
        rightTimeEvents,
        echoEvents,
        producers: result.producers,
        anniversaryNow,
        anniversarySeed,
        bookmarks: memoryBookmarks,
        reflections: memoryReflections,
        surprise: result.surprise,
        anniversaries: result.anniversaries,
        forgotten: result.forgotten,
      },
      moments: {
        events: momentEvents,
        now: momentNow,
        seed: momentSeed,
        expected: result.moments,
        quoteKey: result.quoteKey,
      },
      relationships: {
        anchorKey: "com.apple.Terminal",
        partnerKey: "com.microsoft.VSCode",
        partners: result.partners,
        relationship: result.relationship,
        hasNoRelationship: result.hasNoRelationship,
      },
      chapters: {
        summaries: chapterSummaries,
        expected: result.chapters,
      },
      rituals: {
        events: ritualEvents,
        now: ritualNow,
        expected: result.rituals,
      },
      workflows: {
        events: workflowEvents,
        now: workflowNow,
        sessionCount: result.workflowSessionCount,
        expected: result.workflows,
        projects: result.projects,
      },
      search: { queries: input_searchQueries, expected: result.searchResults },
      history: { summaries: historySummaries, cases: result.history },
      stories: { cases: storyCases, expected: result.stories },
      collections: {
        events: collectionEvents,
        now: collectionNow,
        ...result.collections,
      },
      scopes: {
        events: scopeEvents,
        now: scopeNow,
        todayStart,
        annotations: scopeAnnotations,
        // Every scope the reference offers, so a new one upstream shows up as a
        // key this port does not handle rather than as silence.
        offered: result.scopeLabels.map((s) => s.value),
        allSessionStarts: result.scopeSessionStarts,
        expected: result.scopes,
      },
      report: {
        label: "This Week",
        now: reportNow,
        events: reportEvents,
        annotations,
        expected: result.reports,
      },
    };
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

let exportFixture = null;
try {
  exportFixture = buildExportFixtures();
} catch (error) {
  problems.push(`could not run the Glaze grouping/export code: ${error.message.split("\n")[0]}`);
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
  join(SPEC, "grouping-and-export.json"),
  JSON.stringify({ _generated: provenance, ...exportFixture }, null, 2) + "\n",
);

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
console.log(`  grouping-and-export.json  ${exportFixture.grouping.expected.length} days, ${Object.keys(exportFixture.report.expected).length} report formats`);
console.log(`\nReview 'git diff spec/' — anything that changed is work for the native port.`);
