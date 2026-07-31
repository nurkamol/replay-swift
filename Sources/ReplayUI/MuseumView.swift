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
                        sessions(Loc.t(NarrativeCopy.museumSections[1]), museum.deepestFocus).settlesIn(2)
                    }
                    if !museum.bookmarked.isEmpty {
                        sessions(Loc.t(NarrativeCopy.museumSections[2]), museum.bookmarked).settlesIn(3)
                    }
                    if !museum.reflections.isEmpty { reflections }
                    if !museum.topProjects.isEmpty { projects }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("Museum"))
        .navigationSubtitle(Loc.t(NarrativeCopy.museumSubtitle))
        .onAppear { museum.load() }
    }

    /// One moment given the room, chosen from the day itself so it is the same all day and
    /// different tomorrow.
    private func featured(_ moment: Moment) -> some View {
        // Said in the reader's language, like Memories. `moment.title`/`.detail` are the
        // English contract; reading them directly left the Museum in English after Memories
        // had been translated — the same bug, on a third surface.
        let said = RuntimeCopy.moment(moment, now: Int64(Date().timeIntervalSince1970 * 1000))
        return VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(said.title).cardLabelStyle()
            Text(said.detail)
                .font(Design.Text.prose)
                .lineSpacing(Design.Text.proseLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: Design.Layout.readableWidth, alignment: .leading)
        .padding(Design.Space.page)
        .card(border: Design.Colour.border)
        .settlesIn(0)
        .accessibilityElement(children: .combine)
    }

    private var milestones: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t(NarrativeCopy.museumSections[0])).sectionLabelStyle()
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
                                let said = RuntimeCopy.moment(
                                    moment, now: Int64(Date().timeIntervalSince1970 * 1000)
                                )
                                Text(said.title).font(Design.Text.itemTitle)
                                Text(said.detail)
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
                    .buttonStyle(.row)
                    .disabled(moment.dayStart == nil)
                    .card(border: Design.Colour.borderQuiet)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .settlesIn(1)
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
            Text(Loc.t(NarrativeCopy.museumSections[3])).sectionLabelStyle()
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
                    .buttonStyle(.row)
                    .card(border: Design.Colour.borderQuiet)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Loc.t("Opens that day"))
                }
            }
        }
        .settlesIn(4)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t(NarrativeCopy.museumSections[4])).sectionLabelStyle()
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
                    .buttonStyle(.row)
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIn(5)
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
            Label(Loc.t(NarrativeCopy.museumEmptyTitle), systemImage: "building.columns")
        } description: {
            Text(Loc.t(NarrativeCopy.museumEmptyDetail))
        }
    }
}
