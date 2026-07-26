import Foundation
import ParityKit

// The parity suite, as a plain executable:
//
//     swift run replay-parity [path/to/spec]
//
// Same checks as `swift test`, which runs them through swift-testing. This form exists
// because it needs no Xcode — useful in CI, over SSH, or on a machine with only Command
// Line Tools installed. Both call ParityKit.runAllChecks, so there is one suite.

do {
    let specRoot = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    let report = try ParityKit.runAllChecks(specRoot: specRoot)

    print("Checking this port against Glaze \(report.glazeVersion) (\(report.glazeCommit))")
    print("spec: \(report.specRoot)\n")

    // Groups are read off the report rather than listed here, so adding one to the suite
    // cannot leave it silently unprinted — a summary that omits a group reads like coverage
    // that does not exist. The per-fixture groups (`derivation/…`, `summary/…`) are folded
    // into the section below, which names every fixture anyway.
    var groups: [String] = []
    for check in report.checks where !check.group.contains("/") {
        if !groups.contains(check.group) { groups.append(check.group) }
    }

    for group in groups {
        let checks = report.checks.filter { $0.group == group }
        print("\(checks.allSatisfy(\.passed) ? "✓" : "✗") \(group) — \(checks.count) checks")
    }

    print("\(report.fixtureResults.allSatisfy(\.passed) ? "✓" : "✗") session derivation")
    for fixture in report.fixtureResults {
        print("   \(fixture.passed ? "✓" : "✗") \(fixture.name) — \(fixture.description)")
    }

    print("")
    if report.passed {
        print("PARITY OK — \(report.checks.count) checks against Glaze \(report.glazeVersion)")
        exit(0)
    }

    print("PARITY FAILED — \(report.failures.count) of \(report.checks.count) checks")
    for failure in report.failures {
        print("  · [\(failure.group)] \(failure.what)")
        if let detail = failure.detail { print("      \(detail)") }
    }
    print("""

        Either this port needs updating to match the Glaze app, or spec/ is stale.
        Regenerate with: node tools/sync-spec.mjs
        """)
    exit(1)
} catch {
    print("could not run the parity check: \(error)")
    print("is spec/ generated? run: node tools/sync-spec.mjs")
    exit(2)
}
