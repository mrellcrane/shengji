import Foundation
import XCTest
@testable import ShengjiCore

final class MoveDetectorTests: XCTestCase {
    private typealias Kit = CoachTestKit
    private let trump = CoachTestKit.heartsTwo

    private func c(_ rank: Rank, _ suit: Suit, _ copy: Int = 0) -> Card { Card(rank, suit, copy: copy) }
    private func pair(_ rank: Rank, _ suit: Suit) -> [Card] { Kit.pair(rank, suit) }
    private func p(_ seat: Int, _ cards: [Card]) -> Play { Play(player: seat, cards: cards) }

    /// Moves for `player` in one hand-built trick (hearts trump, rank 2).
    private func moves(_ plays: [Play], player: Int = Seats.human) -> [MoveEvent] {
        let trick = Kit.trick(plays, trump: trump)
        if player == Seats.human {
            // The public seat-view entry point (online play) and the internal one agree.
            let view = Kit.view(tricks: [trick])
            let viaView = MoveDetector.moves(inTrick: 0, of: view)
            XCTAssertEqual(viaView, MoveDetector.trickMoves(trick, trump: trump, player: player))
            return viaView
        }
        return MoveDetector.trickMoves(trick, trump: trump, player: player)
    }

    private func kinds(_ events: [MoveEvent]) -> [MoveKind] { events.map(\.kind) }

    // MARK: Ruff and overruff

    func testRuffWinsAPlainLeadWithTrump() {
        let events = moves([p(1, [c(.king, .spades)]), p(2, [c(.three, .spades)]), p(3, [c(.five, .spades)]), p(0, [c(.four, .hearts)])])
        XCTAssertEqual(kinds(events), [.ruff])
        XCTAssertEqual(events.first?.detail, "Ruff! You trumped East's spade lead and won 15 points.")
        XCTAssertEqual(events.first?.points, 15)

        let noPoints = moves([p(3, [c(.nine, .clubs)]), p(0, [c(.two, .diamonds)]), p(1, [c(.three, .clubs)]), p(2, [c(.four, .clubs)])])
        XCTAssertEqual(noPoints.first?.detail, "Ruff! You trumped West's club lead and took the trick.")
    }

    func testTrumpLeadWonByTrumpIsNotARuff() {
        let events = moves([p(1, [c(.three, .hearts)]), p(2, [c(.four, .hearts)]), p(3, [c(.six, .hearts)]), p(0, [c(.ace, .hearts)])])
        XCTAssertEqual(kinds(events), [])
    }

    func testRuffThatGetsOvertrumpedIsNotARuff() {
        let events = moves([p(1, [c(.king, .spades)]), p(2, [c(.three, .spades)]), p(3, [c(.four, .hearts)]), p(0, [c(.three, .hearts)])])
        XCTAssertEqual(kinds(events), [])
        // For West it is a ruff (of their own partner's lead).
        XCTAssertEqual(kinds(moves([p(1, [c(.king, .spades)]), p(2, [c(.three, .spades)]), p(3, [c(.four, .hearts)]),
                                    p(0, [c(.three, .hearts)])], player: 3)), [.ruff])
    }

    func testMismatchedTrumpsOnAPairLeadAreNotARuff() {
        let events = moves([p(1, pair(.nine, .spades)), p(2, [c(.three, .spades), c(.four, .spades)]),
                            p(3, [c(.five, .spades), c(.six, .spades)]), p(0, [c(.four, .hearts), c(.seven, .hearts)])])
        XCTAssertEqual(kinds(events), [])
    }

    func testOverruffBeatsAnOpponentsRuff() {
        let plays = [p(1, [c(.ace, .clubs)]), p(2, [c(.king, .clubs)]), p(3, [c(.four, .hearts)]), p(0, [c(.nine, .hearts)])]
        let events = moves(plays)
        XCTAssertEqual(kinds(events), [.overruff], "an overruff is reported instead of a plain ruff")
        XCTAssertEqual(events.first?.detail, "Overruff! West trumped the club lead, but your higher trump took the trick and 10 points.")
        // Partner's K♣ went into your winning trick: a feed for Partner.
        XCTAssertEqual(kinds(moves(plays, player: 2)), [.feedPartner])
    }

