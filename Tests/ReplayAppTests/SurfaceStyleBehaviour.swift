import Foundation
import Testing
@testable import ReplayUI

/// What the Surfaces setting offers, and what it draws, on a Mac that cannot draw glass.
///
/// The deployment target is macOS 14 and `glassEffect` begins at 26, so on most of the range
/// this app now supports, one of the three choices does not exist. These cases fix the two
/// decisions that follow from that — which is worth doing precisely because the suite runs on
/// a machine where glass *is* available, so the interesting branch is the one nobody here
/// will ever see by looking.
@MainActor
@Suite("Surfaces below macOS 26")
struct SurfaceStyleBehaviour {

    @Test("Solid and frosted exist everywhere")
    func alwaysOffered() {
        #expect(SurfaceStyle.offered.contains(.solid))
        #expect(SurfaceStyle.offered.contains(.frosted))
    }

    @Test("Glass is offered exactly where it can be drawn")
    func glassTracksAvailability() {
        // Not "glass is always offered" and not "never" — the list follows the one fact it
        // depends on, so this reads the same on a Sonoma runner and a Tahoe one.
        #expect(SurfaceStyle.offered.contains(.glass) == SurfaceStyle.glassAvailable)
        #expect(SurfaceStyle.offered.count == (SurfaceStyle.glassAvailable ? 3 : 2))
    }

    @Test("A style always resolves to something this Mac can draw")
    func everythingIsDrawable() {
        for style in SurfaceStyle.allCases {
            #expect(SurfaceStyle.offered.contains(style.drawable))
        }
    }

    @Test("A glass preference from a newer Mac becomes frosted, not nothing")
    func storedGlassDegrades() {
        // Preferences travel — in a backup, or across an account — so `glass` has to mean
        // something on a Mac that cannot draw it. Frosted is the nearest of the two that can.
        #expect(SurfaceStyle.glass.drawable == (SurfaceStyle.glassAvailable ? .glass : .frosted))
        // And the two that need nothing are never rewritten.
        #expect(SurfaceStyle.solid.drawable == .solid)
        #expect(SurfaceStyle.frosted.drawable == .frosted)
    }
}
