import XCTest
@testable import ShengjiCore

/// Two copies of a card, i.e. a pair.
private func pair(_ r: Rank, _ s: Suit) -> [Card] { [c(r, s, 0), c(r, s, 1)] }

private func plays(_ cardLists: [Card]...) -> [Play] {
    cardLists.enumerated().map { Play(player: $0.offset, cards: $0.element) }
}

final class RulesTests: XCTestCase {
    /// Trump rank 2, hearts trump.
    let t = Trump(rank: .two, suit: .hearts)
    /// Trump rank 8, hearts trump (7 and 9 are adjacent in plain suits).
    let t8 = Trump(rank: .eight, suit: .hearts)
    /// Rank 2, no trump suit.
    let nt = Trump(rank: .two, suit: nil)

    // MARK: Trump order, pairs, tractors

    func testTrumpOrderHighToLow() {
        let order = [bj0, sj0, c(.two, .hearts), c(.two, .spades), c(.ace, .hearts), c(.king, .hearts), c(.three, .hearts)]
        let strengths = order.map { t.strength($0) }
        XCTAssertEqual(strengths, strengths.sorted(by: >))
        XCTAssertEqual(Set(strengths).count, strengths.count)
        XCTAssertTrue(order.allSatisfy { t.isTrump($0) })
        XCTAssertEqual(t.strength(c(.two, .spades)), t.strength(c(.two, .diamonds)))
        XCTAssertEqual(nt.strength(c(.two, .spades)), nt.strength(c(.two, .hearts)))
        XCTAssertGreaterThan(nt.strength(sj0), nt.strength(c(.two, .hearts)))
        XCTAssertFalse(nt.isTrump(c(.ace, .hearts)))
    }

    func testPlainSuitOrderSkipsTrumpRank() {
        XCTAssertEqual(t8.strength(c(.nine, .clubs)) - t8.strength(c(.seven, .clubs)), 1)
        XCTAssertEqual(t8.group(c(.eight, .clubs)), .trump)
        XCTAssertEqual(t8.group(c(.seven, .clubs)), .plain(.clubs))
    }

    func testPairsAndNonPairs() {
        XCTAssertEqual(Combos.shape(of: pair(.seven, .spades), trump: t), .pair)
        XCTAssertNil(Combos.shape(of: [c(.two, .spades), c(.two, .clubs)], trump: t))
        XCTAssertNil(Combos.shape(of: [c(.seven, .spades), c(.seven, .clubs)], trump: t))
        XCTAssertEqual(Combos.shape(of: [sj0, sj1], trump: t), .pair)
        XCTAssertNil(Combos.shape(of: [sj0, bj0], trump: t))
    }

    func testTractorsAcrossTheTrumpRank() {
        // 7799 is a tractor when 8 is the trump rank.
        XCTAssertEqual(Combos.shape(of: pair(.seven, .spades) + pair(.nine, .spades), trump: t8), .tractor(2))
        XCTAssertNil(Combos.shape(of: pair(.seven, .spades) + pair(.nine, .spades), trump: t))
        // Trump suit ace up to an off-suit rank pair, and off-suit rank up to the trump-suit rank.
        XCTAssertEqual(Combos.shape(of: pair(.ace, .hearts) + pair(.two, .spades), trump: t), .tractor(2))
        XCTAssertEqual(Combos.shape(of: pair(.two, .spades) + pair(.two, .hearts), trump: t), .tractor(2))
        XCTAssertEqual(Combos.shape(of: pair(.king, .hearts) + pair(.ace, .hearts) + pair(.two, .clubs) + pair(.two, .hearts),
                                    trump: t), .tractor(4))
        XCTAssertEqual(Combos.shape(of: pair(.two, .hearts) + [sj0, sj1], trump: t), .tractor(2))
        XCTAssertEqual(Combos.shape(of: [sj0, sj1, bj0, bj1], trump: t), .tractor(2))
        // Two off-suit rank pairs are equal in strength, so they are not a tractor.
        XCTAssertNil(Combos.shape(of: pair(.two, .spades) + pair(.two, .clubs), trump: t))
        // No trump: rank pairs lead straight into the small jokers.
        XCTAssertEqual(Combos.shape(of: pair(.two, .clubs) + [sj0, sj1], trump: nt), .tractor(2))
    }

    // MARK: Leading

    func testValidateLead() {
        let hand = [c(.ace, .spades), c(.king, .spades), c(.three, .hearts), sj0]
        XCTAssertEqual(Rules.validateLead([], hand: hand, trump: t), .empty)
        XCTAssertEqual(Rules.validateLead([c(.queen, .spades)], hand: hand, trump: t), .cardsNotInHand)
        XCTAssertEqual(Rules.validateLead([c(.ace, .spades), c(.ace, .spades)], hand: hand, trump: t), .cardsNotInHand)
        XCTAssertEqual(Rules.validateLead([c(.ace, .spades), c(.three, .hearts)], hand: hand, trump: t), .mixedSuits)
        XCTAssertNil(Rules.validateLead([c(.ace, .spades), c(.king, .spades)], hand: hand, trump: t))
        XCTAssertNil(Rules.validateLead([c(.three, .hearts), sj0], hand: hand, trump: t))
    }

