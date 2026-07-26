import ReplayCore
import SwiftUI

/// A quiet walk through the best of your history.
///
/// Everything here was already in the database — the moments, the deepest stretches, the
/// sessions you marked, the lines you wrote. This is a room they are put in, not a thing
/// that was computed about you.
struct MuseumView: View {
    let museum: MuseumModel
    let annotations: AnnotationsModel
    let export: ExportModel
    let onOpenDay: (Int64) -> Void
    let onOpenProject: (String) -> Void
    let onDeleteSession: (ActivitySession) -> Void

    @Environment(\.motion) private var motion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if museum.loaded && museum.isEmpty {
                    empty.centredInPage()
                } else {
                    if let quote = museum.quote { featured(quote) }
                    if museum.moments.contains(where: { $0.key != museum.quote?.key }) {
                        milestones
                    }
                    if !museum.deepestFocus.isEmpty {
                        sessions("Your deepest focus", museum.deepestFocus)
                    }
                    if !museum.bookmarked.isEmpty {
                        sessions("The ones you kept", museum.bookmarked)
                    }
                    if !museum.reflections.isEmpty { reflections }
                    if !museum.topProjects.isEmpty { projects }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Museum")
        .navigationSubtitle("The parts of your history worth coming back to")
        .onAppear { museum.load() }
    }

    /// One moment given the room, chosen from the day itself so it is the same all day and
    /// different tomorrow.
    private func featured(_ moment: Moment) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(moment.title).cardLabelStyle()
            Text(moment.detail)
                .font(Design.Text.prose)
                .lineSpacing(Design.Text.proseLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: Design.Layout.readableWidth, alignment: .leading)
        .padding(Design.Space.page)
        .card(border: Design.Colour.border)
        .settlesIntoView(reduced: motion.reduced)
        .accessibilityElement(children: .combine)
    }

    private var milestones: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Milestones").sectionLabelStyle()
            VStack(spacing: Design.Space.snug) {
                // Without the featured moment: it is already above, in a larger frame, and
                // saying the same thing twice on one screen reads as a bug.
                ForEach(
                    museum.moments.filter { $0.key != museum.quote?.key }.prefix(4),
                    id: \.key
                ) { moment in
                    Button {
                        moment.dayStart.map(onOpenDay)
                    } label: {
                        HStack(spacing: Design.Space.card) {
                            Image(systemName: glyph(for: moment.kind))
                                .font(Design.Text.prose)
                                .foregroundStyle(.tint)
                                .frame(width: Design.Icon.glyphColumn)
                            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                                Text(moment.title).font(Design.Text.itemTitle)
                                Text(moment.detail)
                                    .font(Design.Text.detail)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Design.Space.inline)
                            if moment.dayStart != nil {
                                Image(systemName: "chevron.right")
                                    .font(Design.Text.micro)
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .padding(Design.Space.section)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(moment.dayStart == nil)
                    .card(border: Design.Colour.borderQuiet)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .settlesIntoView(reduced: motion.reduced)
    }

    private func sessions(_ title: String, _ list: [ActivitySession]) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(title).sectionLabelStyle()
            VStack(spacing: Design.Space.row) {
                ForEach(list, id: \.startedAt) { session in
                    SessionCard(
                        session: session,
                        annotations: annotations,
                        export: export,
                        onDelete: { onDeleteSession(session) }
                    )
                }
            }
        }
    }

    private var reflections: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("Things you wrote").sectionLabelStyle()
            VStack(spacing: Design.Space.snug) {
                ForEach(museum.reflections, id: \.dayStart) { reflection in
                    Button {
                        onOpenDay(reflection.dayStart)
                    } label: {
                        VStack(alignment: .leading, spacing: Design.Space.tight) {
                            Text(fullDayLabel(reflection.dayStart)).cardLabelStyle()
                            Text(reflection.text)
                                .font(Design.Text.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Design.Space.section)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .card(border: Design.Colour.borderQuiet)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens that day")
                }
            }
        }
        .settlesIntoView(reduced: motion.reduced)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("The work that took the most").sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(museum.topProjects) { named in
                    Button {
                        onOpenProject(named.id)
                    } label: {
                        HStack(spacing: Design.Space.card) {
                            HStack(spacing: Design.Space.iconOverlap) {
                                ForEach(named.project.apps.prefix(3), id: \.applicationName) { app in
                                    AppIcon(
                                        bundleID: app.bundleIdentifier,
                                        appPath: app.appPath,
                                        size: Design.Icon.inline
                                    )
                                    .background(Circle().fill(.background).padding(-Design.Layout.hairline))
                                }
                            }
                            Text(named.name).font(Design.Text.detail.weight(.medium)).lineLimit(1)
                            Spacer(minLength: Design.Space.inline)
                            Text(formatDurationShort(named.project.totalSeconds))
                                .font(Design.Text.detail)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(Design.Text.micro)
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal, Design.Space.snug)
                        .padding(.vertical, Design.Space.snug)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIntoView(reduced: motion.reduced)
    }

    private func glyph(for kind: Moment.Kind) -> String {
        switch kind {
        case .longestFocus: "target"
        case .peakDay: "flame"
        case .busyMix: "square.grid.3x3"
        case .nightOwl: "moon.stars"
        case .streak: "calendar"
        case .newApp: "sparkles"
        case .origin: "flag"
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label("The museum is still filling", systemImage: "building.columns")
        } description: {
            Text(
                "As you work, bookmark a session and jot a reflection, the most meaningful "
                    + "pieces of your history gather here."
            )
        }
    }
}
