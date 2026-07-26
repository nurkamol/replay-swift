import ReplayCore
import SwiftUI

/// The small marks a collapsed session card carries once it has been annotated.
///
/// They read at a glance, so a bookmarked or noted session is findable while scanning a
/// month without opening anything. A session with nothing on it shows nothing — the app
/// says nothing rather than filling space.
struct AnnotationMarks: View {
    let annotation: SessionAnnotation

    var body: some View {
        if !annotation.isEmpty {
            HStack(spacing: Design.Space.snug) {
                if annotation.bookmarked {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Bookmarked")
                }
                if !annotation.tags.isEmpty {
                    HStack(spacing: Design.Space.hairline) {
                        Image(systemName: "tag")
                        Text("\(annotation.tags.count)").monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("\(annotation.tags.count) tags")
                }
                if !annotation.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Image(systemName: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Has a note")
                }
            }
        }
    }
}

/// Tags and a note, inside an expanded session.
///
/// There is no Save button: the note commits when it loses focus and tags on Return, the
/// way macOS handles inline text everywhere else. Escape abandons what you were typing.
struct AnnotationEditor: View {
    let sessionStart: Int64
    let annotation: SessionAnnotation
    let annotations: AnnotationsModel

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            TagEditor(sessionStart: sessionStart, tags: annotation.tags, annotations: annotations)
            NoteEditor(sessionStart: sessionStart, note: annotation.note, annotations: annotations)
        }
    }
}

private struct TagEditor: View {
    let sessionStart: Int64
    let tags: [String]
    let annotations: AnnotationsModel

    @State private var draft = ""
    @State private var adding = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: Design.Space.snug) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ForEach(tags, id: \.self) { tag in
                HStack(spacing: Design.Space.tight) {
                    Text("#\(tag)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Button {
                        annotations.setTags(sessionStart, tags.filter { $0 != tag })
                    } label: {
                        Image(systemName: "xmark").font(Design.Text.closeGlyph)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Remove tag \(tag)")
                }
                .padding(.leading, Design.Pill.fieldVertical).padding(.trailing, Design.Pill.trailingTight).padding(.vertical, Design.Space.hairline)
                .background(Design.Colour.fillStrong, in: Capsule())
            }

            if adding {
                TextField("tag", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(width: Design.Layout.tagField)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    .onChange(of: fieldFocused) { _, focused in if !focused { commit() } }
                    .onExitCommand { draft = ""; adding = false }
            } else if tags.count < Rules.maxTags {
                Button {
                    adding = true
                    fieldFocused = true
                } label: {
                    Label("Tag", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    /// Normalise before comparing, so "#Deep Work" does not get added next to "deep work".
    private func commit() {
        let tag = normalizeTags([draft]).first
        draft = ""
        adding = false
        guard let tag, !tags.contains(tag) else { return }
        annotations.setTags(sessionStart, tags + [tag])
    }
}

private struct NoteEditor: View {
    let sessionStart: Int64
    let note: String
    let annotations: AnnotationsModel

    @State private var value: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.inline) {
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, Design.Space.tight)

            // A plain growing field rather than a boxed text view: a note on a memory
            // should feel like writing in a margin, not filling in a form.
            TextField("Add a note…", text: $value, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...8)
                .focused($focused)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onExitCommand { value = note; focused = false }
        }
        // A borderless field is a small target and, on an empty note, an invisible one.
        // The whole row takes the click, so "write something here" is the size it looks.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onAppear { value = note }
        // Collapsing the card while writing must not lose what was written: the field goes
        // away without ever reporting that it lost focus.
        .onDisappear(perform: commit)
        // Keep in step when the note changes elsewhere — deleting a day, say.
        .onChange(of: note) { _, new in if !focused { value = new } }
    }

    private func commit() {
        guard value != note else { return }
        annotations.setNote(sessionStart, value)
    }
}