    func testIsThrow() {
        XCTAssertFalse(Rules.isThrow([c(.ace, .spades)], trump: t))
        XCTAssertFalse(Rules.isThrow(pair(.ace, .spades), trump: t))
        XCTAssertFalse(Rules.isThrow(pair(.ace, .spades) + pair(.king, .spades), trump: t))
        XCTAssertTrue(Rules.isThrow([c(.ace, .spades), c(.king, .spades)], trump: t))
        XCTAssertTrue(Rules.isThrow([c(.ace, .spades)] + pair(.queen, .spades), trump: t))
    }

    func testLeadViolationExplanations() {
        // The usual mistake is mixing a trump-rank card (2♠ when 2s are trump) with its printed suit,
        // so the explanation says where those cards belong.
        XCTAssertEqual(LeadViolation.mixedSuits.explanation,
                       "A lead must be all one suit, or all trumps. "
                       + "Jokers and trump-rank cards count as trumps, not as their printed suit.")
        for violation in [LeadViolation.empty, .cardsNotInHand, .mixedSuits] {
            XCTAssertFalse(violation.explanation.isEmpty)
            XCTAssertFalse(violation.explanation.contains("\u{2014}"))
        }
    }

    // MARK: Throws

    func testNonThrowIsAlwaysOK() {
        let hands = [[c(.three, .spades)], [c(.ace, .spades)], [], []]
        XCTAssertEqual(Rules.checkThrow([c(.three, .spades)], leader: 0, hands: hands, trump: t), .ok)
    }

    func testThrowSucceedsWhenNobodyCanBeatAnyPart() {
        let lead = [c(.ace, .spades)] + pair(.king, .spades)
        let hands = [
            lead,
            pair(.queen, .spades) + [c(.jack, .spades)],
            [c(.ace, .spades, 1), c(.ten, .spades)],  // an equal ace does not beat
            pair(.ace, .hearts) + [bj0],              // trumps don't count against a throw
        ]
        XCTAssertEqual(Rules.checkThrow(lead, leader: 0, hands: hands, trump: t), .ok)
    }

