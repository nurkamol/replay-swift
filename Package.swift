// swift-tools-version: 6.2
import PackageDescription

// Zero external dependencies on purpose.
//
// SQLite comes from the system (`import SQLite3`), the tracker from AppKit, and the UI
// from SwiftUI — so there is no package resolution step and nothing to vendor. GRDB
// would be pleasant but the queries here are hand-written SQL that has to stay readable
// against the Glaze app's SQL, which a query builder would only obscure.
//
// Deployment target is macOS 26 — the newest `PackageDescription` can name — and the
// tools-version is 6.2 because `.v26` was introduced there.
//
// Raised deliberately: Replay is built to sit alongside the current system, and the
// interface APIs it leans on begin at 15 (`searchFocused`) and 26 (the current material and
// symbol work). `ReplayCore` needs none of it; the requirement is the interface's alone,
// which is why the parity suite still runs anywhere the toolchain does.
//
// Xcode 27 beta lives at /Applications/Xcode-beta.app but is not the selected developer
// directory, so `swift test` needs it pointed out:
//
//     DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
//
// `swift build` and `swift run replay-parity` work either way. See README.md.
let package = Package(
    name: "Replay",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ReplayCore", targets: ["ReplayCore"]),
        .executable(name: "ReplayApp", targets: ["ReplayApp"]),
        .executable(name: "replay-parity", targets: ["ReplayParity"]),
        // A one-off diagnostic, kept because it answers a question that decides the App
        // Store route — see scripts/icon-probe.sh and docs/PORTING-MAP.md.
        .executable(name: "icon-probe", targets: ["IconProbe"]),
        // Brings a Glaze user's history across, and gives the UI real data to develop
        // against rather than fixtures.
        .executable(name: "replay-import", targets: ["ReplayImport"]),
        // `replay` — the record from a shell. The one thing on the backlog that needs no
        // Developer ID, and the second consumer of ReplayCore from outside the app.
        .executable(name: "replay", targets: ["ReplayCLI"]),
    ],
    targets: [
        .target(name: "ReplayCore"),
        .executableTarget(name: "ReplayApp", dependencies: ["ReplayCore"]),

        // The parity suite lives in its own library so it can run two ways from one
        // implementation: through swift-testing (`swift test`, needs Xcode) and as a
        // plain executable (`swift run replay-parity`, needs nothing). It reads `spec/`
        // from the repo, so the generated contract has exactly one copy.
        .target(name: "ParityKit", dependencies: ["ReplayCore"]),
        .executableTarget(name: "ReplayParity", dependencies: ["ParityKit"]),
        .testTarget(name: "ReplayCoreTests", dependencies: ["ParityKit", "ReplayCore"]),

        .testTarget(name: "ReplayAppTests", dependencies: ["ReplayApp", "ReplayCore"]),
        .executableTarget(name: "IconProbe"),
        .executableTarget(name: "ReplayImport", dependencies: ["ReplayCore"]),
        .executableTarget(name: "ReplayCLI", dependencies: ["ReplayCore"]),
    ]
)
