import Foundation
import ShengjiCore

/// Sample achievements for demo / screenshot scenes, built through `AchievementProgress`'s public API
/// with past dates. It only ever goes into the ephemeral store.
enum AchievementDemoData {
    /// A few evenings of play: plenty of ruffs and fed points, a held deal or two, one game won,
    /// and the journey counts of `learner` (the demo learner from `LearnDemoData`).
    static func sampleProgress(learner: LearnerProgress, now: Date = .now) -> AchievementProgress {
        var progress = AchievementProgress()
        func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        let moves: [(kind: MoveKind, detail: String, points: Int, hoursAgo: Double)] = [
            (.declareTrump, "You declared hearts as trump with 2♥.", 0, 76),
            (.ruff, "Ruff! You trumped West's club lead and won 10 points.", 10, 75),
            (.feedPartner, "You gave Partner your K♦ while they were winning. +10 for your team.", 10, 74),
            (.topCard, "Your A♠ held: nobody could beat it.", 0, 73),
            (.holdDeal, "You and Partner kept the defenders to 45.", 0, 72),
            (.ruff, "Ruff! You trumped East's spade lead and won 15 points.", 15, 52),
            (.topCard, "Your A♣ held: nobody could beat it.", 0, 51),
            (.feedPartner, "You gave Partner your 10♣ while they were winning. +10 for your team.", 10, 50),
            (.tractor, "You led a tractor: 7♦7♦8♦8♦.", 0, 49),
            (.ruff, "Ruff! You trumped East's diamond lead and won 20 points.", 20, 48),
            (.declareTrump, "You declared spades as trump with a pair of 3♠.", 0, 30),
            (.bigJoker, "Your big joker took the trick.", 15, 29),
            (.ruff, "Ruff! You trumped West's heart lead and won 5 points.", 5, 28),
            (.feedPartner, "You gave Partner your 5♥ while they were winning. +5 for your team.", 5, 27),
            (.bigTrick, "Your team won a 35-point trick.", 35, 26),
            (.topCard, "Your A♥ held: nobody could beat it.", 0, 25),
            (.holdDeal, "You and Partner kept the defenders to 60.", 0, 24),
            (.ruff, "Ruff! You trumped East's spade lead and won 10 points.", 10, 5),
            (.overruff, "Overruff! East ruffed, and your higher trump took the trick.", 10, 4),
            (.feedPartner, "You gave Partner your K♠ while they were winning. +10 for your team.", 10, 3),
            (.ruff, "Ruff! You trumped West's diamond lead and won 15 points.", 15, 2),
        ]
        for move in moves {
            _ = progress.record([MoveEvent(kind: move.kind, detail: move.detail, points: move.points)],
                                now: hoursAgo(move.hoursAgo))
        }
        _ = progress.recordGameProgress(teamLevel: .four, wonGame: false, now: hoursAgo(72))
        _ = progress.recordGameProgress(teamLevel: .five, wonGame: true, now: hoursAgo(24))
        _ = progress.recordGameProgress(teamLevel: .six, wonGame: false, now: hoursAgo(2))
        _ = progress.syncLearning(learner, now: hoursAgo(1))
        return progress
    }
}
