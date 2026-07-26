# Findings

Answers to questions that decided something, with the evidence. Re-runnable, so a future
OS version can be re-checked rather than re-argued.

---

## App icons survive App Sandbox — no entitlement needed

**Date:** 2026-07-26 · **Reproduce:** `./scripts/icon-probe.sh` · **Verdict:** not a risk

The concern: Replay's timeline is *made of* application icons — every session card, every
app in a breakdown. If `NSWorkspace.icon(forFile:)` were blocked in a sandboxed app, the
App Store route would need a bundled icon set (poor) or a temporary-exception entitlement
(review friction). This decided whether to design around it, so it was worth answering
before the UI was written.

**Method.** One binary, two ad-hoc-signed `.app` bundles, the second carrying *only*
`com.apple.security.app-sandbox` — the strictest case, no file-access entitlements and no
exceptions. Both launched through LaunchServices, because the sandbox does not apply to a
bare binary and running one would have silently tested nothing.

The comparison is by **pixel hash**, not by success or failure, because the failure mode
here is not an error: `icon(forFile:)` returns a *generic placeholder* when it cannot see
the bundle. Each icon is rasterised at 64×64 and SHA-256'd, which gives two independent
signals — whether a given app hashes the same in both runs, and whether many apps collapse
to one hash within the sandboxed run.

**Result.** Sandbox confirmed engaged (the process's home directory was its container,
`~/Library/Containers/app.replay.iconprobe.sandboxed/Data`).

| | |
|---|---|
| apps probed (installed) | 12 |
| icons byte-identical to unsandboxed | **12 / 12** |
| generic placeholders | 0 |
| distinct icon hashes inside the sandbox | 12 (a single fallback would have given 1) |
| `urlForApplication(withBundleIdentifier:)` | resolved all 12 |

The control matters: the generic-icon hash (`4ec8e10e…`) was identical in both runs and
different from all 12 real icons, so the comparison was measuring something.

Two incidental findings:

- **Listing `/Applications` works sandboxed** — 161 entries, same as unsandboxed. Not
  needed (Replay resolves bundle ids rather than scanning), but it means the fallbacks were
  wider than assumed.
- **`NSRunningApplication.icon` works sandboxed** too, and does not touch the filesystem —
  a second route if the first ever closes.

**Caveats, stated honestly.** This was an ad-hoc signature on the current OS. An App Store
build is signed with a distribution identity and a provisioning profile, which adds
capabilities rather than removing them, so the result should hold — but it is one more
thing to confirm on the first real submission. The apps probed live in `/Applications` and
`/System/Applications`; icons for apps in unusual locations were not tested.

**Consequence.** Design the timeline to use real icons, straightforwardly, via
`NSWorkspace.shared.icon(forFile:)` on the path from
`urlForApplication(withBundleIdentifier:)`. No entitlement to request, no fallback
artwork to commission, and one fewer argument to have with App Review.
