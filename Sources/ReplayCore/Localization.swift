import Foundation

/// Every word the app says, resolved through one table in one bundle.
///
/// **The English text is the key.** `Loc.t("Tracking paused")` looks up "Tracking paused" and
/// returns the translation if there is one, or the key itself if there is not. That choice
/// is doing a lot of work here:
///
/// - **A missing translation falls back to correct English**, never to a raw identifier. A
///   symbolic key like `menubar.paused` is tidier right up until one is missed, and then the
///   app shows `menubar.paused` to somebody. Half-translated is the normal state of a
///   translated app, so the fallback has to be the state that is safe.
/// - **The contract keeps working untouched.** This port's copy is compared character for
///   character against the reference — sixteen Guide answers, the Settings explanations, the
///   narrative surfaces. With the English as the key, the value a parity check sees on an
///   English machine is the same string it always was, and ``base(_:)`` makes that true on
///   any machine.
/// - **It is greppable.** Searching the source for a sentence somebody reported still finds
///   the place it comes from, which a table of symbolic keys destroys.
///
/// The cost is real and worth stating: two different senses of one English word cannot share
/// a key, and changing the English changes the key, orphaning its translations. The first is
/// handled by making the key longer than the ambiguity (`Loc.t("Open Replay")`, not "Open");
/// the second is what `tools/strings-audit.mjs` reports, so an orphan is visible rather than
/// silent.
///
/// One table in `ReplayCore` rather than one per target. `Bundle.module` differs per module,
/// so a helper in each would mean two catalogs, two lookup paths, and a string that works in
/// one target and not the other. The app calls into this.
public enum Loc {

    /// The table name. A named table rather than the default `Localizable`, so it is obvious
    /// in a diff which file a key belongs to.
    public static let table = "Replay"

    /// The language in use: the first of the reader's preferred languages this build carries.
    ///
    /// Resolved explicitly rather than leaving it to `Bundle.localizedString`, which picks a
    /// localisation implicitly and — measured, not assumed — did not follow `-AppleLanguages`
    /// for a SwiftPM resource bundle at all. Implicit was also untestable: proving a
    /// translation resolves would have meant relaunching a process with different language
    /// settings. Explicit is one function anybody can call with any language.
    ///
    /// It is the seam a language picker in Settings would need too, if this ever grows one.
    public static var language: String {
        Bundle.preferredLocalizations(from: available, forPreferences: nil).first ?? "en"
    }

    /// What the reader sees, in whatever language the machine is set to.
    public static func t(_ english: String) -> String {
        string(english, in: language)
    }

    /// One string in one named language, with the English as the fallback at every step.
    ///
    /// A missing `.lproj`, an unreadable table, or a key the translator has not reached yet
    /// all land on the same place: the English sentence that was the key. There is no path
    /// through here that shows somebody an identifier.
    /// The `bundle` parameter exists so the tests can prove a translation resolves without
    /// the app shipping one. A `uz.lproj` in `ReplayCore` would make macOS believe Replay
    /// supports Uzbek, and somebody whose Mac prefers it would get one translated line and
    /// four hundred English ones — a worse experience than no claim at all. The probe
    /// catalogue lives in the test bundle instead.
    /// The bundle the app's own catalogue lives in.
    ///
    /// **Resolved by hand, because `Bundle.module` calls `fatalError` when it cannot find
    /// its bundle** — and that is the wrong failure for this. Every other path here degrades
    /// to English by design: a missing `.lproj`, an unreadable table, a key no translator has
    /// reached. Missing the whole catalogue should degrade the same way, not take the app
    /// down. It shipped in 0.9.1 doing exactly that, and the release was unopenable.
    ///
    /// The shape of the bundle differs by builder, which is how it got through: SwiftPM's
    /// native build produces a *flat* bundle with `Info.plist` at the root, and Xcode's
    /// produces a *deep* one with `Contents/Resources/`. Every local build was deep, the
    /// release was flat, and the test suite never sees either — it runs where the bundle is
    /// always found. So this looks in the places a bundle can be and gives up quietly.
    public static var catalogue: Bundle {
        if let resolved = resolvedCatalogue { return resolved }
        let found = Self.findCatalogue()
        resolvedCatalogue = found
        return found
    }

