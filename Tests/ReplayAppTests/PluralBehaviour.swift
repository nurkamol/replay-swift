import Foundation
import Testing

@testable import ReplayCore

/// Counted nouns, and the rule that picks their form.
///
/// **`n == 1` is not a plural rule, it is English's plural rule.** These cases exist because
/// that distinction is invisible until somebody reads the app in a language with more than
/// two forms, at which point every counted noun in it is wrong — and no amount of translating
/// the two English forms more carefully can fix it.
@Suite("Counted nouns")
struct PluralBehaviour {

    /// The fixture language: four categories, none of them derivable from `n == 1`.
    private let ru = Locale(identifier: "ru")

    @Test("Russian picks by its own rules, and 21 is not plural")
    func russianCategories() {
        // one: 1, 21, 101 — anything ending in 1 except 11.
        // few: 2–4, 22–24.
        // many: 0, 5–20, and everything ending in 11–14.
        //
        // 21 and 11 are the pair worth staring at: a rule written as `n == 1` calls both of
        // them plural, and Russian calls 21 singular and 11 neither.
        let expected: [(Int, String)] = [
            (1, "1 сессия"),
            (2, "2 сессии"),
            (4, "4 сессии"),
            (5, "5 сессий"),
            (11, "11 сессий"),
            (21, "21 сессия"),
            (22, "22 сессии"),
            (100, "100 сессий"),
        ]
        for (n, want) in expected {
            let got = Loc.counted(
                n, "%@ session", "%@ sessions", in: "ru", bundle: .module, locale: ru
            )
            #expect(got == want, "\(n) rendered as \(got), wanted \(want)")
        }
    }

    /// The regression this whole change exists to prevent.
    @Test("The two-form rule would get Russian wrong, which is why it is not used")
    func twoFormsAreNotEnough() {
        // What `n == 1` would have produced, spelled out rather than described.
        for n in [11, 21, 5, 2] {
            let twoForm = n == 1 ? "%@ сессия" : "%@ сессии"
            let real = Loc.counted(
                n, "%@ session", "%@ sessions", in: "ru", bundle: .module, locale: ru
            )
            let twoFormRendered = String(format: twoForm, "\(n)")
            if n == 2 {
                // The one case out of four where the old rule happened to be right.
                #expect(real == twoFormRendered)
            } else {
                #expect(real != twoFormRendered, "\(n) agreed, so this case proves nothing")
            }
        }
    }

    @Test("English is unchanged, because n == 1 is correct English")
    func englishIsUntouched() {
        // English ships no `.stringsdict` on purpose: its rule and `n == 1` are the same rule,
        // and a file that restates it is one more thing to keep in step. So this exercises the
        // fallback, and the fallback is what the parity suite compares against the reference.
        #expect(Loc.counted(1, "%@ session", "%@ sessions", in: "en", locale: .init(identifier: "en")) == "1 session")
        #expect(Loc.counted(0, "%@ session", "%@ sessions", in: "en", locale: .init(identifier: "en")) == "0 sessions")
        #expect(Loc.counted(2, "%@ session", "%@ sessions", in: "en", locale: .init(identifier: "en")) == "2 sessions")
        #expect(Loc.count(1, "%@ session", "%@ sessions") == "1 session")
    }

    @Test("A language with no entry for a noun falls back rather than failing")
    func fallbackWhenTheEntryIsMissing() {
        // The Russian fixture defines `%@ session` and nothing else. A noun it has never heard
        // of has to come back as the two-form translation, or as English — never as empty, and
        // never as the raw `%#@n@` a half-wired lookup would leak.
        let got = Loc.counted(
            3, "%@ visit", "%@ visits", in: "ru", bundle: .module, locale: ru
        )
        #expect(got == "3 visits")
        #expect(!got.contains("%#@"))
        #expect(!got.isEmpty)
    }

    @Test("Uzbek renders through its stringsdict")
    func uzbekUsesTheCatalogue() {
        // Uzbek has two categories, like English — so this proves the *mechanism* is wired to
        // the shipped catalogue, not that the answer differs between them.
        let one = Loc.counted(1, "%@ session", "%@ sessions", in: "uz", locale: Locale(identifier: "uz"))
        let many = Loc.counted(7, "%@ session", "%@ sessions", in: "uz", locale: Locale(identifier: "uz"))
        #expect(one == "1 seans")
        #expect(many == "7 seans")
    }

    /// Every counted noun in the app is in the catalogue.
    ///
    /// Five of them were not, and nothing noticed: `Loc.count`'s arguments reach `Loc` through
    /// a call the key scanner did not read, so `%@ day`, `%@ visit`, `%@ visits`, `%@ switch`
    /// and `%@ switches` were absent from `keys.txt`, absent from every CSV, and rendered in
    /// English in a fully translated app.
    @Test("Every counted noun the app uses is a key")
    func everyCountedNounIsCollected() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let keys = try String(contentsOf: root.appendingPathComponent("translations/keys.txt"),
                              encoding: .utf8)
        let known = Set(keys.split(separator: "\n").map(String.init))
        for noun in ["%@ day", "%@ days", "%@ app", "%@ apps", "%@ session", "%@ sessions",
                     "%@ visit", "%@ visits", "%@ switch", "%@ switches",
                     "%@ result", "%@ results"] {
            #expect(known.contains(noun), "\(noun) is counted in the app but is not a key")
        }
    }
}
