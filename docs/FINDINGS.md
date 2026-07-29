# Findings

Answers to questions that decided something, with the evidence. Re-runnable, so a future
OS version can be re-checked rather than re-argued.

---

## Replay Story stuttered because of an embellishment, not a shortage — 2026-07-29

**Reported as "it centres the icon, then moves with stuttering, like with 2 stops".** That is
an exact description of what the code did, and none of it was the reference's.

Each stop ran three movements where it looked like it should run one:

| phase | curve | ends at |
|---|---|---|
| flight to the stop (760ms) | ease-**out** cubic | rest |
| lean toward the next stop (390ms) | ease-in-out cubic | rest |
| flight to the next stop | ease-**out** cubic — full speed from the first frame | rest |

So the camera arrived, stopped, crept, stopped, and then jerked away. Two stops and a lurch,
per hop, exactly as described. The lean was this port's own addition, added to stop the dwell
looking frozen; the ease-*out* flight was inherited from the focus animation, where it is
right — a double-click should be answered at full speed, because it is an answer.

Neither the curve nor the lean is in the contract (`spec/constants.json` pins the *durations*
— 760ms flight, 1150ms dwell — and those have not changed). So the fix stays level with the
reference: the lean is gone, the dwell is still, and a story's hop eases at **both** ends
(`Design.Motion.tourFlight`), because it begins from a camera at rest and nobody asked for it
in the instant it happens.

The same pass made the timeline panel follow the camera, which the Glaze version does and this
port did not: it stayed on whatever was selected when the story began, so a story was a camera
moving through one memory beside a list describing another.

---

## A conditional request does *not* save rate limit here — measured 2026-07-29

**GitHub's documentation says a `304 Not Modified` does not count against the rate limit.
On the unauthenticated endpoint this app uses, it does.** Measured directly, reading
`x-ratelimit-remaining` out of the replies rather than inferring it:

| request | status | `x-ratelimit-remaining` |
|---|---|---|
| `If-None-Match: <etag>` | `304` | 4 |
| `If-None-Match: <etag>` again | `304` | 3 |
| no conditional header | `200` | 2 |

Three requests, three decrements. The documented exemption is written in the section about
*authenticated* conditional requests; the unauthenticated cap is counted per IP and appears
to count every request that reaches it, body or no body.

This matters because it was the reason given for adding `If-None-Match` in the first place,
and that reason was wrong. The header stays, on the two grounds that survive measurement: a
304 carries no body, so the check moves bytes only on the day something changed, and
"unchanged" becomes an answer the code can act on rather than a payload it has to compare.
Neither is a way to avoid the 60-an-hour cap.

**What actually reduces spend** is doing fewer requests: not counting a refused check as the
day's check (so the retry is tomorrow rather than a second attempt today), and honouring
`x-ratelimit-reset` so nothing is sent into a window GitHub has already closed. Both shipped
in 0.9.5; this table is why the release notes do not claim the third thing.

Re-run it with:

```sh
etag=$(defaults read app.replay.native updateETag)
curl -s -o /dev/null -D - -H "If-None-Match: $etag" \
  https://api.github.com/repos/nurkamol/replay-swift/releases/latest \
  | grep -iE "^HTTP|x-ratelimit-remaining"
```

---

## A self-installed update is not quarantined — measured 2026-07-29

**You meet Gatekeeper once, and never again.** The first copy is downloaded by a browser and
carries `com.apple.quarantine`, which is the dialog the README explains. Every update after
that is downloaded by Replay itself, and does not.

Quarantine is not applied by *being* downloaded — it is applied by the downloading
application, and only when that application opts in with `LSFileQuarantineEnabled` in its
`Info.plist`. Browsers set it. Replay does not, so its own `URLSession` download never
inherits it, and the bundle it puts in place is clean.

Measured on a real self-update from 0.9.0 to 0.9.3:

| check | result |
|---|---|
| `com.apple.quarantine` on the replaced bundle | absent |
| extended attributes actually present | `com.apple.provenance` only |
| launching it afterwards | ran, no dialog |
| `spctl --assess --type execute` | `rejected` |

That last row is worth keeping, because it looks alarming and is not. `spctl` reports what
Gatekeeper *would* say about a notarised distribution, and an ad-hoc signature is not one —
it says `rejected` for every build this project has ever made, including ones that open
perfectly. Gatekeeper blocks on the quarantine flag, not on `spctl`'s opinion, which is why
"it says rejected" was a wrong conclusion earlier in this project's history and is recorded
above as such.

**So no de-quarantining step is needed, and none was added.** A `xattr -dr
com.apple.quarantine` in the update path would be stripping a flag that is not there — and a
line of code that removes a security attribute, kept for a case that does not arise, is the
kind of thing that stays after the reason for it stops being true.

## A test that was only true in the timezone it was written in

