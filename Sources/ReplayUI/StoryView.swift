import ReplayCore
import SwiftUI

/// Story — the long view of your work.
///
/// A hub rather than a screen of its own content: the narrative surfaces each need room, and
/// putting them behind one door keeps the sidebar from becoming a list of everything. The
/// rituals sit here because they are the shortest of them and the one that answers "what am
/// I actually like" in a sentence.
struct StoryView: View {
    let story: StoryModel
    let onOpen: (Navigation.StoryTarget) -> Void


    private let columns = [
        GridItem(.adaptive(minimum: Design.Layout.cardMinWidth), spacing: Design.Space.row)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                // Across the full width: it is the whole archive, and the other two are
                // ways into parts of it.
                // Titles and descriptions are the reference's own and contract-checked;
                // only the glyph and the destination belong to this port.
                hub(0, "archivebox", .legacy).settlesIn(0)

                LazyVGrid(columns: columns, spacing: Design.Space.row) {
                    hub(1, "text.book.closed", .autobiography).settlesIn(1)
                    hub(2, "book", .chapters).settlesIn(2)
                    hub(3, "building.columns", .museum).settlesIn(3)
                }

                rituals
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t(NarrativeCopy.storyTitle))
        .navigationSubtitle(Loc.t(NarrativeCopy.storySubtitle))
        .onAppear { story.load() }
    }

    private func hub(
        _ index: Int, _ glyph: String, _ target: Navigation.StoryTarget
    ) -> some View {
        let title = Loc.t(NarrativeCopy.storyHub[index].title)
        let detail = Loc.t(NarrativeCopy.storyHub[index].detail)
        return Button {
            onOpen(target)
        } label: {
            HStack(alignment: .top, spacing: Design.Space.card) {
                Image(systemName: glyph)
                    .font(Design.Text.prose)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.glyphColumn)
                VStack(alignment: .leading, spacing: Design.Space.tight) {
                    Text(title).font(Design.Text.itemTitle)
                    Text(detail)
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Design.Space.inline)
                Image(systemName: "chevron.right")
                    .font(Design.Text.micro)
                    .foregroundStyle(.quaternary)
            }
            .padding(Design.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .focusable()
        .card(border: Design.Colour.border)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(format: Loc.t("Opens %@"), "\(title)"))
    }

    /// The shape the days tend to take.
    ///
    /// Described, never prescribed: "you tend to start here" is an observation, and there is
    /// deliberately no suggestion attached to it (SPEC §8).
    private var rituals: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t(NarrativeCopy.ritualsLabel)).sectionLabelStyle()
            if story.rituals.slots.isEmpty && story.rituals.firstApp == nil {
                // The section stays and explains itself rather than vanishing. Omitting it
                // was the same mistake Memories made: the only person who ever sees this
                // state is someone new, and they were shown three hub cards and no hint
                // that a fourth thing was coming.
                VStack(spacing: Design.Space.hairline) {
                    Text(Loc.t(NarrativeCopy.ritualsEmptyTitle)).font(Design.Text.itemTitle)
                    Text(Loc.t(NarrativeCopy.ritualsEmptyDetail))
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Design.Space.cardRoomy)
                .frame(maxWidth: .infinity)
                .card(border: Design.Colour.borderQuiet)
            } else {
                VStack(spacing: 0) {
                    if let first = story.rituals.firstApp {
                        ritual("sunrise", Loc.t("You usually begin with"), first)
                    }
                    ForEach(story.rituals.slots, id: \.part) { slot in
                        ritual(glyph(for: slot.part), RuntimeCopy.ritualLead(part: slot.part), slot.app)
                    }
                }
                .padding(Design.Space.snug)
                .card(border: Design.Colour.borderQuiet)

                // The rule, said out loud. Without it a ritual reads as something the app
                // decided, and the last clause is the whole point: nothing was scheduled.
                Text(Loc.t(NarrativeCopy.ritualsFootnote))
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .settlesIn(4)
    }

    private func ritual(_ glyph: String, _ label: String, _ app: Rituals.App) -> some View {
        HStack(spacing: Design.Space.card) {
            Image(systemName: glyph)
                .font(Design.Text.detail)
                .foregroundStyle(.tint)
                .frame(width: Design.Icon.glyphColumn)
            Text(label).font(Design.Text.detail).foregroundStyle(.secondary)
            AppIcon(
                bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.inline
            )
            Text(app.applicationName).font(Design.Text.detail.weight(.medium))
            Spacer(minLength: Design.Space.inline)
            Text(Loc.count(app.days, "%@ day", "%@ days"))
                .font(Design.Text.micro)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, Design.Space.snug)
        .padding(.vertical, Design.Space.inline)
        .accessibilityElement(children: .combine)
    }

    private func glyph(for part: String) -> String {
        switch part {
        case "Morning": "sunrise"
        case "Afternoon": "sun.max"
        case "Evening": "sunset"
        default: "moon.stars"
        }
    }
}

#if DEBUG
#Preview("Story") {
    let world = PreviewWorld().load()
    return StoryView(story: world.story, onOpen: { _ in })
        .frame(width: Design.Layout.windowWidth, height: Design.Layout.windowHeight)
}
#endif
