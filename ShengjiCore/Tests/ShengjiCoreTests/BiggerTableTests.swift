import Foundation
import XCTest
@testable import ShengjiCore

/// Tables of 6 players with 3 decks and 8 players with 4: seats, dealing, triples and four of a kind,
/// following and winning with them, the declaration ladder, scoring per deck, whole games with bots,
/// and the general rules agreeing with the two-deck rules wherever no face appears more than twice.
final class BiggerTableTests: XCTestCase {
    private func c(_ rank: Rank, _ suit: Suit, _ copy: Int = 0) -> Card { Card(rank, suit, copy: copy) }

    /// `count` copies of a face, from deck `from` on.
    private func copies(_ rank: Rank, _ suit: Suit, _ count: Int, from: Int = 0) -> [Card] {
        (from..<(from + count)).map { Card(rank, suit, copy: $0) }
    }

    // MARK: Tables, decks and seats

    func testTableSizes() {
        XCTAssertEqual(TableSize.four.decks, 2)
        XCTAssertEqual(TableSize.four.handSize, 25)
        XCTAssertEqual(TableSize.four.kittySize, 8)
        XCTAssertEqual(TableSize.four.totalPoints, 200)
        XCTAssertEqual(TableSize.six.decks, 3)
        XCTAssertEqual(TableSize.six.handSize, 26)
        XCTAssertEqual(TableSize.six.kittySize, 6)
        XCTAssertEqual(TableSize.six.totalPoints, 300)
        XCTAssertEqual(TableSize.eight.decks, 4)
        XCTAssertEqual(TableSize.eight.handSize, 26)
        XCTAssertEqual(TableSize.eight.kittySize, 8)
        XCTAssertEqual(TableSize.eight.cardCount, 216)
        for table in TableSize.all {
            XCTAssertEqual(table.players * table.handSize + table.kittySize, table.cardCount, "\(table)")
        }
        XCTAssertEqual(TableSize(players: 3), .four)
        XCTAssertEqual(TableSize(players: 12), .eight)
        XCTAssertNil(TableSize(exactly: 5))
        XCTAssertEqual(TableSize(exactly: 6), .six)
    }

    func testDecksHoldEveryFaceOncePerDeck() {
        for decks in 1...4 {
            let cards = Deck.cards(decks: decks)
            XCTAssertEqual(cards.count, 54 * decks)
            XCTAssertEqual(Set(cards.map(\.id)).count, cards.count)
            XCTAssertTrue(cards.faceCounts.values.allSatisfy { $0 == decks })
        }
        XCTAssertEqual(Deck.cards(decks: 2), Deck.double())
    }

    func testSeatsNamesAndTeams() {
        XCTAssertEqual(Seats.teammates(of: 0, players: 4), [2])
        XCTAssertEqual(Seats.opponents(of: 0, players: 4), [1, 3])
        XCTAssertEqual(Seats.teammates(of: 0, players: 6), [2, 4])
        XCTAssertEqual(Seats.opponents(of: 0, players: 6), [1, 3, 5])
        XCTAssertEqual(Seats.teammates(of: 3, players: 6), [5, 1])
        XCTAssertEqual(Seats.teammates(of: 0, players: 8), [2, 4, 6])
        XCTAssertEqual((0..<6).map { Seats.name($0, players: 6) },
                       ["You", "Southeast", "Northeast", "North", "Northwest", "Southwest"])
        XCTAssertEqual((0..<8).map { Seats.shortName($0, players: 8) }, ["You", "SE", "E", "NE", "N", "NW", "W", "SW"])
        XCTAssertEqual((0..<4).map { Seats.name($0, players: 4) }, (0..<4).map { Seats.name($0) })
        XCTAssertEqual(Seats.next(after: 5, players: 6), 0)
        XCTAssertEqual(BotText.name(4, from: 0, players: 6), "your partner Northwest")
        XCTAssertEqual(BotText.name(3, from: 0, players: 6), "North")
        XCTAssertEqual(BotText.possessive(2, from: 0, players: 8), "your partner East's")
        XCTAssertEqual(BotText.name(2, from: 0), "your partner")
    }

