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
        HStack(spacing: 14) {
            ProgressRing(fraction: progress.fraction, met: progress.met)

            VStack(alignment: .leading, spacing: 1) {
                Text("Focus goal")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .kerning(0.6)
                    .textCase(.uppercase)

                if progress.met {
                    Text("Goal reached — \(formatDurationShort(progress.activeSeconds))")
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                } else {
                    HStack(spacing: 4) {
                        Text(formatDurationShort(progress.activeSeconds))
                            .font(.callout.weight(.medium))
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
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.caption2)
                    Text("\(streak) days").font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.orange.opacity(0.12), in: Capsule())
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary.opacity(0.4), lineWidth: 1)
        )
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
                .stroke(.quaternary.opacity(0.6), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(
                    met ? AnyShapeStyle(.green) : AnyShapeStyle(.tint),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            if met {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Text("\(Int((fraction * 100).rounded()))")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .animation(.easeOut(duration: 0.25), value: fraction)
    }
}
