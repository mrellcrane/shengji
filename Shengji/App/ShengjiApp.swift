import SwiftUI
import ShengjiCore

@main
@MainActor
struct ShengjiApp: App {
    /// Push notifications for online games (device token, notification taps).
    @UIApplicationDelegateAdaptor(ShengjiAppDelegate.self) private var appDelegate
    /// Demo / screenshot scenes use ephemeral stores, so they never touch saved progress.
    @State private var store: LearningStore
    @State private var achievements: AchievementStore
    /// Online play: the real server, or the in-memory demo server in screenshot scenes.
    @State private var online: OnlineSession

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
        _online = State(initialValue: OnlineSession.forLaunch(scene: scene))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(achievements)
                .environment(online)
                .task { await online.launch() }
        }
    }
}
