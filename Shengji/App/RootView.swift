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

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        #if DEBUG
        let _ = DebugRender.enabled ? Self._printChanges() : ()
        #endif
        tabs(dueCount: store.dueCount(now: router.now))
            .environment(router)
            .task {
                // Keep "now" fresh so the Review badge picks up items as they fall due.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    router.now = .now
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { router.now = .now }
            }
            // Items scheduled just now (a lesson passed, a review answered) count at once, not after the next tick.
            .onChange(of: store.progress.schedules) {
                router.now = .now
            }
            // A tapped notification for an online game opens it in the Play tab.
            .modifier(OnlineShowsPlayTab {
                if router.selectedTab != .play { router.show(.play) }
            })
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

    /// Play-tab scenes (`game`, `dealing`, `result`, `coach`, `achievements`) are handled by the Play tab.
    private var playScene: DemoScene? {
        guard let scene, scene.isGameScene else { return nil }
        return scene
    }

    // Demo scenes open their lesson or practice session full screen over the tab root, exactly as a
    // tap would, so the screenshot matches real use and closing it lands back on the tab.

    private var learnTab: some View {
        LessonPathView(initialLesson: demoLesson)
    }

    private var reviewTab: some View {
        ReviewView(initialPractice: demoPractice)
    }

    /// `lesson`: lesson 4 at a page with cards. `predict`: a "your turn" page, already answered.
    private var demoLesson: LessonLaunch? {
        let demo: LearnDemoLessonPage?
        switch scene {
        case .lesson?: demo = LearnDemoData.lessonPage()
        case .predict?: demo = LearnDemoData.predictPage()
        default: demo = nil
        }
        return demo.map { LessonLaunch(lesson: $0.lesson, startPage: $0.page, demoAnswer: $0.answer) }
    }

    /// `quiz`: a seeded "who wins the trick?" practice with the first question answered wrongly.
    private var demoPractice: PracticeLaunch? {
        guard scene == .quiz else { return nil }
        return PracticeLaunch(kind: .freePractice(skills: [.trickWinner]), seed: LearnDemoData.quizSeed,
                              answerFirstQuestionWrongly: true)
    }
}
