#if DEBUG
import ReplayCore
import SwiftUI

/// Everything a surface needs to draw, over one sample record.
///
/// Deliberately shaped like ``AppDelegate``: the same models, built from the same `AppModel`,
/// in the same order. A preview that assembled its own subset would drift from what the app
/// actually hands a view, and the first thing you would notice is a canvas that renders
/// something the running app never shows.
///
/// Every model is loaded up front by ``load()``. Views load on `onAppear`, which the canvas
/// does honour — but a preview that paints empty and fills a moment later reads as a layout
/// bug for the moment it is wrong, and that is the moment somebody screenshots.
///
/// `#if DEBUG`, like ``SampleRecord``, so none of it reaches a shipped binary.
@MainActor
final class PreviewWorld {
    let model: AppModel
    let preferences: Preferences

    lazy var history = HistoryModel(model: model)
    lazy var apps = AppsModel(model: model)
    lazy var appHistory = AppHistoryModel(model: model)
    lazy var memories = MemoriesModel(model: model)
    lazy var collections = CollectionsModel(model: model)
    lazy var week = WeekModel(model: model)
    lazy var projects = ProjectsModel(model: model, preferences: preferences)
    lazy var story = StoryModel(model: model, preferences: preferences)
    lazy var search = SearchModel(model: model, preferences: preferences)
    lazy var export = ExportModel(model: model)
    lazy var overlays = TimelineLayersModel(model: model)
    lazy var relationships = RelationshipsModel(model: model)
    lazy var contextual = ContextualMemoryModel(
        model: model, projects: projects, preferences: preferences
    )
    lazy var navigation = Navigation()

    var annotations: AnnotationsModel { model.annotations }

    /// Its own defaults suite, so a canvas cannot write into the settings of the app you are
    /// running beside it — and two previews open at once cannot see each other's.
    init(suite: String = "replay.preview.\(UUID().uuidString)") {
        model = SampleRecord.model()
        preferences = Preferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    /// Fill every model, and return self so a preview can be a single expression.
    @discardableResult
    func load() -> PreviewWorld {
        history.reload()
        apps.load()
        memories.load()
        collections.load()
        week.load()
        projects.load()
        story.load()
        overlays.load()
        contextual.load()
        return self
    }
}
#endif