    func testOvertrumpingYourPartnerIsAPlainRuff() {
        let events = moves([p(1, [c(.ace, .clubs)]), p(2, [c(.four, .hearts)]), p(3, [c(.five, .clubs)]), p(0, [c(.nine, .hearts)])])
        XCTAssertEqual(kinds(events), [.ruff])
    }

    func testOpponentsMismatchedTrumpsDontMakeAnOverruff() {
        let events = moves([p(1, pair(.nine, .clubs)), p(2, [c(.three, .clubs), c(.four, .clubs)]),
                            p(3, [c(.four, .hearts), c(.seven, .hearts)]), p(0, pair(.six, .hearts))])
        XCTAssertEqual(kinds(events), [.ruff])
    }

    // MARK: Feeding

    func testFeedingYourPartner() {
        let fed = moves([p(1, [c(.three, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.four, .spades)]), p(0, [c(.king, .spades)])])
        XCTAssertEqual(kinds(fed), [.feedPartner])
        XCTAssertEqual(fed.first?.detail, "Point feed! You gave Partner 10 points (K♠) in a trick they won.")
        XCTAssertEqual(fed.first?.points, 10)

        let five = moves([p(1, [c(.three, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.four, .spades)]), p(0, [c(.five, .spades)])])
        XCTAssertEqual(kinds(five), [.feedPartner])
        XCTAssertEqual(five.first?.points, 5)

        // No points, or the opponents won, or you led: not a feed.
        XCTAssertEqual(kinds(moves([p(1, [c(.three, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.four, .spades)]), p(0, [c(.six, .spades)])])), [])
        XCTAssertEqual(kinds(moves([p(1, [c(.ace, .spades)]), p(2, [c(.three, .spades)]), p(3, [c(.four, .spades)]), p(0, [c(.king, .spades)])])), [])
        XCTAssertEqual(kinds(moves([p(0, [c(.king, .spades)]), p(1, [c(.three, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.four, .spades)])])), [])
    }

    func testForcedPointsStillCountAsAFeed() {
        // Your only spade was the 10♠, so you had to play it. Partner won, so the points reached your team.
        let events = moves([p(1, [c(.three, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.four, .spades)]), p(0, [c(.ten, .spades)])])
        XCTAssertEqual(kinds(events), [.feedPartner])
    }

    // MARK: Tractors, throws, top cards

    func testLeadingATractor() {
        let lost = moves([p(0, pair(.seven, .spades) + pair(.eight, .spades)), p(1, pair(.nine, .spades) + pair(.ten, .spades)),
                          p(2, [c(.three, .spades), c(.four, .spades), c(.six, .spades), c(.jack, .spades)]),
                          p(3, [c(.three, .clubs), c(.four, .clubs), c(.six, .clubs), c(.jack, .clubs)])])
        XCTAssertEqual(kinds(lost), [.tractor])
        XCTAssertEqual(lost.first?.detail, "Tractor! You led 7♠ 7♠ 8♠ 8♠.")
        XCTAssertEqual(lost.first?.points, 0)

        let won = moves([p(0, pair(.nine, .spades) + pair(.ten, .spades)),
                         p(1, [c(.three, .spades), c(.four, .spades), c(.five, .spades), c(.six, .spades)]),
                         p(2, [c(.three, .clubs), c(.four, .clubs), c(.six, .clubs), c(.jack, .clubs)]),
                         p(3, [c(.three, .diamonds), c(.four, .diamonds), c(.six, .diamonds), c(.jack, .diamonds)])])
        XCTAssertEqual(kinds(won), [.tractor, .topCard])
        XCTAssertEqual(won.first?.detail, "Tractor! You led 9♠ 9♠ 10♠ 10♠ and won 25 points.")
    }

