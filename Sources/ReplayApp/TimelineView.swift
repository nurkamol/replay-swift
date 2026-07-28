import ReplayCore
import SwiftUI

/// The Timeline: your recent days, newest first.
///
/// Today answers "what has today been". The Timeline is the archive — the same sessions,
/// grouped by the day they began, with the quiet gaps left in so the shape of a day is
/// legible. It describes; it does not grade. A day with nothing on it simply is not there.
/// A lens on the same days.
///
/// Two kinds. **Sessions**, **Projects**, **Collections**, **Bookmarks** and **Notes** choose
/// *which* sessions appear — a session shows if any active one keeps it — and **Activity** is
/// the gaps between them, which the plain timeline shows and any narrowing hides.
///
/// **Reflections**, **Moments** and **Memories** do the opposite: they add rows among the
/// days, and each keeps a day on screen even when every session in it has been filtered
/// away. A day you only wrote about is still a day worth seeing.
enum Layer: String, CaseIterable, Hashable {
    case sessions, projects, collections, bookmarks, notes, activity
    case reflections, moments, memories

    var label: String {
        switch self {
        case .sessions: "Sessions"
        case .projects: "Projects"
        case .collections: "Collections"
        case .bookmarks: "Bookmarks"
        case .notes: "Notes"
        case .activity: "Activity"
        case .reflections: "Reflections"
        case .moments: "Moments"
        case .memories: "Memories"
        }
    }

    /// Whether this one *adds* rows rather than choosing which sessions appear.
    var isOverlay: Bool {
        switch self {
        case .reflections, .moments, .memories: true
        default: false
        }
    }
}

struct TimelineView: View {
    let history: HistoryModel
    let overlays: TimelineLayersModel
    let annotations: AnnotationsModel
    let export: ExportModel
    /// Given so a day can be opened from its ⋯ menu.
    let onOpenDay: (Int64) -> Void
    /// Given so a past day can be watched back, the same way today can.
    let onReplayDay: ([ActivitySession], String) -> Void

    /// Which coarse buckets are showing. Empty means all of them — a filter row where
    /// everything starts switched on reads as a set of things to switch *off*, and this one
    /// is a set of things to narrow *to*.
    @State private var categories: Set<FilterCategory> = []
    /// Which layers are on. Sessions alone by default, which is the plain timeline.
    @State private var layers: Set<Layer> = [.sessions]

