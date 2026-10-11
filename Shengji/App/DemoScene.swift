import Foundation

/// Deterministic scenes for CI screenshots: launch with `-ScreenshotScene <rawValue>`.
/// Without the argument `DemoScene.current` is nil and the app starts normally.
enum DemoScene: String, CaseIterable {
    case learn, lesson, predict, review, quiz, game, dealing, result, rules
    /// The `game` table with the coach sheet open on a canned chat (never touches the network).
    case coach
    /// The Play tab's achievements screen with sample progress.
    case achievements
    /// Play online: the online home with sample clubs and games (demo server, never the network).
    case online
    /// An online table mid-play from the demo server (a seeded round's seat view).
    case onlineGame
    /// The `game` table with 6 players (3 decks) and with 8 players (4 decks).
    case game6, game8

    static var current: DemoScene? {
        UserDefaults.standard.string(forKey: "ScreenshotScene").flatMap(DemoScene.init(rawValue:))
    }

    /// Which tab the scene lives in.
    var tab: AppTab {
        switch self {
        case .learn, .lesson, .predict: return .learn
        case .review, .quiz: return .review
        case .game, .dealing, .result, .coach, .achievements, .online, .onlineGame, .game6, .game8: return .play
        case .rules: return .rules
        }
    }

    /// Scenes that belong to the Play tab (handled by `PlayHomeView(demoScene:)`).
    var isGameScene: Bool { tab == .play }
}

/// The app's four tabs.
enum AppTab: String, Hashable, CaseIterable {
    case learn, review, play, rules
}
