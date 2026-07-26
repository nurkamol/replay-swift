import AppKit
import CryptoKit
import Foundation

// Does app-icon fetching survive App Sandbox?
//
// Replay's timeline is *made of* application icons — every session card, every app in a
// breakdown. If a sandboxed app cannot read them, the App Store route needs either a
// bundled icon set (poor) or a temporary-exception entitlement (review friction). So this
// is worth answering before any UI is written, not after.
//
// Run it via scripts/icon-probe.sh, which builds the same binary twice — once plain, once
// signed with com.apple.security.app-sandbox — and diffs the results.
//
// Methodology matters here, because the failure mode is not an error: `icon(forFile:)`
// returns a *generic* placeholder rather than throwing when it cannot see the bundle. So
// each icon's pixels are hashed. Two signals distinguish real icons from fallbacks:
//
//   · the same app hashing differently between the sandboxed and plain runs
//   · many apps hashing identically *within* one run (that is one generic icon reused)
//
// Usage: icon-probe <output.json>

let outputPath = CommandLine.arguments.dropFirst().first
    ?? NSTemporaryDirectory() + "icon-probe.json"

/// Apps to probe: well-known bundle ids that exist on any Mac, spanning /System and
/// /Applications, because those two live behind different sandbox rules.
let bundleIDs = [
    "com.apple.Safari",
    "com.apple.finder",
    "com.apple.systempreferences",
    "com.apple.Terminal",
    "com.apple.TextEdit",
    "com.apple.Music",
    "com.apple.mail",
    "com.apple.Preview",
    "com.apple.dt.Xcode",
    "com.google.Chrome",
    "com.microsoft.VSCode",
    "org.mozilla.firefox",
]

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
}

/// A stable fingerprint of what was actually drawn.
///
/// The NSImage is rasterised at a fixed size and hashed, rather than hashing
/// `tiffRepresentation` directly — that can carry incidental metadata and would make two
/// visually identical icons look different.
func fingerprint(_ image: NSImage) -> (hash: String, bytes: Int, reps: Int, size: String)? {
    let side = 64
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return (
        sha256(png),
        png.count,
        image.representations.count,
        "\(Int(image.size.width))×\(Int(image.size.height))"
    )
}

struct Result: Encodable {
    var bundleID: String
    /// Did NSWorkspace resolve the bundle id to a path at all?
    var resolvedPath: String?
    var iconFound = false
    var iconHash: String?
    var pngBytes: Int?
    var representations: Int?
    var reportedSize: String?
    var note: String?
}

var results: [Result] = []

for bundleID in bundleIDs {
    var result = Result(bundleID: bundleID)

    // Step 1: bundle id → path. Replay needs this too (it replaces the Glaze app's
    // `mdfind` shell-out), so it is part of what is being tested.
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        result.note = "not installed, or urlForApplication was refused"
        results.append(result)
        continue
    }
    result.resolvedPath = url.path

    // Step 2: path → icon.
    let image = NSWorkspace.shared.icon(forFile: url.path)
    if let print = fingerprint(image) {
        result.iconFound = !image.representations.isEmpty
        result.iconHash = print.hash
        result.pngBytes = print.bytes
        result.representations = print.reps
        result.reportedSize = print.size
    } else {
        result.note = "icon(forFile:) returned an image that could not be rasterised"
    }

    results.append(result)
}

// Two extra probes worth having, because they are the fallbacks if icons are blocked.
var extras: [String: String] = [:]

// Can the sandbox even list /Applications? Replay does not need this — it resolves
// bundle ids — but a "no" here narrows what the fallbacks could be.
do {
    let entries = try FileManager.default.contentsOfDirectory(atPath: "/Applications")
    extras["listApplications"] = "ok, \(entries.count) entries"
} catch {
    extras["listApplications"] = "refused: \(error.localizedDescription)"
}

// NSRunningApplication carries its own icon, and does not go through the filesystem —
// so it may survive where icon(forFile:) does not.
if let front = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier != nil }),
   let icon = front.icon,
   let print = fingerprint(icon) {
    extras["runningApplicationIcon"] =
        "ok for \(front.bundleIdentifier ?? "?") — \(print.hash.prefix(16))…"
} else {
    extras["runningApplicationIcon"] = "unavailable"
}

// A generic icon for comparison: whatever a path that does not exist produces. If real
// icons match this hash, they are placeholders.
let genericHash = fingerprint(NSWorkspace.shared.icon(forFile: "/nonexistent-\(UUID().uuidString)"))?.hash
extras["genericIconHash"] = genericHash ?? "unavailable"

struct Report: Encodable {
    let sandboxed: Bool
    let bundlePath: String
    let containerPath: String
    let results: [Result]
    let extras: [String: String]
}

// The surest signal that the sandbox actually engaged: a sandboxed process has its
// container as its home directory.
let home = FileManager.default.homeDirectoryForCurrentUser.path
let report = Report(
    sandboxed: home.contains("/Library/Containers/"),
    bundlePath: Bundle.main.bundlePath,
    containerPath: home,
    results: results,
    extras: extras
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let json = try encoder.encode(report)
try json.write(to: URL(fileURLWithPath: outputPath))

let found = results.filter(\.iconFound).count
NSLog("[icon-probe] sandboxed=\(report.sandboxed) icons=\(found)/\(results.count) → \(outputPath)")
print("sandboxed=\(report.sandboxed) icons=\(found)/\(results.count)")
