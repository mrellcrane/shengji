import Foundation
import XCTest
@testable import ShengjiCore

private func both(_ r: Rank, _ s: Suit) -> [Card] { [c(r, s, 0), c(r, s, 1)] }

/// Every non-rank card of a suit (24 cards) for trump rank 2.
private func fullSuit(_ s: Suit) -> [Card] {
    Rank.allCases.filter { $0 != .two }.flatMap { both($0, s) }
}

private func assertRoundError<T>(_ expression: @autoclosure () throws -> T, _ expected: RoundError,
                              file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        XCTAssertEqual(error as? RoundError, expected, file: file, line: line)
    }
}

final class RoundTests: XCTestCase {
    // MARK: Setup and dealing

    func testInitialState() {
        let deck = Deck.double()
        let round = Round(trumpRank: .five, dealer: 2, deck: deck)
        XCTAssertEqual(round.trumpRank, .five)
        XCTAssertEqual(round.dealer, 2)
        XCTAssertEqual(round.phase, .dealing)
        XCTAssertEqual(round.hands, [[], [], [], []])
        XCTAssertEqual(round.undealt, Array(deck.prefix(100)))
        XCTAssertEqual(round.kitty, Array(deck.suffix(8)))
        XCTAssertNil(round.declaration)
        XCTAssertEqual(round.declarationHistory, [])
        XCTAssertEqual(round.trump, Trump(rank: .five, suit: nil))
        XCTAssertEqual(round.nextToReceive, 2)
        XCTAssertEqual(round.leader, 2)
        XCTAssertEqual(round.currentTrick, [])
        XCTAssertEqual(round.tricks, [])
        XCTAssertEqual(round.defenderTrickPoints, 0)
        XCTAssertNil(round.trumpFromKitty)
        XCTAssertNil(round.result)
        XCTAssertNil(round.turn)
        XCTAssertNil(round.lastTrick)
        XCTAssertFalse(round.isDealingComplete)
        XCTAssertEqual(round.declarerTeam, 0)
        XCTAssertTrue(round.isDefender(1))
        XCTAssertTrue(round.isDefender(3))
        XCTAssertFalse(round.isDefender(0))
        XCTAssertEqual(round.currentLead, [])
        XCTAssertEqual(round.playedCards, [])

        let firstRound = Round(trumpRank: .two, dealer: nil, deck: deck)
        XCTAssertNil(firstRound.dealer)
        XCTAssertEqual(firstRound.nextToReceive, 0)
        XCTAssertEqual(firstRound.leader, 0)
        XCTAssertNil(firstRound.declarerTeam)
        XCTAssertFalse(firstRound.isDefender(1))
    }

    func testDealingStartsWithDealerAndGoesRound() {
        let deck = Deck.double()
        var round = Round(trumpRank: .two, dealer: 3, deck: deck)
        let first = round.dealNext()
        XCTAssertEqual(first?.player, 3)
        XCTAssertEqual(first?.card, deck[0])
        let second = round.dealNext()
        XCTAssertEqual(second?.player, 0)
        XCTAssertEqual(second?.card, deck[1])
        XCTAssertEqual(round.nextToReceive, 1)
        round.dealAll()
        XCTAssertTrue(round.isDealingComplete)
        XCTAssertEqual(round.hands.map(\.count), [25, 25, 25, 25])
        XCTAssertEqual(round.hands[3], stride(from: 0, to: 100, by: 4).map { deck[$0] })
        XCTAssertEqual(round.hands[0], stride(from: 1, to: 100, by: 4).map { deck[$0] })
        XCTAssertNil(round.dealNext())
        XCTAssertEqual(round.kitty, Array(deck.suffix(8)))
        XCTAssertEqual(round.phase, .dealing)
        XCTAssertNil(round.turn)
    }

    func testDeckHelperDealsSpecifiedCards() {
        let deck = EngineTestSupport.deck(hands: [[bj0], [], [sj0, sj1], []], kitty: [c(.ace, .spades)], firstSeat: 2)
        XCTAssertEqual(deck.count, 108)
        XCTAssertEqual(Set(deck.map(\.id)).count, 108)
        var round = Round(trumpRank: .two, dealer: 2, deck: deck)
        round.dealAll()
        XCTAssertTrue(round.hands[0].contains(bj0))
        XCTAssertTrue(round.hands[2].contains(sj0) && round.hands[2].contains(sj1))
        XCTAssertEqual(round.kitty.first, c(.ace, .spades))
    }

