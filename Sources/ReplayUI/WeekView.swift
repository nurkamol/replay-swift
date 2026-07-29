import ReplayCore
import SwiftUI

/// The last seven days.
///
/// Two questions, in the order people ask them: *when* was I here, and *what* was I in. The
/// rhythm strip answers the first — a glance down the column shows not just how much each
/// day held but when it happened, which is the thing a week is actually remembered by. The
/// list answers the second.
///
/// Nothing here grades the week. There is no target line on the strip and no "you were 12%
/// less productive": a quiet day is rest, and it draws as rest (SPEC §8).
struct WeekView: View {
    let week: WeekModel


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                if let summary = week.summary, summary.activeSeconds > 0 {
                    figures(summary)
                    rhythm(summary)
                    if !week.workflows.isEmpty { workflows }
                    mostUsed(summary)
                } else {
                    empty.centredInPage()
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("This Week"))
        .navigationSubtitle(week.rangeLabel)
        .onAppear { week.load() }
    }

    // ── the figures ───────────────────────────────────────────────────────────

    private func figures(_ summary: WeekSummary) -> some View {
        HStack(spacing: Design.Space.statGap) {
            figure(summary.activeLabel, "active")
            figure(
                "\(summary.sessionCount)",
                summary.sessionCount == 1 ? "session" : "sessions"
            )
            figure(
                "\(summary.appsUsed)",
                summary.appsUsed == 1 ? "application" : "applications"
            )
        }
        .settlesIn(0)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        HStack(spacing: Design.Space.snug) {
            Text(value)
                .font(Design.Text.figure)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(Design.Text.subtitle)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: Loc.t("%1$@ %2$@"), value, label))
    }

    // ── the rhythm ────────────────────────────────────────────────────────────

    private func rhythm(_ summary: WeekSummary) -> some View {
        // Every day is measured against the busiest one, not against itself, so a quiet
        // Tuesday reads as genuinely quieter than a busy Friday rather than every day
        // looking equally full.
        let busiest = max(summary.days.map(\.activeSeconds).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("Daily rhythm")).sectionLabelStyle()
            VStack(spacing: 0) {
                ForEach(summary.days, id: \.dayStart) { day in
                    WeekDayRow(day: day, busiestDaySeconds: busiest)
                }
                HourAxis()
            }
            .settlesIn(1)
            if let peak = summary.peak {
                // A statement of when, not a recommendation about when.
                Text(String(format: Loc.t("Most often here on %@."), "\(describePeak(peak))"))
                    .font(Design.Text.detail)
                    .foregroundStyle(.tertiary)
                    .padding(.top, Design.Space.tight)
            }
        }
    }

    // ── the combinations ──────────────────────────────────────────────────────

    /// Applications that keep showing up together.
    ///
    /// Absent rather than empty when nothing recurs: a heading over a blank space implies
    /// something failed to load, and what actually happened is that a week of one-off
    /// pairings has no habits in it to report.
    private var workflows: some View {
        VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("Recurring together")).sectionLabelStyle()
            VStack(spacing: Design.Space.snug) {
                ForEach(week.workflows, id: \.id) { workflow in
                    WorkflowRow(workflow: workflow)
                }
            }
        }
        .settlesIn(2)
    }

    // ── the applications ──────────────────────────────────────────────────────

    private func mostUsed(_ summary: WeekSummary) -> some View {
        let top = Array(summary.apps.prefix(WeekSummary.appLimit))
        return VStack(alignment: .leading, spacing: Design.Space.row) {
            Text(Loc.t("Most used this week")).sectionLabelStyle()
            VStack(spacing: Design.Space.snug) {
                ForEach(top, id: \.applicationName) { app in
                    WeekAppRow(app: app, maxSeconds: top.first?.seconds ?? 0)
                }
            }
        }
        .settlesIn(3)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(Loc.t("Your week is just beginning"), systemImage: "calendar")
        } description: {
            Text(Loc.t("As you use your Mac, each day will fill in here."))
        }
    }
}