    func testFailedThrowForcesSmallestComponentAndNamesFirstBlocker() throws {
        // Q♠Q♠ + 9♠: the single 9♠ is the smallest beatable part.
        let lead = pair(.queen, .spades) + [c(.nine, .spades)]
        let hands = [lead, [c(.five, .spades), c(.three, .diamonds)], pair(.king, .spades), [c(.ten, .spades)]]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, leader: 0, hands: hands, trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.shape, .single)
        XCTAssertEqual(forced.cards, [c(.nine, .spades)])
        // Seat 1's 5♠ is lower; seat 2's K♠ beats the 9♠ and comes before seat 3.
        XCTAssertEqual(blocker, 2)
    }

    func testFailedThrowForcesLowestSingle() throws {
        let lead = [c(.king, .spades), c(.ten, .spades), c(.eight, .spades)]
        let hands = [lead, [c(.ace, .spades)], [c(.nine, .spades)], []]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, leader: 0, hands: hands, trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.cards, [c(.eight, .spades)])
        XCTAssertEqual(blocker, 1)
    }

    func testFailedThrowForcesBeatablePairWhenSinglesAreSafe() {
        let lead = [c(.ace, .spades)] + pair(.seven, .spades)
        let hands = [lead, [c(.king, .spades)], [], pair(.nine, .spades)]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, leader: 0, hands: hands, trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.shape, .pair)
        XCTAssertEqual(Set(forced.cards), Set(pair(.seven, .spades)))
        XCTAssertEqual(blocker, 3)
    }

    func testThrowTractorBeatenOnlyByHigherTractor() {
        let lead = pair(.five, .spades) + pair(.six, .spades) + [c(.ace, .spades)]
        // Two high pairs that are not adjacent can't beat a tractor.
        let safe = [lead, pair(.nine, .spades) + pair(.jack, .spades), [], []]
        XCTAssertEqual(Rules.checkThrow(lead, leader: 0, hands: safe, trump: t), .ok)
        // A longer, higher run contains a higher 2-pair tractor.
        let beaten = [lead, [], pair(.nine, .spades) + pair(.ten, .spades) + pair(.jack, .spades), []]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, leader: 0, hands: beaten, trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.shape, .tractor(2))
        XCTAssertEqual(blocker, 2)
    }

    func testThrowBlockerOrderStartsAfterLeader() {
        let lead = [c(.king, .spades), c(.queen, .spades)]
        // Leader is seat 2: play order is 3, 0, 1. Seats 0 and 3 can both beat the queen.
        let hands = [[c(.ace, .spades)], [], lead, [c(.ace, .spades, 1)]]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, leader: 2, hands: hands, trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.cards, [c(.queen, .spades)])
        XCTAssertEqual(blocker, 3)
        // The leader's own cards never block.
        let ownCards = [lead + [c(.ace, .spades)], [], [], []]
        XCTAssertEqual(Rules.checkThrow(lead, leader: 0, hands: ownCards, trump: t), .ok)
    }

    func testTrumpThrowBeatenByRankCard() {
        let lead = [c(.ace, .hearts)] + pair(.king, .hearts)
        let hands = [lead, [c(.two, .clubs)], [], []]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, leader: 0, hands: hands, trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.cards, [c(.ace, .hearts)])
        XCTAssertEqual(blocker, 1)
    }

    func testThrowAgainstPool() {
        let lead = pair(.queen, .spades) + [c(.nine, .spades)]
        guard case let .fails(forced, blocker) = Rules.checkThrow(lead, against: [c(.ten, .spades), sj0], trump: t) else {
            return XCTFail("throw should fail")
        }
        XCTAssertEqual(forced.cards, [c(.nine, .spades)])
        XCTAssertEqual(blocker, -1)
        XCTAssertEqual(Rules.checkThrow(lead, against: [c(.eight, .spades), c(.ace, .hearts)], trump: t), .ok)
    }

    // MARK: Follow requirement

    func testFollowRequirementForSingleAndPairLeads() {
        XCTAssertEqual(Rules.followRequirement(lead: [c(.king, .spades)], suitCards: pair(.three, .spades), trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 0))
        XCTAssertEqual(Rules.followRequirement(lead: pair(.nine, .spades), suitCards: pair(.three, .spades) + [c(.five, .spades)],
                                               trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 1))
        XCTAssertEqual(Rules.followRequirement(lead: pair(.nine, .spades),
                                               suitCards: [c(.three, .spades), c(.five, .spades), c(.seven, .spades)], trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 0))
    }

    func testFollowRequirementForTractorLeads() {
        let lead = pair(.five, .spades) + pair(.six, .spades)
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: pair(.nine, .spades) + pair(.ten, .spades) + [c(.jack, .spades)],
                                               trump: t),
                       FollowRequirement(tractorLengths: [2], totalPairs: 2))
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: pair(.three, .spades) + pair(.seven, .spades) + [c(.queen, .spades)],
                                               trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 2))
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: pair(.three, .spades) + [c(.seven, .spades), c(.eight, .spades)],
                                               trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 1))
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: [c(.three, .spades), c(.four, .spades), c(.seven, .spades)],
                                               trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 0))
        // Three-pair tractor led: a 2-run is not enough, so pairs are owed instead.
        let long = pair(.five, .spades) + pair(.six, .spades) + pair(.seven, .spades)
        XCTAssertEqual(Rules.followRequirement(lead: long, suitCards: pair(.nine, .spades) + pair(.ten, .spades) + pair(.king, .spades),
                                               trump: t),
                       FollowRequirement(tractorLengths: [], totalPairs: 3))
        XCTAssertEqual(Rules.followRequirement(lead: long, suitCards: pair(.eight, .spades) + pair(.nine, .spades)
                                                    + pair(.ten, .spades) + pair(.jack, .spades), trump: t),
                       FollowRequirement(tractorLengths: [3], totalPairs: 3))
    }

    func testFollowRequirementForThrows() {
        // Tractor + pair + single thrown; follower holds a 3-run: tractor plus the leftover pair.
        let lead = pair(.three, .spades) + pair(.four, .spades) + pair(.nine, .spades) + [c(.ace, .spades)]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: pair(.six, .spades) + pair(.seven, .spades) + pair(.eight, .spades),
                                               trump: t),
                       FollowRequirement(tractorLengths: [2], totalPairs: 3))
        // Two tractors thrown; follower holds a 4-run, which splits into two tractors.
        let twoTractors = pair(.three, .spades) + pair(.four, .spades) + pair(.seven, .spades) + pair(.eight, .spades)
        XCTAssertEqual(Rules.followRequirement(lead: twoTractors, suitCards: pair(.nine, .spades) + pair(.ten, .spades)
                                                    + pair(.jack, .spades) + pair(.queen, .spades), trump: t),
                       FollowRequirement(tractorLengths: [2, 2], totalPairs: 4))
    }

    func testFollowRequirementChoosesTractorsThatKeepStructure() {
        // Trumps (hearts, rank 2): A♥A♥ 2♠2♠ 2♣2♣ 2♥2♥ SJSJ. A 3-tractor can be taken four ways; only
        // 2♠/2♣ + 2♥ + SJ leaves A♥A♥ + the other rank pair as a second tractor.
        let lead = pair(.three, .hearts) + pair(.four, .hearts) + pair(.five, .hearts) + pair(.eight, .hearts) + pair(.nine, .hearts)
        let held = pair(.ace, .hearts) + pair(.two, .spades) + pair(.two, .clubs) + pair(.two, .hearts) + [sj0, sj1]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: held, trump: t),
                       FollowRequirement(tractorLengths: [3, 2], totalPairs: 5))
    }

    func testFollowRequirementKeepsRunsWhenOnlyPairsAreOwed() {
        // 3-tractor + 2-tractor thrown; follower has a 2-run and three loose pairs.
        let lead = pair(.three, .spades) + pair(.four, .spades) + pair(.five, .spades) + pair(.eight, .spades) + pair(.nine, .spades)
        let held = pair(.six, .spades) + pair(.seven, .spades) + pair(.ten, .spades) + pair(.queen, .spades) + pair(.ace, .spades)
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: held, trump: t),
                       FollowRequirement(tractorLengths: [2], totalPairs: 5))
    }

    func testFallbackPairsAreChosenToKeepEveryLaterTractor() {
        // Trumps (hearts, rank 2) thrown: 5♥-6♥-7♥, A♥-2♦ and J♥-Q♥ tractors (7 pairs).
        let lead = pair(.five, .hearts) + pair(.six, .hearts) + pair(.seven, .hearts)
            + pair(.ace, .hearts) + pair(.two, .diamonds) + pair(.jack, .hearts) + pair(.queen, .hearts)
        // The follower has no 3-run, so the 3-tractor asks for 3 pairs. Giving up K♥K♥, BJBJ and one
        // off-suit rank pair keeps three 2-runs (3♥-4♥, 8♥-9♥, 2♠/2♣-2♥) for the two 2-tractors.
        let held = pair(.three, .hearts) + pair(.four, .hearts) + pair(.eight, .hearts) + pair(.nine, .hearts)
            + pair(.king, .hearts) + pair(.two, .clubs) + pair(.two, .spades) + pair(.two, .hearts) + [sj0, bj0, bj1]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: held, trump: t),
                       FollowRequirement(tractorLengths: [2, 2], totalPairs: 7))
        // Seven pairs with only one tractor is not enough.
        let oneTractor = pair(.three, .hearts) + pair(.four, .hearts) + pair(.eight, .hearts) + pair(.king, .hearts)
            + pair(.two, .clubs) + pair(.two, .spades) + [bj0, bj1]
        XCTAssertEqual(Rules.validateFollow(oneTractor, hand: held, lead: lead, trump: t), .mustPlayTractor(length: 2))
        let twoTractors = pair(.three, .hearts) + pair(.four, .hearts) + pair(.eight, .hearts) + pair(.nine, .hearts)
            + pair(.two, .spades) + pair(.two, .hearts) + pair(.king, .hearts)
        XCTAssertNil(Rules.validateFollow(twoTractors, hand: held, lead: lead, trump: t))
    }

    // MARK: Following

    func testWrongCountAndCardsNotInHand() {
        let hand = [c(.three, .spades), c(.four, .spades)]
        XCTAssertEqual(Rules.validateFollow(hand, hand: hand, lead: [c(.king, .spades)], trump: t), .wrongCount(expected: 1))
        XCTAssertEqual(Rules.validateFollow([c(.five, .spades)], hand: hand, lead: [c(.king, .spades)], trump: t), .cardsNotInHand)
    }

    func testMustFollowSuit() {
        let hand = [c(.three, .spades), c(.five, .diamonds), c(.four, .hearts)]
        let lead = [c(.king, .spades)]
        XCTAssertEqual(Rules.validateFollow([c(.five, .diamonds)], hand: hand, lead: lead, trump: t), .mustFollowSuit(.plain(.spades)))
        // Ruffing is not allowed while you still hold the led suit.
        XCTAssertEqual(Rules.validateFollow([c(.four, .hearts)], hand: hand, lead: lead, trump: t), .mustFollowSuit(.plain(.spades)))
        XCTAssertNil(Rules.validateFollow([c(.three, .spades)], hand: hand, lead: lead, trump: t))
        // Trumps led: off-suit rank cards and jokers are trumps too.
        let trumpHand = [c(.two, .clubs), c(.ace, .spades)]
        XCTAssertEqual(Rules.validateFollow([c(.ace, .spades)], hand: trumpHand, lead: [c(.six, .hearts)], trump: t),
                       .mustFollowSuit(.trump))
        XCTAssertNil(Rules.validateFollow([c(.two, .clubs)], hand: trumpHand, lead: [c(.six, .hearts)], trump: t))
    }

    func testTrumpRankCardOfTheLedSuitIsNotThatSuit() {
        // Rank 2, hearts trump: 2♠ is a trump, so it can't follow a spade lead while you hold a real spade,
        // and someone whose only "spade" is 2♠ is void in spades.
        let lead = [c(.king, .spades)]
        let hand = [c(.two, .spades), c(.seven, .spades), c(.nine, .diamonds)]
        XCTAssertEqual(Rules.validateFollow([c(.two, .spades)], hand: hand, lead: lead, trump: t), .mustFollowSuit(.plain(.spades)))
        XCTAssertNil(Rules.validateFollow([c(.seven, .spades)], hand: hand, lead: lead, trump: t))
        let onlyRankSpade = [c(.two, .spades), c(.nine, .diamonds)]
        XCTAssertNil(Rules.validateFollow([c(.nine, .diamonds)], hand: onlyRankSpade, lead: lead, trump: t))
        // ...and 2♠ played to a spade lead is a ruff that wins.
        XCTAssertEqual(Rules.winningIndex(plays(lead, [c(.ace, .spades)], [c(.two, .spades)]), trump: t), 2)
        // A spade and 2♠ together can't be led: they are two different groups.
        XCTAssertEqual(Rules.validateLead([c(.seven, .spades), c(.two, .spades)], hand: hand, trump: t), .mixedSuits)
        // With trumps led, 2♣ and jokers are trumps you must play.
        let trumpLead = [c(.five, .hearts)]
        let trumpHand = [c(.two, .clubs), c(.queen, .clubs)]
        XCTAssertEqual(Rules.validateFollow([c(.queen, .clubs)], hand: trumpHand, lead: trumpLead, trump: t), .mustFollowSuit(.trump))
    }

    func testNoTrumpRoundRankPairsAndJokers() {
        // No trump suit, rank 2: rank cards of every suit are equal trumps just below the jokers.
        let lead = pair(.two, .spades) + [sj0, sj1]
        XCTAssertEqual(Combos.shape(of: lead, trump: nt), .tractor(2))
        // Two rank pairs have the same strength, so they are not a tractor.
        XCTAssertNil(Combos.shape(of: pair(.two, .clubs) + pair(.two, .hearts), trump: nt))
        // A rank pair and the big jokers skip the small jokers, so the follower has two pairs, no tractor.
        let held = pair(.two, .clubs) + [bj0, bj1] + [c(.ace, .hearts), c(.king, .hearts)]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: Combos.cards(held, in: .trump, trump: nt), trump: nt),
                       FollowRequirement(tractorLengths: [], totalPairs: 2))
        XCTAssertEqual(Rules.validateFollow(pair(.two, .clubs) + [c(.ace, .hearts), c(.king, .hearts)], hand: held, lead: lead, trump: nt),
                       .mustFollowSuit(.trump))
        XCTAssertNil(Rules.validateFollow(pair(.two, .clubs) + [bj0, bj1], hand: held, lead: lead, trump: nt))
        // Two loose pairs don't beat the tractor even though the big jokers are higher.
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.two, .clubs) + [bj0, bj1]), trump: nt), 0)
        // In no trump, A♥ is a plain heart, not a trump.
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .hearts)], [c(.ace, .hearts)], [c(.two, .diamonds)]), trump: nt), 2)
    }

    func testShortInSuitPlaysAllAndFills() {
        let hand = [c(.three, .spades), c(.five, .diamonds), c(.six, .clubs), c(.four, .hearts)]
        let lead = pair(.nine, .spades)
        XCTAssertNil(Rules.validateFollow([c(.three, .spades), c(.five, .diamonds)], hand: hand, lead: lead, trump: t))
        XCTAssertNil(Rules.validateFollow([c(.three, .spades), c(.four, .hearts)], hand: hand, lead: lead, trump: t))
        XCTAssertEqual(Rules.validateFollow([c(.five, .diamonds), c(.six, .clubs)], hand: hand, lead: lead, trump: t),
                       .mustFollowSuit(.plain(.spades)))
    }

    func testVoidMeansAnything() {
        let hand = [c(.five, .diamonds), c(.six, .clubs), c(.four, .hearts), sj0]
        let lead = pair(.nine, .spades)
        XCTAssertNil(Rules.validateFollow([c(.five, .diamonds), c(.six, .clubs)], hand: hand, lead: lead, trump: t))
        XCTAssertNil(Rules.validateFollow([c(.four, .hearts), sj0], hand: hand, lead: lead, trump: t))
        XCTAssertNil(Rules.validateFollow([c(.four, .hearts), c(.six, .clubs)], hand: hand, lead: lead, trump: t))
    }

    func testMustPlayPair() {
        let lead = pair(.nine, .spades)
        let hand = pair(.three, .spades) + [c(.five, .spades), c(.six, .diamonds)]
        XCTAssertEqual(Rules.validateFollow([c(.three, .spades), c(.five, .spades)], hand: hand, lead: lead, trump: t),
                       .mustPlayPairs(required: 1))
        XCTAssertNil(Rules.validateFollow(pair(.three, .spades), hand: hand, lead: lead, trump: t))
        // No pair in spades: any two spades. The 2♠ pair is trump, not spades.
        let noPair = pair(.two, .spades) + [c(.three, .spades), c(.five, .spades)]
        XCTAssertNil(Rules.validateFollow([c(.three, .spades), c(.five, .spades)], hand: noPair, lead: lead, trump: t))
    }

    func testTrumpPairLedMustBeAnsweredWithRankPair() {
        let hand = pair(.two, .spades) + [c(.seven, .hearts), c(.king, .diamonds)]
        let lead = pair(.five, .hearts)
        XCTAssertEqual(Rules.validateFollow([c(.seven, .hearts), c(.two, .spades)], hand: hand, lead: lead, trump: t),
                       .mustPlayPairs(required: 1))
        XCTAssertNil(Rules.validateFollow(pair(.two, .spades), hand: hand, lead: lead, trump: t))
    }

    func testMustPlayTractor() {
        let lead = pair(.five, .spades) + pair(.six, .spades)
        let hand = pair(.nine, .spades) + pair(.ten, .spades) + pair(.three, .spades) + [c(.king, .diamonds)]
        XCTAssertEqual(Rules.validateFollow(pair(.three, .spades) + pair(.nine, .spades), hand: hand, lead: lead, trump: t),
                       .mustPlayTractor(length: 2))
        XCTAssertNil(Rules.validateFollow(pair(.nine, .spades) + pair(.ten, .spades), hand: hand, lead: lead, trump: t))
    }

    func testTractorFallsBackToPairs() {
        let lead = pair(.five, .spades) + pair(.six, .spades)
        let hand = pair(.three, .spades) + pair(.nine, .spades) + [c(.king, .spades), c(.queen, .spades)]
        XCTAssertEqual(Rules.validateFollow(pair(.three, .spades) + [c(.king, .spades), c(.queen, .spades)],
                                            hand: hand, lead: lead, trump: t),
                       .mustPlayPairs(required: 2))
        XCTAssertNil(Rules.validateFollow(pair(.three, .spades) + pair(.nine, .spades), hand: hand, lead: lead, trump: t))

        let onePair = pair(.three, .spades) + [c(.nine, .spades), c(.king, .spades), c(.queen, .spades)]
        XCTAssertEqual(Rules.validateFollow([c(.three, .spades), c(.nine, .spades), c(.king, .spades), c(.queen, .spades)],
                                            hand: onePair, lead: lead, trump: t),
                       .mustPlayPairs(required: 1))
        XCTAssertNil(Rules.validateFollow(pair(.three, .spades) + [c(.nine, .spades), c(.king, .spades)],
                                          hand: onePair, lead: lead, trump: t))
    }

    func testTrumpTractorAcrossRankMustBePlayed() {
        let lead = pair(.three, .hearts) + pair(.four, .hearts)
        let hand = pair(.ace, .hearts) + pair(.two, .clubs) + [c(.nine, .hearts), c(.ten, .hearts)]
        XCTAssertEqual(Rules.validateFollow(pair(.ace, .hearts) + [c(.nine, .hearts), c(.ten, .hearts)], hand: hand, lead: lead, trump: t),
                       .mustPlayTractor(length: 2))
        XCTAssertNil(Rules.validateFollow(pair(.ace, .hearts) + pair(.two, .clubs), hand: hand, lead: lead, trump: t))
    }

    func testThrowFollowNeedsMatchingPair() {
        let lead = [c(.ace, .spades)] + pair(.king, .spades)
        let hand = pair(.five, .spades) + [c(.seven, .spades), c(.nine, .spades)]
        XCTAssertEqual(Rules.validateFollow([c(.five, .spades), c(.seven, .spades), c(.nine, .spades)],
                                            hand: hand, lead: lead, trump: t),
                       .mustPlayPairs(required: 1))
        XCTAssertNil(Rules.validateFollow(pair(.five, .spades) + [c(.nine, .spades)], hand: hand, lead: lead, trump: t))
    }

    func testStructureSearchBacktracksAtTrumpRankLevel() {
        // Needs a 3-tractor and a 2-tractor. The first 3-tractors tried (starting at A♥) leave no
        // second tractor; only 2♠2♠ 2♥2♥ SJSJ + A♥A♥ 2♣2♣ works.
        let lead = pair(.three, .hearts) + pair(.four, .hearts) + pair(.five, .hearts) + pair(.eight, .hearts) + pair(.nine, .hearts)
        let trumps = pair(.ace, .hearts) + pair(.two, .spades) + pair(.two, .clubs) + pair(.two, .hearts) + [sj0, sj1]
        let hand = trumps + [c(.six, .hearts), c(.ten, .hearts), c(.three, .diamonds)]
        XCTAssertNil(Rules.validateFollow(trumps, hand: hand, lead: lead, trump: t))
        // Without the small jokers only one tractor fits.
        let missingJokers = pair(.ace, .hearts) + pair(.two, .spades) + pair(.two, .clubs) + pair(.two, .hearts)
            + [c(.six, .hearts), c(.ten, .hearts)]
        XCTAssertEqual(Rules.validateFollow(missingJokers, hand: hand, lead: lead, trump: t), .mustPlayTractor(length: 2))
        XCTAssertTrue(Rules.matchesStructure(trumps, lead: lead, trump: t))
        XCTAssertEqual(Rules.winningIndex([Play(player: 0, cards: lead), Play(player: 1, cards: trumps)], trump: t), 1)
    }

    func testFollowViolationExplanations() {
        // Learners often take a trump-rank card (2♠ when 2s are trump) for a card of its printed
        // suit, so the follow-suit explanations say where those cards belong.
        XCTAssertEqual(FollowViolation.mustFollowSuit(.plain(.spades)).explanation,
                       "Spades were led and you still have spades, so you must play spades. "
                       + "A spade of the trump rank counts as a trump, not a spade. "
                       + "If you have too few spades, play them all and fill up with other cards.")
        XCTAssertEqual(FollowViolation.mustFollowSuit(.trump).explanation,
                       "Trumps were led and you still have trumps, so you must play trumps. "
                       + "Jokers and trump-rank cards of every suit are trumps too. "
                       + "If you have too few trumps, play them all and fill up with other cards.")
        XCTAssertTrue(FollowViolation.mustFollowSuit(.plain(.diamonds)).explanation.contains(
            "A diamond of the trump rank counts as a trump, not a diamond."))
        XCTAssertEqual(FollowViolation.mustPlayTractor(length: 2).explanation,
                       "A tractor was led and you hold a tractor in that suit, so you must play it.")
        XCTAssertTrue(FollowViolation.mustPlayTractor(length: 3).explanation.contains("tractor of 3 pairs"))
        // A "pair" means two identical cards (2♠ + 2♣ is not a pair), so the explanation says so.
        XCTAssertEqual(FollowViolation.mustPlayPairs(required: 1).explanation,
                       "The lead contains a pair and you have a pair in that suit, so you must play a pair "
                       + "(two identical cards).")
        XCTAssertTrue(FollowViolation.mustPlayPairs(required: 2).explanation.contains("at least 2 pairs"))
        XCTAssertEqual(FollowViolation.wrongCount(expected: 1).explanation, "Play exactly 1 card, the same number as the lead.")
        XCTAssertEqual(FollowViolation.wrongCount(expected: 4).explanation, "Play exactly 4 cards, the same number as the lead.")
        let all: [FollowViolation] = [.wrongCount(expected: 2), .cardsNotInHand, .mustFollowSuit(.plain(.clubs)),
                                      .mustPlayTractor(length: 2), .mustPlayPairs(required: 3)]
        for violation in all {
            XCTAssertFalse(violation.explanation.isEmpty)
            XCTAssertFalse(violation.explanation.contains("\u{2014}"))
        }
    }

    // MARK: Winning a trick

    func testWinningSingles() {
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.ace, .spades)], [c(.queen, .spades)]), trump: t), 1)
        // Ties go to the earlier play.
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.ace, .spades)], [c(.queen, .spades)],
                                                [c(.ace, .spades, 1)]), trump: t), 1)
        // Off-suit discards never win.
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.ace, .diamonds)]), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays([c(.three, .spades)], [c(.ace, .diamonds)], [c(.ace, .clubs)]), trump: t), 0)
    }

    func testRuffsAndOverRuffs() {
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.three, .hearts)]), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.three, .hearts)], [c(.five, .hearts)]), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.ace, .hearts)], [c(.two, .clubs)]), trump: t), 2)
        // Off-suit rank cards tie with each other.
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.two, .clubs)], [c(.two, .diamonds)]), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.two, .clubs)], [c(.two, .hearts)]), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.two, .hearts)], [sj0], [bj0]), trump: t), 3)
        // A later plain card can't beat a ruff.
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.three, .hearts)], [c(.ace, .spades)]), trump: t), 1)
    }

    func testTrumpLeads() {
        XCTAssertEqual(Rules.winningIndex(plays([c(.three, .hearts)], [c(.two, .spades)], [c(.ace, .hearts)]), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays([c(.three, .hearts)], [c(.ace, .spades)]), trump: t), 0)
        // No trump suit: all rank cards are equal.
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.two, .clubs)], [c(.two, .hearts)]), trump: nt), 1)
        XCTAssertEqual(Rules.winningIndex(plays([c(.two, .clubs)], [c(.two, .hearts)], [sj0]), trump: nt), 2)
    }

    func testWinningPairs() {
        let lead = pair(.nine, .spades)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.ten, .spades)), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, [c(.ace, .spades), c(.king, .spades)]), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts)), trump: t), 1)
        // Two unmatched trumps don't make a pair, so they can't win.
        XCTAssertEqual(Rules.winningIndex(plays(lead, [c(.three, .hearts), c(.four, .hearts)]), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts), pair(.five, .hearts)), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts), pair(.ace, .spades)), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.two, .clubs), pair(.two, .diamonds)), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.two, .clubs), pair(.two, .hearts)), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.ace, .diamonds)), trump: t), 0)
        // A trump and a spade together is neither suit, so it never wins.
        XCTAssertEqual(Rules.winningIndex(plays(lead, [c(.ace, .hearts), c(.ace, .spades)]), trump: t), 0)
    }

    func testWinningTractors() {
        let lead = pair(.five, .spades) + pair(.six, .spades)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.seven, .spades) + pair(.eight, .spades)), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.nine, .spades) + pair(.king, .spades)), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts) + pair(.four, .hearts)), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts) + pair(.six, .hearts)), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts) + pair(.four, .hearts),
                                                pair(.ace, .hearts) + pair(.two, .spades)), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.two, .spades) + pair(.two, .clubs)), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.two, .clubs) + pair(.two, .hearts)), trump: t), 1)
        // Rank 8: 7799 is a tractor and beats 5566.
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.seven, .spades) + pair(.nine, .spades)), trump: t8), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.seven, .spades) + pair(.nine, .spades)), trump: t), 0)
    }

    func testWinningThrows() {
        let lead = [c(.ace, .spades)] + pair(.king, .spades)
        // Following in suit with a lower pair doesn't win.
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.queen, .spades) + [c(.jack, .spades)]), trump: t), 0)
        // Ruff with a pair and a single wins; three loose trumps don't.
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts) + [c(.four, .hearts)]), trump: t), 1)
        XCTAssertEqual(Rules.winningIndex(plays(lead, [c(.three, .hearts), c(.five, .hearts), c(.seven, .hearts)]), trump: t), 0)
        // Over-ruff is judged on the pair (the lead's largest component), not the single.
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.three, .hearts) + [c(.four, .hearts)],
                                                pair(.six, .hearts) + [c(.five, .hearts)]), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays(lead, pair(.four, .hearts) + [c(.seven, .hearts)],
                                                pair(.three, .hearts) + [bj0]), trump: t), 1)
        // All-singles throw: the ruff's highest card is the key.
        let singles = [c(.ace, .spades), c(.king, .spades)]
        XCTAssertEqual(Rules.winningIndex(plays(singles, [c(.three, .hearts), c(.five, .hearts)],
                                                [c(.four, .hearts), c(.six, .hearts)]), trump: t), 2)
        XCTAssertEqual(Rules.winningIndex(plays(singles, [c(.three, .hearts), c(.six, .hearts)],
                                                [c(.four, .hearts), c(.five, .hearts)]), trump: t), 1)
    }

    func testWinningIndexOnPartialTricks() {
        XCTAssertEqual(Rules.winningIndex([], trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)]), trump: t), 0)
        XCTAssertEqual(Rules.winningIndex(plays([c(.king, .spades)], [c(.ace, .spades)]), trump: t), 1)
        // Player numbers don't matter, only the order of plays.
        let trick = [Play(player: 3, cards: [c(.four, .clubs)]), Play(player: 0, cards: [c(.nine, .clubs)])]
        XCTAssertEqual(Rules.winningIndex(trick, trump: t), 1)
    }

    func testMatchesStructure() {
        let tractorPlusPair = pair(.three, .spades) + pair(.four, .spades) + pair(.nine, .spades)
        XCTAssertTrue(Rules.matchesStructure(pair(.six, .hearts) + pair(.seven, .hearts) + pair(.eight, .hearts),
                                             lead: tractorPlusPair, trump: t))
        XCTAssertFalse(Rules.matchesStructure(pair(.six, .hearts) + pair(.eight, .hearts) + pair(.ten, .hearts),
                                              lead: tractorPlusPair, trump: t))
        // Lead's singles can be covered by anything, even pairs.
        XCTAssertTrue(Rules.matchesStructure(pair(.six, .hearts), lead: [c(.ace, .spades), c(.king, .spades)], trump: t))
        // Two thrown pairs can be matched by a tractor (it contains two pairs).
        XCTAssertTrue(Rules.matchesStructure(pair(.six, .hearts) + pair(.seven, .hearts),
                                             lead: pair(.king, .spades) + pair(.nine, .spades), trump: t))
        // Counts must match and the play must be one group.
        XCTAssertFalse(Rules.matchesStructure(pair(.six, .hearts), lead: [c(.ace, .spades)], trump: t))
        XCTAssertFalse(Rules.matchesStructure([c(.six, .hearts), c(.six, .spades)], lead: [c(.ace, .spades), c(.king, .spades)],
                                              trump: t))
        XCTAssertFalse(Rules.matchesStructure([], lead: [], trump: t))
    }

    func testStructureKeyUsesLargestComponent() {
        // Tractor + pair thrown; a 3-run can be split two ways, the key is the best tractor top.
        let lead = pair(.three, .spades) + pair(.four, .spades) + pair(.nine, .spades)
        let play = pair(.six, .hearts) + pair(.seven, .hearts) + pair(.eight, .hearts)
        XCTAssertEqual(Rules.structureKey(play, lead: lead, trump: t), t.strength(c(.eight, .hearts)))
        XCTAssertEqual(Rules.structureKey([c(.five, .hearts)], lead: [c(.ace, .spades)], trump: t), t.strength(c(.five, .hearts)))
        XCTAssertNil(Rules.structureKey([c(.five, .hearts), c(.six, .hearts)], lead: pair(.ace, .spades), trump: t))
    }
}
