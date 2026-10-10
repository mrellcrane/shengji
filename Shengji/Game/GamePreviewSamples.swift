#if DEBUG
import SwiftUI
import ShengjiCore

/// Static sample content for the Play tab's Xcode previews (no engine calls, so they render
/// even while parts of the core are unfinished).
@MainActor
enum GamePreviewSamples {
    static let trump = Trump(rank: .two, suit: .hearts)

    static func banners() -> some View {
        VStack(spacing: 12) {
            GameCoachBannerView(message: GameCoachMessage("Partner wins with A♠, the highest spade. Defenders +10.",
                                                          concept: "Highest card"))
            GameCoachBannerView(message: GameCoachMessage("Partner is winning, so give them your **K♠** for 10 points.",
                                                          concept: "Feed points", kind: .hint))
            GameCoachBannerView(message: GameCoachMessage("You still have a spade, so you must follow suit.",
                                                          concept: "Follow suit", kind: .warning))
            GameCoachBannerView(message: GameCoachMessage("Yes, well spotted! East ruffs with 3♥, a trump.",
                                                          concept: "Ruff", kind: .success))
            GamePredictionPanel { _ in }
            GameCoachBannerView(message: nil)
        }
        .padding()
        .background(GameFeltBackground())
    }

    static func playSlots() -> some View {
        HStack(spacing: 20) {
            GamePlaySlot(cards: [Card(.ace, .spades)], trump: trump, markTrumps: true, isWinner: true,
                         isLeading: false, cardWidth: 44, maxWidth: 120)
            GamePlaySlot(cards: [Card(.seven, .hearts), Card(.seven, .hearts, copy: 1)], trump: trump, markTrumps: true,
                         isWinner: false, isLeading: true, cardWidth: 44, maxWidth: 120)
        }
        .padding()
        .background(GameFeltBackground())
    }

    static var summary: RoundSummary {
        let kitty = [Card(.five, .clubs), Card(.three, .spades), Card(.four, .diamonds), Card(.six, .clubs),
                     Card(.ten, .diamonds), Card(.seven, .spades), Card(.eight, .clubs), Card(.nine, .diamonds)]
        let outcome = LevelOutcome(declarersHold: false, levels: 0,
                                   summary: "Defenders scored 95 (80 or more): they take over the deal.")
        let result = RoundResult(dealer: 1, declarerTeam: 1, trump: trump, trickPoints: 35, kittyPoints: 15,
                                 kittyMultiplier: 4, defenderPoints: 95, outcome: outcome, kitty: kitty,
                                 lastTrickWinner: 2)
        return RoundSummary(result: result, advancingTeam: nil, levelsGained: 0, levelsBefore: [.two, .two],
                            levelsAfter: [.two, .two], nextDealer: 2, gameWinner: nil,
                            explanation: "You and Partner won the last trick with a pair, so the kitty counted four times. That took you past 80.")
    }

    static func roundResult() -> some View {
        RoundResultView(summary: summary, roundNumber: 1, isDemo: true,
                        onNextRound: {}, onNewGame: {}, onViewTable: {}, onLeave: {})
            .background(GameFeltBackground())
    }
}
#endif