/// One day: its name, when it happened, and how much of it there was.
private struct WeekDayRow: View {
    let day: WeekSummary.Day
    let busiestDaySeconds: Int

    var body: some View {
        HStack(spacing: Design.Space.card) {
            VStack(alignment: .leading, spacing: 0) {
                Text(day.weekdayShort)
                    .font(Design.Text.detail.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(day.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                Text(String(format: Loc.t("%@"), "\(day.dayOfMonth)"))
                    .font(Design.Text.micro)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Design.Layout.weekdayColumn, alignment: .leading)

            DayArc(arc: day.arc, busiestDaySeconds: busiestDaySeconds, empty: day.isEmpty)
                .frame(maxWidth: .infinity)

            // An em dash rather than "0m": nothing was recorded, which is not the same
            // claim as zero minutes of use.
            Text(day.isEmpty ? "—" : formatDurationShort(day.activeSeconds))
                .font(Design.Text.detail.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(day.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.primary))
                .frame(width: Design.Layout.durationColumn, alignment: .trailing)
                // Sized before the strip beside it. Without this the strip — which is
                // twenty-four bars that each want to fill — claims the whole row, and the
                // duration is pushed past the edge and clipped away entirely. It was capped
                // at 560pt before, which hid the greed behind a dead gap rather than fixing
                // it.
                .layoutPriority(1)
        }
        .padding(.horizontal, Design.Space.inline)
        .padding(.vertical, Design.Space.inline)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .fill(day.isToday ? Design.Colour.surfaceQuiet : AnyShapeStyle(.clear))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            day.isEmpty
                ? "\(day.weekdayShort) \(day.dayOfMonth), nothing recorded"
                : "\(day.weekdayShort) \(day.dayOfMonth), "
                    + "\(formatDurationShort(day.activeSeconds)) active, "
                    + Loc.count(day.sessionCount, "%@ session", "%@ sessions")
        )
    }
}

/// A day's twenty-four hours as a low strip of bars.
private struct DayArc: View {
    let arc: [Int]
    let busiestDaySeconds: Int
    let empty: Bool

    var body: some View {
        // A sixth of the busiest day, floored at ten minutes: without the floor a week of
        // short days would draw every bar at full height and say nothing.
        let ceiling = max(Double(busiestDaySeconds) / Design.Layout.arcCeilingDivisor,
                          Design.Layout.arcCeilingFloorSeconds)
        HStack(alignment: .bottom, spacing: Design.Layout.hairline) {
            ForEach(arc.indices, id: \.self) { hour in
                bar(seconds: arc[hour], ceiling: ceiling)
            }
        }
        .frame(height: Design.Layout.arcHeight, alignment: .bottom)
        // The strip is a picture of the row's own numbers; announcing it would say the
        // same thing twice.
        .accessibilityHidden(true)
    }

    /// One hour.
    private func bar(seconds: Int, ceiling: Double) -> some View {
        let ratio: Double = min(1, Double(seconds) / ceiling)
        let quiet: Bool = seconds <= 0
        // A quiet hour keeps a baseline rather than vanishing: the shape of the day should
        // be legible even where nothing happened.
        let height: CGFloat = quiet
            ? Design.Layout.arcBaseline
            : max(Design.Layout.arcMinBar, CGFloat(ratio) * Design.Layout.arcHeight)
        let fill: AnyShapeStyle = quiet ? Design.Colour.divider : AnyShapeStyle(.tint)
        let weight: Double
        if empty {
            weight = Design.Colour.arcRestOpacity
        } else if quiet {
            weight = Design.Colour.arcQuietOpacity
        } else {
            weight = Design.Colour.arcFloorOpacity + ratio * Design.Colour.arcRangeOpacity
        }
        return RoundedRectangle(cornerRadius: Design.Radius.hair, style: .continuous)
            .fill(fill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .opacity(weight)
    }
}

/// The hour scale, once, under all seven rows.
///
/// Under all seven rather than beneath each: the scale is identical for every day, and
/// repeating it seven times would be noise standing in for information.
private struct HourAxis: View {
    private static let ticks = WeekSummary.arcTicks

