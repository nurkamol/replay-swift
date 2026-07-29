import AppKit
import ReplayCore
import SwiftUI

/// A note on the stretch you are in, written without opening Replay.
///
/// **A panel rather than a field in the menu bar popover, and that is a correction.** The
/// first version put the field in the popover, where it looked right and could not work: an
/// `NSPopover` window does not take the keyboard, so the first character went to whatever
/// window did — and for a `.transient` popover that is an interaction outside it, which
/// closes it. The field opened with a focus ring, ate one keystroke, and vanished with
/// nothing saved. A panel is a real window, it becomes key, and it can be typed in.
///
/// Small, floating, and closable: it is the size of the sentence it exists for. Return saves
/// and closes, Escape leaves without writing — the two things a one-field window has to do.
struct NoteView: View {
    let sessionTitle: String
    let sessionStart: Int64
    let annotations: AnnotationsModel
    let onClose: () -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(
        sessionTitle: String, sessionStart: Int64, annotations: AnnotationsModel,
        onClose: @escaping () -> Void
    ) {
        self.sessionTitle = sessionTitle
        self.sessionStart = sessionStart
        self.annotations = annotations
        self.onClose = onClose
        _draft = State(initialValue: annotations.annotation(for: sessionStart).note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.card) {
            // The session's name and nothing above it: the window is already called Note, and
            // a "NOTE" eyebrow under a title bar reading "Note" is the same word twice.
            Text(sessionTitle)
                .font(Design.Text.itemTitle)
                .lineLimit(1)

            TextField(Loc.t("What is this about?"), text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Design.Text.body)
                .lineLimit(3...6)
                .focused($focused)
                .padding(Design.Space.inline)
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.small, style: .continuous)
                        .fill(Design.Colour.fill)
                )
                // Return saves. `axis: .vertical` would otherwise insert a newline, which is
                // not what a one-sentence note wants — and there is a Save button for the
                // case where somebody does want more than a line.
                .onSubmit(save)

            HStack {
                Spacer()
                Button(Loc.t("Cancel"), action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(Loc.t("Save"), action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Design.Space.page)
        .frame(width: Design.Layout.notePanelWidth)
        // Focused on arrival: this window exists to be typed in, and a panel that opens for
        // one field and then asks to be clicked first is a panel that wasted the trip.
        .onAppear { focused = true }
    }

    private func save() {
        annotations.setNote(
            sessionStart, draft.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        onClose()
    }
}
