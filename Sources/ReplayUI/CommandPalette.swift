import ReplayCore
import SwiftUI

/// Everything you can reach, from the keyboard, in one place.
///
/// ⌘K. Surfaces, applications, projects and the actions that are not places — matched as you
/// type, ranked, arrow keys to move, Return to go, Escape to leave.
///
/// The matcher has no counterpart upstream: the reference leans on a JavaScript library's
/// own scoring, which is not something to reproduce character for character. So this one is
/// written for what it has to rank — short names, typed in a hurry, often as initials — and
/// it is the one part of this app whose behaviour no fixture covers. That is recorded rather
/// than hidden.
@MainActor
@Observable
final class CommandPaletteModel {
    struct Item: Identifiable {
        enum Action {
            case surface(Navigation.Surface)
            case app(String)
            case project(String)
            case day(Int64)
            case screensaver
            case ambient
            case settings
            case toggleSidebar
        }

        var id: String
        var group: String
        var title: String
        var subtitle: String?
        var symbol: String
        var bundleID: String?
        var appPath: String?
        /// Extra text worth matching against, beyond the title.
        ///
        /// Deliberate rather than "everything on the row": every application's subtitle ends
        /// "this week", so matching subtitles wholesale made the query "week" list every
        /// application in the app. A day carries its full date here, because searching for
        /// one is the point of a day being in this list at all.
        var alsoMatches: String?
        var action: Action
    }

    var query = "" {
        didSet { if query != oldValue { refilter() } }
    }

    var open = false {
        didSet {
            if open {
                query = ""
                reload()
            }
        }
    }

    private(set) var results: [Item] = []
    /// Which result Return would activate.
    var highlighted = 0

    private var all: [Item] = []
    private let model: AppModel
    private let apps: AppsModel
    private let projects: ProjectsModel

    init(model: AppModel, apps: AppsModel, projects: ProjectsModel) {
        self.model = model
        self.apps = apps
        self.projects = projects
    }

    private func reload() {
        var items: [Item] = Navigation.Surface.allCases.map { surface in
            Item(
                id: "surface:\(surface.rawValue)", group: "Go", title: Loc.t(surface.rawValue),
                subtitle: Loc.t(surface.purpose), symbol: surface.symbol,
                action: .surface(surface)
            )
        }

        items += [
            // The reference groups these two under "Display", and they belong together:
            // both take the whole screen, and the choice between them is which one you
            // want, not whether you want one.
            Item(id: "action:ambient", group: "Display", title: Loc.t("Ambient Mode"),
                 subtitle: Loc.t("Today, large enough to read across a room"),
                 symbol: "rectangle.on.rectangle",
                 action: .ambient),
            Item(id: "action:screensaver", group: "Display", title: Loc.t("Screensaver"),
                 subtitle: Loc.t("A slow drift through your day"), symbol: "sparkles.tv",
                 action: .screensaver),
            Item(id: "action:settings", group: "Actions", title: Loc.t("Settings"),
                 subtitle: nil, symbol: "gearshape", action: .settings),
            Item(id: "action:sidebar", group: "Actions", title: Loc.t("Show or Hide Sidebar"),
                 subtitle: nil, symbol: "sidebar.leading", action: .toggleSidebar),
        ]

        if !apps.loaded { apps.load() }
        items += apps.stats.prefix(20).compactMap { stat in
            stat.bundleIdentifier.map { bundleID in
                Item(
                    id: "app:\(bundleID)", group: "Applications",
                    title: stat.applicationName,
                    subtitle: String(
                        format: Loc.t("%@ this week"), formatDurationShort(stat.totalSeconds)
                    ),
                    symbol: "app", bundleID: bundleID, appPath: stat.appPath,
                    action: .app(bundleID)
                )
            }
        }

        if !projects.loaded { projects.load() }
        items += projects.projects.prefix(12).map { named in
            Item(
                id: "project:\(named.id)", group: "Projects", title: named.name,
                subtitle: Loc.count(named.project.sessionCount, "%@ session", "%@ sessions") + " · "
                    + formatDurationShort(named.project.totalSeconds),
                symbol: "shippingbox",
                appPath: named.project.apps.first?.appPath,
                action: .project(named.id)
            )
        }

        // Recent days, so "yesterday" or a date gets you there without the Timeline.
        let today = startOfLocalDay(Int64(Date().timeIntervalSince1970 * 1000))
        items += (0..<14).map { offset in
            let day = today - Int64(offset) * dayMillis
            return Item(
                id: "day:\(day)", group: "Days",
                title: dayLabel(day, today: today),
                subtitle: offset == 0 ? nil : fullDayLabel(day),
                symbol: "calendar", alsoMatches: fullDayLabel(day), action: .day(day)
            )
        }

        all = items
        refilter()
    }

