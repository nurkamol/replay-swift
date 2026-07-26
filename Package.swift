// swift-tools-version: 6.0
import PackageDescription

// Zero external dependencies on purpose.
//
// SQLite comes from the system (`import SQLite3`), the tracker from AppKit, and the UI
// from SwiftUI — so there is no package resolution step and nothing to vendor. GRDB
// would be pleasant but the queries here are hand-written SQL that has to stay readable
// against the Glaze app's SQL, which a query builder would only obscure.
//
// Xcode 27 beta lives at /Applications/Xcode-beta.app but is not the selected developer
// directory, so `swift test` needs it pointed out:
//
//     DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test
//
// `swift build` and `swift run replay-parity` work either way. See README.md.
let package = Package(
    name: "Replay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReplayCore", targets: ["ReplayCore"]),
        .executable(name: "ReplayApp", targets: ["ReplayApp"]),
        .executable(name: "replay-parity", targets: ["ReplayParity"]),
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
    ]
)