    // MARK: Declaring

    /// Rank 5. Seat 0: BJ BJ. Seat 1: 5♥ 5♥. Seat 2: 5♠ 5♣. Seat 3: SJ SJ 5♦. Kitty: the other 5s.
    private func declarationRound(dealer: Int? = nil) -> Round {
        let deck = EngineTestSupport.deck(
            hands: [[bj0, bj1], both(.five, .hearts), [c(.five, .spades), c(.five, .clubs)], [sj0, sj1, c(.five, .diamonds)]],
            kitty: [c(.five, .spades, 1), c(.five, .clubs, 1), c(.five, .diamonds, 1)],
            firstSeat: dealer ?? 0, seed: 11)
        return Round(trumpRank: .five, dealer: dealer, deck: deck)
    }

    private func labels(_ declarations: [Declaration]) -> [String] {
        declarations.map { "\($0.suit?.symbol ?? "NT")\($0.strength)" }
    }

    func testAvailableDeclarations() {
        var round = declarationRound()
        XCTAssertEqual(round.availableDeclarations(for: 1), [])
        round.dealAll()
        XCTAssertEqual(labels(round.availableDeclarations(for: 0)), ["NT4"])
        XCTAssertEqual(labels(round.availableDeclarations(for: 1)), ["♥1", "♥2"])
        XCTAssertEqual(labels(round.availableDeclarations(for: 2)), ["♠1", "♣1"])
        XCTAssertEqual(labels(round.availableDeclarations(for: 3)), ["♦1", "NT3"])
        XCTAssertEqual(round.availableDeclarations(for: 1).last?.cards.count, 2)
        XCTAssertEqual(round.availableDeclarations(for: 7), [])
    }

    func testOverridesMustBeStrictlyStronger() throws {
        var round = declarationRound()
        round.dealAll()
        let spade = try XCTUnwrap(round.availableDeclarations(for: 2).first { $0.suit == .spades })
        try round.declare(spade)
        XCTAssertEqual(round.declaration, spade)
        XCTAssertEqual(round.trump.suit, .spades)

        // Equal strength can't override, and the holder can't switch suits.
        assertRoundError(try round.declare(Declaration(player: 3, cards: [c(.five, .diamonds)], suit: .diamonds, strength: 1)),
                         .invalidDeclaration)
        assertRoundError(try round.declare(Declaration(player: 2, cards: [c(.five, .clubs)], suit: .clubs, strength: 1)),
                         .invalidDeclaration)
        XCTAssertEqual(labels(round.availableDeclarations(for: 3)), ["NT3"])
        XCTAssertEqual(round.availableDeclarations(for: 2), [])

        try round.declare(Declaration(player: 1, cards: both(.five, .hearts), suit: .hearts, strength: 2))
        XCTAssertEqual(round.trump.suit, .hearts)
        XCTAssertEqual(round.availableDeclarations(for: 2), [])

        try round.declare(Declaration(player: 3, cards: [sj0, sj1], suit: nil, strength: 3))
        XCTAssertNil(round.trump.suit)
        XCTAssertEqual(round.availableDeclarations(for: 1), [])

        try round.declare(Declaration(player: 0, cards: [bj0, bj1], suit: nil, strength: 4))
        XCTAssertEqual(round.declaration?.player, 0)
        XCTAssertEqual(round.declaration?.strength, 4)
        for seat in 0..<4 { XCTAssertEqual(round.availableDeclarations(for: seat), []) }
        XCTAssertEqual(round.declarationHistory.map(\.player), [2, 1, 3, 0])

        round.finishDealing()
        XCTAssertEqual(round.dealer, 0, "first round: the winning declarer deals")
        XCTAssertNil(round.trump.suit)
        XCTAssertNil(round.trumpFromKitty)
        XCTAssertEqual(round.phase, .burying)
        XCTAssertEqual(round.hands[0].count, 33)
        assertRoundError(try round.declare(Declaration(player: 0, cards: [bj0, bj1], suit: nil, strength: 4)),
                         .invalidDeclaration)
        XCTAssertEqual(round.availableDeclarations(for: 1), [])
    }