    func testWinningATractorLeadWithATrumpTractor() {
        let events = moves([p(1, pair(.three, .spades) + pair(.four, .spades)),
                            p(2, [c(.six, .spades), c(.seven, .spades), c(.eight, .spades), c(.nine, .spades)]),
                            p(3, [c(.jack, .spades), c(.queen, .spades), c(.king, .spades), c(.ace, .spades)]),
                            p(0, pair(.five, .hearts) + pair(.six, .hearts))])
        XCTAssertEqual(kinds(events), [.ruff, .tractor])
        XCTAssertEqual(events[1].detail, "Tractor! Your 5♥ 5♥ 6♥ 6♥ beat East's tractor lead and won 20 points.")
        // Following a tractor lead without winning is nothing (here Partner wins and you add no points).
        XCTAssertEqual(kinds(moves([p(1, pair(.three, .spades) + pair(.four, .spades)), p(2, pair(.five, .hearts) + pair(.six, .hearts)),
                                    p(3, [c(.jack, .spades), c(.queen, .spades), c(.king, .spades), c(.ace, .spades)]),
                                    p(0, pair(.six, .spades) + pair(.seven, .spades))])), [])
    }

    func testCleanThrowStandsEvenIfRuffed() {
        let throwCards = [c(.ace, .spades)] + pair(.king, .spades)
        let won = moves([p(0, throwCards), p(1, [c(.three, .spades), c(.four, .spades), c(.five, .spades)]),
                         p(2, [c(.six, .spades), c(.seven, .spades), c(.eight, .spades)]),
                         p(3, [c(.three, .clubs), c(.four, .clubs), c(.six, .clubs)])])
        XCTAssertEqual(kinds(won), [.cleanThrow], "a throw is not a single top card")
        XCTAssertEqual(won.first?.detail, "Clean throw! Your K♠ K♠ A♠ stood: nobody could beat any part of it. You won 25 points.")

        // East trumps the whole throw with a matching pair and single: the throw still stood.
        let ruffedPlays = [p(0, throwCards), p(1, pair(.three, .hearts) + [c(.four, .hearts)]),
                           p(2, [c(.six, .spades), c(.seven, .spades), c(.eight, .spades)]),
                           p(3, [c(.three, .clubs), c(.four, .clubs), c(.six, .clubs)])]
        let ruffed = moves(ruffedPlays)
        XCTAssertEqual(kinds(ruffed), [.cleanThrow])
        XCTAssertEqual(ruffed.first?.points, 0)
        XCTAssertEqual(kinds(moves(ruffedPlays, player: 1)), [.ruff])
    }

    func testTopCard() {
        let events = moves([p(0, [c(.ace, .diamonds)]), p(1, [c(.three, .diamonds)]), p(2, [c(.five, .diamonds)]), p(3, [c(.four, .diamonds)])])
        XCTAssertEqual(kinds(events), [.topCard])
        XCTAssertEqual(events.first?.detail, "Top card! Nobody could beat your A♦, and it won 5 points.")
        let quiet = moves([p(0, [c(.ace, .diamonds)]), p(1, [c(.three, .diamonds)]), p(2, [c(.six, .diamonds)]), p(3, [c(.four, .diamonds)])])
        XCTAssertEqual(quiet.first?.detail, "Top card! Nobody could beat your A♦, so you keep the lead.")
        // A trump lead is not a top card; a ruffed ace is not either.
        XCTAssertEqual(kinds(moves([p(0, [c(.ace, .hearts)]), p(1, [c(.three, .hearts)]), p(2, [c(.five, .hearts)]), p(3, [c(.four, .hearts)])])), [])
        XCTAssertEqual(kinds(moves([p(0, [c(.ace, .diamonds)]), p(1, [c(.three, .diamonds)]), p(2, [c(.six, .diamonds)]), p(3, [c(.three, .hearts)])])), [])
        // Pair leads count too.
        XCTAssertEqual(kinds(moves([p(0, pair(.queen, .clubs)), p(1, [c(.three, .clubs), c(.four, .clubs)]),
                                    p(2, [c(.six, .clubs), c(.seven, .clubs)]), p(3, [c(.eight, .clubs), c(.nine, .clubs)])])), [.topCard])
    }

    // MARK: Big joker and big tricks

