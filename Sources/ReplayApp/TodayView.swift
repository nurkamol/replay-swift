import ReplayCore
import SwiftUI

/// Today: the day's headline, then the day itself.
///
/// It describes rather than grades — no targets, no red, no scolding a quiet day. The
/// figures are large because they are the point; everything else is quiet around them.
struct TodayView: View {
    @Environment(\.motion) private var motion
    let model: AppModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let memories: MemoriesModel
    let contextual: ContextualMemoryModel
    @Bindable var preferences: Preferences
    /// Given so the card can lead somewhere rather than just informing.
    let onOpenDay: (Int64) -> Void
    /// Watching a day is a whole-window thing, so the root is what raises it.
    let onReplayDay: ([ActivitySession]) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let summary = model.summary, summary.switches > 0 {
                    HeadlineCard(summary: summary)
                    // Only when one has been asked for. No goal means no card, not an
                    // invitation to set one — the app does not push a target on anybody.
                    if let goal = preferences.focusGoalMinutes {
                        FocusGoalCard(
                            progress: Goals.progress(
                                activeSeconds: summary.activeSeconds, goalMinutes: goal
                            ),
                            streak: Goals.streak(
                                summaries: model.recentSummaries,
                                todayStart: startOfLocalDay(model.now),
                                todayActiveSeconds: summary.activeSeconds,
                                goalMinutes: goal
                            ),
                            goalMinutes: goal,
                            onSetGoal: { preferences.focusGoalMinutes = $0 }
                        )
                    }
                    // First, because it is about the day before this one — and gone by
                    // lunchtime, when the day is underway and looking back is no longer
                    // what you came for.
                    if let briefing = contextual.briefing {
                        MorningBriefingCard(
                            briefing: briefing,
                            onOpenDay: onOpenDay,
                            onDismiss: { contextual.dismissBriefing() }
                        )
                    }
                    if let quote = contextual.quote {
                        QuoteLine(moment: quote, onOpen: {
                            if let day = quote.dayStart { onOpenDay(day) }
                        })
                    }
                    // Above everything it could interrupt, and absent far more often than
                    // present — most days Replay has nothing worth saying, and says nothing.
                    if let memory = contextual.memory {
                        ContextualMemoryCard(
                            memory: memory,
                            onOpen: {
                                if let day = memory.dayStart { onOpenDay(day) }
                            },
                            onDismiss: { contextual.dismiss(memory) },
                            onArchive: memory.archivable
                                ? { contextual.archive(memory) }
                                : nil
                        )
                    }
                    // Above the reflection: this is the one card that leads somewhere
                    // other than into the app, and burying it under a text field would
                    // make it a footnote to the day rather than an offer about it.
                    if let target = findResumeTarget(model.timeline, now: model.now) {
                        ResumeCard(target: target, now: model.now)
                    }
                    reflection
                    // The nearest one only, and only when there is one. Today is about
                    // today; a gallery of the past belongs on its own surface.
                    if let memory = memories.memories.first {
                        TodayInHistoryCard(
                            memory: memory,
                            onOpen: { onOpenDay(memory.range.dayStart) }
                        )
                    }
                    sessionList
                } else {
                    quietDay.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .toolbar {
            ToolbarItem {
                Button {
                    // Raised at the root rather than here: `fullScreenCover` is iOS-only,
                    // and an overlay inside this view would have the toolbar and the sidebar
                    // drawing on top of it — the same mistake the welcome screen made.
                    onReplayDay(
                        model.timeline.compactMap {
                            if case .session(let session) = $0 { return session } else { return nil }
                        }
                    )
                } label: {
                    Label("Replay Day", systemImage: "play.rectangle")
                }
                .disabled(model.timeline.isEmpty)
                .help("Watch today play back")
            }
        }
        .navigationTitle("Today")
        .navigationSubtitle(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .onAppear {
            if !memories.loaded { memories.load() }
            contextual.load()
        }
    }


    private var quietDay: some View {
        ContentUnavailableView {
            Label("A quiet day", systemImage: "moon.stars")
        } description: {
            Text("Nothing recorded yet. Your sessions will appear here as you work.")
        }
    }

    private var reflection: some View {
        ReflectionCard(
            dayStart: startOfLocalDay(model.now),
            reflection: model.reflection,
            prompt: "What do you want to remember about today?",
            onCommit: { model.setReflection($0) }
        )
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("\(model.sessions.count) \(model.sessions.count == 1 ? "session" : "sessions")")
                .font(Design.Text.sectionLabel)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(Design.Text.labelKerning)

            ForEach(Array(model.timeline.enumerated()), id: \.offset) { _, item in
                switch item {
                case .session(let session):
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        export: export,
                        onDelete: { model.deleteSession(session) }
                    )
                    .settlesIn(0)
                case .breakItem(let gap):
                    BreakRow(gap: gap)
                }
            }
        }
    }
}

