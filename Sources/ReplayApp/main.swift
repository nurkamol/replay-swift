import AppKit
import ReplayUI

// A `@main` type cannot coexist with top-level code, so the app is started explicitly.
// `.regular` rather than `.accessory` for now: a Dock icon is convenient while the UI is
// being built, and menu-bar-only becomes a setting later, as it is in the Glaze app.
//
// Five lines, and deliberately so. Everything else lives in `ReplayUI` because Xcode's canvas
// cannot preview an executable target: it wants `ENABLE_DEBUG_DYLIB`, which a SwiftPM package
// has no way to express, and its own error offers the alternative — "break out your preview
// code into a separate framework with its own scheme". That is this split, measured first
// with a throwaway library target rather than assumed. It is also what a widget would need,
// since an app extension cannot link an executable target either.
//
// `AppDelegate` is the only symbol this file names, which is why it is the only one `ReplayUI`
// makes public. `Intents.swift` stays here beside it: the App Intents metadata processor in
// `scripts/make-app.sh` is passed `--module-name ReplayApp`, and an intent that moved would
// stop being found with no error and no warning.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