    // MARK: Combinations

    func testWidestSetsComeFirst() {
        let trump = Trump(rank: .two, suit: .hearts)
        let lead = copies(.seven, .spades, 3) + copies(.eight, .spades, 3) + copies(.nine, .spades, 2)
        let components = Combos.decompose(lead, trump: trump)
        XCTAssertEqual(components.map(\.shape), [.setTractor(width: 3, length: 2), .pair])
        XCTAssertEqual(Combos.shape(of: copies(.king, .clubs, 3), trump: trump), .set(3))
        XCTAssertEqual(Combos.shape(of: copies(.king, .clubs, 4), trump: trump), .set(4))
        XCTAssertNil(Combos.shape(of: copies(.king, .clubs, 3) + [c(.nine, .clubs)], trump: trump))
        XCTAssertEqual(ComboShape.set(3).name, "triple")
        XCTAssertEqual(ComboShape.set(4).name, "four of a kind")
        XCTAssertEqual(ComboShape.setTractor(width: 3, length: 2).name, "tractor of triples")
        XCTAssertEqual(ComboShape.setTractor(width: 4, length: 3).name, "tractor of 3 fours")
        XCTAssertEqual(ComboShape.make(width: 2, length: 3), .tractor(3))
        XCTAssertEqual(ComboShape.set(3).cardCount, 3)
    }

    func testTractorsOfTriplesSkipTheTrumpRank() {
        let trump = Trump(rank: .eight, suit: .hearts)
        let cards = copies(.seven, .spades, 3) + copies(.nine, .spades, 3)
        XCTAssertEqual(Combos.shape(of: cards, trump: trump), .setTractor(width: 3, length: 2))
        // Trump-rank triples of different suits are equal, not consecutive.
        let rankCards = copies(.eight, .spades, 3) + copies(.eight, .clubs, 3)
        XCTAssertEqual(Combos.decompose(rankCards, trump: trump).map(\.shape), [.set(3), .set(3)])
    }

    // MARK: Following

    func testFollowingATriple() {
        let trump = Trump(rank: .two, suit: .hearts)
        let lead = copies(.king, .spades, 3)
        let triple = copies(.five, .spades, 3)
        let junk = [c(.nine, .spades), c(.four, .spades), c(.three, .spades)]
        let hand = triple + junk
        XCTAssertEqual(Rules.validateFollow(junk, hand: hand, lead: lead, trump: trump),
                       .mustPlaySets(width: 3, required: 1))
        XCTAssertNil(Rules.validateFollow(triple, hand: hand, lead: lead, trump: trump))
        XCTAssertTrue(FollowViolation.mustPlaySets(width: 3, required: 1).explanation.contains("triple"))

        // Without a triple, a pair is owed.
        let pairHand = copies(.five, .spades, 2) + junk
        XCTAssertEqual(Rules.validateFollow(junk, hand: pairHand, lead: lead, trump: trump), .mustPlayPairs(required: 1))
        XCTAssertNil(Rules.validateFollow(copies(.five, .spades, 2) + [c(.nine, .spades)], hand: pairHand, lead: lead,
                                          trump: trump))
        // Singles only: anything of the suit.
        let singles = junk + [c(.ace, .spades)]
        XCTAssertNil(Rules.validateFollow(Array(singles.prefix(3)), hand: singles, lead: lead, trump: trump))
    }