    func testReinforcingYourOwnDeclarationAndPartnerOverride() throws {
        var round = declarationRound()
        // One card each: every seat gets its first specified card.
        for _ in 0..<4 { round.dealNext() }
        XCTAssertEqual(labels(round.availableDeclarations(for: 1)), ["♥1"])
        try round.declare(Declaration(player: 1, cards: [c(.five, .hearts)], suit: .hearts, strength: 1))
        XCTAssertEqual(round.trump.suit, .hearts)
        XCTAssertEqual(round.availableDeclarations(for: 1), [])
        for _ in 0..<4 { round.dealNext() }
        XCTAssertEqual(labels(round.availableDeclarations(for: 1)), ["♥2"])
        try round.declare(Declaration(player: 1, cards: both(.five, .hearts), suit: .hearts, strength: 2))
        XCTAssertEqual(round.declaration?.strength, 2)
        XCTAssertEqual(round.availableDeclarations(for: 1), [])
        // Seat 3 is seat 1's partner and may still override with a stronger declaration.
        XCTAssertEqual(labels(round.availableDeclarations(for: 3)), ["NT3"])
        try round.declare(Declaration(player: 3, cards: [sj0, sj1], suit: nil, strength: 3))
        XCTAssertEqual(round.declaration?.player, 3)
    }

    func testHolderCannotSwitchSuitOrUpgradeJokers() throws {
        // Seat 1 holds 5♥ and a pair of 5♠; seat 0 holds both joker pairs.
        let deck = EngineTestSupport.deck(
            hands: [[sj0, sj1, bj0, bj1], [c(.five, .hearts)] + both(.five, .spades), [], []],
            kitty: [c(.five, .hearts, 1)] + both(.five, .clubs) + both(.five, .diamonds), seed: 5)
        var round = Round(trumpRank: .five, dealer: nil, deck: deck)
        round.dealAll()
        try round.declare(Declaration(player: 1, cards: [c(.five, .hearts)], suit: .hearts, strength: 1))
        XCTAssertEqual(round.availableDeclarations(for: 1), [], "a stronger spade pair is not a reinforcement")
        assertRoundError(try round.declare(Declaration(player: 1, cards: both(.five, .spades), suit: .spades, strength: 2)),
                         .invalidDeclaration)
        try round.declare(Declaration(player: 0, cards: [sj0, sj1], suit: nil, strength: 3))
        XCTAssertEqual(round.availableDeclarations(for: 0), [], "a joker declaration can't be upgraded by its holder")
        XCTAssertEqual(labels(round.availableDeclarations(for: 2)), [])
    }

    func testDeclareRejectsBadInput() {
        var round = declarationRound()
        assertRoundError(try round.declare(Declaration(player: 1, cards: [c(.five, .hearts)], suit: .hearts, strength: 1)),
                         .invalidDeclaration)
        round.dealAll()
        let bad: [Declaration] = [
            Declaration(player: 1, cards: [c(.five, .hearts)], suit: .hearts, strength: 2),
            Declaration(player: 1, cards: both(.five, .hearts), suit: nil, strength: 3),
            Declaration(player: 1, cards: [c(.five, .spades)], suit: .spades, strength: 1),
            Declaration(player: 2, cards: [c(.five, .hearts)], suit: .hearts, strength: 1),
            Declaration(player: 2, cards: [c(.five, .clubs)], suit: .spades, strength: 1),
            Declaration(player: 1, cards: [], suit: .hearts, strength: 1),
            Declaration(player: 7, cards: [c(.five, .hearts)], suit: .hearts, strength: 1),
            Declaration(player: 0, cards: [bj0, bj1], suit: .hearts, strength: 4),
        ]
        for declaration in bad {
            assertRoundError(try round.declare(declaration), .invalidDeclaration)
        }
        XCTAssertNil(round.declaration)
        XCTAssertEqual(round.declarationHistory, [])
    }

