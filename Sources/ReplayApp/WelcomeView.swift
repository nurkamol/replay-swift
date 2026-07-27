import AppKit
import ReplayCore
import SwiftUI

/// The first thing anyone sees, and the last chance to be honest before they start.
///
/// Two pages. The first offers the things Replay can do that it will not do unasked — every
/// one of them off by default except the memory feature, because a first run that quietly
/// switches on notifications and a screensaver is a first run that has decided for you. The
/// second is the claim this app is built on, shown working rather than asserted: Replay reads
/// which application is frontmost, that is all it reads, and it needs no permission to do it.
///
/// It is not a tour. There is nothing here about how to use the app, because an app that
/// needs explaining before it is opened has a different problem.
struct WelcomeView: View {
    let model: AppModel
    @Bindable var preferences: Preferences
    let notifications: NotificationsModel
    let onFinish: () -> Void

    @Environment(\.motion) private var motion
    @State private var page = 0

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            // Scrolls rather than sizing to its content: on a short window the choices are
            // taller than the space, and a first run that cannot reach its own Continue
            // button is worse than one that scrolls.
            ScrollView {
                Group {
                    if page == 0 { choices } else { theClaim }
                }
                .frame(maxWidth: Design.Layout.welcomeWidth)
                .frame(maxWidth: .infinity)
                .transition(motion.transition(.opacity))
            }
        }
        .animation(motion.animation(Design.Motion.settle), value: page)
    }

    // ── page one ──────────────────────────────────────────────────────────────

    private var choices: some View {
        VStack(spacing: Design.Space.block) {
            mark
            VStack(spacing: Design.Space.snug) {
                Text("Welcome to Replay").font(Design.Text.title)
                Text(
                    "Replay quietly notes which apps you use and turns your day into a "
                        + "memory you can return to — all on your Mac."
                )
                .font(Design.Text.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                choice(
                    "clock.arrow.circlepath", "Today in History",
                    "Rediscover what you were doing on this date a week, a month, a year ago.",
                    isOn: $preferences.contextualMemories
                )
                Divider()
                choice(
                    "target", "Daily focus goal",
                    "A gentle daily target, with a streak on Today. Around three hours to start.",
                    isOn: Binding(
                        get: { preferences.focusGoalMinutes != nil },
                        set: { preferences.focusGoalMinutes = $0 ? Design.welcomeGoalMinutes : nil }
                    )
                )
                Divider()
                choice(
                    "bell", "Daily recap",
                    "A quiet end-of-day summary each evening, delivered by macOS.",
                    isOn: Binding(
                        get: { preferences.dailySummary },
                        set: { on in
                            preferences.dailySummary = on
                            Task {
                                if on, await notifications.request() == false {
                                    preferences.dailySummary = false
                                }
                                await notifications.reschedule()
                            }
                        }
                    )
                )
                Divider()
                choice(
                    "sparkles.tv", "Screensaver when idle",
                    "After a few quiet minutes, drift through today's sessions and memories.",
                    isOn: Binding(
                        get: { preferences.screensaverIdleMinutes > 0 },
                        set: { preferences.screensaverIdleMinutes = $0 ? Design.welcomeIdleMinutes : 0 }
                    )
                )
                Divider()
                choice(
                    "app.badge", "Dock badge",
                    "Show today's active hours on the Dock icon as the day adds up.",
                    isOn: Binding(
                        get: { preferences.dockBadge },
                        set: {
                            preferences.dockBadge = $0
                            DockBadge.update(model, enabled: $0)
                        }
                    )
                )
            }
            .card(border: Design.Colour.borderQuiet)

            Label(
                "Everything stays on this Mac. No account, no cloud, nothing to sign in to.",
                systemImage: "lock"
            )
            .font(Design.Text.detail)
            .foregroundStyle(.tertiary)

            Button {
                page = 1
            } label: {
                Label("Continue", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Space.snug)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            dots
        }
        .padding(Design.Space.page)
    }

    private func choice(
        _ glyph: String, _ title: String, _ detail: String, isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: Design.Space.card) {
                Image(systemName: glyph)
                    .font(Design.Text.prose)
                    .foregroundStyle(.tint)
                    .frame(width: Design.Icon.glyphColumn)
                VStack(alignment: .leading, spacing: Design.Space.hairline) {
                    Text(title).font(Design.Text.itemTitle)
                    Text(detail)
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Claims the rest of the row, so every switch lands on the same right edge
                // and every glyph on the same left one. Without it a `Toggle` sizes its
                // label to its content, and five rows of different-length text produced
                // five different indents.
                Spacer(minLength: Design.Space.inline)
            }
        }
        .toggleStyle(.switch)
        .padding(Design.Space.section)
    }

    // ── page two ──────────────────────────────────────────────────────────────

    private var theClaim: some View {
        VStack(spacing: Design.Space.block) {
            mark
            VStack(spacing: Design.Space.snug) {
                Text("One quick check").font(Design.Text.title)
                Text(
                    "Replay reads which app is frontmost using macOS's standard signal — no "
                        + "Automation, and it never looks inside your windows. Here it is "
                        + "working:"
                )
                .font(Design.Text.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Shown rather than claimed. A sentence saying "no permissions needed" is a
            // promise; a live green tick that is already recording is evidence.
            VStack(alignment: .leading, spacing: Design.Space.card) {
                HStack(spacing: Design.Space.card) {
                    Image(systemName: model.isRecording ? "checkmark.circle" : "exclamationmark.circle")
                        .font(Design.Text.prose)
                        .foregroundStyle(model.isRecording ? Design.Colour.assurance : .orange)
                    VStack(alignment: .leading, spacing: Design.Space.hairline) {
                        Text(
                            model.isRecording
                                ? "Replay is recording your activity"
                                : "Replay is not recording"
                        )
                        .font(Design.Text.itemTitle)
                        Text(
                            model.current.map { "Right now: \($0.applicationName)" }
                                ?? "Reads only which app is frontmost."
                        )
                        .font(Design.Text.detail)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Text(
                    "It needs no permission to work. The buttons below are only for "
                        + "verifying, or for a Mac that has been locked down."
                )
                .font(Design.Text.micro)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                // Two panes, not three. "Privacy & Security" was the parent category of the
                // other two and opened the same place less precisely — and a third button
                // under a green tick reads as a third thing you ought to be doing, which
                // argues against the sentence directly above it. These two name specific
                // panes somebody on a managed Mac might genuinely be sent to.
                HStack(spacing: Design.Space.inline) {
                    settingsLink("Accessibility", "Privacy_Accessibility")
                    settingsLink("App Management", "Privacy_AppBundles")
                }
            }
            .padding(Design.Space.section)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(border: Design.Colour.borderQuiet)

            Button(action: onFinish) {
                Text("Start Remembering")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Design.Space.snug)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Button {
                page = 0
            } label: {
                Label("Back", systemImage: "arrow.left")
                    .font(Design.Text.detail)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            dots
        }
        .padding(Design.Space.page)
    }

    private func settingsLink(_ title: String, _ pane: String) -> some View {
        Button(title) {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // ── shared ────────────────────────────────────────────────────────────────

    private var mark: some View {
        Image(nsImage: BundleIcon.image)
            .resizable()
            .frame(width: Design.Icon.welcomeMark, height: Design.Icon.welcomeMark)
            .accessibilityHidden(true)
    }

    private var dots: some View {
        HStack(spacing: Design.Space.snug) {
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .fill(index == page ? AnyShapeStyle(.tint) : Design.Colour.fill)
                    .frame(width: Design.Layout.welcomeDot, height: Design.Layout.welcomeDot)
            }
        }
        .accessibilityHidden(true)
    }
}
