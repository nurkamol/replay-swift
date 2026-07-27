import ReplayCore
import SwiftUI

/// What each version actually gained.
///
/// A list rather than a carousel: someone opening this wants to find the thing they half
/// remember reading about, and a page at a time makes that a hunt. Newest first, and the
/// current version is marked so it is obvious where you are.
struct WhatsNewView: View {
    let onClose: () -> Void
    @Environment(\.themeTint) private var tint


    private var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Design.Space.card) {
                Image(nsImage: BundleIcon.image)
                    .resizable()
                    .frame(width: Design.Icon.about, height: Design.Icon.about)
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text("What's New").font(Design.Text.title)
                    Text("Everything Replay has gained, newest first.")
                        .font(Design.Text.body)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Design.Space.inline)
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(Design.Space.page)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Design.Space.block) {
                    ForEach(releases) { release in
                        VStack(alignment: .leading, spacing: Design.Space.row) {
                            HStack(spacing: Design.Space.inline) {
                                Text(release.title).font(Design.Text.itemTitle)
                                Text(release.version)
                                    .font(Design.Text.micro)
                                    .monospacedDigit()
                                    .padding(.horizontal, Design.Pill.countHorizontal)
                                    .padding(.vertical, Design.Pill.countVertical)
                                    .background(
                                        Capsule().fill(
                                            release.version == current
                                                ? AnyShapeStyle(tint.opacity(Design.Colour.markedOpacity))
                                                : Design.Colour.fill
                                        )
                                    )
                                if release.version == current {
                                    Text("You have this")
                                        .font(Design.Text.micro)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            VStack(alignment: .leading, spacing: Design.Space.inline) {
                                ForEach(Array(release.changes.enumerated()), id: \.offset) { _, change in
                                    HStack(alignment: .top, spacing: Design.Space.inline) {
                                        Circle()
                                            .fill(.tertiary)
                                            .frame(
                                                width: Design.Layout.bulletSize,
                                                height: Design.Layout.bulletSize
                                            )
                                            .padding(.top, Design.Space.snug)
                                        Text(change)
                                            .font(Design.Text.body)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: Design.Layout.readableWidth, alignment: .leading)
                .padding(Design.Space.page)
            }
        }
        .frame(width: Design.Layout.whatsNewWidth, height: Design.Layout.whatsNewHeight)
        .background(.background)
    }
}
