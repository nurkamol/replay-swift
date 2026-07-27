# Porting map

What each piece of the Glaze app becomes natively, what it costs, and where the real
risk is. Line counts are from Glaze 2.3.1: **4.0k lines of backend, 19.6k of renderer**
across 103 files.

The shape of the job in one sentence: **the backend is small and gets smaller; the
renderer is the whole cost.**

> **How it turned out, 2026-07-28.** The sentence held. The core was finished and verified
> early and has barely moved since; every week after that went into the renderer, and the
> last stretch was not new features at all but seven audits reading each view beside its
> reference — which found more real divergence than the porting had. Line counts below are
> from Glaze 2.3.1 and are left as they were: they are a record of the estimate, and an
> estimate rewritten after the fact stops being one.

---

## Backend → native

The Glaze backend touches a remarkably thin native surface — 35 `app.*` calls, 4
workspace subscriptions, 1 idle-time read, a menu, a notification, a file dialog.

| Glaze / Electron | Native | Notes |
|---|---|---|
| `systemPreferences.subscribeWorkspaceNotification` | `NSWorkspace.shared.notificationCenter` | **Done** — `ActivityTracker.swift` |
| `powerMonitor.getSystemIdleTime` | `CGEventSource.secondsSinceLastEventType` | **Done** |
| `node:sqlite` `DatabaseSync` | `import SQLite3` | **Done** — `ActivityStore.swift`, zero dependencies |
| `mdfind` via `child_process` | the notification's `NSRunningApplication` | **Done, and better** — see below |
| `shell.openPath` | `NSWorkspace.openApplication(at:configuration:)` | |
| `app.getFileIcon` | `NSWorkspace.icon(forFile:)` | ⚠️ sandbox risk, see below |
| `Tray` + `Menu` | `NSStatusItem` + `NSMenu` | |
| `Notification` | `UNUserNotificationCenter` | needs an authorisation request; Electron's did not |
| `dialog.showSaveDialog` | `NSSavePanel` | |
| `safeStorage` | Keychain | unused today; Replay stores no secrets |
| `app.getPath("userData")` | `~/Library/Application Support/<bundle-id>/` | different container from the Glaze app — see migration in SYNC.md |
| `ipcMain.handle` / `invoke` | direct calls | the entire IPC layer disappears |
| `printToPDF` for exports | `NSPrintOperation` / `PDFKit` | |

**`mdfind` is the one thing that could not have survived.** The Glaze tracker shells out
to Spotlight to turn a bundle id into an app path, because its bridge hands over
`NSRunningApplication` as a *string* that has to be parsed. A sandboxed app cannot spawn
that. Natively the notification carries the object itself, so `localizedName` and
`bundleURL` are just there — the port deletes ~60 lines of parsing and caching and gains
correctness.

## Renderer → SwiftUI

19.6k lines, and this is where the months are:

| area | lines | native plan |
|---|---|---|
| `main/views/` (21 views) | 7,197 | SwiftUI, view by view |
| `lib/` (derivation, memories, export, canvas…) | 5,474 | mostly pure logic — ports cleanly, **start here** |
| `components/` (30) | 3,434 | SwiftUI views; `List`/`LazyVStack` replace most of it |
| `main/` (router, canvas, playback, screensaver) | 1,786 | `NavigationSplitView`; Canvas needs real work |
| `settings/` | 1,335 | `Settings` scene + `Form` |

Recommended v1 scope — roughly a third of the renderer, and the part people install the
app for:

1. **Today** — the day's headline, sessions, focus goal, reflection.
2. **Timeline** — days with dividers, expandable session cards, the ⋯ menus.
3. **A past day** — reopened, with delete/export.
4. **Settings** — General, Privacy, Data/Storage, Guide, About.

Leave for later, in this order: Memories → Search → Collections/Projects → Story →
Canvas → Museum/Autobiography → Screensaver. They are the delightful surfaces, but
nobody installs for them first, and Canvas (infinite pan/zoom with a synced timeline) is
a project of its own.

## Toolchain

**Xcode 27 beta** at `/Applications/Xcode-beta.app` (Swift 6.4) — installed, but *not*
the selected developer directory, so anything test-related needs it named:

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test                     # 188 checks, via swift-testing
```

Command Line Tools alone (Swift 6.2.3) still builds every target and runs the same suite
as an executable — `swift run replay-parity` — which is why the checks live in `ParityKit`
rather than only in a test target. Keep that property: it makes the suite runnable in CI
or over SSH with no Xcode present.

Everything needed for distribution is now available: a `.xcodeproj` can be generated when
wanted, and notarisation works. `scripts/make-app.sh` still assembles a runnable `.app`
by hand for the development loop, which is faster than a full Xcode build.

One caveat with a *beta* Xcode: its SDK is macOS 27 and notarising against a beta SDK is
not something to ship on. Build releases with a stable Xcode when there is a release to
build.

## Risks

**1. App icons inside the sandbox — ANSWERED, not a risk.** Tested 2026-07-26: all 12
probed icons come back **byte-identical** under a bare `com.apple.security.app-sandbox`,
with no entitlement and no exception. `urlForApplication(withBundleIdentifier:)` works
too, so the whole bundle-id → path → icon chain is clear. Reproduce with
`./scripts/icon-probe.sh`; evidence and caveats in [FINDINGS.md](FINDINGS.md).

**2. App Review on a tracking app.** An app that logs which applications you use will
draw privacy scrutiny. The defence is strong and should be stated plainly in the
listing: entirely local, no network code at all, no permissions requested, and the user
can delete any session, any day, or everything. Note also that the *name* Replay is
taken on the App Store by other apps — check availability before building the listing.

## Distribution

| route | pros | cons |
|---|---|---|
| Direct + Sparkle | no sandbox, no review, ship today | you own updates and notarisation |
| Mac App Store | discovery, trust, payments | sandbox (see risk 1), review, 30% |

For a privacy-first local app, direct distribution first is the lower-risk path — and it
keeps the option open. With the icon question answered, the App Store route no longer has
a known technical blocker: the sandbox costs nothing that Replay actually needs.