    private func refilter() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Nothing typed: the places, then the actions. Not everything — a palette that
            // opens onto two hundred rows is a list, not a way through.
            results = all.filter { $0.group == "Go" || $0.group == "Actions" }
        } else {
            results = all
                .compactMap { item -> (Item, Int)? in
                    guard let score = Self.score(item.title, query: trimmed)
                        ?? item.alsoMatches.flatMap({ Self.score($0, query: trimmed) })
                            .map({ $0 / 2 })
                    else { return nil }
                    return (item, score)
                }
                .enumerated()
                .sorted {
                    $0.element.1 == $1.element.1
                        ? $0.offset < $1.offset
                        : $0.element.1 > $1.element.1
                }
                .prefix(30)
                .map(\.element.0)
        }
        highlighted = results.isEmpty ? 0 : min(highlighted, results.count - 1)
    }

    /// How well `text` answers `query`, or nothing when it does not.
    ///
    /// Three tiers, because that is how people actually type into one of these: the whole
    /// thing from the start, the start of a word, or the letters in order somewhere inside.
    /// Contiguity is rewarded so "can" prefers "Canvas" over "Collections".
    static func score(_ text: String, query: String) -> Int? {
        let haystack = text.lowercased()
        let needle = query.lowercased()
        if needle.isEmpty { return 0 }

        if haystack.hasPrefix(needle) { return 1000 - haystack.count }
        // The start of any word — "this week" found by "week".
        for word in haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        where word.hasPrefix(needle) {
            return 800 - haystack.count
        }
        if haystack.contains(needle) { return 600 - haystack.count }

        // Letters in order, with a bonus for runs — how initials find things.
        var index = haystack.startIndex
        var matched = 0
        var run = 0
        var bonus = 0
        var lastWasMatch = false
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return nil }
            if lastWasMatch, found == index { run += 1; bonus += run * 4 } else { run = 0 }
            matched += 1
            lastWasMatch = true
            index = haystack.index(after: found)
        }
        return matched == needle.count ? 200 + bonus - haystack.count : nil
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        highlighted = (highlighted + delta + results.count) % results.count
    }

    var chosen: Item? { results.indices.contains(highlighted) ? results[highlighted] : nil }
}