    func testFollowingATractorOfTriples() {
        let trump = Trump(rank: .two, suit: .hearts)
        let lead = copies(.seven, .spades, 3) + copies(.eight, .spades, 3)
        let run = copies(.four, .spades, 3) + copies(.five, .spades, 3)
        let hand = run + [c(.king, .spades), c(.queen, .spades)]
        let requirement = Rules.followRequirement(lead: lead, suitCards: hand, trump: trump)
        XCTAssertEqual(requirement.units, [.setTractor(width: 3, length: 2)])
        XCTAssertEqual(Rules.validateFollow(copies(.four, .spades, 3) + [c(.five, .spades), c(.king, .spades),
                                                                        c(.queen, .spades)],
                                            hand: hand, lead: lead, trump: trump),
                       .mustPlaySetTractor(width: 3, length: 2))
        XCTAssertNil(Rules.validateFollow(run, hand: hand, lead: lead, trump: trump))

        // Two separate triples: both are owed.
        let apart = copies(.four, .spades, 3) + copies(.ten, .spades, 3) + [c(.queen, .spades)]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: apart, trump: trump).units, [.set(3), .set(3)])
        // Pairs only: as many pairs as the tractor has steps.
        let pairs = copies(.four, .spades, 2) + copies(.five, .spades, 2) + copies(.jack, .spades, 2) + [c(.three, .spades)]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: pairs, trump: trump).units, [.pair, .pair])
    }

    func testFourOfAKindCountsAsTwoPairsAgainstATractor() {
        let trump = Trump(rank: .two, suit: .hearts)
        let lead = copies(.three, .spades, 2) + copies(.four, .spades, 2)
        let quad = copies(.seven, .spades, 4)
        let hand = quad + [c(.nine, .spades), c(.king, .spades)]
        XCTAssertEqual(Rules.followRequirement(lead: lead, suitCards: hand, trump: trump).units, [.pair, .pair])
        XCTAssertNil(Rules.validateFollow(quad, hand: hand, lead: lead, trump: trump))
        XCTAssertEqual(Rules.validateFollow(copies(.seven, .spades, 2) + [c(.nine, .spades), c(.king, .spades)],
                                            hand: hand, lead: lead, trump: trump),
                       .mustPlayPairs(required: 2))
    }

    // MARK: Winning and throws

    func testOnlyATripleBeatsATriple() {
        let trump = Trump(rank: .two, suit: .hearts)
        let plays = [
            Play(player: 0, cards: copies(.nine, .spades, 3)),
            Play(player: 1, cards: copies(.king, .spades, 3)),
            Play(player: 2, cards: copies(.ace, .spades, 2) + [c(.three, .spades)]),
        ]
        XCTAssertEqual(Rules.winningIndex(plays, trump: trump), 1)
        // A trump triple from someone out of spades beats them all; a trump pair and single do not.
        let ruff = plays + [Play(player: 3, cards: copies(.three, .hearts, 3))]
        XCTAssertEqual(Rules.winningIndex(ruff, trump: trump), 3)
        let weak = plays + [Play(player: 3, cards: copies(.ace, .hearts, 2) + [c(.three, .hearts)])]
        XCTAssertEqual(Rules.winningIndex(weak, trump: trump), 1)
    }

    func testThrowWithATripleFailsAgainstAHigherTriple() {
        let trump = Trump(rank: .two, suit: .hearts)
        let throwCards = copies(.ace, .spades, 3) + copies(.six, .spades, 3)
        var hands = Array(repeating: [Card](), count: 6)
        hands[0] = throwCards
        hands[3] = copies(.seven, .spades, 3)
        guard case let .fails(forced, blocker) = Rules.checkThrow(throwCards, leader: 0, hands: hands, trump: trump) else {
            return XCTFail("the throw should fail")
        }
        XCTAssertEqual(forced.shape, .set(3))
        XCTAssertEqual(Set(forced.cards.map(\.id)), Set(copies(.six, .spades, 3).map(\.id)))
        XCTAssertEqual(blocker, 3)
        // A pair of sevens can't beat a triple of sixes.
        hands[3] = copies(.seven, .spades, 2)
        XCTAssertEqual(Rules.checkThrow(throwCards, leader: 0, hands: hands, trump: trump), .ok)
    }

    // MARK: Declaring

    func testDeclarationStrengthLadder() {
        XCTAssertEqual(Declaration.strength(count: 1, kind: .rankCards), 1)
        XCTAssertEqual(Declaration.strength(count: 2, kind: .rankCards), 2)
        XCTAssertEqual(Declaration.strength(count: 2, kind: .smallJokers), 3)
        XCTAssertEqual(Declaration.strength(count: 2, kind: .bigJokers), 4)
        XCTAssertEqual(Declaration.strength(count: 3, kind: .rankCards), 5)
        XCTAssertEqual(Declaration.strength(count: 4, kind: .bigJokers), 10)
        for strength in 1...10 {
            let count = Declaration.cardCount(forStrength: strength)
            XCTAssertEqual(Declaration.strength(count: count, kind: Declaration.kind(forStrength: strength)), strength)
        }
    }

    func testThreeRankCardsBeatAPairOfBigJokers() throws {
        var hands = Array(repeating: [Card](), count: 6)
        hands[0] = copies(.two, .spades, 3)
        hands[1] = [Card.bigJoker(copy: 0), .bigJoker(copy: 1)]
        var round = Round(trumpRank: .two, dealer: nil, deck: Self.deck(table: .six, hands: hands), table: .six)
        round.dealAll()
        XCTAssertEqual(round.availableDeclarations(for: 0).map(\.strength), [1, 2, 5])
        try round.declare(Declaration(player: 0, cards: [c(.two, .spades)], suit: .spades, strength: 1))
        // Holding it: only more of the same card.
        XCTAssertEqual(round.availableDeclarations(for: 0).map(\.strength), [2, 5])
        try round.declare(Declaration(player: 0, cards: copies(.two, .spades, 2), suit: .spades, strength: 2))
        try round.declare(Declaration(player: 1, cards: [.bigJoker(copy: 0), .bigJoker(copy: 1)], suit: nil, strength: 4))
        XCTAssertEqual(round.availableDeclarations(for: 0).map(\.strength), [5])
        let triple = Declaration(player: 0, cards: copies(.two, .spades, 3), suit: .spades, strength: 5)
        XCTAssertEqual(triple.description, "You declare ♠ (three 2♠)")
        try round.declare(triple)
        XCTAssertEqual(round.trump.suit, .spades)
        // A triple only shows three cards.
        XCTAssertThrowsError(try round.declare(Declaration(player: 1, cards: [.bigJoker(copy: 0)], suit: nil, strength: 7)))
    }

    // MARK: Scoring

    func testScoringScalesWithTheDecks() {
        func check(_ points: Int, decks: Int, hold: Bool, levels: Int) {
            let outcome = Scoring.outcome(defenderPoints: points, decks: decks)
            XCTAssertEqual(outcome.declarersHold, hold, "\(points) with \(decks) decks")
            XCTAssertEqual(outcome.levels, levels, "\(points) with \(decks) decks")
        }
        check(0, decks: 3, hold: true, levels: 3)
        check(55, decks: 3, hold: true, levels: 2)
        check(60, decks: 3, hold: true, levels: 1)
        check(115, decks: 3, hold: true, levels: 1)
        check(120, decks: 3, hold: false, levels: 0)
        check(175, decks: 3, hold: false, levels: 0)
        check(180, decks: 3, hold: false, levels: 1)
        check(300, decks: 3, hold: false, levels: 3)
        check(75, decks: 4, hold: true, levels: 2)
        check(80, decks: 4, hold: true, levels: 1)
        check(160, decks: 4, hold: false, levels: 0)
        check(240, decks: 4, hold: false, levels: 1)
        for points in stride(from: 0, through: 300, by: 5) {
            XCTAssertEqual(Scoring.outcome(defenderPoints: points, decks: 2), Scoring.outcome(defenderPoints: points))
        }
        XCTAssertEqual(Scoring.outcome(defenderPoints: 55, decks: 3).summary,
                       "Defenders scored 55 (under 60): the declarers keep the deal and go up 2 levels.")
    }

    // MARK: Rounds and games

    func testRoundsDealAndPlayOutAtEveryTable() throws {
        for table in TableSize.all {
            for seed in UInt64(1)...6 {
                var rng = SeededGenerator(seed: seed * 31 + UInt64(table.players))
                var round = Round(trumpRank: .five, dealer: seed % 2 == 0 ? nil : Int(seed) % table.players,
                                  rng: &rng, table: table)
                XCTAssertEqual(round.hands.count, table.players)
                try EngineTestSupport.dealWithDeclarations(&round, rng: &rng)
                XCTAssertTrue(round.hands.allSatisfy { $0.count == table.handSize })
                XCTAssertEqual(round.kitty.count, table.kittySize)
                round.finishDealing()
                let dealer = try XCTUnwrap(round.dealer)
                XCTAssertEqual(round.hands[dealer].count, table.handSize + table.kittySize)
                try round.bury(Array(round.hands[dealer].shuffled(using: &rng).prefix(table.kittySize)))
                var moves = 0
                while round.phase == .playing && moves < 600 {
                    guard let seat = round.turn else { break }
                    let hand = round.hands[seat]
                    let cards = round.currentTrick.isEmpty
                        ? Self.randomLead(hand: hand, trump: round.trump, rng: &rng)
                        : Self.legalFollow(hand: hand, lead: round.currentLead, trump: round.trump, rng: &rng)
                    _ = try round.play(cards, by: seat)
                    moves += 1
                }
                XCTAssertEqual(round.phase, .finished, "\(table) seed \(seed)")
                let result = try XCTUnwrap(round.result)
                XCTAssertTrue(round.tricks.allSatisfy { $0.plays.count == table.players })
                let allPoints = round.tricks.reduce(0) { $0 + $1.points } + round.kitty.points
                XCTAssertEqual(allPoints, table.totalPoints)
                XCTAssertEqual(result.outcome, Scoring.outcome(defenderPoints: result.defenderPoints, decks: table.decks))
            }
        }
    }

    func testBotsPlayWholeGamesAtBiggerTables() {
        let fallbacksBefore = BotDiagnostics.shared.fallbackCount
        for table in [TableSize.six, .eight] {
            for (index, levels) in [[BotLevel.standard], [.standard, .beginner]].enumerated() {
                var stats = BotRunStats()
                var game = GameState(settings: GameSettings(table: table))
                var rng = SeededGenerator(seed: UInt64(100 + 10 * table.players + index))
                var rounds = 0
                while game.winner == nil && rounds < 8 {
                    var round = game.makeRound(rng: &rng)
                    BotHarness.play(&round, levels: levels, stats: &stats)
                    guard let result = round.result else { break }
                    let summary = game.record(result)
                    XCTAssertTrue(summary.explanation.contains("\(Scoring.takeoverThreshold(decks: table.decks))"),
                                  summary.explanation)
                    rounds += 1
                }
                XCTAssertEqual(stats.finishedRounds, rounds, "\(table)")
                XCTAssertGreaterThan(rounds, 0)
                XCTAssertEqual(stats.problems, [], "\(table)")
            }
        }
        XCTAssertEqual(BotDiagnostics.shared.fallbackCount, fallbacksBefore, "a bot fell back to the plain legal play")
    }

    func testBotsUseTriplesAtBiggerTables() {
        var stats = BotRunStats()
        var sets = 0
        for seed in UInt64(1)...12 {
            let round = BotHarness.playRound(rank: .two, dealer: Int(seed) % 6, seed: seed, levels: [.standard],
                                             stats: &stats, table: .six)
            for trick in round.tricks {
                let lead = trick.plays[0].cards
                if Combos.decompose(lead, trump: round.trump).contains(where: { $0.shape.needsMoreDecks }) { sets += 1 }
            }
        }
        XCTAssertEqual(stats.problems, [])
        XCTAssertGreaterThan(sets, 0, "bots never led a triple")
    }

    func testNextDealerMovesRoundTheTeam() {
        var game = GameState(settings: GameSettings(table: .six))
        func result(dealer: Int, points: Int) -> RoundResult {
            RoundResult(dealer: dealer, declarerTeam: Seats.team(of: dealer), trump: Trump(rank: .two, suit: .spades),
                        trickPoints: points, kittyPoints: 0, kittyMultiplier: 0, defenderPoints: points,
                        outcome: Scoring.outcome(defenderPoints: points, decks: 3), kitty: [], lastTrickWinner: 1)
        }
        XCTAssertEqual(game.record(result(dealer: 0, points: 60)).nextDealer, 2)
        XCTAssertEqual(game.record(result(dealer: 2, points: 60)).nextDealer, 4)
        XCTAssertEqual(game.record(result(dealer: 4, points: 60)).nextDealer, 0)
        let takeOver = game.record(result(dealer: 0, points: 130))
        XCTAssertEqual(takeOver.nextDealer, 1)
        XCTAssertTrue(takeOver.explanation.contains("reaching 120"), takeOver.explanation)
        XCTAssertTrue(takeOver.explanation.contains("Southeast deals next"), takeOver.explanation)
        XCTAssertEqual(game.nextTrumpRank, game.levels[1])
        // Seen from seat 3 (an opponent of seat 0), the dealer-to-be is two seats to the left.
        let rotated = takeOver.rotated(by: 3, target: .ace, players: 6)
        XCTAssertEqual(rotated.nextDealer, 4)
        XCTAssertTrue(rotated.explanation.contains("reaching 120"), rotated.explanation)
        XCTAssertTrue(rotated.explanation.contains("Northwest deals next"), rotated.explanation)
    }

    func testSeatViewRotatesEverySeat() {
        var rng = SeededGenerator(seed: 9)
        var round = Round(trumpRank: .three, dealer: 4, rng: &rng, table: .eight)
        round.dealAll()
        let view = round.seatView(for: 5)
        XCTAssertEqual(view.players.count, 8)
        XCTAssertEqual(view.handCounts, Array(repeating: 26, count: 8))
        XCTAssertEqual(view.playerCount, 8)
        XCTAssertEqual(view.table, .eight)
        XCTAssertEqual(view.hand, round.hands[5])
        XCTAssertEqual(view.dealer, 7)
        XCTAssertEqual(view.players[3].name, Seats.name(0, players: 8))
    }

    func testSavedRoundsWithoutATableAreForFourPlayers() throws {
        var rng = SeededGenerator(seed: 4)
        let classic = Round(trumpRank: .two, dealer: 0, rng: &rng)
        let data = try JSONEncoder().encode(classic)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("tableSize"))
        XCTAssertEqual(try JSONDecoder().decode(Round.self, from: data).players, 4)

        let big = Round(trumpRank: .two, dealer: 0, rng: &rng, table: .six)
        let decoded = try JSONDecoder().decode(Round.self, from: JSONEncoder().encode(big))
        XCTAssertEqual(decoded.table, .six)
        XCTAssertEqual(decoded.kittySize, 6)

        let settings = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"startRank":2,"targetRank":14}"#.utf8))
        XCTAssertEqual(settings.table, .four)
        let eight = try JSONDecoder().decode(GameSettings.self, from: JSONEncoder().encode(GameSettings(table: .eight)))
        XCTAssertEqual(eight.table, .eight)
    }

    // MARK: Agreement with the two-deck rules

    /// The general rules (sets of any width) give exactly the two-deck answers whenever no face
    /// appears more than twice: decomposition, follow requirements, follow verdicts and trick keys.
    func testGeneralRulesMatchTwoDeckRules() {
        var rng = SeededGenerator(seed: 2024)
        let faces = Deck.double().prefix(54).map(\.face)
        var checked = 0, withTractors = 0
        for index in 0..<900 {
            let trump = Trump(rank: Rank.allCases[index % 13], suit: index % 5 == 4 ? nil : Suit.allCases[index % 4])
            let group: SuitGroup = index % 3 == 0 ? .trump : .plain(Suit.allCases[(index / 3) % 4])
            let groupFaces = faces.filter { trump.group($0) == group }.shuffled(using: &rng)
            guard groupFaces.count >= 6 else { continue }
            func cards(from faces: ArraySlice<Face>, pairPercent: Int) -> [Card] {
                faces.flatMap { face in
                    Int.random(in: 0..<100, using: &rng) < pairPercent ? [Card(face, copy: 0), Card(face, copy: 1)]
                        : [Card(face, copy: Int.random(in: 0...1, using: &rng))]
                }
            }
            let split = Int.random(in: 2...min(6, groupFaces.count - 3), using: &rng)
            let lead = cards(from: groupFaces.prefix(split), pairPercent: 70)
            let held = cards(from: groupFaces.dropFirst(split), pairPercent: 60)
            guard held.count >= lead.count, lead.count >= 2 else { continue }

            // Decomposition.
            let classic = Combos.decompose(lead, trump: trump)
            XCTAssertEqual(Combos.decomposeSets(lead, trump: trump), classic, "\(lead.shortText)")
            if classic.contains(where: { $0.shape.isTractor }) { withTractors += 1 }

            // Follow requirement.
            let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
            let walk = Rules.unitWalk(classic[...], remaining: held, trump: trump)
            let general = FollowRequirement(units: walk.tractors + walk.sets)
            let message = "\(trump): lead \(lead.shortText), held \(held.shortText)"
            XCTAssertEqual(general.tractorLengths, requirement.tractorLengths, message)
            XCTAssertEqual(general.totalPairs, requirement.totalPairs, message)

            // Follow verdicts and trick keys for random plays of the right size.
            let format = Rules.LeadFormat(lead, trump: trump)
            for _ in 0..<6 {
                let play = Array(held.shuffled(using: &rng).prefix(lead.count))
                XCTAssertEqual(Rules.unitViolation(play, units: general.units, trump: trump),
                               Rules.validateFollow(play, hand: held, lead: lead, trump: trump), message + " play \(play.shortText)")
                XCTAssertEqual(Rules.unitStructureKey(play, format: format, keyShape: format.largest?.shape ?? .single,
                                                      trump: trump),
                               Rules.structureKey(play, format: format, trump: trump), message + " play \(play.shortText)")
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 500)
        XCTAssertGreaterThan(withTractors, 100)
    }

    // MARK: Helpers

    /// A deck in dealing order for `table` where `hands[seat]` lists cards that seat must receive;
    /// everything else is filled in from the remaining cards in a seeded order.
    static func deck(table: TableSize, hands spec: [[Card]], firstSeat: Int = 0, seed: UInt64 = 1) -> [Card] {
        var hands = spec + Array(repeating: [Card](), count: max(0, table.players - spec.count))
        let used = Set(hands.flatMap { $0 }.map(\.id))
        var rng = SeededGenerator(seed: seed)
        var rest = Deck.cards(decks: table.decks).filter { !used.contains($0.id) }.shuffled(using: &rng)
        for seat in 0..<table.players {
            while hands[seat].count < table.handSize { hands[seat].append(rest.removeLast()) }
        }
        var deck: [Card] = []
        for index in 0..<(table.players * table.handSize) {
            let seat = (firstSeat + index) % table.players
            deck.append(hands[seat][index / table.players])
        }
        return deck + rest
    }

    /// A random lead: singles, pairs, sets, tractors of any width, sometimes a throw attempt.
    static func randomLead<G: RandomNumberGenerator>(hand: [Card], trump: Trump, rng: inout G) -> [Card] {
        let byGroup = EngineTestSupport.groups(hand, trump: trump)
        guard let groupCards = byGroup.randomElement(using: &rng), let pick = groupCards.randomElement(using: &rng) else {
            return []
        }
        let roll = Int.random(in: 0..<10, using: &rng)
        if roll < 4 {
            var options: [[Card]] = []
            for cards in byGroup {
                for width in 2...max(2, Combos.maxCopies(cards)) {
                    options += Combos.sets(in: cards, width: width, trump: trump)
                    let longest = Combos.longestRun(in: cards, width: width, trump: trump)
                    if longest >= 2 {
                        options += Combos.setTractors(in: cards, width: width,
                                                      length: Int.random(in: 2...longest, using: &rng), trump: trump)
                    }
                }
            }
            if let choice = options.randomElement(using: &rng) { return choice }
        }
        if roll == 5, groupCards.count >= 2 {
            return Array(groupCards.shuffled(using: &rng).prefix(Int.random(in: 2...min(7, groupCards.count), using: &rng)))
        }
        return [pick]
    }

    /// A legal follow from the rules: every owed combination first, then random filler.
    static func legalFollow<G: RandomNumberGenerator>(hand: [Card], lead: [Card], trump: Trump,
                                                      rng: inout G) -> [Card] {
        guard let first = lead.first else { return [] }
        let n = lead.count
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let held = hand.filter { trump.group($0) == ledGroup }
        let others = hand.filter { trump.group($0) != ledGroup }
        if held.count <= n { return held + Array(others.shuffled(using: &rng).prefix(n - held.count)) }
        let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
        var play: [Card] = []
        Rules.searchUnits(held, shapes: Rules.sortedUnits(requirement.units)[...], trump: trump, chosen: []) { _, chosen in
            play = chosen.flatMap(\.cards)
            return true
        }
        var pool = held
        pool.remove(cards: play)
        return play + pool.shuffled(using: &rng).prefix(n - play.count)
    }
}