    func testBigJoker() {
        let events = moves([p(1, [c(.three, .hearts)]), p(2, [c(.five, .hearts)]), p(3, [c(.four, .hearts)]), p(0, [Card.bigJoker()])])
        XCTAssertEqual(kinds(events), [.bigJoker])
        XCTAssertEqual(events.first?.detail, "Big joker! Your BJ took the trick and 5 points.")
        // A big joker that can't win (wrong shape on a pair lead) is nothing.
        XCTAssertEqual(kinds(moves([p(1, pair(.three, .spades)), p(2, [c(.five, .spades), c(.six, .spades)]),
                                    p(3, [c(.seven, .spades), c(.eight, .spades)]), p(0, [Card.bigJoker(), c(.three, .hearts)])])), [])
        // Ruffing a plain lead with the big joker is both.
        XCTAssertEqual(kinds(moves([p(1, [c(.king, .clubs)]), p(2, [c(.five, .clubs)]), p(3, [c(.four, .clubs)]), p(0, [Card.bigJoker()])])),
                       [.ruff, .bigJoker])
    }

    func testBigTrickForYourTeam() {
        let plays = [p(1, [c(.king, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.ten, .spades)]), p(0, [c(.ten, .spades, 1)])]
        let events = moves(plays)
        XCTAssertEqual(kinds(events), [.feedPartner, .bigTrick])
        XCTAssertEqual(events[1].detail, "Big trick! Partner won a trick worth 30 points for your team.")
        XCTAssertEqual(events[1].points, 30)
        // For the opponents, nothing.
        XCTAssertEqual(kinds(moves(plays, player: 1)), [])
        // 25 points is not a big trick.
        XCTAssertEqual(kinds(moves([p(1, [c(.king, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.ten, .spades)]), p(0, [c(.five, .spades)])])),
                       [.feedPartner])
    }

    func testMissingPlayerOrTrickGivesNothing() throws {
        let trick = Kit.trick([p(1, [c(.king, .spades)]), p(2, [c(.ace, .spades)]), p(3, [c(.ten, .spades)])])
        XCTAssertEqual(MoveDetector.trickMoves(trick, trump: trump, player: 0), [])
        XCTAssertEqual(MoveDetector.trickMoves(TrickRecord(plays: [], winner: 0, points: 0), trump: trump, player: 0), [])
        let deck = EngineTestSupport.deck(seed: 1)
        let round = Round(trumpRank: .two, dealer: 0, deck: deck)
        XCTAssertEqual(MoveDetector.moves(inTrick: 0, of: round), [])
        XCTAssertEqual(MoveDetector.moves(inTrick: -1, of: round), [])
        XCTAssertEqual(MoveDetector.moves(inFinishedRound: round), [])
        XCTAssertEqual(MoveDetector.moves(inDeclarationsOf: round), [])
    }

    // MARK: Round end

    private func result(dealer: Int, defenders: Int, kittyPoints: Int = 0, lastWinner: Int, lastLeadCards: Int = 1) -> RoundResult {
        let defendersWonLast = Seats.team(of: lastWinner) != Seats.team(of: dealer)
        let multiplier = defendersWonLast ? 2 * lastLeadCards : 0
        return RoundResult(dealer: dealer, declarerTeam: Seats.team(of: dealer), trump: trump,
                           trickPoints: defenders - kittyPoints * multiplier, kittyPoints: kittyPoints, kittyMultiplier: multiplier,
                           defenderPoints: defenders, outcome: Scoring.outcome(defenderPoints: defenders), kitty: [],
                           lastTrickWinner: lastWinner)
    }

    private func roundEnd(_ result: RoundResult) -> [MoveEvent] {
        MoveDetector.moves(inFinishedRoundOf: Kit.view(phase: .finished, dealer: result.dealer, turn: nil, result: result))
    }

    func testHoldingAndShuttingOut() {
        let held = roundEnd(result(dealer: 0, defenders: 45, lastWinner: 2))
        XCTAssertEqual(kinds(held), [.holdDeal])
        XCTAssertEqual(held.first?.detail, "Deal held! The defenders scored 45, under 80, so your team keeps the deal.")
        XCTAssertEqual(held.first?.points, 45)

        let shutout = roundEnd(result(dealer: 2, defenders: 0, lastWinner: 0))
        XCTAssertEqual(kinds(shutout), [.holdDeal, .shutout])
        XCTAssertEqual(shutout[1].detail, "Shutout! The defenders scored nothing: the biggest win a declaring team can have.")

        // The opponents held: nothing for you, and holdDeal for them.
        let theirs = result(dealer: 1, defenders: 30, lastWinner: 3)
        XCTAssertEqual(kinds(roundEnd(theirs)), [])
        XCTAssertEqual(kinds(MoveDetector.roundMoves(theirs, player: 3)), [.holdDeal])
    }

