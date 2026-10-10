import SwiftUI
import ShengjiCore

@main
@MainActor
struct ShengjiApp: App {
    /// Demo / screenshot scenes use ephemeral stores, so they never touch saved progress.
    @State private var store: LearningStore
    @State private var achievements: AchievementStore

    init() {
        let scene = DemoScene.current
        let store = LearningStore(ephemeral: scene != nil)
        let achievements = AchievementStore(ephemeral: scene != nil)
        if scene != nil {
            // A realistic mid-course learner, so every scene has something to show.
            store.replaceProgress(LearnDemoData.sampleProgress())
            achievements.replaceProgress(AchievementDemoData.sampleProgress(learner: store.progress))
        } else {
            achievements.syncLearning(store.progress)
        }
        // Lessons, reviews and streaks count towards the Journey badges as they happen.
        store.onProgressChange = { [weak achievements] progress in
            achievements?.syncLearning(progress)
        }
        _store = State(initialValue: store)
        _achievements = State(initialValue: achievements)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(achievements)
        }
    }
}
