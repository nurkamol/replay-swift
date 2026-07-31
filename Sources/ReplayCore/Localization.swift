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
        if let override, available.contains(override) { return override }
        return Bundle.preferredLocalizations(from: available, forPreferences: nil).first ?? "en"
    }

    /// A language the reader chose in Settings, overriding what the Mac is set to.
    ///
    /// The comment above used to end "It is the seam a language picker in Settings would need
    /// too, if this ever grows one" — this is that. Nil means follow the system, which is the
    /// default and the right one: an app that ignores the language a Mac is set to is an app
    /// arguing with a choice already made.
    ///
    /// Checked against ``available`` on the way in, so a code for a language this build does
    /// not carry falls back to the system's rather than to a table of nothing.
    nonisolated(unsafe) public static var override: String?

    /// The locale everything *formatted* should use: dates, times, counted numbers.
    ///
    /// **Strings and formatting are two different systems, and this is the seam between
    /// them.** The picker chooses which strings table is read; it has no effect at all on
    /// Foundation, which formats "Wednesday, July 29" from the *system* locale. So an app
    /// could be — and was — entirely translated with an English date across the top of it.
    ///
    /// Only when a language has been chosen explicitly. With the picker on Match System the
    /// answer is `.current`, which is the Mac's own answer to a question its owner already
    /// answered in System Settings.
    public static var locale: Locale {
        guard let override, available.contains(override) else { return .current }
        return Locale(identifier: override)
    }

    /// What the reader sees, in whatever language the machine is set to.
    public static func t(_ english: String) -> String {
        record(english)
        return string(english, in: language)
    }

    /// Every key the app actually asks for, written to a file when `REPLAY_LOG_KEYS` is set.
    ///
    /// **The ground truth, and the reason it exists.** Every other way of finding translatable
    /// strings is a scan of the source guessing what will reach a person, and each guess has
    /// been wrong in a different way: enum raw values are invisible to it, several `case`s on
    /// one line hid half a sidebar, a helper that collected copy and never looked it up read
    /// as complete. This asks the opposite question — what did the app *ask* for while
    /// somebody drove it through every surface — and the answer cannot be wrong about the
    /// surfaces it visited.
    ///
    /// Off unless the variable is set, and it appends rather than truncating so a run of
    /// `tools/screenshots.sh` accumulates every surface into one file.
    private static func record(_ english: String) {
        guard let path = ProcessInfo.processInfo.environment["REPLAY_LOG_KEYS"] else { return }
        recordLock.lock()
        defer { recordLock.unlock() }
        guard let data = (english + "\n").data(using: .utf8) else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    nonisolated(unsafe) private static let recordLock = NSLock()

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

    /// A counted noun: "1 session", "14 sessions", "21 сессия", "11 сессий".
    ///
    /// **The plural form comes from the language's own rules, not from `n == 1`.** English
    /// has two forms and picking by `n == 1` is right; Russian has four and Arabic six, and
    /// there it is simply wrong — Russian 21 takes the same form as 1, and 11 does not, so
    /// no test of `n == 1` can ever produce correct Russian.
    ///
    /// A `.stringsdict` states those forms per language, and Foundation resolves them
    /// against the locale's CLDR rules. It is consulted *before* `Replay.strings` for the
    /// same table, so the lookup below returns `%#@n@` — a reference to a variable rather
    /// than a sentence — whenever the language has an entry. `String(format:locale:)` then
    /// picks the form. The locale has to be passed explicitly for the same reason every
    /// formatter in this app takes it: the picker chooses the strings table and has no
    /// effect at all on Foundation's own idea of the current locale.
    ///
    /// **The two-form path is still here and is not dead code.** A language whose
    /// `.stringsdict` has no entry for this noun — or one carrying no `.stringsdict` at all —
    /// falls back to it, which degrades to the old behaviour rather than to nothing. Both
    /// forms therefore remain keys in their own right, and both are still translated.
    public static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        // Both forms are keys and both are translated, so both are recorded — the two-form
        // fallback needs them, and a recorder that only wrote down the branch this call took
        // would report a noun as reachable or not depending on the number it was handed.
        record(singular)
        record(plural)
        return counted(n, singular, plural, in: language, locale: locale)
    }

    /// The whole of ``count(_:_:_:)``, with everything it reads from global state passed in.
    ///
    /// Only so a test can ask for a language this build does not ship. Russian is the useful
    /// one — four plural categories against English's two — and it is the smallest thing that
    /// can tell a real plural rule apart from `n == 1`.
    public static func counted(
        _ n: Int, _ singular: String, _ plural: String,
        in language: String, bundle: Bundle? = nil, locale: Locale
    ) -> String {
        let format = string(singular, in: language, bundle: bundle)
        // `%#@` is what a `.stringsdict` hands back, and nothing else in the catalogue
        // contains it — a plain translation is a sentence, not a variable reference.
        if format.contains("%#@") {
            return String(format: format, locale: locale, n)
        }
        let form = string(n == 1 ? singular : plural, in: language, bundle: bundle)
        return String(format: form, "\(n)")
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