**Date:** 2026-07-28 · **Reproduce:** `TZ=UTC swift run replay-parity` at commit `0e1b604`
· **Verdict:** derive the fixture, never assert it

The Monday-week check pinned an instant and called it a Monday:

```swift
let mondayProbe = startOfLocalDay(1_785_092_400_000)  // a Monday
```

It is a Monday in UTC+5, where it was written. In UTC it is a Sunday, so `startOfWeek` walked
back six days and all seven checks failed — on every CI runner, from the commit that
introduced them, for six hours and twenty commits.

**Both halves of that are the finding.** The four-timezone matrix caught it on the first
push and kept saying so; nobody read the result. A check that fails unwatched is worth
nothing, and this project now has two entries in this file about local truths written into
tests — the other is the day-part titles. Both were invisible at the desk and obvious in CI.

The fix is a shape, not a value: **derive the fixture from the function under test, then
assert the property.**

```swift
let mondayProbe = startOfWeek(1_785_092_400_000)          // whatever week that is
equal("a week begins on a Monday",
      calendar.component(.weekday, from: mondayDate), 2)  // the actual claim
for offset in 0..<7 {                                     // all seven agree
    let day = calendar.date(byAdding: .day, value: offset, to: mondayDate)!
    equal("day \(offset) resolves to the same Monday", startOfWeek(millis(day)), mondayProbe)
}
```

Verified in eight zones including Pacific/Chatham (+12:45) and Australia/Lord_Howe (+10:30),
whose half-hour offsets break arithmetic that assumes a day is 86,400,000ms. The loop uses
`Calendar.date(byAdding:)` for the same reason: across a daylight-saving boundary a day is
not 24 hours, and adding milliseconds lands the probe on the wrong side of midnight.

---

## An unsigned disk image can be published, and cannot be opened

**Date:** 2026-07-28 · **Reproduce:** the three commands below · **Verdict:** no download
until it is signed

Asked whether the DMG could go on GitHub without a certificate. GitHub will host any file,
so the question is really what happens to the person who downloads it. Measured on macOS
27.0 rather than recalled:

```bash
codesign -dv --verbose=2 build/Replay.app     # Signature=adhoc, TeamIdentifier=not set
xattr -w com.apple.quarantine "0083;0;Safari;" build/Replay-0.9.0.dmg
spctl --assess --type open --context context:primary-signature -vv build/Replay-0.9.0.dmg
#   → rejected, source=no usable signature
```

The app copied out of the image and quarantined is rejected too. In practice that is
*"Apple could not verify Replay is free of malware"* with **Move to Trash** or **Cancel** —
and since macOS 15 the Control-click-to-open bypass is gone, so the only route in is System
Settings ▸ Privacy & Security ▸ Open Anyway, or `xattr -d com.apple.quarantine` in a
terminal.

**Measured, three ways, 2026-07-28.** The idea that an archive can be prepared "without
quarantine" does not survive contact:

| shipped as | after the user extracts it | `spctl` |
|---|---|---|
| `.zip` (`ditto`) | quarantine **propagated** to the app | rejected |
| `.tar.gz` (command-line `tar`) | quarantine **propagated** | rejected |
| `.dmg` | clean *inside* the mounted volume, **propagated on copy-out** | rejected |

The flag is not stored in the archive. It is applied on the *recipient's* machine by whatever
downloaded it, and macOS propagates it into anything a quarantined process extracts — so tar
is not the loophole it is sometimes said to be. Nothing done before uploading can prevent it.

**And a worked example.** `gityeop/FlowClip` ships a plain `FlowClip.zip` on its releases page
and it opens fine. Inspected: `Authority=Developer ID Application: Sang Yeop Lim (79Q5RV23F9)`,
`source=Notarized Developer ID`, `accepted`. It is not a packaging trick — they paid for a
Developer ID and notarised. That is what every project shipping an openable download has done.

**And there is no way around it.** A `.zip` carries the same quarantine; a `.pkg` needs a
*Developer ID Installer* certificate from the same paid programme; a self-signed certificate
is rejected identically because Gatekeeper trusts Apple's chain and nothing else; and
`xattr -dr com.apple.quarantine` is the user performing a bypass on their own machine, which
a publisher cannot do for them. Making a downloaded app open without friction *is* what the
Developer ID programme sells.

**So the decision is not "does it work" but "what are we asking of someone".** Two reasons
not to:

- **It undercuts the product.** Replay's claim is that nothing leaves your Mac and nothing is
  asked of you. Instructing somebody to override macOS's own security check to install it
  argues against that better than any feature argues for it.
- **Building it is genuinely better for the audience.** An app built locally is never
  quarantined, so it opens with no fight at all. Anyone who finds a Swift port with a parity
  suite has a toolchain. The "fallback" is the nicer path.

