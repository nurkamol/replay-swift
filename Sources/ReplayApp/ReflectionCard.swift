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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("Reflection")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.6)
                    .textCase(.uppercase)
            }

            TextField(prompt, text: $value, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...10)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { value = reflection.text; focused = false }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.4), lineWidth: 1)
        )
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
