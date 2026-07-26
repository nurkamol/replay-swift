# Keeping two implementations honest

Two codebases, one product. The Glaze app ships first and is **the reference
implementation** — when the two disagree about what Replay does, Glaze is right by
definition, because that is what users have installed.

The risk in that arrangement is not that the native port falls behind. It is that it
falls behind *silently*: a threshold nudged in TypeScript, a rule refined, and months
later two apps that describe the same day differently. Documentation does not solve
this, because documentation is not checked.

So the contract is generated and executable.

## The contract

`spec/` is written by `tools/sync-spec.mjs`, which reads the Glaze sources. Nothing in
it is hand-authored:

| file | what it pins | why it matters |
|---|---|---|
| `spec/schema.sql` | the database, verbatim | a database written by one app must be readable by the other |
| `spec/constants.json` | every behavioural threshold | 5-minute away, 30-minute idle break, 45-second stray switch, compaction ratio, the category table |
| `spec/fixtures/*.json` | session derivation, **run** | inputs plus the output the Glaze code actually produced |

The fixtures are the important part. Session derivation is the one piece of logic a
port is most likely to get subtly wrong — and subtly wrong here means every title and
total in the app is off. So instead of describing it in prose, `sync-spec.mjs` bundles
the real `renderer/lib/sessions.ts` with esbuild, runs it against eight scenarios, and
records what came back. The Swift port is then measured against that.

## The loop

**Every change lands in the Glaze app first.** Then:

```bash
cd ~/coding/replay
node tools/sync-spec.mjs        # re-read the Glaze sources
git diff spec/                  # ← this diff IS the porting work
```

A clean diff means nothing behavioural moved: ship the Glaze change and carry on. A
non-empty diff is a precise, reviewable statement of what changed. Then:

```bash
swift test                      # 188 checks against the regenerated contract
# or, with no Xcode available:
swift run replay-parity
```

If it fails, the port has not caught up yet. Fix `Sources/ReplayCore`, re-run, commit
`spec/` and the Swift change **together** — so every commit here says which Glaze
version it corresponds to.

`spec/constants.json` records the Glaze version and commit it was generated from, so
"which upstream is this port level with?" always has an answer:

```json
{ "glazeVersion": "2.3.1", "glazeCommit": "9dcd1bb" }
```

## Why the generator fails loudly

`sync-spec.mjs` exits non-zero if a constant it expects has been renamed or removed,
rather than quietly omitting it. A vanished threshold is itself a behavioural change,
and the failure mode to avoid is a spec that looks fine while having silently stopped
tracking something.

It has already earned this: the first version of its category-table regex matched only
3 of the 7 patterns, because four were written on one line and ended `/i],` instead of
`/i,`. A permissive extractor would have produced a plausible-looking spec, and the
Swift port would have quietly mis-titled every browsing and writing session.

## What the contract does not cover

Be clear-eyed about the boundary. `spec/` pins **behaviour of the core**: storage,
derivation, thresholds. It says nothing about:

- **UI.** Layout, motion, and copy are ported by eye and by judgement. That is fine —
  they should not be identical anyway; a native app should feel native.
- **The interesting invariants**, which are prose in [SPEC.md](SPEC.md) because they are
  about consequences rather than values: that a day is the day a run *started*, that a
  pruned day's headline is the only record left of it, that an annotation is live only
  while its first event exists. Those are the rules a port gets wrong at the *design*
  level, and no fixture catches them.
- **The Glaze app's own tests.** Six suites live in that repo's scratchpad workflow;
  they check the reference implementation's store, not this port.

When you change one of those invariants in Glaze, the diff to `spec/` may be empty and
the parity check may still pass. Read [SPEC.md](SPEC.md) and update it by hand.

## Migration between the two apps

They are separate apps with separate containers, so they will never share a live
database. What they *do* share is the backup format — `spec/constants.json` records it
as `replay.activity` version 1 — which the native app should read on first launch, so a
Glaze user can carry their history over:

```
Glaze:  Settings ▸ Data ▸ Full backup ▸ Export…   →  Replay.json
Native: Welcome ▸ Import from Replay for Glaze     →  same rows, same ids dropped
```

Import merges and never overwrites, keyed on `(type, started_at, bundle_identifier)`,
so running it twice is a no-op. Keep that property.