`scripts/make-dmg.sh --release` therefore refuses rather than producing an unsigned image,
and the README's Install section points at the source build.

---

## The Timeline's wait was layout, not data

**Date:** 2026-07-28 · **Reproduce:** the numbers below, against a 4,002-row database ·
**Verdict:** do not change the default range

Reported as "Last 7 Days loads a bit longer", with a proposal to default the Timeline to
Yesterday instead. The default range is contract-checked — `spec/constants.json` says `7d`
because the Glaze app says `7d` — so trading it away is a real cost and worth measuring
first.

| range | `store.sessions` | derivation | total |
|---|---|---|---|
| Today | 0.9 ms | 0.9 ms | **~2 ms** |
| Yesterday | 2.2 ms | 3.7 ms | **~6 ms** |
| Last 7 Days | 9.0 ms | 13.4 ms | **~22 ms** |

Twenty-two milliseconds is about 1.3 frames. Application icons were the other suspect and
are already cached twice over, by source and by drawn size.

The cost was the layout. `TimelineView` used a plain `VStack` inside a `ScrollView`, which
builds *every* child up front — so opening on Last 7 Days constructed all ~280 rows, every
session card and icon and annotation lookup, before one was on screen. It scaled with the
range exactly the way a slow query would, which is why it read as one. A `LazyVStack` builds
what is near the viewport, so the cost now scales with the window.

**The general lesson:** a symptom that scales with the amount of data is not evidence that
the data layer is slow. Measure the layers separately before spending a contracted value to
work around one of them.

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

---

## Backup import: what a round trip does and does not preserve

**Date:** 2026-07-26 · **Reproduce:** `swift run replay-import <backup.json> /tmp/test.db` · **Verdict:** safe, with one documented gap

Tested against a real export of 3,084 rows from the Glaze app's own database.

**A bug found and fixed on the way.** The Glaze importer's accepted-types set was
`activated, launched, terminated` — **`idle` was missing**, while the exporter writes every
row. So restoring a backup dropped every measured away stretch, and because a gap with no
`idle` row behind it is relabelled by the derivation, those stretches came back as "Replay
wasn't running" rather than "away". That is not lost detail, it is a changed account of the
day. Fixed in Glaze (`EVENT_TYPES` now includes `idle`), pinned in
`spec/constants.json → backup.acceptedEventTypes` so neither implementation can drop one
silently again, and covered by the parity suite.

**What the round trip preserves.** Import merges on `(type, started_at, bundle_identifier)`
and skips what it already has, which makes running it twice a no-op. On real data:

| row type | rows | lost on import |
|---|---|---|
| `activated` | 2,762 | **0** |
| `idle` | 53 | **0** |
| `launched` | 100 | 4 |
| `terminated` | 169 | 7 |

The derived timeline is identical either side — 2,815 rows, 210,491 seconds — so everything
any view reads survives intact.

**The gap, stated plainly.** 11 rows *were* dropped: zero-duration `launched`/`terminated`
point events where the same app produced two notifications in the same millisecond, which
that identity triple cannot tell apart. Nothing in either app reads those rows — the
timeline, the headlines, and every total are built from `activated` and `idle` only — so the
practical effect is nil. It was left alone deliberately: making the identity stricter would
risk re-importing genuine duplicates, which is the worse failure. But it means **"lossless"
is the wrong word for the round trip**, and the honest claim is "loses nothing any view
reads".

---

## A session can render as ending before it began — and the port reproduces it

**Date:** 2026-07-26 · **Reproduce:** the query below · **Verdict:** faithful, leave it

Building the Timeline surfaced a card reading `12:58 – 12:56 PM`. An end before its start
looked like a porting mistake in `formatRange`, so it was worth chasing down before
shipping the view that exposed it.

**It is in the data, not the formatting.** The imported history contains an `activated` row
whose `ended_at` precedes its `started_at`:

```sql
SELECT id, application_name,
       datetime(started_at/1000,'unixepoch','localtime') AS started,
       datetime(ended_at/1000,'unixepoch','localtime')   AS ended
FROM events WHERE ended_at < started_at;
-- 1214 | Replay | 2026-07-25 13:04:32 | 2026-07-25 12:56:48
```

`12:56:48` is exactly the `started_at` of the two `idle`/Away rows either side of it (1210,
1211). The mechanism: an away stretch is detected *retroactively* — `awayStart` is `now`
minus the measured idle time — and the open session is then closed at `awayStart`. When the
session opened *after* that computed instant, it is closed at a time before it began.

**Why the port shows it too.** The derivation is line-for-line the reference's: the session's
end is `pendingEnd`, taken from the last row in the run (`SessionBuilder.swift:259`,
`sessions.ts:367`), so a backwards row makes a backwards session in both implementations.
`spanSeconds` clamps with `max(0, …)`; the *displayed* range does not.

