import ReplayCore
import SwiftUI

/// What you would like to remember about a day.
///
/// A line for your future self, not a field to fill in — so it commits when it loses focus,
/// says nothing when there is nothing to say, and never asks twice. Keyed by the day rather
/// than by a session, because it is about the day as a whole.
struct ReflectionCard: View {
    let dayStart: Int64
    let reflection: Reflection
    let prompt: String
    let onCommit: (String) -> Void

    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            HStack(spacing: Design.Space.snug) {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text(Loc.t("Reflection"))
                    .font(Design.Text.cardLabel)
                    .foregroundStyle(.tertiary)
                    .kerning(Design.Text.labelKerning)
                    .textCase(.uppercase)
            }

            TextField(Loc.t(prompt), text: $value, axis: .vertical)
                // The prompt is a placeholder, and a placeholder is not announced. Without
                // this VoiceOver reached the one writable thing on Today and said "text
                // field" — the question it is asking never reaching the person answering it.
                .accessibilityLabel(Loc.t("Reflection"))
                .accessibilityHint(Loc.t(prompt))
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...10)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { value = reflection.text; focused = false }
        }
        .padding(Design.Space.cardRoomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(background: Design.Colour.surface, border: Design.Colour.fill)
        // A borderless field on an empty day is an invisible target; the card takes the click.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { value = reflection.text }
        // Leaving the day while writing must not lose what was written: the field goes away
        // without ever reporting that it lost focus.
        .onDisappear(perform: commit)
        .onChange(of: reflection.text) { _, new in if !focused { value = new } }
    }

    private func commit() {
        guard value != reflection.text else { return }
        onCommit(value)
    }
}
