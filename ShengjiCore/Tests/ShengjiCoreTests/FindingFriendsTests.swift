import Foundation
import XCTest
@testable import ShengjiCore

/// Odd tables (5, 7 or 9 players) play Finding Friends (找朋友): the dealer calls friends by naming
/// cards when burying, whoever plays the called copy joins the dealer's side, and everyone keeps their
/// own level.
final class FindingFriendsTests: XCTestCase {
    private func c(_ rank: Rank, _ suit: Suit, _ copy: Int = 0) -> Card { Card(rank, suit, copy: copy) }

    // MARK: Tables

    func testOddTables() {
        XCTAssertEqual(TableSize.five.decks, 3)
        XCTAssertEqual(TableSize.five.handSize, 31)
        XCTAssertEqual(TableSize.five.kittySize, 7)
        XCTAssertEqual(TableSize.seven.decks, 4)
        XCTAssertEqual(TableSize.seven.handSize, 30)
        XCTAssertEqual(TableSize.seven.kittySize, 6)
        XCTAssertEqual(TableSize.nine.decks, 5)
        XCTAssertEqual(TableSize.nine.handSize, 29)
        XCTAssertEqual(TableSize.nine.kittySize, 9)
        XCTAssertEqual(TableSize.nine.totalPoints, 500)
        XCTAssertEqual(TableSize.nine.cardCount, 270)
        XCTAssertEqual([TableSize.five, .seven, .nine].map(\.friendCount), [1, 2, 3])
        XCTAssertEqual([TableSize.five, .seven, .nine].map(\.teamSize), [2, 3, 4])
        XCTAssertEqual([TableSize.four, .six, .eight].map(\.friendCount), [0, 0, 0])
        XCTAssertTrue(TableSize.nine.findsFriends)
        XCTAssertFalse(TableSize.eight.findsFriends)
        XCTAssertEqual(TableSize(exactly: 9), .nine)
        XCTAssertEqual(Deck.cards(decks: 5).count, 270)
        XCTAssertEqual(Card(id: 269), Card(.bigJoker, copy: 4))
    }

    func testOddTableSeatNames() {
        XCTAssertEqual((0..<5).map { Seats.name($0, players: 5) }, ["You", "East", "Northeast", "Northwest", "West"])
        XCTAssertEqual((0..<7).map { Seats.shortName($0, players: 7) }, ["You", "SE", "E", "NE", "NW", "W", "SW"])
        XCTAssertEqual((0..<9).map { Seats.shortName($0, players: 9) },
                       ["You", "SE", "E", "NE", "NNE", "NNW", "NW", "W", "SW"])
        XCTAssertEqual(Set((0..<9).map { Seats.name($0, players: 9) }).count, 9)
        // No fixed partners to name.
        XCTAssertEqual(BotText.name(2, from: 0, players: 5), "Northeast")
    }

    // MARK: Calls

    func testFriendCallRules() {
        let table = TableSize.nine
        let good = [FriendCall(.ace, .spades), FriendCall(.ace, .clubs), FriendCall(.king, .spades, ordinal: 2)]
        XCTAssertNil(FriendCall.problem(with: good, table: table, trumpRank: .two))
        XCTAssertEqual(FriendCall.problem(with: Array(good.prefix(2)), table: table, trumpRank: .two),
                       "Call exactly 3 friends (you called 2).")
        XCTAssertEqual(FriendCall.problem(with: [FriendCall(.ace, .spades)], table: .five, trumpRank: .two), nil)
        XCTAssertEqual(FriendCall.problem(with: [FriendCall(face: .bigJoker)], table: .five, trumpRank: .two),
                       "Jokers can't be called: pick a suited card.")
        XCTAssertEqual(FriendCall.problem(with: [FriendCall(.two, .clubs)], table: .five, trumpRank: .two),
                       "Trump-rank cards (2) can't be called: pick another card.")
        XCTAssertNotNil(FriendCall.problem(with: [FriendCall(.ace, .clubs, ordinal: 4)], table: .five, trumpRank: .two))
        XCTAssertNil(FriendCall.problem(with: [FriendCall(.ace, .clubs, ordinal: 3)], table: .five, trumpRank: .two))
        XCTAssertNotNil(FriendCall.problem(with: [FriendCall(.ace, .clubs, ordinal: 0)], table: .five, trumpRank: .two))
        XCTAssertEqual(FriendCall.problem(with: [FriendCall(.ace, .clubs), FriendCall(.ace, .clubs)], table: .seven,
                                          trumpRank: .two),
                       "You called the first A♣ twice: pick a different card or copy.")
        XCTAssertNotNil(FriendCall.problem(with: [FriendCall(.ace, .clubs)], table: .four, trumpRank: .two))
        XCTAssertNil(FriendCall.problem(with: [], table: .four, trumpRank: .two))
        XCTAssertEqual(FriendCall(.king, .hearts, ordinal: 2).description, "the second K♥")
        XCTAssertEqual([FriendCall(.ace, .spades), FriendCall(.ace, .clubs)].spokenList, "the first A♠ and the first A♣")
    }