    func testTakingOverAndRaidingTheKitty() {
        let raid = roundEnd(result(dealer: 1, defenders: 95, kittyPoints: 10, lastWinner: 2, lastLeadCards: 2))
        XCTAssertEqual(kinds(raid), [.kittyRaid, .takeOver])
        XCTAssertEqual(raid[0].detail, "Kitty raid! Your team won the last trick, so the kitty's 10 points counted ×4: 40 bonus points.")
        XCTAssertEqual(raid[0].points, 40)
        XCTAssertEqual(raid[1].detail, "Take over! Your team scored 95, so you take over the deal.")

        let raidOnly = roundEnd(result(dealer: 3, defenders: 60, kittyPoints: 0, lastWinner: 0))
        XCTAssertEqual(kinds(raidOnly), [.kittyRaid])
        XCTAssertTrue(raidOnly[0].detail.contains("held no points"))

        let bigTakeOver = roundEnd(result(dealer: 1, defenders: 165, lastWinner: 1))
        XCTAssertEqual(kinds(bigTakeOver), [.takeOver])
        XCTAssertEqual(bigTakeOver[0].detail, "Take over! Your team scored 165, so you take over the deal.")

        // Declarers who lose the last trick get no raid; defenders who lose it neither.
        XCTAssertEqual(kinds(roundEnd(result(dealer: 0, defenders: 50, lastWinner: 1))), [.holdDeal])
        XCTAssertEqual(kinds(roundEnd(result(dealer: 1, defenders: 50, lastWinner: 3))), [])
    }

    func testRoundEndNeedsAFinishedRound() {
        let finished = result(dealer: 0, defenders: 45, lastWinner: 2)
        let notFinished = Kit.view(phase: .playing, dealer: 0, result: finished)
        XCTAssertEqual(MoveDetector.moves(inFinishedRoundOf: notFinished), [])
    }

    // MARK: Declarations

