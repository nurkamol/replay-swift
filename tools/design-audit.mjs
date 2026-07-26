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

if (findings.length === 0) {
  console.log("design audit: every view reads its values from Design.");
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