    nonisolated(unsafe) private static var resolvedCatalogue: Bundle?

    private static func findCatalogue() -> Bundle {
        let name = "Replay_ReplayCore.bundle"
        let marker = Bundle(for: CatalogueMarker.self)
        let roots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            marker.resourceURL,
            marker.bundleURL,
            // A test run puts the resource bundle *beside* the binary rather than inside it.
            marker.bundleURL.deletingLastPathComponent(),
        ]
        // Loading is not enough: `Bundle(url:)` succeeds for any directory that exists, so a
        // candidate has to be checked for actually holding the catalogue. Without this the
        // search settled on the first thing that opened — a bundle with no localisations at
        // all — and `available` came back empty on CI while every local build was fine.
        for candidate in roots.compactMap({ $0?.appendingPathComponent(name) }) {
            if let bundle = Bundle(url: candidate), bundle.holdsCatalogue { return bundle }
        }
        // Resources compiled straight in rather than into a bundle of their own.
        if marker.holdsCatalogue { return marker }
        // Nothing found. Every lookup falls through to the English key, which is the whole
        // reason the key is the English — a build with no catalogue is in English, not dead.
        return marker
    }

    /// Only exists to be a class the runtime can locate a bundle from.
    private final class CatalogueMarker {}

    public static func string(
        _ english: String, in language: String, bundle: Bundle? = nil
    ) -> String {
        let bundle = bundle ?? catalogue
        guard let path = bundle.path(forResource: language, ofType: "lproj"),
              let localised = Bundle(path: path)
        else { return english }
        return localised.localizedString(forKey: english, value: english, table: table)
    }

    /// What the *contract* sees: always English, whatever the machine is set to.
    ///
    /// The parity suite compares this port's copy against text generated from the reference,
    /// and CI already runs in four timezones — the day it runs under a translated locale, a
    /// check reading the user's language would compare a translation against English and
    /// fail for a reason that has nothing to do with the port drifting. Same seam, and same
    /// reason, as `Report.Environment` injecting a locale rather than reading `.current`.
    public static func base(_ english: String) -> String {
        string(english, in: "en")
    }

    /// A counted noun: "1 session", "14 sessions".
    ///
    /// Two forms, and the limit is worth stating plainly rather than discovering later:
    /// English has two, and plenty of languages do not. Russian has three, Arabic six, and
    /// Japanese does not inflect for number at all. The real answer is a `.stringsdict`,
    /// which expresses those rules per language — and this is the seam it would go behind,
    /// since every counted noun in the app already comes through here. Adding it before
    /// there is a translator would be building for a language nobody has chosen.
    public static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        String(format: t(n == 1 ? singular : plural), "\(n)")
    }

    /// Every key the base catalog defines, for the audit to check against the source.
    ///
    /// Returns an empty set when the catalog has no entries yet, which is the correct state
    /// for a project whose only language is the one the keys are written in.
    public static var baseKeys: Set<String> {
        guard let path = catalogue.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path),
              let strings = bundle.path(forResource: table, ofType: "strings"),
              let contents = NSDictionary(contentsOfFile: strings) as? [String: String]
        else { return [] }
        return Set(contents.keys)
    }

    /// The languages this build carries, English first.
    public static var available: [String] {
        let codes = catalogue.localizations.filter { $0 != "Base" }.sorted()
        return codes.contains("en") ? ["en"] + codes.filter { $0 != "en" } : codes
    }
}

private extension Bundle {
    /// Whether this bundle is the one carrying Replay's strings, rather than merely a
    /// directory that opened.
    var holdsCatalogue: Bool {
        path(forResource: "en", ofType: "lproj") != nil
    }
}
