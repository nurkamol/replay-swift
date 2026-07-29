import ReplayCore
import SwiftUI

/// Where your time went, by application.
///
/// Ranked by time and nothing else. There is no "distracting" column and no traffic light:
/// which of your applications deserve your hours is not something this app has any business
/// having an opinion about (SPEC §8). Pinning exists because *you* might have one.
struct AppsView: View {
    let apps: AppsModel
    @Bindable var preferences: Preferences
    /// Given so a row can lead into that application's own history.
    let onOpenApp: (String) -> Void


    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Design.Space.block) {
                header
                if apps.stats.isEmpty {
                    empty.centredInPage()
                } else {
                    let favourites = apps.favourites(pinned: preferences.pinnedApps)
                    if !favourites.isEmpty {
                        section("Favourites", favourites, glyph: "star.fill")
                    }
                    section(
                        favourites.isEmpty ? "Most used" : "Everything",
                        apps.stats,
                        glyph: nil
                    )
                }
            }
            .pageContent()
        }
        .background(.background)
        .navigationTitle(Loc.t("Apps"))
        .navigationSubtitle(apps.window.subtitle)
        .onAppear { if !apps.loaded { apps.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Design.Space.card) {
            Picker(Loc.t("Window"), selection: Binding(
                get: { apps.window }, set: { apps.window = $0 }
            )) {
                ForEach(AppWindow.allCases) { window in
                    Text(window.label).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: Design.Layout.segmentedWidth)

            if !apps.stats.isEmpty {
                HStack(spacing: Design.Space.statGap) {
                    figure("\(apps.stats.count)", apps.stats.count == 1 ? "application" : "applications")
                    figure(formatDurationShort(apps.totalSeconds), "in total")
                }
            }
        }
        .settlesIn(0)
    }

    private func figure(_ value: String, _ label: String) -> some View {
        HStack(spacing: Design.Space.snug) {
            Text(value)
                .font(Design.Text.figure)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(Loc.t(label)).font(Design.Text.subtitle).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: Loc.t("%1$@ %2$@"), value, label))
    }

    private func section(_ title: String, _ rows: [AppStat], glyph: String?) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.snug) {
            HStack(spacing: Design.Space.snug) {
                if let glyph {
                    Image(systemName: glyph)
                        .font(Design.Text.micro)
                        .foregroundStyle(Design.Colour.marked)
                }
                Text(title).sectionLabelStyle()
            }
            VStack(spacing: 0) {
                ForEach(rows, id: \.key) { stat in
                    AppStatRow(
                        stat: stat,
                        maxSeconds: apps.stats.first?.totalSeconds ?? 0,
                        pinned: stat.bundleIdentifier.map(preferences.pinnedApps.contains) ?? false,
                        onOpen: { stat.bundleIdentifier.map(onOpenApp) },
                        onTogglePin: { stat.bundleIdentifier.map(preferences.togglePinned) }
                    )
                    if stat.key != rows.last?.key { Divider() }
                }
            }
        }
        .settlesIn(1)
    }

    private var empty: some View {
        ContentUnavailableView {
            Label(Loc.t("No applications tracked yet"), systemImage: "square.grid.2x2")
        } description: {
            Text(Loc.t("Once you have used a few, Replay will rank them here by the time you spent in each."))
        }
    }
}

/// One application: how long, how often, and a bar for the shape of it.
private struct AppStatRow: View {
    let stat: AppStat
    let maxSeconds: Int
    let pinned: Bool
    let onOpen: () -> Void
    let onTogglePin: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Design.Space.card) {
                AppIcon(
                    bundleID: stat.bundleIdentifier,
                    appPath: stat.appPath,
                    size: Design.Icon.appRow
                )
                VStack(alignment: .leading, spacing: Design.Space.snug) {
                    HStack(spacing: Design.Space.inline) {
                        Text(stat.applicationName)
                            .font(Design.Text.itemTitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: Design.Space.inline)
                        pin
                        Text(formatDurationShort(stat.totalSeconds))
                            .font(Design.Text.detail.weight(.medium))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(Design.Text.micro)
                            .foregroundStyle(.quaternary)
                    }
                    HStack(spacing: Design.Space.card) {
                        bar
                        Text(Loc.count(stat.sessionCount, "%@ session", "%@ sessions"))
                            .font(Design.Text.micro)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
            }
            .padding(.vertical, Design.Space.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.row)
        .focusable()
        .disabled(stat.bundleIdentifier == nil)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(stat.applicationName), \(formatDurationShort(stat.totalSeconds)), "
                + Loc.count(stat.sessionCount, "%@ session", "%@ sessions")
                + (pinned ? ", pinned" : "")
        )
        .accessibilityHint(Loc.t("Opens this application's history"))
    }

    /// Visible on hover, or always once pinned — a star on every row would be a column of
    /// controls rather than a list of applications.
    @ViewBuilder
    private var pin: some View {
        if stat.bundleIdentifier != nil {
            Button(action: onTogglePin) {
                Image(systemName: pinned ? "star.fill" : "star")
                    .font(Design.Text.micro)
                    .foregroundStyle(pinned ? AnyShapeStyle(Design.Colour.marked) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .opacity(pinned || hovering ? 1 : 0)
            .help(pinned ? "Unpin \(stat.applicationName)" : "Pin \(stat.applicationName)")
            .accessibilityLabel(pinned ? "Unpin \(stat.applicationName)" : "Pin \(stat.applicationName)")
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            // Floored so an application with a sliver of time still draws something: a bar
            // of zero width reads as "no data" when it means "not much".
            let fraction = maxSeconds > 0
                ? max(Design.Layout.barMinFraction, Double(stat.totalSeconds) / Double(maxSeconds))
                : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Design.Colour.fill)
                    .frame(height: Design.Layout.barThin)
                Capsule().fill(.tint)
                    .frame(width: geometry.size.width * fraction, height: Design.Layout.barThin)
            }
            .frame(height: geometry.size.height, alignment: .center)
        }
        .frame(height: Design.Layout.barThin)
    }
}
