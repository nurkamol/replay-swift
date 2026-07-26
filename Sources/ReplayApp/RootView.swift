import Observation
import ReplayCore
import SwiftUI

/// Which surface the window is showing.
///
/// Held outside the view because the menu bar drives it too — "Open Today" and "Open
/// Timeline" have to reach a window that already exists, and a `View` is a value the
/// delegate cannot call into.
@MainActor
@Observable
final class Navigation {
    enum Surface: String, CaseIterable, Identifiable {
        case today = "Today", timeline = "Timeline"
        var id: String { rawValue }
    }

    var surface: Surface = .today
    /// The day being read, pushed over the top of whichever surface is behind it.
    var openDay: Int64?

    func show(_ surface: Surface) {
        openDay = nil
        self.surface = surface
    }
}

/// The window: Today, the Timeline, and whatever day you opened from it.
///
/// Two surfaces and a detail is not enough to earn a sidebar yet — the Glaze app has one
/// because it has a dozen views. This stays a picker until there is more to hold, with a
/// reopened day pushed over the top rather than made a third tab: it is somewhere you go
/// *from* the Timeline, and it comes back there.
struct RootView: View {
    let model: AppModel
    let history: HistoryModel
    @Bindable var navigation: Navigation
    let preferences: Preferences
    let export: ExportModel

    /// The opened day, built when it is opened rather than while the body runs — deriving a
    /// day loads its annotations, and a view body must not be what mutates them.
    @State private var opened: (day: TimelineDay, headline: DailySummary?, reflection: Reflection)?

    var body: some View {
        VStack(spacing: 0) {
            if let opened {
                DayView(
                    day: opened.day,
                    headline: opened.headline,
                    reflection: opened.reflection,
                    annotations: model.annotations,
                    export: export,
                    onReflect: { text in
                        history.setReflection(opened.day.dayStart, text)
                        reloadOpenDay()
                    },
                    onDeleteSession: { history.deleteSession($0) },
                    onBack: { navigation.openDay = nil }
                )
            } else {
                picker
                Divider()
                switch navigation.surface {
                case .today:
                    TodayView(
                        model: model, annotations: model.annotations, preferences: preferences
                    )
                case .timeline:
                    TimelineView(
                        history: history,
                        annotations: model.annotations,
                        export: export,
                        onOpenDay: { navigation.openDay = $0 }
                    )
                }
            }
        }
        .onChange(of: navigation.surface, initial: true) { _, new in
            // The Timeline reads the store directly rather than following the tracker, so
            // it reloads when it is shown rather than on every recorded event.
            if new == .timeline { history.reload() }
        }
        .onChange(of: navigation.openDay, initial: true) { _, _ in reloadOpenDay() }
        .preferredColorScheme(preferences.appearance.colorScheme)
    }

    /// Rebuild the opened day outside the body — deriving it loads annotations, and a view
    /// body must not be what mutates them.
    private func reloadOpenDay() {
        opened = navigation.openDay.map {
            (history.day($0), history.headline($0), history.reflection($0))
        }
    }

    private var picker: some View {
        Picker("Surface", selection: $navigation.surface) {
            ForEach(Navigation.Surface.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}
