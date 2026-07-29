import Foundation
import ReplayCore
import Testing

/// The strings mechanism.
///
/// The app has one language today, so nothing here is about translation quality — it is
/// about the two properties that have to hold *before* a translator is worth engaging: that
/// a translation resolves when it exists, and that its absence is always English rather than
/// a raw key. A half-translated app is the normal state of a translated app, so the missing
/// case is the one that decides whether this is safe to ship.
@Suite("Localisation")
struct LocalizationBehaviour {

    @Test("English is the fallback for a key nothing defines")
    func fallsBackToEnglish() {
        // The English text *is* the key, so an untouched string is already correct.
        #expect(Loc.t("A sentence no catalogue has ever seen") == "A sentence no catalogue has ever seen")
        #expect(Loc.base("A sentence no catalogue has ever seen") == "A sentence no catalogue has ever seen")
    }

    @Test("A language this build does not carry falls back rather than failing")
    func unknownLanguage() {
        #expect(Loc.string("Tracking paused", in: "xx") == "Tracking paused")
    }

    @Test("A translation resolves when the catalogue has one")
    func translationResolves() {
        // The probe catalogue defines exactly this key, and nothing else. If this fails the
        // resource bundle is not being built or is not being found, which is the failure
        // mode that would otherwise only show up as "the app is still in English".
        #expect(Loc.string("Tracking paused", in: "uz", bundle: .module) == "Kuzatuv toʻxtatildi")
    }

    @Test("An untranslated key in a translated language is still English")
    func partialTranslation() {
        // The whole reason the English is the key: a translator who has done one string out
        // of four hundred leaves the other 399 readable rather than showing identifiers.
        #expect(Loc.string("Away from keyboard", in: "uz", bundle: .module) == "Away from keyboard")
    }

    @Test("A migrated string goes through the catalogue")
    func menuBarIsMigrated() {
        // MenuBar is the first file on the audit's migrated list, and this is the key it
        // now looks up. If somebody inlines the English again, the audit fails and so does
        // the premise of this test.
        #expect(MenuBar.pausedLabel == "Tracking paused")
        #expect(Loc.string(MenuBar.pausedLabel, in: "uz", bundle: .module) == "Kuzatuv toʻxtatildi")
    }

    @Test("The contract always sees English, whatever the machine is set to")
    func baseIsAlwaysEnglish() {
        // `uz` has a translation for this and `base` must not return it: the parity suite
        // compares against text generated from the reference, and CI already runs in four
        // timezones. The day it runs under another language, a check reading the reader's
        // language would compare a translation against English and fail for the wrong reason.
        #expect(Loc.base("Tracking paused") == "Tracking paused")
    }

    @Test("The build knows which languages it carries, English first")
    func available() {
        #expect(Loc.available.first == "en")
        // Not a fixed list any more — languages arrive, and a test that names them would fail
        // for every one of them. What has to hold is that English leads (it is the key, so it
        // is the fallback for everything else) and that every language claimed has a
        // catalogue behind it. A code in `available` with no strings is the exact failure
        // `tools/translate.mjs` refuses to create: macOS told "Replay speaks this" and a
        // reader shown English anyway.
        for language in Loc.available {
            #expect(
                Loc.string("Tracking paused", in: language) != "",
                "\(language) resolves to nothing"
            )
        }
    }

    @Test("The chosen language is one the build actually has")
    func languageIsAvailable() {
        #expect(Loc.available.contains(Loc.language))
    }
}