    var body: some View {
        HStack(spacing: Design.Space.card) {
            Color.clear.frame(width: Design.Layout.weekdayColumn)
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    ForEach(Self.ticks, id: \.self) { hour in
                        Text(Self.label(hour))
                            .font(Design.Text.micro)
                            .foregroundStyle(.quaternary)
                            .monospacedDigit()
                            .offset(x: geometry.size.width * Double(hour) / 24)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Design.Layout.axisHeight)
            Color.clear
                .frame(width: Design.Layout.durationColumn)
                .layoutPriority(1)
        }
        .padding(.horizontal, Design.Space.inline)
        .accessibilityHidden(true)
    }

    private static func label(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour == 12 { return "12 PM" }
        return hour < 12 ? "\(hour) AM" : "\(hour - 12) PM"
    }
}

/// One application's week.
private struct WeekAppRow: View {
    let app: WeekSummary.App
    let maxSeconds: Int

    var body: some View {
        HStack(spacing: Design.Space.row) {
            AppIcon(bundleID: app.bundleIdentifier, appPath: app.appPath, size: Design.Icon.inline)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.applicationName).font(Design.Text.subtitle)
                Text(app.daysUsed == 1 ? "1 day" : "\(app.daysUsed) days")
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: Design.Layout.appNameColumn, alignment: .leading)
            GeometryReader { geometry in
                let fraction = maxSeconds > 0 ? Double(app.seconds) / Double(maxSeconds) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Design.Colour.fill)
                        .frame(height: Design.Layout.barThickness)
                    Capsule().fill(.tint)
                        .frame(
                            width: geometry.size.width * fraction,
                            height: Design.Layout.barThickness
                        )
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(height: Design.Layout.barRow)
            Text(formatDurationShort(app.seconds))
                .font(Design.Text.detail)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: Design.Layout.durationColumn, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(app.applicationName), \(formatDurationShort(app.seconds)), "
                + "on \(app.daysUsed) \(app.daysUsed == 1 ? "day" : "days")"
        )
    }
}

/// One recurring combination: whose apps, how long, how often.
private struct WorkflowRow: View {
    let workflow: Workflow

    var body: some View {
        HStack(spacing: Design.Space.card) {
            // Overlapped rather than spaced, so three apps read as one thing — which is
            // the claim: these were used together, not one after another.
            HStack(spacing: Design.Space.iconOverlap) {
                ForEach(workflow.apps, id: \.applicationName) { app in
                    AppIcon(
                        bundleID: app.bundleIdentifier,
                        appPath: app.appPath,
                        size: Design.Icon.stack
                    )
                    .background(
                        Circle()
                            .fill(.background)
                            .padding(-Design.Layout.hairline)
                    )
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(workflow.title).font(Design.Text.itemTitle)
                Text(workflow.apps.map(\.applicationName).joined(separator: " · "))
                    .font(Design.Text.detail)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: Design.Space.inline)
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatDurationShort(workflow.totalSeconds))
                    .font(Design.Text.detail.weight(.medium))
                    .monospacedDigit()
                Text(String(format: Loc.t("%@×"), "\(workflow.sessionCount)"))
                    .font(Design.Text.micro)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, Design.Space.cardRoomy)
        .padding(.vertical, Design.Space.card)
        .card(border: Design.Colour.border)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(workflow.title), \(workflow.apps.map(\.applicationName).joined(separator: ", ")), "
                + "\(formatDurationShort(workflow.totalSeconds)) across "
                + "\(workflow.sessionCount) sessions"
        )
    }
}