    func testFriendCallWireFormat() throws {
        let call = FriendCall(face: .regular(.spades, .ace), ordinal: 2, friend: 3)
        let data = try JSONEncoder().encode(call)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertEqual(object, ["face": 12, "ordinal": 2, "friend": 3])
        XCTAssertEqual(try JSONDecoder().decode(FriendCall.self, from: data), call)
        let unfound = try JSONEncoder().encode(FriendCall(.ace, .spades))
        XCTAssertEqual(String(data: unfound, encoding: .utf8)?.contains("friend"), false)
        XCTAssertThrowsError(try JSONDecoder().decode(FriendCall.self, from: Data(#"{"face":54,"ordinal":1}"#.utf8)))
    }

    func testCountingCopiesFindsTheFriend() {
        let calls = [FriendCall(.ace, .spades, ordinal: 2), FriendCall(.king, .clubs)]
        // One A♠ already played: the next one is the second.
        let first = calls.noting([c(.ace, .spades, 1)], by: 3, playedBefore: [c(.ace, .spades, 0)])
        XCTAssertEqual(first.map(\.friend), [3, nil])
        // A pair of A♠ led first: its second card reaches the call.
        let pair = calls.noting([c(.ace, .spades, 0), c(.ace, .spades, 1)], by: 4, playedBefore: [])
        XCTAssertEqual(pair.map(\.friend), [4, nil])
        // A third A♠ is too late; a found call never changes.
        let late = first.noting([c(.ace, .spades, 2), c(.king, .clubs, 1)], by: 1,
                                playedBefore: [c(.ace, .spades, 0), c(.ace, .spades, 1)])
        XCTAssertEqual(late.map(\.friend), [3, 1])
    }

    // MARK: A round

    /// Five players, hearts trump (rank 2), seat 0 deals and calls the first K♣. Seat 2 wins the first
    /// trick (10 points) before anyone knows it is the friend, then leads the K♣.
    private func fivePlayerRound(calls: [FriendCall] = [FriendCall(.king, .clubs)]) throws -> Round {
        let hands: [[Card]] = [
            [c(.two, .hearts), c(.three, .spades), c(.five, .clubs)],
            [c(.king, .spades), c(.six, .clubs)],
            [c(.ace, .spades), c(.king, .clubs)],
            [c(.four, .spades), c(.three, .clubs)],
            [c(.six, .spades), c(.four, .clubs)],
        ]
        let deck = BiggerTableTests.deck(table: .five, hands: hands, firstSeat: 0, seed: 5)
        var round = Round(trumpRank: .two, dealer: 0, deck: deck, table: .five)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [c(.two, .hearts)], suit: .hearts, strength: 1))
        round.finishDealing()
        let keep: Set<Card> = [c(.two, .hearts), c(.three, .spades), c(.five, .clubs)]
        let bury = Array(round.hands[0].filter { !keep.contains($0) }.prefix(round.kittySize))
        XCTAssertThrowsError(try round.bury(bury)) { error in
            XCTAssertEqual(error as? RoundError, .invalidBury("Call exactly 1 friend (you called 0)."))
        }
        try round.bury(bury, calls: calls)
        return round
    }

    func testAFriendIsFoundWhenTheCalledCardIsPlayed() throws {
        var round = try fivePlayerRound()
        XCTAssertTrue(round.isFindingFriends)
        XCTAssertEqual(round.friendCalls, [FriendCall(.king, .clubs)])
        XCTAssertEqual(round.declarers, [0])
        XCTAssertEqual(round.declarerTeam, 0)

        for (seat, card) in [(0, c(.three, .spades)), (1, c(.king, .spades)), (2, c(.ace, .spades)),
                             (3, c(.four, .spades)), (4, c(.six, .spades))] {
            try round.play([card], by: seat)
        }
        XCTAssertEqual(round.lastTrick?.winner, 2)
        XCTAssertTrue(round.isDefender(2), "a hidden friend counts as a defender")
        XCTAssertEqual(round.defenderTrickPoints, 10)

        try round.play([c(.king, .clubs)], by: 2)
        XCTAssertEqual(round.friendCalls.first?.friend, 2)
        XCTAssertEqual(round.declarers, [0, 2])
        XCTAssertTrue(round.isDeclarer(2))
        XCTAssertEqual(round.defenderTrickPoints, 0, "the friend's trick moves to the dealer's side")
        for (seat, card) in [(3, c(.three, .clubs)), (4, c(.four, .clubs)), (0, c(.five, .clubs)), (1, c(.six, .clubs))] {
            try round.play([card], by: seat)
        }
        XCTAssertEqual(round.lastTrick?.winner, 2)
        XCTAssertEqual(round.defenderTrickPoints, 0)

        // The view: friends are public, seats rotate.
        let view = round.seatView(for: 2)
        XCTAssertEqual(view.friendCalls?.first?.friend, 0)
        XCTAssertEqual(view.dealer, 3)
        XCTAssertEqual(view.declarers, [3, 0])
        XCTAssertEqual(view.declarerTeam, 0)
        XCTAssertTrue(view.findsFriends)
        XCTAssertEqual(round.seatView(for: 1).declarerTeam, 1)

        try playOut(&round)
        let result = try XCTUnwrap(round.result)
        XCTAssertEqual(result.declarers, [0, 2])
        XCTAssertEqual(result.friendCalls?.first?.friend, 2)
        XCTAssertEqual(result.declarerTeam, 0)
        XCTAssertEqual(result.outcome, Scoring.outcome(defenderPoints: result.defenderPoints, decks: 3))
        let defenderTricks = round.tricks.filter { ![0, 2].contains($0.winner) }.reduce(0) { $0 + $1.points }
        XCTAssertEqual(result.trickPoints, defenderTricks)
        // Seen from a defender, the dealer's side is the other team.
        XCTAssertEqual(result.rotated(by: 1, players: 5).declarerTeam, 1)
        XCTAssertEqual(result.rotated(by: 2, players: 5).declarerTeam, 0)
        XCTAssertEqual(result.rotated(by: 2, players: 5).declarers, [3, 0])
    }

    func testTheDealerCanBeTheirOwnFriend() throws {
        var round = try fivePlayerRound(calls: [FriendCall(.five, .clubs)])
        for (seat, card) in [(0, c(.five, .clubs)), (1, c(.six, .clubs)), (2, c(.king, .clubs)),
                             (3, c(.three, .clubs)), (4, c(.four, .clubs))] {
            try round.play([card], by: seat)
        }
        XCTAssertEqual(round.friendCalls.first?.friend, 0)
        XCTAssertEqual(round.declarers, [0])
        try playOut(&round)
        let result = try XCTUnwrap(round.result)
        XCTAssertEqual(result.declarers, [0])
        let plain = Scoring.outcome(defenderPoints: result.defenderPoints, decks: 3)
        if plain.declarersHold {
            XCTAssertEqual(result.outcome.levels, plain.levels + 1, "short-handed bonus")
            XCTAssertTrue(result.outcome.summary.contains("short-handed (1 of 2)"), result.outcome.summary)
        } else {
            XCTAssertEqual(result.outcome, plain)
        }
    }

    func testShortHandedBonus() {
        let base = Scoring.outcome(defenderPoints: 45, decks: 5)
        XCTAssertEqual(base.levels, 2)
        let bonus = Scoring.findingFriendsOutcome(base, declarers: 3, fullSide: 4)
        XCTAssertEqual(bonus.levels, 3)
        XCTAssertEqual(bonus.summary, "Defenders scored 45 (under 100): the declarers keep the deal and go up 2 levels, "
                       + "plus 1 for playing short-handed (3 of 4): 3 levels in all.")
        XCTAssertEqual(Scoring.findingFriendsOutcome(base, declarers: 4, fullSide: 4), base)
        let takeover = Scoring.outcome(defenderPoints: 250, decks: 5)
        XCTAssertEqual(Scoring.findingFriendsOutcome(takeover, declarers: 1, fullSide: 4), takeover)
    }

    // MARK: Games

    private func result(dealer: Int, declarers: [Int], points: Int, players: Int = 9) -> RoundResult {
        let table = TableSize(players: players)
        let outcome = Scoring.findingFriendsOutcome(Scoring.outcome(defenderPoints: points, decks: table.decks),
                                                    declarers: declarers.count, fullSide: table.teamSize)
        return RoundResult(dealer: dealer, declarerTeam: declarers.contains(0) ? 0 : 1,
                           trump: Trump(rank: .two, suit: .spades), trickPoints: points, kittyPoints: 0,
                           kittyMultiplier: 0, defenderPoints: points, outcome: outcome, kitty: [], lastTrickWinner: 1,
                           declarers: declarers, friendCalls: [])
    }

    func testEveryoneKeepsTheirOwnLevel() {
        var game = GameState(settings: GameSettings(table: .nine))
        XCTAssertEqual(game.levels.count, 9)
        XCTAssertTrue(game.findsFriends)
        // Dealer 4 with friends 6, 8 and 1 hold with 45 points (2 levels).
        let first = game.record(result(dealer: 4, declarers: [4, 6, 8, 1], points: 45))
        XCTAssertEqual(game.levels.map(\.label), ["2", "4", "2", "2", "4", "2", "4", "2", "4"])
        XCTAssertEqual(first.nextDealer, 6, "the dealer's next friend deals")
        XCTAssertEqual(first.advancingTeam, 1, "seat 0 was a defender")
        XCTAssertEqual(first.levelsGained, 2)
        XCTAssertEqual(game.nextTrumpRank, .four)
        XCTAssertTrue(first.explanation.hasPrefix("North-northeast, Northwest, Southwest and Southeast played together"),
                      first.explanation)
        XCTAssertTrue(first.explanation.contains("200"), first.explanation)

        // Dealer 6 is taken over (300 points: +1 for the defenders): the next defender after 6 deals.
        let second = game.record(result(dealer: 6, declarers: [6, 7, 2, 4], points: 300))
        XCTAssertEqual(second.nextDealer, 8)
        XCTAssertEqual(game.levels.map(\.label), ["3", "5", "2", "3", "4", "3", "4", "2", "5"])
        XCTAssertEqual(second.advancingTeam, 0, "seat 0 defended")
        XCTAssertTrue(second.explanation.contains("You are now at level 3."), second.explanation)
        XCTAssertTrue(second.explanation.contains("The defenders go up 1 level."), second.explanation)

        // Playing alone and holding: the dealer deals again, with the bonus level.
        let third = game.record(result(dealer: 8, declarers: [8], points: 100))
        XCTAssertEqual(third.nextDealer, 8)
        XCTAssertEqual(game.levels[8], .seven)
        XCTAssertTrue(third.explanation.hasPrefix("Southwest played alone: no friend joined."), third.explanation)
        XCTAssertTrue(third.explanation.contains("Southwest goes up 2 levels (1 of them for playing short-handed)."),
                      third.explanation)
    }

    func testTheDealerWinsTheGameAtTheTarget() {
        var game = GameState(settings: GameSettings(startRank: .ace, table: .five))
        let summary = game.record(result(dealer: 3, declarers: [3, 0], points: 10, players: 5))
        XCTAssertEqual(summary.gameWinner, 0, "seat 0 was on the winning side")
        XCTAssertEqual(game.winner, 0)
        XCTAssertTrue(summary.explanation.contains("so you win the game!"), summary.explanation)
        let other = summary.rotated(by: 1, target: .ace, players: 5)
        XCTAssertEqual(other.gameWinner, 1)
        XCTAssertTrue(other.explanation.contains("so they win the game."), other.explanation)
        XCTAssertEqual(summary.rotated(by: 3, target: .ace, players: 5).gameWinner, 0)

        var lost = GameState(settings: GameSettings(startRank: .ace, table: .five))
        XCTAssertEqual(lost.record(result(dealer: 3, declarers: [3, 4], points: 10, players: 5)).gameWinner, 1)
    }

    func testSummariesRotateSeatsAndLevels() {
        var game = GameState(settings: GameSettings(table: .seven))
        let summary = game.record(result(dealer: 2, declarers: [2, 5, 6], points: 0, players: 7))
        let rotated = summary.rotated(by: 5, target: .ace, players: 7)
        XCTAssertEqual(rotated.result.dealer, 4)
        XCTAssertEqual(rotated.result.declarers, [4, 0, 1])
        XCTAssertEqual(rotated.levelsAfter[0], .five)
        XCTAssertEqual(rotated.levelsAfter.map(\.label), ["5", "5", "2", "2", "5", "2", "2"])
        XCTAssertEqual(rotated.advancingTeam, 0)
        XCTAssertEqual(summary.advancingTeam, 1)
        XCTAssertEqual(rotated.nextDealer, 0, "seat 5 deals next: the viewer")
        XCTAssertTrue(rotated.explanation.contains("You deal next"), rotated.explanation)
    }

    func testSavedGamesAndRoundsRoundTrip() throws {
        var round = try fivePlayerRound()
        try round.play([c(.three, .spades)], by: 0)
        let data = try JSONEncoder().encode(round)
        let decoded = try JSONDecoder().decode(Round.self, from: data)
        XCTAssertEqual(decoded.friendCalls, round.friendCalls)
        XCTAssertEqual(decoded.table, .five)
        let game = GameState(settings: GameSettings(table: .nine))
        let back = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(back.levels.count, 9)
        XCTAssertEqual(back.settings.table, .nine)
    }

    // MARK: Bots

    func testBotCallsTopCardsItDoesNotHold() {
        // Spades trump: one call per plain suit, highest card not held.
        let hand = [c(.ace, .hearts), c(.three, .hearts), c(.four, .clubs), c(.nine, .diamonds), c(.ace, .diamonds),
                    c(.king, .diamonds)]
        let view = SeatView(players: (0..<9).map { SeatView.Player(name: "\($0)", isBot: true) },
                            teamLevels: Array(repeating: .two, count: 9), targetRank: .ace, roundNumber: 1,
                            phase: .burying, trump: Trump(rank: .two, suit: .spades), trumpFromKitty: nil, dealer: 0,
                            hand: hand, handCounts: [hand.count] + Array(repeating: 29, count: 8), declaration: nil,
                            declarationHistory: [], bidding: nil, kitty: [], currentTrick: [], leader: 0, turn: 0,
                            tricks: [], defenderTrickPoints: 0, result: nil, lastRoundSummary: nil, gameWinnerTeam: nil)
        let calls = Bot(seat: 0).friendCalls(view: view, buried: [])
        // Shortest held suit first: clubs (1 card), hearts (2), diamonds (3): A♣, K♥, Q♦.
        XCTAssertEqual(calls, [FriendCall(.ace, .clubs), FriendCall(.king, .hearts), FriendCall(.queen, .diamonds)])
        XCTAssertNil(FriendCall.problem(with: calls, table: .nine, trumpRank: .two))
        let choice = Bot(seat: 0).friendCallChoice(view: view, buried: [])
        XCTAssertTrue(choice.reason.hasPrefix("Call the first A♣, the first K♥ and the first Q♦"), choice.reason)
    }

    func testBotsPlayWholeGamesAtOddTables() {
        let fallbacksBefore = BotDiagnostics.shared.fallbackCount
        for table in [TableSize.five, .seven, .nine] {
            for (index, levels) in [[BotLevel.standard], [.standard, .beginner]].enumerated() {
                var stats = BotRunStats()
                var game = GameState(settings: GameSettings(table: table))
                var rng = SeededGenerator(seed: UInt64(300 + 10 * table.players + index))
                var rounds = 0
                var found = 0
                var calls = 0
                while game.winner == nil && rounds < 6 {
                    var round = game.makeRound(rng: &rng)
                    BotHarness.play(&round, levels: levels, stats: &stats)
                    guard let result = round.result else { break }
                    calls += result.friendCalls?.count ?? 0
                    found += result.friendCalls?.filter { $0.friend != nil }.count ?? 0
                    XCTAssertEqual(result.friendCalls?.count, table.friendCount)
                    XCTAssertEqual(result.declarers?.first, result.dealer)
                    let allPoints = round.tricks.reduce(0) { $0 + $1.points } + round.kitty.points
                    XCTAssertEqual(allPoints, table.totalPoints)
                    let summary = game.record(result)
                    XCTAssertTrue(summary.explanation.contains("\(Scoring.takeoverThreshold(decks: table.decks))"),
                                  summary.explanation)
                    XCTAssertEqual(game.levels.count, table.players)
                    rounds += 1
                }
                XCTAssertEqual(stats.finishedRounds, rounds, "\(table)")
                XCTAssertGreaterThan(rounds, 0)
                XCTAssertEqual(stats.problems, [], "\(table)")
                XCTAssertGreaterThan(found * 2, calls, "\(table): bots found only \(found) of \(calls) friends")
            }
        }
        XCTAssertEqual(BotDiagnostics.shared.fallbackCount, fallbacksBefore, "a bot fell back to the plain legal play")
    }

    func testAHiddenFriendLeadsTheCalledCard() throws {
        var round = try fivePlayerRound(calls: [FriendCall(.ace, .clubs)])
        for (seat, card) in [(0, c(.three, .spades)), (1, c(.king, .spades)), (2, c(.ace, .spades)),
                             (3, c(.four, .spades)), (4, c(.six, .spades))] {
            try round.play([card], by: seat)
        }
        let aceOfClubs = Face.regular(.clubs, .ace)
        let mine = round.hands[2].filter { $0.face == aceOfClubs }.sorted { $0.id < $1.id }
        XCTAssertFalse(mine.isEmpty)
        let table = BotTable(view: round.seatView(for: 2))
        XCTAssertEqual(table.friends?.onDealerSide, true)
        XCTAssertEqual(table.friends?.reveal?.call, FriendCall(.ace, .clubs))
        XCTAssertTrue(table.isDeclarer)
        XCTAssertTrue(table.isTeammate(3), "the dealer (seat 3 from here) is a partner")
        XCTAssertTrue(table.isOpponent(1))
        let decision = Bot(seat: 2).decide(in: round)
        XCTAssertEqual(decision.cards, [mine[0]])
        XCTAssertEqual(decision.concept, "Find friends")
        // A defender who holds no A♣ counts nobody as a partner while the friend is hidden; another
        // A♣ holder could still answer the call first, so it counts itself on the dealer's side.
        for seat in [1, 3, 4] {
            let holds = round.hands[seat].contains { $0.face == aceOfClubs }
            let view = BotTable(view: round.seatView(for: seat))
            XCTAssertEqual(view.isDeclarer, holds, "seat \(seat)")
            XCTAssertEqual(view.teammates, holds ? [5 - seat] : [], "seat \(seat)")
        }
        XCTAssertTrue([1, 3, 4].contains { seat in !round.hands[seat].contains { $0.face == aceOfClubs } })
    }

    func testAHiddenFriendKeepsBeatablePoints() throws {
        var round = try fivePlayerRound()
        for (seat, card) in [(0, c(.three, .spades)), (1, c(.king, .spades)), (2, c(.ace, .spades)),
                             (3, c(.four, .spades)), (4, c(.six, .spades))] {
            try round.play([card], by: seat)
        }
        // Seat 2 holds the called K♣, but an A♣ is still out: it doesn't lead 10 points into it.
        XCTAssertEqual(BotTable(view: round.seatView(for: 2)).friends?.reveal?.call, FriendCall(.king, .clubs))
        XCTAssertNotEqual(Bot(seat: 2).decide(in: round).concept, "Find friends")
    }

    // MARK: Helpers

    private func playOut(_ round: inout Round) throws {
        var rng = SeededGenerator(seed: 9)
        var moves = 0
        while round.phase == .playing && moves < 600 {
            guard let seat = round.turn else { break }
            let hand = round.hands[seat]
            let cards = round.currentTrick.isEmpty
                ? [hand.min { $0.id < $1.id }!]
                : BiggerTableTests.legalFollow(hand: hand, lead: round.currentLead, trump: round.trump, rng: &rng)
            _ = try round.play(cards, by: seat)
            moves += 1
        }
        XCTAssertEqual(round.phase, .finished)
    }
}

// MARK: - Coach context and moves at an odd table

final class FindingFriendsCoachTests: XCTestCase {
    func testCoachContextDescribesFindingFriends() throws {
        var rng = SeededGenerator(seed: 21)
        var round = Round(trumpRank: .two, dealer: 3, rng: &rng, table: .nine)
        round.dealAll()
        round.finishDealing()
        let dealer = try XCTUnwrap(round.dealer)
        let buried = Array(round.hands[dealer].prefix(round.kittySize))
        try round.bury(buried, calls: Bot(seat: dealer).friendCalls(in: round, buried: buried))
        var moves = 0
        while round.currentTrick.count < 3 || round.tricks.count < 2, moves < 200, let seat = round.turn {
            _ = try round.play(Bot(seat: seat).decide(in: round).cards, by: seat)
            moves += 1
        }
        let game = GameState(settings: GameSettings(table: .nine))
        let text = CoachContext.describe(round: round, game: game, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(text.contains("9 players and 5 decks"), text)
        XCTAssertTrue(text.contains("Finding Friends"), text)
        XCTAssertTrue(text.contains("Friends called: the first"), text)
        XCTAssertTrue(text.contains("The dealer's side so far:"), text)
        XCTAssertTrue(text.contains("Levels (everyone climbs on their own)"), text)
        XCTAssertFalse(text.contains("East and West"), text)
        XCTAssertFalse(text.contains("your team is you"), text)
        XCTAssertLessThanOrEqual(text.count, CoachContext.maxTableCharacters)
    }

    func testMovesFollowTheKnownSides() {
        // Seat 0 dealt with seat 2 as its friend; seat 1 and seat 3 defended.
        let result = RoundResult(dealer: 0, declarerTeam: 0, trump: Trump(rank: .two, suit: .spades), trickPoints: 0,
                                 kittyPoints: 0, kittyMultiplier: 0, defenderPoints: 0,
                                 outcome: Scoring.outcome(defenderPoints: 0, decks: 3), kitty: [], lastTrickWinner: 2,
                                 declarers: [0, 2], friendCalls: [FriendCall(face: .regular(.spades, .ace), friend: 2)])
        let mine = MoveDetector.roundMoves(result, player: 0).map(\.kind)
        XCTAssertTrue(mine.contains(.holdDeal))
        XCTAssertTrue(mine.contains(.shutout))
        XCTAssertEqual(MoveDetector.roundMoves(result, player: 1).map(\.kind), [])
        // A friend found counts as a partner for feeding points; an unknown seat doesn't.
        let side = MoveDetector.knownSide(of: 0, players: 5, isDeclarer: { [0, 2].contains($0) }, allFound: false)
        XCTAssertTrue(side(2))
        XCTAssertFalse(side(1))
        let defender = MoveDetector.knownSide(of: 1, players: 5, isDeclarer: { [0, 2].contains($0) }, allFound: false)
        XCTAssertFalse(defender(3), "fellow defenders aren't known until every friend is found")
        let allKnown = MoveDetector.knownSide(of: 1, players: 5, isDeclarer: { [0, 2].contains($0) }, allFound: true)
        XCTAssertTrue(allKnown(3))
    }
}
