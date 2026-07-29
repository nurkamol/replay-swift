import ReplayCore
import SwiftUI

/// My Story — the whole archive, at a glance.
///
/// How long this memory has been accumulating, the years it spans, what is in it, and the
/// applications that ran through all of it. Read from the durable daily headlines, which is
/// what makes it an archive rather than a view of the last month: the raw activity behind
/// most of these days was pruned long ago, and the headline is what outlives it.
struct LegacyView: View {
    let model: AppModel
    let story: StoryModel
    let projects: ProjectsModel
    let onOpenApp: (String) -> Void
    let onOpenAutobiography: () -> Void
    let onOpenDay: (Int64) -> Void

    @State private var legacy: Legacy?
    @State private var byDay: [Int64: Int] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let legacy {
                    headline(legacy)
                    tiles(legacy)
                    if !legacy.years.isEmpty { years(legacy) }
                    if !byDay.isEmpty { growth }
                    if !legacy.favourites.isEmpty { favourites(legacy) }
                    Text(Loc.t("Everything here was recorded on this Mac and has never left it."))
                        .font(Design.Text.detail)
                        .foregroundStyle(.tertiary)
                } else {
                    empty.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("My Story"))
        .navigationSubtitle(NarrativeCopy.legacySubtitle)
        .onAppear {
            if !story.loaded { story.load() }
            byDay = model.activityByDay()
            if !projects.loaded { projects.load() }
            legacy = story.legacy()
        }
    }

    private func headline(_ legacy: Legacy) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            Text(Loc.t("Your story so far")).cardLabelStyle()
            Text(
                "You have been building this memory since "
                    + "\(shortDateLabel(legacy.firstDay)) — \(legacy.activeDays) active "
                    + "\(legacy.activeDays == 1 ? "day" : "days"), and "
                    + "\(formatDurationShort(legacy.totalSeconds)) in all."
            )
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

    private func tiles(_ legacy: Legacy) -> some View {
        HStack(spacing: Design.Space.row) {
            tile("Active days", "\(legacy.activeDays)")
            tile(
                story.chapters.count == 1 ? "Chapter" : "Chapters",
                "\(story.chapters.count)"
            )
            tile(
                projects.projects.count == 1 ? "Project" : "Projects",
                "\(projects.projects.count)"
            )
            tile(
                "Last active",
                RuntimeCopy.relativeDayLabel(legacy.lastDay, now: Int64(Date().timeIntervalSince1970 * 1000))
            )
        }
        .settlesIn(1)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.tight) {
            Text(label).cardLabelStyle()
            Text(value).font(Design.Text.figure).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.card)
        .card(border: Design.Colour.borderQuiet)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: Loc.t("%@, %2$@"), "\(label), \(value)"))
    }

    private func years(_ legacy: Legacy) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(NarrativeCopy.legacySections[0]).sectionLabelStyle()
            FlowRow(spacing: Design.Space.inline) {
                ForEach(legacy.years, id: \.self) { year in
                    Button(action: onOpenAutobiography) {
                        // `String(year)` rather than interpolation: `Text` formats an `Int`
                        // with the locale's grouping separator, and 2026 came out as "2,026".
                        Text(String(year))
                            .font(Design.Text.detail.weight(.medium))
                            .monospacedDigit()
                            .padding(.horizontal, Design.Pill.horizontal)
                            .padding(.vertical, Design.Pill.vertical)
                            .background(Capsule().fill(Design.Colour.surface))
                            .overlay(Capsule().strokeBorder(Design.Colour.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Loc.t("Opens the autobiography"))
                }
            }
        }
        .settlesIn(2)
    }

    private func favourites(_ legacy: Legacy) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(NarrativeCopy.legacySections[2]).sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(legacy.favourites, id: \.key) { app in
                    Button {
                        // A key with no dot in it is a fallback name rather than a bundle
                        // identifier, and there is no history page to open for one.
                        if app.key.contains(".") { onOpenApp(app.key) }
                    } label: {
                        HStack(spacing: Design.Space.card) {
                            AppIcon(
                                bundleID: app.key.contains(".") ? app.key : nil,
                                appPath: app.appPath,
                                size: Design.Icon.stack
                            )
                            Text(app.applicationName).font(Design.Text.detail.weight(.medium))
                            Spacer(minLength: Design.Space.inline)
                            Text(Loc.count(app.days, "%@ day", "%@ days"))
                                .font(Design.Text.micro)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                            Text(formatDurationShort(app.seconds))
                                .font(Design.Text.detail)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: Design.Layout.durationColumn, alignment: .trailing)
                        }
                        .padding(.horizontal, Design.Space.snug)
                        .padding(.vertical, Design.Space.snug)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.row)
                    .disabled(!app.key.contains("."))
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIn(3)
    }

    /// The archive as a grid of days.
    ///
    /// The reference has had this here all along and this port did not — found by comparing
    /// its three section labels against our two. It belongs on this page more than anywhere
    /// else: My Story is the surface *about* how long the record is, and a year of squares
    /// says that in one look where a figure only asserts it.
    private var growth: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(NarrativeCopy.legacySections[1]).sectionLabelStyle()
            Heatmap(byDay: byDay, onOpenDay: onOpenDay)
                .padding(Design.Space.section)
                .card(border: Design.Colour.borderQuiet)
        }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(NarrativeCopy.legacyEmptyTitle, systemImage: "archivebox")
        } description: {
            Text(NarrativeCopy.legacyEmptyDetail)
        }
    }
}
