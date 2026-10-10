import SwiftUI
import ShengjiCore

@main
@MainActor
struct ShengjiApp: App {
    /// Demo / screenshot scenes use an ephemeral store, so they never touch saved progress.
    @State private var store: LearningStore

    init() {
        let scene = DemoScene.current
        let store = LearningStore(ephemeral: scene != nil)
        if scene != nil {
            // A realistic mid-course learner, so every scene has something to show.
            store.replaceProgress(LearnDemoData.sampleProgress())
        }
        _store = State(initialValue: store)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}
