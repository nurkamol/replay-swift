#!/usr/bin/env node
/**
 * Check that no view spells a visual constant.
 *
 * A design system is only worth having if it is the *only* place values live. One view
 * with `.padding(13)` in it is not a bug anybody reports — it is how a system rots, one
 * plausible number at a time, until "change a token to change the app" quietly stops being
 * true.
 *
 * So this reads the view sources and fails on any numeric literal in a visual position:
 * padding, spacing, radii, font sizes, line widths, durations, frame dimensions. The fix is
 * always the same — name it in `DesignSystem.swift` and use the name.
 *
 * `DesignSystem.swift` is exempt, because it is the place the numbers are supposed to be.
 *
 *   node tools/design-audit.mjs
 */

import { readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const VIEWS = resolve(HERE, "..", "Sources", "ReplayApp");

/** The one file allowed to contain magic numbers, because it is where they are named. */
const EXEMPT = new Set(["DesignSystem.swift"]);

/*
 * Values that are not really constants of the design: 0 and 1 are structural (a hairline, a
 * zero inset, a single line limit), and `.infinity` is a layout instruction rather than a
 * measurement. Flagging them would train people to ignore this check, which is worse than
 * not having it.
 */
const ALLOWED = new Set(["0", "1", "0.0", "1.0"]);

const RULES = [
  { name: "padding", pattern: /\.padding\(\s*(?:\.(?:horizontal|vertical|top|bottom|leading|trailing)\s*,\s*)?(\d+(?:\.\d+)?)\s*\)/g },
  { name: "spacing", pattern: /\bspacing:\s*(\d+(?:\.\d+)?)/g },
  { name: "corner radius", pattern: /\bcornerRadius:\s*(\d+(?:\.\d+)?)/g },
  { name: "line width", pattern: /\blineWidth:\s*(\d+(?:\.\d+)?)/g },
  { name: "font size", pattern: /\.system\(\s*size:\s*(\d+(?:\.\d+)?)/g },
  { name: "kerning", pattern: /\.kerning\(\s*(\d+(?:\.\d+)?)\s*\)/g },
  { name: "frame width", pattern: /\bwidth:\s*(\d+(?:\.\d+)?)/g },
  { name: "frame height", pattern: /\bheight:\s*(\d+(?:\.\d+)?)/g },
  { name: "animation duration", pattern: /\bduration:\s*(\d+(?:\.\d+)?)/g },
  { name: "opacity", pattern: /\.opacity\(\s*(\d+\.\d+)\s*\)/g },
  { name: "line spacing", pattern: /\.lineSpacing\(\s*(\d+(?:\.\d+)?)\s*\)/g },
];

const findings = [];
for (const file of readdirSync(VIEWS).filter((f) => f.endsWith(".swift"))) {
  if (EXEMPT.has(file)) continue;
  const lines = readFileSync(join(VIEWS, file), "utf8").split("\n");
  lines.forEach((line, index) => {
    // A commented-out example is prose, not code.
    if (line.trim().startsWith("//")) return;
    for (const rule of RULES) {
      rule.pattern.lastIndex = 0;
      let match;
      while ((match = rule.pattern.exec(line)) !== null) {
        if (ALLOWED.has(match[1])) continue;
        findings.push({ file, line: index + 1, rule: rule.name, value: match[1], text: line.trim() });
      }
    }
  });
}

/*
 * The other half: the mirror in `ParityKit` has to still be the app's own numbers.
 *
 * The parity suite checks `MotionTokens` and `CanvasTokens` against `spec/constants.json`,
 * and cannot check `DesignSystem.swift` at all — `ReplayApp` is an executable, so nothing
 * can import it. That left a gap wide enough to drive the whole point through: change a
 * duration in the design system and the suite goes on comparing the mirror to the spec,
 * agreeing with itself about a number the app no longer uses. Found while porting the
 * canvas camera, which is exactly the kind of change that would have slipped through.
 *
 * So the chain is closed from this end. `spec/` fixes the mirror, and this fixes the app to
 * the mirror; a value can only move by moving in the Glaze app first.
 */
const MIRRORED = [
  ["Design.Motion", "MotionTokens", [
    "pressSeconds", "hoverSeconds", "enterSeconds", "staggerSeconds", "staggerCapSeconds",
  ]],
  ["Design.Motion", "CanvasTokens", [
    ["tourDwellSeconds", "tourDwellSeconds"],
    ["tourCameraSeconds", "tourCameraSeconds"],
    ["cameraSeconds", "cameraSeconds"],
    ["cameraCentreSeconds", "centreSeconds"],
    ["cameraZoomSeconds", "zoomButtonSeconds"],
  ]],
  ["Design.Layout", "CanvasTokens", [
    ["canvasFocusZoom", "focusZoom"],
    ["canvasTourEndZoom", "tourEndZoom"],
    ["canvasTourStepZoom", "tourStepZoom"],
    ["canvasZoomStep", "zoomButtonStep"],
    ["canvasMinZoom", "minZoom"],
    ["canvasMaxZoom", "maxZoom"],
    ["canvasWheelStep", "wheelStep"],
    ["canvasWheelSensitivity", "wheelSensitivity"],
    ["canvasGlideDecay", "glideDecay"],
    ["canvasGlideMinSpeed", "glideMinSpeed"],
    ["canvasGlideRestSpeed", "glideRestSpeed"],
  ]],
];

/** Every `static let NAME: Type = <number>` in a file, by name. */
function numbers(source) {
  const out = new Map();
  for (const m of source.matchAll(
    /static\s+let\s+(\w+)\s*(?::\s*[\w.]+\s*)?=\s*(-?\d+(?:\.\d+)?)\s*$/gm,
  )) {
    out.set(m[1], Number(m[2]));
  }
  return out;
}

const design = numbers(readFileSync(join(VIEWS, "DesignSystem.swift"), "utf8"));
const mirror = numbers(
  readFileSync(resolve(HERE, "..", "Sources", "ParityKit", "MotionChecks.swift"), "utf8"),
);
const drifted = [];
for (const [, , pairs] of MIRRORED) {
  for (const pair of pairs) {
    const [inDesign, inMirror] = Array.isArray(pair) ? pair : [pair, pair];
    const a = design.get(inDesign);
    const b = mirror.get(inMirror);
    if (a === undefined) drifted.push(`Design has no ${inDesign} — renamed or removed?`);
    else if (b === undefined) drifted.push(`the mirror has no ${inMirror} — renamed or removed?`);
    else if (a !== b) drifted.push(`${inDesign} is ${a}, but the mirror says ${inMirror} is ${b}`);
  }
}

if (drifted.length > 0) {
  console.error(
    `design audit: ${drifted.length} value(s) drifted between DesignSystem.swift and the\n` +
      "mirror the parity suite checks against.\n",
  );
  for (const line of drifted) console.error(`  ${line}`);
  console.error(
    "\nThe mirror is what the suite compares to spec/, so a value that differs here is a\n" +
      "value the app uses and nothing checks. Fix whichever is wrong — and if the intent is\n" +
      "to change the behaviour, change it in the Glaze app and re-run tools/sync-spec.mjs.",
  );
  process.exit(1);
}

if (findings.length === 0) {
  console.log(
    "design audit: every view reads its values from Design, and the parity mirror still " +
      "matches it.",
  );
  process.exit(0);
}

console.error(`design audit: ${findings.length} hard-coded values in views\n`);
for (const f of findings) {
  console.error(`  ${f.file}:${f.line}  ${f.rule} = ${f.value}`);
  console.error(`      ${f.text}`);
}
console.error(
  "\nName these in Sources/ReplayApp/DesignSystem.swift and use the name, so changing a" +
    "\ntoken still changes the whole app.",
);
process.exit(1);
