import Foundation
import ShengjiCore

/// Deterministic tables for CI screenshots (`-ScreenshotScene game|dealing|result|game6|game8`).
/// Built by driving the real engine and bots from seed 7 (a bot plays your seat where needed),
/// entirely in memory: demo controllers never save and never touch the saved game.
extension GameController {
    static let demoSeed: UInt64 = 7

    /// Seed 7 first. Later seeds are only a safety net in case seed 7 never reaches the wanted moment.
    private static var demoSeeds: [UInt64] { [demoSeed] + (8...40).map { UInt64($0) } }

    /// The table for a Play-tab demo scene (nil for scenes of other tabs).
    static func demo(_ scene: DemoScene) -> GameController? {
        switch scene {
        case .game, .coach: return playingDemo()
        case .game6: return playingDemo(table: .six)
        case .game8: return playingDemo(table: .eight)
        case .dealing: return dealingDemo()
        case .result: return resultDemo()
        case .learn, .lesson, .predict, .review, .quiz, .rules, .achievements, .online, .onlineGame: return nil
        }
    }

    private static func demoTable(seed: UInt64, table: TableSize = .four) -> GameController {
        let controller = GameController.newGame(settings: GameSettings(table: table), seed: seed, persistence: nil,
                                                isDemo: true, coachLevel: .guided)
        controller.predictionsEnabled = false
        controller.speed = .normal
        return controller
    }

    /// Mid-round, at least 3 tricks done, your turn with 1 or 2 bot plays on the table, Guided, a hint shown
    /// (the ladder's second step, so the concept tag shows and the button offers "Show me").
    static func playingDemo(table: TableSize = .four) -> GameController {
        var last: GameController?
        for seed in demoSeeds {
            let controller = demoTable(seed: seed, table: table)
            controller.botSeats = Set(controller.seats)
            controller.advanceSynchronously { $0.isPlayingDemoMoment }
            controller.botSeats = Set(controller.seats.dropFirst())
            last = controller
            if controller.isPlayingDemoMoment {
                controller.coachLevel = .guided
                controller.showHint()
                controller.showHint()
                controller.predictionsEnabled = true
                return controller
            }
        }
        return last ?? demoTable(seed: demoSeed, table: table)
    }

    /// Your turn after a few tricks with some plays on the table (1 or 2 at a table of four; at bigger
    /// tables at least 3, so the seats round the table show their cards).
    var isPlayingDemoMoment: Bool {
        let plays = players == 4 ? 1...2 : 3...(players - 1)
        return stage == .playing && round.tricks.count >= 3 && round.turn == Seats.human
            && plays.contains(round.currentTrick.count)
    }

    /// About 60 cards dealt, you can declare (so the declare buttons show), dealing paused.
    static func dealingDemo() -> GameController {
        for seed in demoSeeds {
            guard let target = dealingDemoTarget(seed: seed) else { continue }
            let controller = demoTable(seed: seed)
            controller.advanceSynchronously { $0.dealtCount >= target || $0.stage != .dealing }
            guard controller.stage == .dealing, !controller.availableDeclarations.isEmpty else { continue }
            controller.autoplayPaused = true
            return controller
        }
        let controller = demoTable(seed: demoSeed)
        controller.advanceSynchronously { $0.dealtCount >= 60 || $0.stage != .dealing }
        controller.autoplayPaused = true
        return controller
    }

    /// The number of dealt cards closest to 60 at which you hold a declaration (bots declare as usual).
    private static func dealingDemoTarget(seed: UInt64) -> Int? {
        let probe = demoTable(seed: seed)
        var best: Int?
        while probe.stage == .dealing {
            guard probe.advanceSynchronously(maxSteps: 1) == 1 else { break }
            let dealt = probe.dealtCount
            guard probe.stage == .dealing, !probe.availableDeclarations.isEmpty else { continue }
            if let current = best {
                if abs(dealt - 60) < abs(current - 60) { best = dealt }
            } else {
                best = dealt
            }
        }
        return best
    }

    /// A finished first round with the result shown.
    static func resultDemo() -> GameController {
        let controller = demoTable(seed: demoSeed)
        controller.botSeats = Set(Seats.all)
        controller.advanceSynchronously()
        controller.botSeats = [1, 2, 3]
        return controller
    }
}