    func testDeclarationDescriptions() {
        XCTAssertEqual(Declaration(player: 1, cards: [c(.two, .hearts)], suit: .hearts, strength: 1).description,
                       "East declares ♥ (one 2♥)")
        XCTAssertEqual(Declaration(player: 0, cards: [bj0, bj1], suit: nil, strength: 4).description,
                       "You declare no trump (pair of big jokers)")
        XCTAssertEqual(Declaration(player: 3, cards: [sj0, sj1], suit: nil, strength: 3).description,
                       "West declares no trump (pair of small jokers)")
        XCTAssertEqual(Declaration(player: 2, cards: both(.five, .spades), suit: .spades, strength: 2).description,
                       "Partner declares ♠ (pair of 5♠)")
    }

    // MARK: Closing the deal and the kitty

    private func flipped(kitty: [Card], rank: Rank = .seven, dealer: Int? = nil) -> Round {
        var round = Round(trumpRank: rank, dealer: dealer,
                          deck: EngineTestSupport.deck(kitty: kitty, firstSeat: dealer ?? 0, seed: 21))
        round.dealAll()
        round.finishDealing()
        return round
    }

    func testKittyFlipFirstRankCardFixesSuit() {
        let kitty = [c(.three, .spades), c(.nine, .diamonds), c(.seven, .clubs), sj0,
                     c(.four, .spades), c(.five, .spades), c(.six, .spades), c(.eight, .spades)]
        let round = flipped(kitty: kitty)
        XCTAssertEqual(round.trump.suit, .clubs)
        XCTAssertEqual(round.trumpFromKitty, c(.seven, .clubs))
        XCTAssertEqual(round.dealer, 0, "nobody declared in the first round: seat 0 deals")
        XCTAssertEqual(round.hands[0].count, 33)
        XCTAssertEqual(round.kitty, kitty, "the kitty keeps the original cards until burying")
        XCTAssertTrue(round.hands[0].containsAll(kitty))
        XCTAssertEqual(round.phase, .burying)
        XCTAssertEqual(round.leader, 0)
    }

    func testKittyFlipJokerFirstMeansNoTrump() {
        let kitty = [c(.three, .spades), bj0, c(.seven, .clubs), c(.four, .spades),
                     c(.five, .spades), c(.six, .spades), c(.eight, .spades), c(.nine, .spades)]
        let round = flipped(kitty: kitty)
        XCTAssertNil(round.trump.suit)
        XCTAssertEqual(round.trumpFromKitty, bj0)
    }

    func testKittyFlipHighestCardWhenNoRankOrJoker() {
        let kitty = [c(.three, .spades), c(.king, .diamonds), c(.nine, .clubs), c(.king, .hearts),
                     c(.four, .spades), c(.two, .clubs), c(.ten, .diamonds), c(.six, .hearts)]
        let round = flipped(kitty: kitty, dealer: 2)
        XCTAssertEqual(round.trump.suit, .diamonds, "first of the tied kings")
        XCTAssertEqual(round.trumpFromKitty, c(.king, .diamonds))
        XCTAssertEqual(round.dealer, 2, "a later round keeps its dealer")
        XCTAssertEqual(round.hands[2].count, 33)
        XCTAssertEqual(round.hands[0].count, 25)

        let aceKitty = [c(.three, .spades), c(.king, .diamonds), c(.ace, .clubs), c(.king, .hearts),
                        c(.four, .spades), c(.two, .clubs), c(.ten, .diamonds), c(.six, .hearts)]
        XCTAssertEqual(flipped(kitty: aceKitty).trump.suit, .clubs)
    }

    func testDeclarationInLaterRoundKeepsDealer() throws {
        var round = declarationRound(dealer: 1)
        round.dealAll()
        try round.declare(Declaration(player: 3, cards: [sj0, sj1], suit: nil, strength: 3))
        round.finishDealing()
        XCTAssertEqual(round.dealer, 1)
        XCTAssertNil(round.trump.suit)
        XCTAssertNil(round.trumpFromKitty)
        XCTAssertEqual(round.hands[1].count, 33)
        XCTAssertEqual(round.declarerTeam, 1)
    }

    func testFinishDealingNeedsCompleteDeal() {
        var round = Round(trumpRank: .two, dealer: nil, deck: Deck.double())
        for _ in 0..<10 { round.dealNext() }
        round.finishDealing()
        XCTAssertEqual(round.phase, .dealing)
        XCTAssertNil(round.dealer)
        round.dealAll()
        round.finishDealing()
        XCTAssertEqual(round.phase, .burying)
        round.finishDealing()
        XCTAssertEqual(round.hands[0].count, 33, "a second call does nothing")
    }