    var body: some View {
        ScrollView {
            // Lazy, and it has to be. A `VStack` inside a `ScrollView` builds every child
            // up front, so opening the Timeline on Last 7 Days constructed all ~280 rows —
            // every session card, its icons, its annotations — before a single one was on
            // screen. That is where the wait came from: the data is not the cost (fetching
            // and deriving seven days measures about 22ms), the eager layout of the rows is.
            //
            // `LazyVStack` builds what is near the viewport and the rest as it is scrolled
            // to, so the cost stops scaling with the range and starts scaling with the
            // window — which is the only thing a person is actually looking at.
            LazyVStack(alignment: .leading, spacing: Design.Space.block) {
                controls
                if filtered.isEmpty {
                    // Two different silences: a range with nothing in it, and a range whose
                    // contents the chips have hidden. Saying "no history yet" to someone who
                    // has just filtered it all out would be a lie.
                    if history.days.isEmpty {
                        empty.centredInPage()
                    } else {
                        narrowed.centredInPage()
                    }
                } else {
                    ForEach(filtered) { day in
                        VStack(alignment: .leading, spacing: Design.Space.row) {
                            DaySection(
                                day: day,
                                history: history,
                                annotations: annotations,
                                export: export,
                                onOpenDay: onOpenDay,
                                onReplayDay: onReplayDay
                            )
                            overlayRows(for: day.dayStart)
                        }
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Timeline")
        .navigationSubtitle(history.range.subtitle)
        .onAppear { if !overlays.loaded { overlays.load() } }
        .toolbar {
            // The range belongs in the chrome rather than the content: it governs the whole
            // surface, and a control that scrolls away with what it controls is a control
            // you have to go looking for.
            ToolbarItem(placement: .principal) {
                Picker("Range", selection: Binding(
                    get: { history.range },
                    set: { history.range = $0 }
                )) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("How much history the Timeline shows")
            }
        }
    }

    /// The two rows of chips: what kind of work, and which layers.
    private var controls: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            FlowRow(spacing: Design.Space.snug) {
                ForEach(FilterCategory.allCases, id: \.self) { category in
                    chip(
                        category.rawValue,
                        on: categories.contains(category),
                        toggle: {
                            if categories.contains(category) {
                                categories.remove(category)
                            } else {
                                categories.insert(category)
                            }
                        }
                    )
                }
            }
            HStack(alignment: .top, spacing: Design.Space.inline) {
                Label("Layers", systemImage: "square.3.layers.3d")
                    .labelStyle(.titleAndIcon)
                    .sectionLabelStyle()
                    .padding(.top, Design.Space.snug)
                FlowRow(spacing: Design.Space.snug) {
                    ForEach(Layer.allCases, id: \.self) { layer in
                        chip(
                            layer.label,
                            on: layers.contains(layer),
                            toggle: {
                                if layers.contains(layer) {
                                    // Never nothing: a timeline with every layer off is a
                                    // blank page, and the way to see less is a filter.
                                    if layers.count > 1 { layers.remove(layer) }
                                } else {
                                    layers.insert(layer)
                                }
                            }
                        )
                    }
                }
            }
        }
        .settlesIn(0)
    }

    private func chip(_ label: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Text(label)
                .font(Design.Text.detail.weight(.medium))
                .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .padding(.horizontal, Design.Pill.horizontal)
                .padding(.vertical, Design.Pill.vertical)
                .background(
                    Capsule().fill(on ? AnyShapeStyle(.tint) : Design.Colour.surface)
                )
                .overlay(Capsule().strokeBorder(on ? AnyShapeStyle(.clear) : Design.Colour.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// The days as the chips leave them.
    ///
    /// A day whose sessions are all filtered out disappears entirely rather than remaining
    /// as an empty heading — an empty day under a filter says "nothing here", which is what
    /// the absence of the day already says.
    private var filtered: [TimelineDay] {
        guard !categories.isEmpty || layers != [.sessions] else { return history.days }
        return history.days.compactMap { day in
            let items = day.items.filter { item in
                guard case .session(let session) = item else {
                    // Any narrowing hides the breaks too: a gap between two sessions you are
                    // no longer looking at describes a rhythm that is not on screen.
                    return categories.isEmpty && layers.contains(.activity)
                }
                if !categories.isEmpty,
                   !categories.contains(sessionFilterCategory(session)) { return false }
                return keeps(session)
            }
            // An overlay keeps a day even when its sessions are all gone: a day you only
            // wrote about, or that only echoes an earlier year, is still worth showing.
            guard !items.isEmpty || hasOverlay(day.dayStart) else { return nil }
            var narrowed = day
            narrowed.items = items
            return narrowed
        }
    }

    /// The rows the overlay layers add to a day.
    @ViewBuilder
    private func overlayRows(for day: Int64) -> some View {
        VStack(spacing: Design.Space.snug) {
            if layers.contains(.reflections), let text = overlays.reflections[day] {
                overlayRow("quote.opening", "Reflection", text, day: day)
            }
            if layers.contains(.moments) {
                ForEach(overlays.moments[day] ?? [], id: \.key) { moment in
                    overlayRow("sparkles", moment.title, moment.detail, day: day)
                }
            }
            if layers.contains(.memories), let earlier = overlays.earlierYears[day] {
                overlayRow(
                    "clock.arrow.circlepath", "On this date before",
                    "\(fullDayLabel(earlier.dayStart))"
                        + (earlier.topApp.map { " · mostly \($0)" } ?? ""),
                    day: earlier.dayStart
                )
            }
        }
    }

    private func overlayRow(
        _ glyph: String, _ label: String, _ detail: String, day: Int64
    ) -> some View {
        Button {
            onOpenDay(day)
        } label: {
            HStack(alignment: .top, spacing: Design.Space.card) {
                Image(systemName: glyph)
                    .font(Design.Text.detail)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.glyphColumn)
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(label).cardLabelStyle()
                    Text(detail)
                        .font(Design.Text.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Design.Space.inline)
            }
            .padding(Design.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .card(border: Design.Colour.borderQuiet)
        .accessibilityElement(children: .combine)
    }

    /// Whether any day has something for the active overlay layers to show.
    private func hasOverlay(_ day: Int64) -> Bool {
        (layers.contains(.reflections) && overlays.reflections[day] != nil)
            || (layers.contains(.moments) && !(overlays.moments[day] ?? []).isEmpty)
            || (layers.contains(.memories) && overlays.earlierYears[day] != nil)
    }

    /// Whether any active selection layer keeps this session.
    private func keeps(_ session: ActivitySession) -> Bool {
        var wanted = false
        for layer in layers {
            switch layer {
            case .sessions: wanted = true
            case .bookmarks:
                if annotations.annotation(for: session.startedAt).bookmarked { wanted = true }
            case .notes:
                if !annotations.annotation(for: session.startedAt).note.isEmpty { wanted = true }
            case .collections:
                if Collections.isCollectable(session.category) { wanted = true }
            case .projects:
                if overlays.projectSessions.contains(session.startedAt) { wanted = true }
            // These add rows rather than choosing sessions, so they keep none by themselves.
            case .activity, .reflections, .moments, .memories:
                break
            }
        }
        return wanted
    }

    private var narrowed: some View {
        ContentUnavailableView {
            Label("Nothing matches", systemImage: "line.3.horizontal.decrease")
        } description: {
            Text("No session in this range is in the kinds of work, or the layers, you chose.")
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(
                history.range == .today ? "A quiet day" : "No history yet",
                systemImage: "calendar.day.timeline.left"
            )
        } description: {
            Text(emptyDetail)
        }
    }

    private var emptyDetail: String {
        switch history.range {
        case .today: "Nothing recorded yet today — your sessions will appear here as you work."
        case .yesterday: "Replay didn't record anything yesterday."
        case .week, .month:
            "Replay keeps your recent history. Your first sessions will appear here as you work."
        }
    }
}

/// One day in the Timeline: its divider, its actions, and everything that happened on it.
private struct DaySection: View {
    let day: TimelineDay
    let history: HistoryModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onOpenDay: (Int64) -> Void
    let onReplayDay: ([ActivitySession], String) -> Void

    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            header

            ForEach(Array(day.items.enumerated()), id: \.offset) { index, item in
                // A quiet rule where the day turns over. Not per-hour: sessions routinely
                // span two or three hours, so an hour rule between every pair would
                // out-number the sessions it was meant to organise.
                if let part = partBreak(at: index) {
                    PartDivider(part: part).settlesIn(1)
                }
                switch item {
                case .session(let session):
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        export: export,
                        onDelete: { history.deleteSession(session) }
                    )
                    .settlesIn(1)
                case .breakItem(let gap):
                    // Everything in the day arrives together. The cards used to settle in
                    // while the breaks and the day-part labels between them were simply
                    // already there, which read as the list arriving around them.
                    BreakRow(gap: gap).settlesIn(1)
                }
            }
        }
        .confirmationDialog(
            "Delete \(day.label)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Day", role: .destructive) { history.deleteDay(day.dayStart) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Deleting \(day.label) permanently removes its sessions, its summary, and any "
                    + "notes or bookmarks on it. Every other day is left untouched, and this "
                    + "can't be undone."
            )
        }
    }

    private var header: some View {
        HStack(spacing: Design.Space.row) {
            Text(day.label)
                .font(Design.Text.sectionLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(Design.Text.labelKerning)
                .fixedSize()

            Rectangle().fill(.quaternary).frame(height: 1)

            Text(formatDurationShort(day.activeSeconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .fixedSize()

            // Gathered behind one button rather than sitting inline: a permanent destructive
            // control beside every day is easy to hit by accident, and noisy for something
            // rarely wanted.
            Menu {
                Button("Open This Day") { onOpenDay(day.dayStart) }
                Button("Replay This Day") {
                    onReplayDay(day.sessions, day.label)
                }
                .disabled(day.sessions.isEmpty)
                Menu("Export This Day") {
                    ForEach(Report.Format.allCases, id: \.self) { format in
                        Button(format.label) {
                            // Named by its date, not by "Today": a file called "Replay
                            // Today" stops being true tomorrow.
                            export.exportReport(
                                format, label: fullDayLabel(day.dayStart), sessions: day.sessions
                            )
                        }
                    }
                }
                Divider()
                Button("Delete This Day…", role: .destructive) { confirmingDelete = true }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    /// The day-part label to draw above this item, or `nil` when it is still the same part
    /// as the item before it.
    private func partBreak(at index: Int) -> String? {
        let part = dayPart(of: startedAt(day.items[index]))
        guard index > 0 else { return part }
        return dayPart(of: startedAt(day.items[index - 1])) == part ? nil : part
    }

    private func startedAt(_ item: TimelineItem) -> Int64 {
        switch item {
        case .session(let session): session.startedAt
        case .breakItem(let gap): gap.startedAt
        }
    }
}

private struct PartDivider: View {
    let part: String

    var body: some View {
        HStack(spacing: Design.Space.inline) {
            Text(part)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .kerning(Design.Text.tightKerning)
            Rectangle().fill(Design.Colour.divider).frame(height: 1)
        }
        .padding(.top, Design.Space.tight)
    }
}

/// One day from the past, reopened.
///
/// The same sessions the Timeline builds, for a single fixed day. When the rows are gone —
/// pruned past the retention window — it says so plainly rather than pretending the day was
/// empty, because the day's headline is still there to prove otherwise.
struct DayView: View {
    let day: TimelineDay
    let headline: DailySummary?
    let reflection: Reflection
    let annotations: AnnotationsModel
    let export: ExportModel
    let onReflect: (String) -> Void
    let onDeleteSession: (ActivitySession) -> Void
    let onReplayDay: ([ActivitySession], String) -> Void
    /// Where this day sits in the long view, once it is old enough to have a place in one.
    let context: ChapterContext?
    /// Resolved by the caller, which is where the chosen names live.
    let chapterName: String
    let onOpenChapter: (String) -> Void
    let onOpenDay: (Int64) -> Void

    private var story: [String] { DayStory.build(day.sessions) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                header

                // The day in a few sentences, when it can support them. A thin day gets
                // none rather than a padded one — see DayStory.
                if !story.isEmpty {
                    VStack(alignment: .leading, spacing: Design.Space.snug) {
                        Text("The story of this day")
                            .font(Design.Text.cardLabel)
                            .foregroundStyle(.tertiary)
                            .kerning(Design.Text.labelKerning)
                            .textCase(.uppercase)
                        Text(story.joined(separator: " "))
                            .font(Design.Text.prose)
                            .lineSpacing(Design.Text.proseLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                            .proseColumn()
                    }
                    .padding(Design.Space.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Design.Colour.surface, in: RoundedRectangle(cornerRadius: Design.Radius.card))
                }

                if let context { chapterCard(context) }

                // Offered even on a day whose rows were pruned: what you wrote about a day
                // outlives the activity behind it, and is often the only thing left.
                ReflectionCard(
                    dayStart: day.dayStart,
                    reflection: reflection,
                    prompt: "What do you want to remember about this day?",
                    onCommit: onReflect
                )

                if day.items.isEmpty {
                    pruned
                } else {
                    VStack(alignment: .leading, spacing: Design.Space.row) {
                        HStack {
                            Text("\(day.sessions.count) \(day.sessions.count == 1 ? "session" : "sessions")")
                                .font(Design.Text.sectionLabel)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .kerning(Design.Text.labelKerning)
                            Spacer()
                            Menu("Export…") {
                                ForEach(Report.Format.allCases, id: \.self) { format in
                                    Button(format.label) {
                                        export.exportReport(
                                            format,
                                            label: fullDayLabel(day.dayStart),
                                            sessions: day.sessions
                                        )
                                    }
                                }
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .fixedSize()
                        }

                        ForEach(Array(day.items.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .session(let session):
                                SessionCard(
                                    session: session,
                                    annotations: annotations,
                                    export: export,
                                    onDelete: { onDeleteSession(session) }
                                )
                                .settlesIn(2)
                            case .breakItem(let gap):
                                BreakRow(gap: gap).settlesIn(2)
                            }
                        }
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(fullDayLabel(day.dayStart))
        .navigationSubtitle(
            day.items.isEmpty ? "" : "\(formatDurationShort(day.activeSeconds)) active"
        )
        .toolbar {
            if !day.sessions.isEmpty {
                // The same offer Today makes, on a day that has already happened. Watching
                // a day back is the point of the app; there was no reason it only worked on
                // the one day you had already lived through.
                ToolbarItem {
                    Button {
                        onReplayDay(day.sessions, day.label)
                    } label: {
                        Label("Replay Day", systemImage: "play.rectangle")
                    }
                    .help("Watch this day play back")
                }
                ToolbarItem {
                    Menu {
                        ForEach(Report.Format.allCases, id: \.self) { format in
                            Button(format.label) {
                                export.exportReport(
                                    format,
                                    label: fullDayLabel(day.dayStart),
                                    sessions: day.sessions
                                )
                            }
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export this day")
                }
            }
        }
    }

    /// No back button of its own: the navigation stack draws one, and ⌘[ works because it
    /// is the system's rather than a `Button` that happens to look like it.
    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Space.hairline) {
            Text(fullDayLabel(day.dayStart))
                .font(Design.Text.title)
            if !day.items.isEmpty {
                Text("\(formatDurationShort(day.activeSeconds)) active")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The chapter this day belonged to, and the days either side of it.
    ///
    /// Only past a week old. A day still inside the chapter it is part of has no distance to
    /// be seen from, and being told which era you are currently living through is not
    /// context — it is the app narrating your Tuesday back at you.
    private func chapterCard(_ context: ChapterContext) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.card) {
            Button {
                onOpenChapter(context.chapter.id)
            } label: {
                HStack(spacing: Design.Space.row) {
                    Image(systemName: "book.closed")
                        .font(Design.Text.prose)
                        .foregroundStyle(.tint)
                        .frame(width: Design.Icon.listItem)
                    VStack(alignment: .leading, spacing: Design.Space.hairline) {
                        Text("Part of the chapter").cardLabelStyle()
                        Text(chapterName)
                            .font(Design.Text.itemTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: Design.Space.inline)
                    Image(systemName: "chevron.right")
                        .font(Design.Text.micro)
                        .foregroundStyle(.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.row)

            if !context.nearbyDays.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: Design.Space.snug) {
                    Text("Around this time").cardLabelStyle()
                    FlowRow(spacing: Design.Space.snug) {
                        ForEach(context.nearbyDays, id: \.self) { day in
                            Button { onOpenDay(day) } label: {
                                Text(dayChipLabel(day))
                                    .font(Design.Text.detail)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, Design.Pill.leadingRoomy)
                                    .padding(.vertical, Design.Pill.countVertical)
                                    .background(Design.Colour.surfaceQuiet, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Design.Colour.borderQuiet))
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens that day")
                        }
                    }
                }
            }
        }
        .padding(Design.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Design.Colour.borderQuiet)
        .settlesIn(1)
    }

    private var pruned: some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text("No timeline for this day")
                .font(.headline)
            Text(prunedDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Design.Space.emptyStateRoomy)
    }

    /// The headline is what survives pruning, so when there is one the day was not empty —
    /// it is simply older than the kept history, and saying "nothing happened" would be a lie.
    private var prunedDetail: String {
        if let headline, headline.activeSeconds > 0 {
            let top = headline.topAppName.map { " Most of it was \($0)." } ?? ""
            return "This day is older than your kept history. Its summary survives: "
                + "\(formatDurationShort(headline.activeSeconds)) active.\(top)"
        }
        return "Either nothing was recorded, or this day is older than your kept history."
    }
}
