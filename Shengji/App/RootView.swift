import SwiftUI
import ShengjiCore

/// The four tabs: Learn, Review (badged with the due count), Play and Rules.
/// Child views switch tabs through the `AppRouter` in the environment.
/// With `-ScreenshotScene <name>` the matching tab opens straight into that scene.
@MainActor
struct RootView: View {
    @Environment(LearningStore.self) private var store
    @State private var router = AppRouter(initialTab: DemoScene.current?.tab ?? .learn)

    private let scene = DemoScene.current

    var body: some View {
        // Re-evaluated every minute so the Review badge picks up items as they fall due.
        TimelineView(.everyMinute) { context in
            tabs(dueCount: store.dueCount(now: context.date))
        }
        .environment(router)
    }

    private func tabs(dueCount: Int) -> some View {
        TabView(selection: $router.selectedTab) {
            learnTab
                .tabItem { Label("Learn", systemImage: "graduationcap") }
                .tag(AppTab.learn)
            reviewTab
                .tabItem { Label("Review", systemImage: "arrow.triangle.2.circlepath") }
                .badge(dueCount)
                .tag(AppTab.review)
            PlayHomeView(demoScene: playScene)
                .tabItem { Label("Play", systemImage: "suit.spade.fill") }
                .tag(AppTab.play)
            RulesView()
                .tabItem { Label("Rules", systemImage: "book") }
                .tag(AppTab.rules)
        }
    }

    /// Game scenes (`game`, `dealing`, `result`) are handled by the Play tab.
    private var playScene: DemoScene? {
        guard let scene, scene.isGameScene else { return nil }
        return scene
    }

    @ViewBuilder private var learnTab: some View {
        if scene == .lesson, let demo = LearnDemoData.lessonPage() {
            LessonView(demo.lesson, startPage: demo.page)
        } else if scene == .predict, let demo = LearnDemoData.predictPage() {
            LessonView(demo.lesson, startPage: demo.page, demoAnswer: demo.answer)
        } else {
            LessonPathView()
        }
    }

    @ViewBuilder private var reviewTab: some View {
        if scene == .quiz {
            PracticeView(kind: .freePractice(skills: [.trickWinner]), seed: LearnDemoData.quizSeed,
                         answerFirstQuestionWrongly: true)
        } else {
            ReviewView()
        }
    }
}