    func testBurying() throws {
        var round = Round(trumpRank: .two, dealer: 1, deck: EngineTestSupport.deck(firstSeat: 1, seed: 3))
        assertRoundError(try round.bury([]), .wrongPhase)
        round.dealAll()
        round.finishDealing()
        let originalKitty = round.kitty
        let hand = round.hands[1]
        XCTAssertEqual(hand.count, 33)
        XCTAssertNil(round.turn)
        XCTAssertEqual(round.legalityError(for: [hand[0]], by: 1), .wrongPhase)

        assertRoundError(try round.bury(Array(hand.prefix(7))),
                         .invalidBury("Choose exactly 8 cards to bury (you chose 7)."))
        assertRoundError(try round.bury(Array(repeating: hand[0], count: 8)), .invalidBury("Each card can only be buried once."))
        assertRoundError(try round.bury(Array(round.hands[0].prefix(8))),
                         .invalidBury("You can only bury cards from your own hand."))
        XCTAssertEqual(RoundError.invalidBury("Each card can only be buried once.").explanation,
                       "Each card can only be buried once.")

        let buried = Array(hand.suffix(8))
        try round.bury(buried)
        XCTAssertEqual(round.phase, .playing)
        XCTAssertEqual(round.kitty, buried)
        XCTAssertEqual(round.hands[1].count, 25)
        XCTAssertFalse(round.hands[1].contains(where: buried.contains))
        XCTAssertTrue(round.hands[1].containsAll(originalKitty.filter { !buried.contains($0) }))
        XCTAssertEqual(round.leader, 1)
        XCTAssertEqual(round.turn, 1)
        assertRoundError(try round.bury(buried), .wrongPhase)
    }

    // MARK: Playing

