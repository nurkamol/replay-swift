import ReplayCore
import SwiftUI

/// Your history told back to you, a week, a month or a year at a time.
///
/// Every sentence is a template filled from numbers already in the daily headlines. Nothing
/// is generated and nothing is guessed: when the history does not support a sentence, the
/// sentence is absent rather than hedged. There is no model here and no network — which is
/// the point, and worth saying on the screen itself.
struct AutobiographyView: View {
    let story: StoryModel

    @State private var selected: Period?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if story.periods.isEmpty {
                    empty.centredInPage()
                } else {
                    picker
                    if let period = selected ?? story.periods.first {
                        told(story.autobiography(for: period))
                    }
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle("Autobiography")
        .navigationSubtitle(NarrativeCopy.autobiographySubtitle)
        .onAppear {
            if !story.loaded { story.load() }
            if selected == nil { selected = story.periods.first }
        }
    }

    /// Weeks, months and years in one list rather than three tabs: they are all "a stretch
    /// of time", and which one you want depends on the question, not on a mode.
    private var picker: some View {
        Picker("Period", selection: Binding(
            get: { selected ?? story.periods.first },
            set: { selected = $0 }
        )) {
            ForEach(story.periods) { period in
                Text(period.label).tag(Optional(period))
            }
        }
        .labelsHidden()
        .frame(maxWidth: Design.Layout.segmentedWidth)
        .settlesIn(0)
    }

    private func told(_ story: Autobiography) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.block) {
            VStack(alignment: .leading, spacing: Design.Space.card) {
                ForEach(Array(story.sentences.enumerated()), id: \.offset) { _, sentence in
                    Text(sentence)
                        .font(Design.Text.prose)
                        .lineSpacing(Design.Text.proseLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: Design.Layout.readableWidth, alignment: .leading)
            .padding(Design.Space.section)
            .card(border: Design.Colour.borderQuiet)
            .accessibilityElement(children: .combine)

            if !story.topApps.isEmpty {
                VStack(alignment: .leading, spacing: Design.Space.row) {
                    Text("What led the days").sectionLabelStyle()
                    VStack(spacing: 0) {
                        ForEach(story.topApps, id: \.bundleIdentifier) { app in
                            HStack(spacing: Design.Space.card) {
                                AppIcon(
                                    bundleID: app.bundleIdentifier,
                                    appPath: app.appPath,
                                    size: Design.Icon.stack
                                )
                                Text(app.applicationName).font(Design.Text.detail.weight(.medium))
                                Spacer(minLength: Design.Space.inline)
                                Text("\(app.days) \(app.days == 1 ? "day" : "days")")
                                    .font(Design.Text.micro)
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, Design.Space.snug)
                            .padding(.vertical, Design.Space.snug)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(Design.Space.snug)
                    .card(border: Design.Colour.borderQuiet)
                }
            }

            // Said plainly, because it is the product rather than a disclaimer. "Told back
            // to you" invites the question of who is doing the telling, and this answers it.
            HStack(spacing: Design.Space.snug) {
                Spacer(minLength: 0)
                Image(systemName: "lock").font(Design.Text.micro)
                Text(NarrativeCopy.autobiographyFootnote).font(Design.Text.micro)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.tertiary)
            .accessibilityElement(children: .combine)
        }
        .settlesIn(1)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(NarrativeCopy.autobiographyEmptyTitle, systemImage: "text.book.closed")
        } description: {
            Text(NarrativeCopy.autobiographyEmptyDetail)
        }
    }
}