Left alone deliberately. Clamping the display would diverge from the reference for a
cosmetic gain, and the honest fix belongs upstream in Glaze's away handling — `closeSession`
should not accept an `endedAt` earlier than the session's `started_at`. Worth raising there;
until it is, this is inherited, not introduced.

---

## A backup this app wrote, this app could not read

**Date:** 2026-07-26 · **Reproduce:** `swift run replay-parity` (report export) · **Verdict:** fixed

Writing backups was the last half of the migration path — the reader has worked since the
import landed, and was checked against a real 3,084-row Glaze export. The writer was added
against the same `Backup.Row` type, and the first version of it produced files this app's
own reader parsed as **zero events**, without erroring.

**The cause.** `Backup.read` expects the keys SQLite produced: `application_name`,
`started_at`, `bundle_identifier`. The reference exports rows straight out of the database
(`events: rows.map(({ id: _id, ...rest }) => rest)`), so a real backup carries column names.
Writing from a Swift struct, the obvious thing is to name the keys after the *properties* —
`applicationName`, `startedAt` — which is what the first version did. Every row then failed
the reader's `guard` and was counted as skipped rather than rejected loudly.

**Why it was silent.** The reader is deliberately lenient about individual rows, so that one
bad row cannot lose the other 40,000. That is the right call for a file a user may have
hand-edited, and it is exactly what hid this: a file where *every* row is malformed reads as
a valid backup containing nothing.

**What caught it.** A round-trip check — encode, then read back, and compare the rows — not
a check that the writer produced plausible JSON. The two-line difference between those two
tests is the whole finding:

```swift
let encoded = Backup.encode(rows: try store.rowsForBackup(), appVersion: "test")
let reread = try Backup.read(encoded)
equal(xg, "and its rows survive intact", reread.rows, backupRows)
```

Verified afterwards on real data: 3,149 rows exported, re-imported, and all 3,149 recognised
as already present — nothing duplicated, nothing lost, including the 57 `idle` rows whose
loss upstream is the subject of the finding above.

**The general lesson, since this port will grow more serialisers.** A format's writer must be
tested against its own reader, never against a human reading the output. And a lenient
parser needs a caller that notices when leniency swallowed everything — `declaredCount`
exists for exactly that comparison and should be checked on import, not just recorded.

---

## The parity suite only passed in one timezone

**Date:** 2026-07-26 · **Reproduce:** `TZ=Asia/Tokyo swift run replay-parity` · **Verdict:** fixed

Teaching `tools/sync-spec.mjs` to emit fixtures for day grouping and report text meant
pinning a timezone, because both depend on one. That pinning immediately failed against the
*existing* derivation fixtures — and the reason turned out to be a latent bug in the suite
rather than in either implementation.

**Session titles are named after the local day part.** `nameSession` calls `dayPart(of:)`,
which reads the hour from `Calendar.current`. The fixture generator ran under whatever
timezone the machine had, and the Swift checks derived under the same one, so the two always
agreed — on that machine. The committed fixture said `"Morning in Code"` for an event at
`1770000000000`, which is 07:40 in +05 and 02:40 in UTC. In UTC the same code names it
`"Late night in Code"`, and the check fails:

```
· [derivation/one-session-two-apps] [0] title
    got Late night in Code, want Morning in Code
```

Nobody would have seen this until the suite ran somewhere else — CI, a colleague's machine,
or this one after a move. A fixture that encodes the machine that produced it is worse than
no fixture, because it looks like coverage.

**The fix, in three parts.** `buildTimeline` takes a `calendar` and threads it to
`nameSession`; the generator pins `TZ` and `LC_ALL` for every runner and records the timezone
in each fixture; the checks build a calendar from that field rather than using the machine's.
The suite now passes in UTC, America/New_York and Asia/Tokyo alike.

**A second divergence surfaced on the way**, and was *not* fixed, deliberately. Foundation
and Node bundle different ICU versions: the newer separates a time from its meridiem with a
narrow no-break space (U+202F) where the older uses a plain space. So `2:40:00 AM` from
Swift and `2:40:00 AM` from Node differ by one invisible byte that neither implementation
chose. The comparison folds the non-breaking space variants onto U+0020 and nothing else —
pinning that byte would break the suite on an OS or Node upgrade for a reason no reader of
the exported file could ever see.

**What the fixtures caught in the port itself**, none of which reading the reference had
found: the markdown timestamp used an abbreviated date where the reference uses
`toLocaleString()`; `dateStyle = .short` renders a two-digit year (`2/2/26`) where JavaScript
renders four; a session's time range collapsed its shared meridiem (`12:40 – 1:00 AM`) where
a report prints both (`12:40 AM – 1:00 AM`); the JSON omitted the `scope` field entirely; and
`exportedAt` lacked the milliseconds `toISOString()` writes. Five real differences in a
format that had been "verified by reading".