    /// Rank 2, dealer 0 declares hearts with 2♥. Seat 0 holds 3♠ 4♠; seat 1 holds 5♠ 6♦.
    private func playingRound(extra: [Card] = [], seed: UInt64 = 8) throws -> Round {
        let deck = EngineTestSupport.deck(
            hands: [[c(.two, .hearts), c(.three, .spades), c(.four, .spades)] + extra, [c(.five, .spades), c(.six, .diamonds)], [], []],
            seed: seed)
        var round = Round(trumpRank: .two, dealer: 0, deck: deck)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [c(.two, .hearts)], suit: .hearts, strength: 1))
        round.finishDealing()
        let keep = Set([c(.two, .hearts), c(.three, .spades), c(.four, .spades)] + extra)
        try round.bury(Array(round.hands[0].filter { !keep.contains($0) }.prefix(8)))
        return round
    }

    func testPlayErrors() throws {
        var round = try playingRound()
        XCTAssertEqual(round.turn, 0)
        assertRoundError(try round.play([c(.five, .spades)], by: 1), .notYourTurn)
        assertRoundError(try round.play([c(.three, .spades)], by: 9), .notYourTurn)
        assertRoundError(try round.play([], by: 0), .illegalLead(.empty))
        assertRoundError(try round.play([c(.five, .spades)], by: 0), .illegalLead(.cardsNotInHand))
        assertRoundError(try round.play([c(.three, .spades), c(.two, .hearts)], by: 0), .illegalLead(.mixedSuits))
        XCTAssertEqual(round.legalityError(for: [c(.three, .spades), c(.two, .hearts)], by: 0), .illegalLead(.mixedSuits))
        XCTAssertNil(round.legalityError(for: [c(.three, .spades)], by: 0))

        XCTAssertEqual(try round.play([c(.three, .spades)], by: 0), .played)
        XCTAssertEqual(round.currentLead, [c(.three, .spades)])
        XCTAssertEqual(round.turn, 1)
        XCTAssertEqual(round.hands[0].count, 24)
        assertRoundError(try round.play([c(.six, .diamonds)], by: 1), .illegalFollow(.mustFollowSuit(.plain(.spades))))
        assertRoundError(try round.play([c(.five, .spades), c(.six, .diamonds)], by: 1), .illegalFollow(.wrongCount(expected: 1)))
        XCTAssertEqual(round.legalityError(for: [c(.six, .diamonds)], by: 1),
                       .illegalFollow(.mustFollowSuit(.plain(.spades))))
        XCTAssertEqual(RoundError.illegalFollow(.mustFollowSuit(.plain(.spades))).explanation,
                       FollowViolation.mustFollowSuit(.plain(.spades)).explanation)
        XCTAssertEqual(try round.play([c(.five, .spades)], by: 1), .played)
        XCTAssertEqual(round.turn, 2)
        XCTAssertEqual(round.playedCards, [c(.three, .spades), c(.five, .spades)])
    }

    func testCompletedTrickIsScored() throws {
        var round = try playingRound()
        var rng = SeededGenerator(seed: 4)
        try round.play([c(.three, .spades)], by: 0)
        for seat in 1...3 {
            let follow = EngineTestSupport.legalFollow(hand: round.hands[seat], lead: round.currentLead,
                                                       trump: round.trump, rng: &rng)
            try round.play(follow, by: seat)
        }
        XCTAssertEqual(round.tricks.count, 1)
        let trick = try XCTUnwrap(round.lastTrick)
        XCTAssertEqual(trick.leader, 0)
        XCTAssertEqual(trick.plays.map(\.player), [0, 1, 2, 3])
        XCTAssertEqual(trick.winner, trick.plays[Rules.winningIndex(trick.plays, trump: round.trump)].player)
        XCTAssertEqual(trick.points, trick.plays.flatMap(\.cards).points)
        XCTAssertEqual(round.defenderTrickPoints, round.isDefender(trick.winner) ? trick.points : 0)
        XCTAssertTrue(round.currentTrick.isEmpty)
        XCTAssertEqual(round.leader, trick.winner)
        XCTAssertEqual(round.turn, trick.winner)
        XCTAssertEqual(round.hands.map(\.count), [24, 24, 24, 24])
        XCTAssertEqual(round.playedCards.count, 4)
    }

    func testFailedThrowPlaysOnlyTheForcedCard() throws {
        var round = try playingRound()
        let lead = [c(.three, .spades), c(.four, .spades)]
        XCTAssertNil(round.legalityError(for: lead, by: 0), "the throw check only happens in play")
        // Seat 1 holds 5♠, which beats both singles, and is first after the leader.
        XCTAssertEqual(try round.play(lead, by: 0), .throwFailed(forced: [c(.three, .spades)], blocker: 1))
        XCTAssertEqual(round.currentTrick, [Play(player: 0, cards: [c(.three, .spades)])])
        XCTAssertTrue(round.hands[0].contains(c(.four, .spades)))
        XCTAssertEqual(round.hands[0].count, 24)
        XCTAssertEqual(round.turn, 1)
        XCTAssertEqual(round.currentLead, [c(.three, .spades)])
    }

    func testSuccessfulThrow() throws {
        // Seat 0 holds both aces and both kings of spades, so A♠ + K♠K♠ can't be beaten.
        var round = try playingRound(extra: both(.ace, .spades) + both(.king, .spades))
        let lead = [c(.ace, .spades), c(.king, .spades), c(.king, .spades, 1)]
        XCTAssertEqual(try round.play(lead, by: 0), .played)
        XCTAssertEqual(round.currentLead, lead)
        var rng = SeededGenerator(seed: 2)
        for seat in 1...3 {
            let follow = EngineTestSupport.legalFollow(hand: round.hands[seat], lead: lead, trump: round.trump, rng: &rng)
            XCTAssertEqual(follow.count, 3)
            try round.play(follow, by: seat)
        }
        XCTAssertEqual(round.tricks.count, 1)
        XCTAssertEqual(round.hands.map(\.count), [22, 22, 22, 22])
    }

    func testThrowBlockedByPartnerForcesThePairAndFollowersMustMatchIt() throws {
        // Rank 2, hearts trump. Seat 0 throws A♠ + 7♠7♠. Only the partner (seat 2) can beat a part of it
        // (9♠9♠ beats the pair), and a partner blocks a throw just like an opponent.
        let otherSpades = [c(.ace, .spades, 1), c(.five, .spades, 1)]
            + [Rank.king, .queen, .jack, .ten, .nine, .eight, .six, .four].flatMap { both($0, .spades) }
        let deck = EngineTestSupport.deck(
            hands: [[c(.two, .hearts), c(.ace, .spades)] + both(.seven, .spades), both(.three, .spades) + [c(.five, .spades)],
                    otherSpades, []],
            seed: 13)
        var round = Round(trumpRank: .two, dealer: 0, deck: deck)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [c(.two, .hearts)], suit: .hearts, strength: 1))
        round.finishDealing()
        let keep = Set([c(.two, .hearts), c(.ace, .spades)] + both(.seven, .spades))
        try round.bury(Array(round.hands[0].filter { !keep.contains($0) }.prefix(8)))

        let lead = [c(.ace, .spades)] + both(.seven, .spades)
        XCTAssertEqual(try round.play(lead, by: 0), .throwFailed(forced: both(.seven, .spades), blocker: 2))
        XCTAssertEqual(round.currentLead, both(.seven, .spades))
        XCTAssertTrue(round.hands[0].contains(c(.ace, .spades)), "the rest of the throw goes back to the hand")
        // Seat 1 must now follow the pair with its 3♠3♠.
        XCTAssertEqual(round.legalityError(for: [c(.three, .spades), c(.five, .spades)], by: 1),
                       .illegalFollow(.mustPlayPairs(required: 1)))
        try round.play(both(.three, .spades), by: 1)
        try round.play(both(.nine, .spades), by: 2)
        let seat3 = round.hands[3]
        XCTAssertFalse(seat3.contains { round.trump.group($0) == .plain(.spades) }, "seat 3 has no spades")
        try round.play(Array(seat3.filter { !round.trump.isTrump($0) }.prefix(2)), by: 3)
        XCTAssertEqual(round.lastTrick?.winner, 2)
        XCTAssertEqual(round.leader, 2)
        XCTAssertEqual(round.hands.map(\.count), [23, 23, 23, 23])
    }

    func testRoundErrorExplanations() {
        XCTAssertEqual(RoundError.notYourTurn.explanation, "Wait for your turn.")
        let errors: [RoundError] = [.wrongPhase, .notYourTurn, .illegalLead(.mixedSuits), .illegalFollow(.mustPlayPairs(required: 1)),
                                    .invalidDeclaration, .invalidBury("Choose exactly 8 cards to bury (you chose 3).")]
        for error in errors {
            XCTAssertFalse(error.explanation.isEmpty)
            XCTAssertFalse(error.explanation.contains("\u{2014}"))
        }
        XCTAssertEqual(RoundError.illegalLead(.empty).explanation, LeadViolation.empty.explanation)
    }

    // MARK: Whole rounds with an explicit deal

    /// Plays the lowest single card when leading, and the lowest legal card when following a single.
    private func playLowestCards(_ round: inout Round) throws {
        var moves = 0
        while round.phase == .playing, let seat = round.turn, moves < 200 {
            moves += 1
            let trump = round.trump
            let hand = trump.sorted(round.hands[seat])
            let card: Card?
            if let led = round.currentLead.first {
                card = hand.first { trump.group($0) == trump.group(led) } ?? hand.first
            } else {
                card = hand.first
            }
            try round.play([try XCTUnwrap(card)], by: seat)
        }
    }

    func testDefendersWinningLastTrickDoubleTheKitty() throws {
        // Rank 2, hearts trump (seat 0 declares with 2♥). Seat 3, a defender, holds every top trump.
        let highHearts: [Rank] = [.ace, .king, .queen, .jack, .ten, .nine, .eight]
        let seat3 = [bj0, bj1, sj0, sj1, c(.two, .hearts, 1)] + both(.two, .spades) + both(.two, .clubs) + both(.two, .diamonds)
            + highHearts.flatMap { both($0, .hearts) }
        let hands = [[c(.two, .hearts)] + fullSuit(.spades), fullSuit(.diamonds) + [c(.three, .hearts)],
                     fullSuit(.clubs) + [c(.three, .hearts, 1)], seat3]
        let kitty = [Rank.four, .five, .six, .seven].flatMap { both($0, .hearts) }
        var round = Round(trumpRank: .two, dealer: 0, deck: EngineTestSupport.deck(hands: hands, kitty: kitty))
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [c(.two, .hearts)], suit: .hearts, strength: 1))
        round.finishDealing()
        // Bury 50 points of spades.
        let buried = both(.king, .spades) + both(.ten, .spades) + both(.five, .spades) + both(.ace, .spades)
        try round.bury(buried)
        XCTAssertEqual(round.kitty.points, 50)

        try playLowestCards(&round)
        let result = try XCTUnwrap(round.result)
        XCTAssertEqual(round.tricks.count, 25)
        // Trick 1: 3♠ led, seat 3 ruffs.
        XCTAssertEqual(round.tricks[0].plays[0].cards, [c(.three, .spades)])
        XCTAssertEqual(round.tricks[0].winner, 3)
        // The only trick the declarers take is the one where 2♥ beats a queen of hearts.
        let declarerTricks = round.tricks.filter { !round.isDefender($0.winner) }
        XCTAssertEqual(declarerTricks.count, 1)
        XCTAssertTrue(declarerTricks[0].plays.contains { $0.cards == [c(.two, .hearts)] })
        XCTAssertEqual(result.lastTrickWinner, 3)
        XCTAssertEqual(result.kittyPoints, 50)
        XCTAssertEqual(result.kittyMultiplier, 2)
        let declarerPoints = declarerTricks.reduce(0) { $0 + $1.points }
        XCTAssertEqual(result.trickPoints, 150 - declarerPoints)
        XCTAssertEqual(result.defenderPoints, result.trickPoints + 100)
        XCTAssertFalse(result.outcome.declarersHold)
        XCTAssertEqual(result.outcome, Scoring.outcome(defenderPoints: result.defenderPoints))
        XCTAssertEqual(result.dealer, 0)
        XCTAssertEqual(result.declarerTeam, 0)
        XCTAssertEqual(result.trump, Trump(rank: .two, suit: .hearts))
        XCTAssertEqual(round.phase, .finished)
    }

    func testDeclarersWinningLastTrickKeepTheKitty() throws {
        // Mirror image: the dealer (seat 0) holds every top trump, so declarers take the last trick.
        let highHearts: [Rank] = [.ace, .king, .queen, .jack, .ten, .nine, .eight]
        let seat0 = [bj0, bj1, sj0, sj1, c(.two, .hearts, 1)] + both(.two, .spades) + both(.two, .clubs) + both(.two, .diamonds)
            + highHearts.flatMap { both($0, .hearts) }
        let hands = [seat0, fullSuit(.diamonds) + [c(.three, .hearts)], fullSuit(.clubs) + [c(.three, .hearts, 1)],
                     [c(.two, .hearts)] + fullSuit(.spades)]
        let kitty = [Rank.four, .five, .six, .seven].flatMap { both($0, .hearts) }
        var round = Round(trumpRank: .two, dealer: 0, deck: EngineTestSupport.deck(hands: hands, kitty: kitty))
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [c(.two, .hearts, 1)], suit: .hearts, strength: 1))
        round.finishDealing()
        try round.bury(kitty)
        XCTAssertEqual(round.kitty.points, 10)

        try playLowestCards(&round)
        let result = try XCTUnwrap(round.result)
        XCTAssertFalse(round.isDefender(result.lastTrickWinner))
        XCTAssertEqual(result.kittyMultiplier, 0)
        XCTAssertEqual(result.kittyPoints, 10)
        XCTAssertEqual(result.defenderPoints, result.trickPoints)
        let defenderTricks = round.tricks.filter { round.isDefender($0.winner) }.reduce(0) { $0 + $1.points }
        XCTAssertEqual(result.trickPoints, defenderTricks)
        XCTAssertEqual(round.tricks.reduce(0) { $0 + $1.points } + result.kittyPoints, 200)
    }

    func testCodableRoundTripKeepsEverything() throws {
        var round = try playingRound()
        var rng = SeededGenerator(seed: 6)
        for _ in 0..<9 { _ = try EngineTestSupport.playOneMove(&round, rng: &rng) }
        let data = try EngineTestSupport.encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)
        XCTAssertEqual(try EngineTestSupport.encode(decoded), data)
        XCTAssertEqual(decoded.hands, round.hands)
        XCTAssertEqual(decoded.kitty, round.kitty)
        XCTAssertEqual(decoded.declarationHistory, round.declarationHistory)
        XCTAssertEqual(decoded.currentTrick, round.currentTrick)
        XCTAssertEqual(decoded.tricks, round.tricks)
        XCTAssertEqual(decoded.leader, round.leader)
        XCTAssertEqual(decoded.turn, round.turn)
    }
}