    func testDeclarationsAndOverrides() throws {
        let human = [c(.two, .hearts), Card.smallJoker(copy: 0), Card.smallJoker(copy: 1)]
        let east = pair(.two, .spades)
        let deck = EngineTestSupport.deck(hands: [human, east, [], []], firstSeat: 0, seed: 15)
        var round = Round(trumpRank: .two, dealer: nil, deck: deck)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [human[0]], suit: .hearts, strength: 1))
        try round.declare(Declaration(player: 1, cards: east, suit: .spades, strength: 2))
        XCTAssertEqual(MoveDetector.moves(inDeclarationsOf: round), [], "nothing while dealing is still open")
        try round.declare(Declaration(player: 0, cards: Array(human[1...2]), suit: nil, strength: 3))
        round.finishDealing()

        let mine = MoveDetector.moves(inDeclarationsOf: round)
        XCTAssertEqual(kinds(mine), [.declareTrump, .overrideDeclaration])
        XCTAssertEqual(mine[0].detail, "Trump declared! Your pair of small jokers made this a no-trump round.")
        XCTAssertEqual(mine[1].detail, "Override! You beat East's ♠ declaration with a pair of small jokers.")
        let easts = MoveDetector.moves(inDeclarationsOf: round, player: 1)
        XCTAssertEqual(kinds(easts), [.overrideDeclaration])
        XCTAssertEqual(kinds(MoveDetector.moves(inDeclarationsOf: round, player: 2)), [])
        // Seat view path agrees for the human.
        XCTAssertEqual(MoveDetector.moves(inDeclarationsOf: round.seatView(for: 0)), mine)
    }

    func testOverridingYourPartnerIsNotAnOverride() throws {
        let human = [c(.two, .hearts)]
        let partner = pair(.two, .diamonds)
        let deck = EngineTestSupport.deck(hands: [human, [], partner, []], firstSeat: 0, seed: 16)
        var round = Round(trumpRank: .two, dealer: 0, deck: deck)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: human, suit: .hearts, strength: 1))
        try round.declare(Declaration(player: 2, cards: partner, suit: .diamonds, strength: 2))
        round.finishDealing()
        XCTAssertEqual(kinds(MoveDetector.moves(inDeclarationsOf: round)), [])
        let partners = MoveDetector.moves(inDeclarationsOf: round, player: 2)
        XCTAssertEqual(kinds(partners), [.declareTrump])
        XCTAssertEqual(partners.first?.detail, "Trump declared! Your pair of 2♦ made diamonds trump this round.")
    }

    func testSingleDeclarationAndKittyFlip() throws {
        let human = [c(.five, .clubs)]
        var round = Round(trumpRank: .five, dealer: nil, deck: EngineTestSupport.deck(hands: [human, [], [], []], seed: 17))
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: human, suit: .clubs, strength: 1))
        round.finishDealing()
        XCTAssertEqual(MoveDetector.moves(inDeclarationsOf: round).map(\.detail), ["Trump declared! Your 5♣ made clubs trump this round."])

        var flip = Round(trumpRank: .five, dealer: nil, deck: EngineTestSupport.deck(seed: 18))
        flip.dealAll()
        flip.finishDealing()
        XCTAssertEqual(MoveDetector.moves(inDeclarationsOf: flip), [])
    }

    // MARK: Real rounds against an independent oracle

    /// Moves for `player` in `trick`, decided straight from the documented rules with the reference
    /// structure matcher from the engine tests.
    private func oracle(_ trick: TrickRecord, trump: Trump, player: Int) -> [MoveKind] {
        guard let leadPlay = trick.plays.first, let me = trick.plays.firstIndex(where: { $0.player == player }) else { return [] }
        let lead = leadPlay.cards
        let ledIsTrump = lead.allSatisfy { trump.isTrump($0) }
        let mine = trick.plays[me].cards
        let mineAllTrump = mine.allSatisfy { trump.isTrump($0) }
        let iWon = trick.winner == player
        let team = Seats.team(of: player)
        var found: [MoveKind] = []
        if !ledIsTrump && me > 0 && iWon && mineAllTrump {
            let opponentRuffed = trick.plays[1..<me].contains { play in
                Seats.team(of: play.player) != team && play.cards.allSatisfy { trump.isTrump($0) }
                    && EngineTestSupport.referenceKey(play.cards, lead: lead, trump: trump) != nil
            }
            found.append(opponentRuffed ? .overruff : .ruff)
        }
        if me > 0 && trick.winner == Seats.partner(of: player) && mine.points >= 5 { found.append(.feedPartner) }
        let components = Combos.decompose(lead, trump: trump)
        if components.contains(where: { $0.shape.isTractor }) && (me == 0 || iWon) { found.append(.tractor) }
        if me == 0 && components.count > 1 { found.append(.cleanThrow) }
        if me == 0 && iWon && !ledIsTrump && components.count == 1 { found.append(.topCard) }
        if iWon && mine.contains(where: { $0.face == .bigJoker }) { found.append(.bigJoker) }
        if Seats.team(of: trick.winner) == team && trick.points >= 30 { found.append(.bigTrick) }
        return MoveKind.allCases.filter { found.contains($0) }
    }

    private let prefixes: [MoveKind: String] = [
        .ruff: "Ruff! ", .overruff: "Overruff! ", .feedPartner: "Point feed! ", .tractor: "Tractor! ",
        .cleanThrow: "Clean throw! ", .topCard: "Top card! ", .bigJoker: "Big joker! ", .kittyRaid: "Kitty raid! ",
        .declareTrump: "Trump declared! ", .overrideDeclaration: "Override! ", .holdDeal: "Deal held! ",
        .shutout: "Shutout! ", .takeOver: "Take over! ", .bigTrick: "Big trick! ",
    ]

    func testRealRoundsMatchTheOracle() throws {
        var counts: [MoveKind: Int] = [:]
        for seed in UInt64(0)..<UInt64(160) {
            var rng = SeededGenerator(seed: seed &* 31 &+ 7)
            var round = Round(trumpRank: Rank.allCases[Int(seed % 13)], dealer: seed % 2 == 0 ? nil : Int(seed % 4), rng: &rng)
            try EngineTestSupport.dealWithDeclarations(&round, rng: &rng, chance: 5)
            round.finishDealing()
            for player in Seats.all {
                for event in MoveDetector.moves(inDeclarationsOf: round, player: player) {
                    counts[event.kind, default: 0] += 1
                    XCTAssertTrue(event.detail.hasPrefix(prefixes[event.kind] ?? "?"), event.detail)
                }
                // Oracle for declarations.
                let history = round.declarationHistory
                var overrides = 0
                for index in history.indices.dropFirst()
                where history[index].player == player && Seats.team(of: history[index - 1].player) != Seats.team(of: player) {
                    overrides += 1
                }
                let events = MoveDetector.moves(inDeclarationsOf: round, player: player)
                XCTAssertEqual(events.filter { $0.kind == .overrideDeclaration }.count, overrides, "seed \(seed)")
                XCTAssertEqual(events.contains { $0.kind == .declareTrump }, round.declaration?.player == player, "seed \(seed)")
            }
            guard let dealer = round.dealer else { return XCTFail("no dealer") }
            try round.bury(Array(round.hands[dealer].shuffled(using: &rng).prefix(8)))
            while round.phase == .playing {
                let before = round.tricks.count
                _ = try EngineTestSupport.playOneMove(&round, rng: &rng)
                guard round.tricks.count > before, let trick = round.tricks.last else { continue }
                let index = round.tricks.count - 1
                for player in Seats.all {
                    let events = MoveDetector.moves(inTrick: index, of: round, player: player)
                    XCTAssertEqual(kinds(events), oracle(trick, trump: round.trump, player: player), "seed \(seed) trick \(index) player \(player)")
                    for event in events {
                        counts[event.kind, default: 0] += 1
                        XCTAssertTrue(event.detail.hasPrefix(prefixes[event.kind] ?? "?"), event.detail)
                        XCTAssertFalse(event.detail.contains(Kit.emDash))
                        XCTAssertGreaterThanOrEqual(event.points, 0)
                    }
                }
                XCTAssertEqual(MoveDetector.moves(inTrick: index, of: round), MoveDetector.moves(inTrick: index, of: round.seatView(for: 0)))
            }
            let result = try XCTUnwrap(round.result)
            for player in Seats.all {
                let events = MoveDetector.moves(inFinishedRound: round, player: player)
                let team = Seats.team(of: player)
                let declared = result.declarerTeam == team
                var expected: [MoveKind] = []
                if !declared && Seats.team(of: result.lastTrickWinner) == team { expected.append(.kittyRaid) }
                if declared && result.defenderPoints < 80 { expected.append(.holdDeal) }
                if declared && result.defenderPoints == 0 { expected.append(.shutout) }
                if !declared && result.defenderPoints >= 80 { expected.append(.takeOver) }
                XCTAssertEqual(kinds(events), expected, "seed \(seed) player \(player)")
                for event in events { counts[event.kind, default: 0] += 1 }
            }
        }
        // Every kind shows up in real play except the rare shutout (covered by hand-built results).
        for kind in MoveKind.allCases where kind != .shutout {
            XCTAssertGreaterThan(counts[kind] ?? 0, 0, "\(kind) never happened in 160 random rounds")
        }
    }

    func testDetectionIsFast() throws {
        var rng = SeededGenerator(seed: 3)
        var round = Round(trumpRank: .two, dealer: 0, rng: &rng)
        try EngineTestSupport.prepare(&round, rng: &rng)
        try EngineTestSupport.playOut(&round, rng: &rng)
        let start = Date()
        for _ in 0..<20 {
            for index in round.tricks.indices { _ = MoveDetector.moves(inTrick: index, of: round) }
        }
        let perTrick = Date().timeIntervalSince(start) / Double(20 * max(1, round.tricks.count))
        XCTAssertLessThan(perTrick, 0.005)
    }
}
