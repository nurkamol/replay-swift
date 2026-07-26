import ReplayCore
import SwiftUI

/// The day's progress toward a self-set focus goal.
///
/// Deliberately understated: this is the **one** evaluative surface in an app that otherwise
/// only describes (SPEC §8), so it stays a gentle nudge rather than a scoreboard. When the
/// goal is reached the ring fills and the figure gives way to a plain sentence. It never
/// turns red, never scolds a short day, and shows a streak only once there is one worth
/// celebrating.
struct FocusGoalCard: View {
    let progress: Goals.Progress
    let streak: Int
    let goalMinutes: Int
    let onSetGoal: (Int?) -> Void

    var body: some View {
        HStack(spacing: Design.Space.cardRoomy) {
            ProgressRing(fraction: progress.fraction, met: progress.met)

            VStack(alignment: .leading, spacing: 1) {
                Text("Focus goal")
                    .font(Design.Text.cardLabel)
                    .foregroundStyle(.tertiary)
                    .kerning(Design.Text.labelKerning)
                    .textCase(.uppercase)

                if progress.met {
                    Text("Goal reached — \(formatDurationShort(progress.activeSeconds))")
                        .font(Design.Text.figure)
                        .monospacedDigit()
                } else {
                    HStack(spacing: Design.Space.tight) {
                        Text(formatDurationShort(progress.activeSeconds))
                            .font(Design.Text.figure)
                            .monospacedDigit()
                        Text("of \(formatDurationShort(progress.goalSeconds))")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    if progress.remainingSeconds > 0 {
                        Text("\(formatDurationShort(progress.remainingSeconds)) to go")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 0)

            // Only past one day: "1 day" is not a streak, it is today.
            if streak > 1 {
                HStack(spacing: Design.Space.tight) {
                    Image(systemName: "flame.fill").font(.caption2)
                    Text("\(streak) days").font(Design.Text.sectionLabel).monospacedDigit()
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, Design.Pill.horizontal).padding(.vertical, Design.Pill.vertical)
                .background(.orange.opacity(Design.Colour.streakOpacity), in: Capsule())
            }

            // Adjustable from where it is read, rather than only from Settings — the figure
            // and the control for it belong together.
            Menu {
                ForEach(Goals.presetMinutes, id: \.self) { minutes in
                    Button {
                        onSetGoal(minutes)
                    } label: {
                        if minutes == goalMinutes {
                            Label(Goals.format(minutes), systemImage: "checkmark")
                        } else {
                            Text(Goals.format(minutes))
                        }
                    }
                }
                Divider()
                Button("Stop Keeping a Goal") { onSetGoal(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(Design.Space.cardRoomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(background: Design.Colour.surface, border: Design.Colour.fill)
    }
}

/// A quiet ring rather than a bar: it reads as a dial you are filling, not a deadline you
/// are running out of.
private struct ProgressRing: View {
    let fraction: Double
    let met: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Design.Colour.divider, lineWidth: Design.Layout.ringThickness)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(
                    met ? AnyShapeStyle(.green) : AnyShapeStyle(.tint),
                    style: StrokeStyle(lineWidth: Design.Layout.ringThickness, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if met {
                Image(systemName: "checkmark")
                    .font(Design.Text.ringGlyph)
                    .foregroundStyle(.green)
            } else {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(Design.Text.ringFigure)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: Design.Icon.ring, height: Design.Icon.ring)
        .animation(Design.Motion.inPlace, value: fraction)
    }
}
