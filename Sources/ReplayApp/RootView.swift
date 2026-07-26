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

    var body: some View {
        VStack(spacing: 0) {
            if let day = navigation.openDay {
                DayView(
                    day: history.day(day),
                    headline: history.headline(day),
                    onDeleteSession: { history.deleteSession($0) },
                    onBack: { navigation.openDay = nil }
                )
            } else {
                picker
                Divider()
                switch navigation.surface {
                case .today:
                    TodayView(model: model)
                case .timeline:
                    TimelineView(history: history, onOpenDay: { navigation.openDay = $0 })
                }
            }
        }
        .onChange(of: navigation.surface, initial: true) { _, new in
            // The Timeline reads the store directly rather than following the tracker, so
            // it reloads when it is shown rather than on every recorded event.
            if new == .timeline { history.reload() }
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
