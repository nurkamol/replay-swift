# Porting map

What each piece of the Glaze app becomes natively, what it costs, and where the real
risk is. Line counts are from Glaze 2.3.1: **4.0k lines of backend, 19.6k of renderer**
across 103 files.

The shape of the job in one sentence: **the backend is small and gets smaller; the
renderer is the whole cost.**

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

## Toolchain reality

This machine has **Swift 6.2.3 via Command Line Tools, no full Xcode.** That is enough
to build and check everything in `Sources/`:

```bash
swift build
swift run replay-parity        # 188 checks against the Glaze app
```

It is *not* enough for: `XCTest` or `swift-testing` (both ship with Xcode — which is why
the parity check is an executable, not a test target), a `.xcodeproj`, notarisation, or
any App Store submission. `scripts/make-app.sh` assembles a runnable `.app` by hand for
local use. **Install Xcode before the first real build you intend to distribute.**

## The two risks worth prototyping early

**1. App icons inside the sandbox.** `NSWorkspace.icon(forFile:)` on a path in
`/Applications` is the one API here whose sandbox behaviour I am not certain of, and
Replay's timeline is *made of* app icons — every session card, every breakdown row. If
it is blocked, the fallbacks are a bundled icon set (poor) or a temporary-exception
entitlement (App Review friction). **Test this on a hardened sandboxed build before
committing to the App Store route.** It is a two-hour experiment that de-risks months.

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
keeps the option open. The sandbox work is the same either way if you build for it from
the start, which is why the icon question is worth answering now rather than later.