// MARK: - Coach context at bigger tables

final class BiggerTableCoachTests: XCTestCase {
    func testCoachContextDescribesASixPlayerTable() throws {
        var rng = SeededGenerator(seed: 12)
        var round = Round(trumpRank: .two, dealer: 3, rng: &rng, table: .six)
        round.dealAll()
        round.finishDealing()
        let dealer = try XCTUnwrap(round.dealer)
        try round.bury(Array(round.hands[dealer].prefix(round.kittySize)))
        // Play a few cards so a trick is in progress.
        var moves = 0
        while round.currentTrick.count < 2, moves < 40, let seat = round.turn {
            let hand = round.hands[seat]
            let cards = round.currentTrick.isEmpty ? [round.trump.sorted(hand)[0]]
                : Rules.legalFollow(hand: hand, lead: round.currentLead, trump: round.trump)
            _ = try round.play(cards, by: seat)
            moves += 1
        }
        let text = CoachContext.describe(round: round, game: GameState(settings: GameSettings(table: .six)), hint: nil,
                                         selection: [], lastIllegal: nil)
        XCTAssertTrue(text.contains("6 players and 3 decks"), text)
        XCTAssertTrue(text.contains("120 takes over the deal"), text)
        XCTAssertTrue(text.contains("of 300"), text)
        XCTAssertTrue(text.contains("Northeast"), text)
        XCTAssertFalse(text.contains("East and West"), text)
        XCTAssertTrue(text.contains("Still to play:"), text)
    }

    func testMoveTextsNameSeatsAtABiggerTable() {
        let trump = Trump(rank: .two, suit: .hearts)
        // Seat 0 feeds a K to its partner at seat 4, who wins.
        let plays = [
            Play(player: 3, cards: [Card(.three, .spades)]),
            Play(player: 4, cards: [Card(.ace, .spades)]),
            Play(player: 5, cards: [Card(.four, .spades)]),
            Play(player: 0, cards: [Card(.king, .spades)]),
            Play(player: 1, cards: [Card(.six, .spades)]),
            Play(player: 2, cards: [Card(.seven, .spades)]),
        ]
        let trick = TrickRecord(plays: plays, winner: 4, points: 10)
        let events = MoveDetector.trickMoves(trick, trump: trump, player: 0)
        let feed = events.first { $0.kind == .feedPartner }
        XCTAssertEqual(feed?.detail.contains("Northwest"), true, "\(events)")
    }
}
