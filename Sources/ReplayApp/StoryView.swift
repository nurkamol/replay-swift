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

    @Environment(\.motion) private var motion

    private let columns = [
        GridItem(.adaptive(minimum: Design.Layout.cardMinWidth), spacing: Design.Space.row)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                // Across the full width: it is the whole archive, and the other two are
                // ways into parts of it.
                hub(
                    "My Story", "archivebox",
                    "The whole of it at a glance — how long you have been building this, "
                        + "and everything it holds.",
                    .legacy
                )
                .settlesIn(0)

                LazyVGrid(columns: columns, spacing: Design.Space.row) {
                    hub(
                        "Autobiography", "text.book.closed",
                        "Your history told back to you, a month or a year at a time.",
                        .autobiography
                    )
                    hub(
                        "Chapters", "book",
                        "Your history divided into the eras it naturally fell into.",
                        .chapters
                    )
                    hub(
                        "Museum", "building.columns",
                        "A quiet walk through the parts worth coming back to.",
                        .museum
                    )
                }
                .settlesIn(1)

                if !story.rituals.slots.isEmpty || story.rituals.firstApp != nil {
                    rituals
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Your story")
        .navigationSubtitle("The long view of your work")
        .onAppear { story.load() }
    }

    private func hub(
        _ title: String, _ glyph: String, _ detail: String, _ target: Navigation.StoryTarget
    ) -> some View {
        Button {
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
        .buttonStyle(.plain)
        .focusable()
        .card(border: Design.Colour.border)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
    }

    /// The shape the days tend to take.
    ///
    /// Described, never prescribed: "you tend to start here" is an observation, and there is
    /// deliberately no suggestion attached to it (SPEC §8).
    private var rituals: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text("What your days tend to look like").sectionLabelStyle()
            VStack(spacing: 0) {
                if let first = story.rituals.firstApp {
                    ritual("sunrise", "You usually begin with", first)
                }
                ForEach(story.rituals.slots, id: \.part) { slot in
                    ritual(glyph(for: slot.part), "\(slot.part) tends to lead with", slot.app)
                }
            }
            .padding(Design.Space.snug)
            .card(border: Design.Colour.borderQuiet)
        }
        .settlesIn(2)
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
            Text("\(app.days) \(app.days == 1 ? "day" : "days")")
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
