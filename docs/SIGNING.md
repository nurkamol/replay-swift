# Signing

Replay is signed three different ways depending on what is available, and the middle one is
the one worth understanding.

| tier | identity | when | what it buys |
|---|---|---|---|
| 1 | `Developer ID Application: …` | `REPLAY_SIGN_IDENTITY` is set | notarisation, no warnings at all |
| 2 | `Replay Self-Signed` | that cert is in the keychain | **a stable identity across builds** |
| 3 | ad-hoc (`--sign -`) | nothing else available | it launches on this Mac |

`scripts/make-app.sh` picks the best available, says which one it used, and the release
workflow does the same. Tier 1 does not exist yet — see the note at the bottom.

## Why a certificate nobody trusts is worth having

An ad-hoc signature has no identity. Its designated requirement *is* the code hash:

```
$ codesign -d -r- /Applications/Replay.app
Identifier=app.replay.native
Signature=adhoc
# designated => cdhash H"3c387bf0d047f3375f48a93688114b79da769709"
```

That hash changes with every build, so as far as macOS is concerned each release is a
different program wearing the same name. Three things are keyed to that identity:

- **A Gatekeeper "Open Anyway" approval.** Granted to a signature, not to a path.
- **Any TCC grant** — Accessibility, App Management. Replay needs none of these to record
  (SPEC §1), so this matters only for the locked-down-Mac case `PermissionsModel` exists for.
- **Homebrew's upgrade path.** This is the big one, and it is recent. `Cask::Upgrade`
  (`upgrade.rb:303`) reads the old app's designated requirement, compares it to the new
  one, and calls `inherit_user_approval!` when they match — carrying the reader's approval
  forward, silently, with Gatekeeper still armed. When they do not match it takes the
  `:signer_changed` branch and prints *"macOS will prompt at next launch."*

Under ad-hoc signing that last branch is taken on **every single upgrade**, so every update
sent the reader back through System Settings — forever, not once. The in-app updater has the
same problem for the same reason: it replaces this bundle with a downloaded one.

A stable certificate fixes all three and costs nothing but a keychain entry.

**What it does not do.** It does not make the first launch any quieter. macOS treats
self-signed and unsigned identically on first contact, and the dialog is the same. It is not
a Developer ID, it is not notarisation, and it does not substitute for either. It only makes
the *second* install as quiet as the first one ended up being.

## Create the identity (once)

```sh
# A self-signed code-signing certificate, valid ten years.
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/replay-key.pem -out /tmp/replay-cert.pem \
  -subj "/CN=Replay Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12. The password is not optional — `security import` rejects an empty one.
#
# The three `pbe`/`macalg` flags are required on OpenSSL 3, which is what Homebrew installs.
# Its default algorithms produce a file macOS cannot read, and the error it gives is
# "MAC verification failed during PKCS12 import (wrong password?)" — which sends you off
# checking the password, where there is nothing wrong.
openssl pkcs12 -export -inkey /tmp/replay-key.pem -in /tmp/replay-cert.pem \
  -name "Replay Self-Signed" -out /tmp/replay.p12 -passout pass:replay \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1

# Into the login keychain, where codesign can reach it without prompting.
security import /tmp/replay.p12 -k ~/Library/Keychains/login.keychain-db \
  -P replay -A -T /usr/bin/codesign

rm -f /tmp/replay-key.pem /tmp/replay-cert.pem /tmp/replay.p12
```

Check it took — **without `-v`**:

```sh
security find-identity -p codesigning | grep "Replay Self-Signed"
```

`-v` filters to identities that chain to a trusted root, and a self-signed certificate never
does: with it you get `0 valid identities found`, and the identity you just imported looks
absent. What you should see instead is the certificate listed with `CSSMERR_TP_NOT_TRUSTED`
beside it, which is not a problem — `codesign` signs with it regardless. Only *verifying*
against a trust policy cares, and nothing here does.

From here `./scripts/make-app.sh release` uses it automatically and says so.

## The two CI secrets

The release workflow needs the same certificate, so every published build carries the
identity your local builds carry:

```sh
P12_PASSWORD="$(openssl rand -base64 24)"; echo "password: $P12_PASSWORD"

security export -t identities -f pkcs12 \
  -k ~/Library/Keychains/login.keychain-db \
  -P "$P12_PASSWORD" -o /tmp/replay-signing.p12
base64 -i /tmp/replay-signing.p12 | tr -d '\n' > /tmp/replay-signing.p12.base64
rm -f /tmp/replay-signing.p12
```

Then, as the repository owner:

```sh
gh secret set SELF_SIGN_P12_BASE64   --repo nurkamol/replay-swift < /tmp/replay-signing.p12.base64
gh secret set SELF_SIGN_P12_PASSWORD --repo nurkamol/replay-swift --body "$P12_PASSWORD"
rm -f /tmp/replay-signing.p12.base64   # this file is your private key
```

With neither secret set the workflow falls back to ad-hoc and warns; nothing breaks, updates
just go back to prompting.

**If you lose the secrets** but still have the certificate in your keychain, re-run this
section — the exported identity is the same one, so readers notice nothing. **If you lose the
certificate**, make a new one and expect every existing reader to approve Replay once more on
their next update, after which it is stable again.

**The key is a real secret, but a low-value one.** Nothing trusts this certificate root, so
possessing it lets somebody sign a build as "Replay Self-Signed" — which grants no authority
on any Mac. Treat it as worth protecting and not worth panicking about.

## Quarantine is a separate thing

Signing and quarantine are independent, and conflating them is the usual mistake. macOS marks
anything *downloaded* — by a browser, by `curl`, by Homebrew installing a cask — and refuses
to launch anything under that mark unless it is notarised. A perfect self-signed signature
does not help.

`Casks/replay-app.rb` clears the flag in `postflight`, so people who install through the tap
never meet the dialog. People who download the zip from the releases page clear it once by
hand, or click through System Settings. Both routes are documented in the README, and the
cask's own caveats state plainly that the check was skipped and what replaced it.

## Tier 1, when it comes

`make-dmg.sh --release` already signs, notarises and staples, and `release.yml` already has
the steps behind a `SIGNED` gate that is off until the secrets exist. The day there is a
Developer ID, the self-signed tier stops being reachable in CI and everything in this
document becomes history — including the `postflight` block in the cask, which exists only
because notarisation does not.
