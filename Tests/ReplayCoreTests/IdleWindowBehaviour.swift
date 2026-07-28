@testable import ReplayCore
import Testing

/// The hours a display is allowed to start itself in.
///
/// A small rule with one case that reads wrong, which is why it is a function in `ReplayCore`
/// rather than two comparisons inside the idle timer: a span that runs through midnight is a
/// perfectly ordinary answer to "when am I at this desk", and the obvious implementation is
/// false for every hour of it. Nothing else in the app could catch that — the timer fires
/// twenty seconds apart on a real clock, so a bug here would show up as "it never came on
/// last night" and be blamed on the machine having been asleep.
@Suite("Idle window")
struct IdleWindowBehaviour {

    @Test("A plain span holds its own hours and nothing else")
    func plainSpan() {
        #expect(IdleWindow.allows(hour: 9, from: 9, until: 18))
        #expect(IdleWindow.allows(hour: 17, from: 9, until: 18))
        #expect(!IdleWindow.allows(hour: 8, from: 9, until: 18))
        #expect(!IdleWindow.allows(hour: 20, from: 9, until: 18))
    }

    @Test("The end of a span is outside it, as every other span in the app is")
    func halfOpen() {
        #expect(!IdleWindow.allows(hour: 18, from: 9, until: 18))
    }

    @Test("A span through midnight holds both sides of it")
    func wrapsMidnight() {
        #expect(IdleWindow.allows(hour: 22, from: 22, until: 7))
        #expect(IdleWindow.allows(hour: 23, from: 22, until: 7))
        #expect(IdleWindow.allows(hour: 0, from: 22, until: 7))
        #expect(IdleWindow.allows(hour: 6, from: 22, until: 7))
        #expect(!IdleWindow.allows(hour: 7, from: 22, until: 7))
        #expect(!IdleWindow.allows(hour: 12, from: 22, until: 7))
    }

    @Test("Both ends equal means the whole day, not none of it")
    func degenerateSpanIsNotOff() {
        for hour in 0..<24 {
            #expect(IdleWindow.allows(hour: hour, from: 13, until: 13))
        }
    }

    @Test("An hour outside a clock is not in any span")
    func nonsenseHour() {
        #expect(!IdleWindow.allows(hour: 24, from: 0, until: 24))
        #expect(!IdleWindow.allows(hour: -1, from: 0, until: 24))
    }
}
