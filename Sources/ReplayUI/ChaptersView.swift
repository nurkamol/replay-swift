import ReplayCore
import SwiftUI

/// Your history divided into the eras it naturally fell into.
///
/// Read from the durable daily headlines rather than the rows, so chapters reach back across
/// *all* kept history — including days whose raw activity the retention window has already
/// taken away. That is what those headlines are kept for.
struct ChaptersView: View {
    let story: StoryModel
    let onOpen: (String) -> Void


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.row) {
                if story.chapters.isEmpty {
                    empty.centredInPage()
                } else {
                    ForEach(story.chapters) { chapter in
                        ChapterRow(named: chapter, onOpen: { onOpen(chapter.id) })
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("Chapters"))
        .navigationSubtitle(NarrativeCopy.chaptersSubtitle)
        .onAppear { if !story.loaded { story.load() } }
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(NarrativeCopy.chaptersEmptyTitle, systemImage: "book")
        } description: {
            // The reference's own, and it says the thing the paraphrase left out: how much
            // history is enough. "A few of those" is not an answer; "a week or two" is.
            Text(NarrativeCopy.chaptersEmptyDetail)
        }
    }
}

private struct ChapterRow: View {
    let named: StoryModel.NamedChapter
    let onOpen: () -> Void

    private var chapter: Chapter { named.chapter }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Space.card) {
                VStack(alignment: .leading, spacing: Design.Space.snug) {
                    Text(named.name).font(Design.Text.itemTitle).lineLimit(1)
                    Text(
                        "\(chapter.dayCount) \(chapter.dayCount == 1 ? "day" : "days") · "
                            + formatDurationShort(chapter.totalActiveSeconds)
                    )
                    .font(Design.Text.detail)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    HStack(spacing: Design.Space.snug) {
                        ForEach(chapter.apps.prefix(4), id: \.bundleIdentifier) { app in
                            AppIcon(
                                bundleID: app.bundleIdentifier,
                                appPath: app.appPath,
                                size: Design.Icon.inline
                            )
                        }
                        Text(chapter.apps.map(\.applicationName).joined(separator: ", "))
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.leading, Design.Space.tight)
                    }
                }
                Spacer(minLength: Design.Space.inline)
                VStack(alignment: .trailing, spacing: Design.Space.tight) {
                    Text(shortDateLabel(chapter.startDay))
                        .font(Design.Text.micro)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.right")
                        .font(Design.Text.micro)
                        .foregroundStyle(.quaternary)
                }
                .fixedSize()
            }
            .padding(Design.Space.section)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .focusable()
        .card(border: Design.Colour.border)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(named.name), \(chapter.dayCount) days, "
                + "\(formatDurationShort(chapter.totalActiveSeconds)), "
                + "from \(shortDateLabel(chapter.startDay)) to \(shortDateLabel(chapter.endDay))"
        )
        .accessibilityHint(Loc.t("Opens this chapter"))
    }
}

/// One chapter: what it held, which applications led it, and every day in it.
struct ChapterDetailView: View {
    let id: String
    let story: StoryModel
    let onOpenDay: (Int64) -> Void

    @State private var renaming = false
    @State private var draft = ""

    private var named: StoryModel.NamedChapter? { story.chapter(id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let named {
                    header(named)
                    tiles(named.chapter)
                    apps(named.chapter)
                    days(named.chapter)
                } else {
                    missing.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(named?.name ?? "Chapter")
        .onAppear { if !story.loaded { story.load() } }
        .alert(Loc.t("Rename chapter"), isPresented: $renaming) {
            TextField(named.map { chapterDefaultName($0.chapter) } ?? "", text: $draft)
            Button(Loc.t("Save")) { story.rename(chapter: id, to: draft) }
            Button(Loc.t("Cancel"), role: .cancel) {}
        } message: {
            Text(Loc.t("Leave it empty to go back to the name Replay chose."))
        }
    }

    private func header(_ named: StoryModel.NamedChapter) -> some View {
        HStack(spacing: Design.Space.card) {
            VStack(alignment: .leading, spacing: Design.Space.hairline) {
                Text(named.name).font(Design.Text.title).lineLimit(2)
                Text(
                    "\(shortDateLabel(named.chapter.startDay)) – "
                        + shortDateLabel(named.chapter.endDay)
                )
                .font(Design.Text.body)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: Design.Space.inline)
            Button(Loc.t("Rename…")) {
                draft = named.named ? named.name : ""
                renaming = true
            }
        }
        .settlesIn(0)
    }

    private func tiles(_ chapter: Chapter) -> some View {
        HStack(spacing: Design.Space.row) {
            tile(chapter.dayCount == 1 ? "Active day" : "Active days", "\(chapter.dayCount)")
            tile("Total", formatDurationShort(chapter.totalActiveSeconds))
            tile("Character", Collections.label(for: chapter.category))
            tile("Fullest day", shortDateLabel(chapter.representativeDay))
        }
        .settlesIn(1)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.tight) {
            Text(Loc.t(label)).cardLabelStyle()
            Text(value).font(Design.Text.figure).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.card)
        .card(border: Design.Colour.borderQuiet)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: Loc.t("%1$@, %2$@"), Loc.t(label), value))
    }

    private func apps(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("What led its days")).sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(chapter.apps, id: \.bundleIdentifier) { app in
                    HStack(spacing: Design.Space.card) {
                        AppIcon(
                            bundleID: app.bundleIdentifier,
                            appPath: app.appPath,
                            size: Design.Icon.stack
                        )
                        Text(app.applicationName).font(Design.Text.detail.weight(.medium))
                        Spacer(minLength: Design.Space.inline)
                        Text(Loc.count(app.days, "%@ day", "%@ days"))
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                        Text(formatDurationShort(app.activeSeconds))
                            .font(Design.Text.detail)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: Design.Layout.durationColumn, alignment: .trailing)
                    }
                    .padding(.horizontal, Design.Space.snug)
                    .padding(.vertical, Design.Space.snug)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIn(2)
    }

    private func days(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(chapter.days.count == 1 ? "1 day" : "\(chapter.days.count) days")
                .sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(chapter.days, id: \.self) { day in
                    Button {
                        onOpenDay(day)
                    } label: {
                        HStack(spacing: Design.Space.card) {
                            Text(fullDayLabel(day)).font(Design.Text.detail)
                            Spacer(minLength: Design.Space.inline)
                            if day == chapter.representativeDay {
                                Text(Loc.t("Fullest"))
                                    .font(Design.Text.micro)
                                    .foregroundStyle(.tint)
                            }
                            Image(systemName: "chevron.right")
                                .font(Design.Text.micro)
                                .foregroundStyle(.quaternary)
                        }
                        .padding(.horizontal, Design.Space.snug)
                        .padding(.vertical, Design.Space.inline)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.row)
                    .accessibilityHint(Loc.t("Opens this day"))
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
    }

    private var missing: some View {
        ContentUnavailableView {
            Label(Loc.t("Chapter not found"), systemImage: "book")
        } description: {
            Text(Loc.t("A chapter exists only while the days beneath it do."))
        }
    }
}