/// The day in one glance: how long, across how much, and what dominated it.
private struct HeadlineCard: View {
    let summary: DaySummary
    @Environment(\.motion) private var motion
    /// The one display figure in the app, scaled by hand because no semantic style is
    /// anywhere near 46 points.
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize = Design.Text.heroSize

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.section) {
            VStack(alignment: .leading, spacing: 0) {
                Text(formatDurationShort(summary.activeSeconds))
                    .font(Design.Text.hero(heroSize))
                    .monospacedDigit()
                    // The day's total re-derives every thirty seconds. A number that
                    // replaces itself is a flicker; one that rolls is the same number,
                    // still counting.
                    .contentTransition(.numericText())
                    .animation(motion.animation(Design.Motion.settle), value: summary.activeSeconds)
                    .accessibilityLabel("\(formatDurationShort(summary.activeSeconds)) active today")
                Text("active")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Design.Space.statGap) {
                Stat(value: "\(summary.appsUsed)", label: "applications")
                Stat(value: "\(summary.sessionCount)", label: "sessions")
                if let focus = summary.focus {
                    Stat(
                        value: formatDurationShort(focus.averageStretchSeconds),
                        label: "\(focus.quality.rawValue) focus"
                    )
                }
                if let longest = summary.longestSession {
                    Stat(value: formatDurationShort(longest.activeSeconds), label: "longest focus")
                }
            }

            if let top = summary.mostUsed {
                HStack(spacing: Design.Space.row) {
                    AppIcon(bundleID: top.bundleIdentifier, appPath: top.appPath, size: Design.Icon.feature)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TOP APP")
                            .font(Design.Text.cardLabel)
                            .foregroundStyle(.tertiary)
                            .kerning(Design.Text.labelKerning)
                        Text(top.applicationName).font(Design.Text.figure)
                    }
                    Spacer()
                    Text(formatDurationShort(top.seconds))
                        .font(Design.Text.figure)
                        .monospacedDigit()
                }
                .padding(Design.Space.card)
                .background(Design.Colour.fill, in: RoundedRectangle(cornerRadius: Design.Radius.card))
            }
        }
        .padding(Design.Space.block)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The hour, behind the day's own figure. It shifts across the day, so the card is
        // quietly different at nine in the morning and at nine at night — the number is
        // describing a time, and this is that time. Held back to a fraction of its strength:
        // a full sky under a hero figure would be a poster.
        .background {
            RoundedRectangle(cornerRadius: Design.Radius.surface, style: .continuous)
                .fill(Design.Colour.surfaceRaised)
                .overlay {
                    Sky(at: now, strength: Design.Colour.skyOnCard)
                        .clipShape(RoundedRectangle(
                            cornerRadius: Design.Radius.surface, style: .continuous
                        ))
                }
        }
    }

    /// Re-read on every draw rather than held: the card already redraws every thirty seconds
    /// as the day's total moves, and the sky only has to keep up with that.
    private var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private struct Stat: View {
        let value: String
        let label: String
        var body: some View {
            HStack(spacing: Design.Space.snug) {
                Text(value).font(.callout.weight(.semibold)).monospacedDigit()
                Text(label).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// One run of work: its apps, its name, its length — expandable to the breakdown.
///
/// Shared by Today, the Timeline, and a reopened day: a session reads the same wherever it
/// is found, which is the whole point of building it from the same derivation.
struct SessionCard: View {
    let session: ActivitySession
    let annotations: AnnotationsModel
    let export: ExportModel
    let onDelete: () -> Void

    @State private var expanded = false
    @Environment(\.motion) private var motion

    private var annotation: SessionAnnotation { annotations.annotation(for: session.startedAt) }

    /// One sentence, because VoiceOver reads a card as a sentence rather than as the six
    /// fragments it is laid out from. Marks are named, since their meaning is carried by
    /// colour and shape on screen.
    private var accessibilityDescription: String {
        var parts = [
            session.title,
            formatRange(session.startedAt, session.endedAt),
            "\(formatDurationShort(session.activeSeconds)) active",
            "\(session.apps.count) \(session.apps.count == 1 ? "app" : "apps")",
        ]
        if annotation.bookmarked { parts.append("bookmarked") }
        if !annotation.tags.isEmpty {
            parts.append("tagged \(annotation.tags.joined(separator: ", "))")
        }
        if !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("has a note")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(motion.animation(Design.Motion.settle)) { expanded.toggle() }
            } label: {
                HStack(spacing: Design.Space.card) {
                    HStack(spacing: Design.Space.tight) {
                        ForEach(session.apps.prefix(4), id: \.applicationName) { app in
                            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.stack)
                        }
                        if session.apps.count > 4 {
                            Text("+\(session.apps.count - 4)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, Design.Pill.countHorizontal).padding(.vertical, Design.Pill.countVertical)
                                .background(Design.Colour.fillStrong, in: Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title).font(Design.Text.itemTitle)
                        Text("\(formatRange(session.startedAt, session.endedAt)) · \(session.apps.count) apps · \(session.switches) switches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AnnotationMarks(annotation: annotation)
                    Text(formatDurationShort(session.activeSeconds))
                        .font(Design.Text.figure)
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(Design.Space.card)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // A real focus ring, so Tab reaches the card and Return opens it. Without this
            // the whole surface was mouse-only: the cards were buttons the keyboard could
            // not get to.
            .focusable()
            .focusEffectDisabled(false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint(expanded ? "Collapses this session" : "Expands this session")
            .accessibilityAddTraits(.isButton)

            if expanded {
                Divider().padding(.horizontal, Design.Space.card)
                VStack(spacing: Design.Space.snug) {
                    ForEach(session.apps, id: \.applicationName) { app in
                        AppShareRow(app: app, maxSeconds: session.apps.first?.seconds ?? 1)
                    }
                }
                .padding(Design.Space.card)

                Divider().padding(.horizontal, Design.Space.card)
                AnnotationEditor(
                    sessionStart: session.startedAt,
                    annotation: annotation,
                    annotations: annotations
                )
                .padding(Design.Space.card)

                // Actions on the whole session, in their own row at the foot of the card —
                // the same shape as the Glaze app, and out of the way until wanted.
                HStack {
                    Spacer()
                    Menu {
                        Button(annotation.bookmarked ? "Remove Bookmark" : "Bookmark") {
                            annotations.setBookmarked(session.startedAt, !annotation.bookmarked)
                        }
                        Menu("Export Session") {
                            ForEach(Report.Format.allCases, id: \.self) { format in
                                Button(format.label) {
                                    // Named for the session, not the day it sits in: one
                                    // session's file should say which session.
                                    export.exportReport(
                                        format, label: session.title, sessions: [session]
                                    )
                                }
                            }
                        }
                        Menu("Share Session") {
                            ForEach(Report.Format.allCases, id: \.self) { format in
                                Button(format.label) {
                                    export.share(
                                        format,
                                        label: session.title,
                                        sessions: [session],
                                        from: NSApp.keyWindow?.contentView
                                    )
                                }
                            }
                        }
                        Divider()
                        Button("Delete Session…", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, Design.Space.card)
                .padding(.bottom, Design.Space.row)
            }
        }
        // A bookmarked session gently glows rather than shouting: the same card, warmed.
        .card(border: annotation.bookmarked ? Design.Colour.markedBorder : Design.Colour.border)
        // Escape closes what is open, consistently with every other transient thing on the
        // Mac. Only when something *is* open, so it does not swallow the key otherwise.
        .onExitCommand(perform: expanded ? { withAnimation(motion.animation(Design.Motion.settle)) { expanded = false } } : nil)
        // The same actions on right-click, because that is where a Mac user looks first
        // and a ⋯ that only appears once expanded is a menu you have to find.
        .contextMenu {
            Button(annotation.bookmarked ? "Remove Bookmark" : "Bookmark") {
                annotations.setBookmarked(session.startedAt, !annotation.bookmarked)
            }
            Divider()
            Menu("Export Session") {
                ForEach(Report.Format.allCases, id: \.self) { format in
                    Button(format.label) {
                        export.exportReport(format, label: session.title, sessions: [session])
                    }
                }
            }
            Menu("Share Session") {
                ForEach(Report.Format.allCases, id: \.self) { format in
                    Button(format.label) {
                        export.share(
                            format, label: session.title, sessions: [session],
                            from: NSApp.keyWindow?.contentView
                        )
                    }
                }
            }
            Divider()
            Button("Delete Session…", role: .destructive, action: onDelete)
        }
    }
}

private struct AppShareRow: View {
    let app: SessionApp
    let maxSeconds: Int

    var body: some View {
        HStack(spacing: Design.Space.row) {
            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.inline)
            Text(app.applicationName).font(.subheadline).frame(width: Design.Layout.appNameColumn, alignment: .leading)
            GeometryReader { geometry in
                let fraction = maxSeconds > 0 ? Double(app.seconds) / Double(maxSeconds) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Colour.fill).frame(height: Design.Layout.ringThickness)
                    Capsule().fill(.tint)
                        .frame(
                            width: geometry.size.width * fraction,
                            height: Design.Layout.ringThickness
                        )
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: Design.Layout.barRow)
            Text(formatDurationShort(app.seconds))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: Design.Layout.durationColumn, alignment: .trailing)
        }
        // The bar is a picture of the number beside it; announcing both would say the
        // same thing twice.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(app.applicationName), \(formatDurationShort(app.seconds))")
    }
}

/// A gap in the day, named for what it was — away, idle, or not recorded.
struct BreakRow: View {
    let gap: ActivityBreak

    /// The words come from `ReplayCore`, where the parity suite can reach them.
    private var described: BreakDescription { describeBreak(gap) }
    private var label: String { described.title }
    private var detail: String { described.detail }

    var body: some View {
        HStack(spacing: Design.Space.inline) {
            Rectangle().fill(.quaternary).frame(width: Design.Icon.inline, height: Design.Layout.hairline)
            Image(systemName: gap.reason == .unrecorded ? "circle.slash" : "moon.zzz")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            // The figure ("8m away") is the point and the explanation supports it, so the
            // explanation truncates rather than wrapping. Not `layoutPriority(-1)`, which
            // starved it to nothing at every width — a row that silently drops half its
            // meaning is worse than one that wraps.
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.vertical, Design.Space.hairline)
    }
}

/// A real macOS application icon.
///
/// Verified to work under App Sandbox with no entitlement — see docs/FINDINGS.md. Icons are
/// cached because the timeline asks for the same handful over and over.
struct AppIcon: View {
    let bundleID: String?
    let appPath: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = IconCache.shared.icon(bundleID: bundleID, appPath: appPath) {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(bundleID: String?, appPath: String?) -> NSImage? {
        let key = bundleID ?? appPath ?? ""
        guard !key.isEmpty else { return nil }
        if let hit = cache[key] { return hit }

        var path = appPath
        if path == nil, let bundleID {
            path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
        }
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[key] = image
        return image
    }
}

/// "Pick up where you left off" — the last piece of work you stepped away from.
///
/// Deliberately not the session you are in: while you are working, the newest session is
/// the one already on screen, and offering to resume it is noise.
///
/// What it claims is limited to what Replay actually knows. The app and the session, never
/// a document or a project it has no way to see — that would need permissions this app
/// does not ask for, and inventing the detail would be worse than omitting it.
struct ResumeCard: View {
    let target: ResumeTarget
    let now: Int64

    @Environment(\.motion) private var motion
    @State private var failure: String?

    var body: some View {
        HStack(spacing: Design.Space.section) {
            AppIcon(
                bundleID: target.app.bundleIdentifier,
                appPath: target.app.appPath,
                size: Design.Icon.resume
            )
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(target.isEarlierDay ? "Continue where you left off" : "Pick up where you left off")
                    .cardLabelStyle()
                Text(target.session.title)
                    .font(Design.Text.itemTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(Design.Text.detail)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Design.Space.inline)
            Button("Open \(target.app.applicationName)", action: open)
                .buttonStyle(.borderedProminent)
                // Nothing to open without a bundle identifier, and a button that cannot
                // work should say so by being unavailable rather than by failing.
                .disabled(target.app.bundleIdentifier == nil)
                .help(
                    target.app.bundleIdentifier == nil
                        ? "Replay doesn't know where \(target.app.applicationName) lives"
                        : "Brings \(target.app.applicationName) to the front"
                )
        }
        .padding(Design.Space.section)
        .card(border: Design.Colour.border)
        .accessibilityElement(children: .contain)
        .alert("Couldn't open \(target.app.applicationName)", isPresented: showingFailure) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var detail: String {
        "\(target.app.applicationName) · \(formatWhen(target.session.endedAt, now: now)) · "
            + formatDurationShort(target.session.activeSeconds)
    }

    private var showingFailure: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    /// Bring the app to the front.
    ///
    /// `NSWorkspace` needs no permission for this — it is the same thing Launchpad does.
    private func open() {
        guard let bundleID = target.app.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            failure = "It is not installed, or it has moved."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in failure = error.localizedDescription }
            }
        }
    }
}

/// The one memory Replay has decided is worth a word today.
///
/// Quiet by construction: a line, sometimes a second line, a way in and a way to make it go
/// away. No score is shown — the confidence is how the card earned its place, not something
/// the reader should have to weigh — and nothing here is a suggestion about what to do next.
struct ContextualMemoryCard: View {
    let memory: MemoryCandidate
    let onOpen: () -> Void
    let onDismiss: () -> Void
    /// Given only where putting something away for good makes sense.
    let onArchive: (() -> Void)?

    @Environment(\.motion) private var motion
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.card) {
            AppIcon(
                bundleID: memory.bundleID, appPath: memory.appPath, size: Design.Icon.feature
            )
            VStack(alignment: .leading, spacing: Design.Space.tight) {
                Text(label).cardLabelStyle()
                Text(memory.headline)
                    .font(Design.Text.prose)
                    .lineSpacing(Design.Text.proseLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = memory.detail {
                    Text(detail)
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Design.Space.inline)
            // Visible on hover: controls always on screen invite use, and the point of the
            // card is that it is worth reading rather than worth clearing.
            HStack(spacing: Design.Space.snug) {
                if let onArchive {
                    Button(action: onArchive) {
                        Image(systemName: "archivebox")
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Put this away for good")
                    .accessibilityLabel("Put this away for good")
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Not today")
                .accessibilityLabel("Put this memory away for now")
            }
            .opacity(hovering ? 1 : 0)
        }
        .padding(Design.Space.section)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if memory.dayStart != nil { onOpen() } }
        .onHover { hovering = $0 }
        .card(border: Design.Colour.markedBorder)
        .settlesIn(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label). \(memory.headline) \(memory.detail ?? "")")
        .accessibilityHint(memory.dayStart != nil ? "Opens that day" : "")
    }

    /// What kind of memory this is, in the app's own words rather than the type's name.
    private var label: String {
        switch memory.kind {
        case .rightTime: "Since last time"
        case .anniversary: "A year ago"
        case .forgotten: "You had kept this"
        case .echo: "This feels familiar"
        case .threadUpdate: "Picked back up"
        case .todayInHistory: "On this day"
        }
    }
}

/// A quiet look back at the day just gone.
///
/// Not a dashboard. Three lines at most, each one a fact about yesterday, and it is gone by
/// lunchtime — a greeting that is still there at four in the afternoon is a panel.
struct MorningBriefingCard: View {
    let briefing: MorningBriefing
    let onOpenDay: (Int64) -> Void
    let onDismiss: () -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.card) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(greeting).font(Design.Text.title)
                    Text("A quiet look back, before the day begins.")
                        .font(Design.Text.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Design.Space.inline)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(Design.Text.detail)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Put this away until tomorrow")
                .accessibilityLabel("Put the briefing away")
            }

            VStack(spacing: 0) {
                row(
                    "clock", "Yesterday",
                    "\(formatDurationShort(briefing.yesterdayActiveSeconds)) active"
                        + (briefing.yesterdayTopApp.map { ", mostly in \($0)" } ?? ""),
                    day: briefing.dayStart - dayMillis
                )
                if let longest = briefing.longestFocusSeconds {
                    Divider()
                    row(
                        "hourglass", "Longest focus",
                        "\(formatDurationShort(longest)) without switching away",
                        day: briefing.dayStart - dayMillis
                    )
                }
                if let project = briefing.continuedProject {
                    Divider()
                    row("arrow.triangle.branch", "Continue", project.name, day: nil)
                }
                if let monthAgo = briefing.monthAgo {
                    Divider()
                    row(
                        "clock.arrow.circlepath", "A month ago",
                        monthAgo.topApp.map { "Mostly \($0)" } ?? "Worth a look back",
                        day: monthAgo.dayStart
                    )
                }
            }
        }
        .padding(Design.Space.page)
        .card(border: Design.Colour.border)
        .settlesIn(2)
    }

    /// Named for the time of day, because that is what a greeting is for.
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 5 ? "Still up." : "Good morning."
    }

    private func row(_ glyph: String, _ label: String, _ detail: String, day: Int64?) -> some View {
        Button {
            if let day { onOpenDay(day) }
        } label: {
            HStack(spacing: Design.Space.card) {
                Image(systemName: glyph)
                    .font(Design.Text.detail)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.glyphColumn)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).cardLabelStyle()
                    Text(detail).font(Design.Text.itemTitle)
                }
                Spacer(minLength: Design.Space.inline)
            }
            .padding(.vertical, Design.Space.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
        .accessibilityElement(children: .combine)
    }
}

/// One moment, as a single line. The smallest way to say something worth remembering.
struct QuoteLine: View {
    let moment: Moment
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Space.card) {
                Image(systemName: "quote.opening")
                    .font(Design.Text.detail)
                    .foregroundStyle(.tint)
                Text(moment.detail)
                    .font(Design.Text.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(moment.dayStart == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(moment.detail)
    }
}
