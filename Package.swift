// swift-tools-version: 6.0
import PackageDescription

// Zero external dependencies on purpose.
//
// SQLite comes from the system (`import SQLite3`), the tracker from AppKit, and the
// UI from SwiftUI — so the package builds with Command Line Tools alone, with no
// package resolution step and nothing to vendor. GRDB would be pleasant but the
// queries here are hand-written SQL that must stay identical to the Glaze app's,
// which a query builder would only obscure.
//
// Full Xcode is needed later for notarisation and any App Store submission; it is
// not needed to build or test the core.
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

        // The parity check is an executable, not a test target, on purpose: both
        // swift-testing and XCTest ship with Xcode, and this has to be runnable with
        // Command Line Tools alone —
        //
        //     swift run replay-parity
        //
        // It reads `spec/` directly, so the generated contract has exactly one copy.
        // Once full Xcode is installed, wrap it in a .testTarget as well if you want
        // it inside `swift test`.
        .executableTarget(name: "ReplayParity", dependencies: ["ReplayCore"]),
    ]
)