/// The palette itself.
struct CommandPaletteView: View {
    @Environment(\.themeTint) private var tint
    @Bindable var palette: CommandPaletteModel
    let onRun: (CommandPaletteModel.Item.Action) -> Void

    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            if palette.results.isEmpty {
                Text(Loc.t("Nothing matches."))
                    .font(Design.Text.detail)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Design.Space.section)
            } else {
                list
            }
            hints
        }
        .frame(width: Design.Layout.paletteWidth)
        .background(Design.Material.panel, in: RoundedRectangle(
            cornerRadius: Design.Radius.surface, style: .continuous
        ))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.surface, style: .continuous)
                .strokeBorder(Design.Colour.border)
        )
        .shadow(
            color: Design.Colour.paletteShadow,
            radius: Design.Layout.paletteShadowRadius,
            y: Design.Layout.paletteShadowOffset
        )
        .onAppear { focused = true }
    }

    /// What the keys do, said once at the foot. The brief's discoverability point: a
    /// keyboard surface that does not tell you its keys is a keyboard surface for the person
    /// who wrote it.
    private var hints: some View {
        HStack(spacing: Design.Space.card) {
            hint("↑↓", "Move")
            hint("↩", "Open")
            hint("esc", "Close")
            Spacer(minLength: 0)
            if !palette.results.isEmpty {
                Text(Loc.count(palette.results.count, "%@ result", "%@ results"))
                    .font(Design.Text.micro)
                    .foregroundStyle(.quaternary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Design.Space.section)
        .padding(.vertical, Design.Space.inline)
        .overlay(alignment: .top) { Divider() }
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: Design.Space.tight) {
            Text(key)
                .font(Design.Text.micro)
                .padding(.horizontal, Design.Pill.countHorizontal)
                .padding(.vertical, Design.Pill.countVertical)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous)
                        .fill(Design.Colour.fill)
                )
            Text(label).font(Design.Text.micro).foregroundStyle(.tertiary)
        }
    }

    private var field: some View {
        HStack(spacing: Design.Space.card) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField(Loc.t("Go to a surface, an application, a project, a day…"), text: $palette.query)
                .textFieldStyle(.plain)
                .font(Design.Text.prose)
                .focused($focused)
                .onSubmit { if let item = palette.chosen { onRun(item.action) } }
                // Arrow keys move the highlight rather than the caret: the field is where
                // you type, but the list is what you are steering.
                .onKeyPress(.downArrow) { palette.move(1); return .handled }
                .onKeyPress(.upArrow) { palette.move(-1); return .handled }
        }
        .padding(Design.Space.section)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.0) { group, items in
                        Section {
                            ForEach(items) { item in
                                row(item)
                                    .id(item.id)
                            }
                        } header: {
                            Text(paletteGroupHeading(group))
                                .sectionLabelStyle()
                                .padding(.horizontal, Design.Space.section)
                                .padding(.vertical, Design.Space.snug)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Design.Material.panel)
                        }
                    }
                }
                .padding(.bottom, Design.Space.snug)
            }
            .frame(maxHeight: Design.Layout.paletteMaxHeight)
            .onChange(of: palette.highlighted) { _, _ in
                if let item = palette.chosen { proxy.scrollTo(item.id, anchor: .bottom) }
            }
        }
    }

    /// Results in their groups, in the order the groups first appear — so ranking decides
    /// which group leads rather than a fixed order overriding the match.
    private var groups: [(String, [CommandPaletteModel.Item])] {
        var order: [String] = []
        var byGroup: [String: [CommandPaletteModel.Item]] = [:]
        for item in palette.results {
            if byGroup[item.group] == nil { order.append(item.group) }
            byGroup[item.group, default: []].append(item)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    private func row(_ item: CommandPaletteModel.Item) -> some View {
        let isChosen = item.id == palette.chosen?.id
        return Button {
            onRun(item.action)
        } label: {
            HStack(spacing: Design.Space.card) {
                if item.bundleID != nil || item.appPath != nil {
                    AppIcon(
                        bundleID: item.bundleID, appPath: item.appPath,
                        size: Design.Icon.listItem
                    )
                } else {
                    Image(systemName: item.symbol)
                        .foregroundStyle(.tint)
                        .frame(width: Design.Icon.listItem)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(Design.Text.body)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: Design.Space.inline)
            }
            .padding(.horizontal, Design.Space.section)
            .padding(.vertical, Design.Space.inline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(isChosen ? AnyShapeStyle(tint.opacity(Design.Colour.paletteHighlightOpacity)) : AnyShapeStyle(.clear))
                    .padding(.horizontal, Design.Space.snug)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }
}

/// The palette's group headings, spelled out so the key scanner can see them.
///
/// `Loc.t(group)` hands the scanner a variable, and this is the third time that has cost
/// something: "Go", "Actions", "Days" and "Applications" were absent from the catalogue
/// entirely, while "Display" and "Projects" were in it *by coincidence* — other files happen
/// to say `Loc.t("Display")`. A heading translated by luck is not translated.
///
/// The `default` is deliberate rather than exhaustive: `group` is a plain `String` on `Item`,
/// so the compiler cannot check this, and a new group should render in English rather than
/// crash. `translate.mjs` sees the literals either way.
func paletteGroupHeading(_ group: String) -> String {
    switch group {
    case "Go": Loc.t("Go")
    case "Display": Loc.t("Display")
    case "Actions": Loc.t("Actions")
    case "Days": Loc.t("Days")
    case "Applications": Loc.t("Applications")
    case "Projects": Loc.t("Projects")
    default: Loc.t(group)
    }
}
