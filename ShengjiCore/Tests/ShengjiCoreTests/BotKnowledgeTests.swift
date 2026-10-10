import Foundation
import XCTest
@testable import ShengjiCore

/// `BotKnowledge` holds only what a seat may know: unseen = the 108-card deck minus its own hand,
/// every played card and (for the dealer, once buried) the kitty; voids come from the play history.
final class BotKnowledgeTests: XCTestCase {
    private func ids(_ cards: [Card]) -> [Int] { cards.map(\.id).sorted() }

    /// Voids worked out independently: a player whose play held fewer cards of the led group than
    /// the lead is out of that group.
    private func referenceVoids(_ round: Round) -> [Set<SuitGroup>] {
        var voids = [Set<SuitGroup>](repeating: [], count: 4)
        let tricks = round.tricks.map(\.plays) + [round.currentTrick]
        for plays in tricks {
            guard let lead = plays.first?.cards, let first = lead.first else { continue }
            let group = round.trump.group(first)
            for play in plays.dropFirst() {
                let followed = play.cards.filter { round.trump.group($0) == group }.count
                if followed < lead.count { voids[play.player].insert(group) }
            }
        }
        return voids
    }

    func testUnseenAndVoidsThroughWholeRounds() {
        var checks = 0, voidsSeen = 0
        for seed in UInt64(0)..<UInt64(12) {
            var rng = SeededGenerator(seed: seed + 40)
            var round = Round(trumpRank: Rank.allCases[Int(seed % 13)], dealer: Int(seed % 4), rng: &rng)
            let bots = (0..<4).map { Bot(seat: $0) }
            var stats = BotRunStats()

            // During the deal, only your own cards are known.
            for _ in 0..<37 { round.dealNext() }
            for seat in 0..<4 {
                let knowledge = BotKnowledge(round: round, seat: seat)
                XCTAssertEqual(knowledge.unseen.count, 108 - round.hands[seat].count)
                XCTAssertTrue(Set(knowledge.unseen.map(\.id)).isDisjoint(with: round.hands[seat].map(\.id)))
            }
            BotHarness.deal(&round, bots: bots, stats: &stats)
            guard let dealer = round.dealer else { return XCTFail("no dealer") }
            // Burying: the dealer holds the kitty, everything else is unseen.
            XCTAssertEqual(BotKnowledge(round: round, seat: dealer).unseen.count, 108 - 33)
            BotHarness.bury(&round, bots: bots, stats: &stats)

            while round.phase == .playing {
                for seat in 0..<4 {
                    let knowledge = BotKnowledge(round: round, seat: seat)
                    XCTAssertEqual(knowledge.seat, seat)
                    XCTAssertEqual(knowledge.trump, round.trump)
                    // Unseen is exactly the other hands plus the kitty (unless you buried it)...
                    var expected = (0..<4).filter { $0 != seat }.flatMap { round.hands[$0] }
                    if seat != dealer { expected += round.kitty }
                    XCTAssertEqual(ids(knowledge.unseen), ids(expected), "seed \(seed) seat \(seat)")
                    // ...and never includes your hand, the played cards or the kitty you buried.
                    let unseenIDs = Set(knowledge.unseen.map(\.id))
                    XCTAssertTrue(unseenIDs.isDisjoint(with: round.playedCards.map(\.id)))
                    if seat == dealer { XCTAssertTrue(unseenIDs.isDisjoint(with: round.kitty.map(\.id))) }
                    XCTAssertEqual(knowledge.voids, referenceVoids(round), "seed \(seed)")
                    checks += 1
                }
                voidsSeen += referenceVoids(round).reduce(0) { $0 + $1.count }
                BotHarness.step(&round, bots: bots, stats: &stats)
            }
            XCTAssertEqual(stats.problems, [])
        }
        XCTAssertGreaterThan(checks, 3000)
        XCTAssertGreaterThan(voidsSeen, 100)
    }

    /// The bots' shortcuts must agree with the engine: `TrickJudge` with `Rules.winningIndex`,
    /// `unseenCanBeat` with `Rules.canBeat` over the unseen cards, `pieces` with `Combos.components`.
    func testShortcutsAgreeWithTheEngine() {
        var judged = 0, probed = 0, step = 0
        for seed in UInt64(0)..<UInt64(8) {
            var rng = SeededGenerator(seed: seed + 900)
            var round = Round(trumpRank: Rank.allCases[Int((seed * 5) % 13)], dealer: Int(seed % 4), rng: &rng)
            let bots = (0..<4).map { Bot(seat: $0) }
            var stats = BotRunStats()
            BotHarness.deal(&round, bots: bots, stats: &stats)
            BotHarness.bury(&round, bots: bots, stats: &stats)
            while round.phase == .playing, let seat = round.turn {
                let table = BotTable(round: round, seat: seat)
                let trump = round.trump
                step += 1
                // Probes of every shape, group and strength (every fifth decision, to keep this quick).
                let groups: [SuitGroup] = step % 5 == 0 ? [.trump] + Suit.allCases.map { .plain($0) } : []
                for group in groups {
                    for strength in 0...Trump.bigJokerStrength {
                        for shape in [ComboShape.single, .pair, .tractor(2)] {
                            let probe = Component(shape: shape, cards: [], group: group, topStrength: strength)
                            XCTAssertEqual(table.unseenCanBeat(probe),
                                           Rules.canBeat(probe, with: table.knowledge.unseen, trump: trump))
                            probed += 1
                        }
                    }
                    let pieces = table.pieces(in: group)
                    let mine = table.cards(in: group)
                    XCTAssertEqual(Set(pieces.singles),
                                   Set(Combos.components(of: .single, in: mine, trump: trump).flatMap(\.cards)))
                    XCTAssertEqual(Set(pieces.pairs.map { Set($0) }),
                                   Set(Combos.pairs(in: mine, trump: trump).map { Set($0) }))
                }
                if !round.currentTrick.isEmpty {
                    let judge = TrickJudge(trick: round.currentTrick, trump: trump)
                    XCTAssertEqual(judge.winnerIndex, Rules.winningIndex(round.currentTrick, trump: trump))
                    var candidates: [[Card]] = [bots[seat].decide(in: round).cards]
                    for _ in 0..<4 {
                        candidates.append(EngineTestSupport.legalFollow(hand: round.hands[seat], lead: round.currentLead,
                                                                        trump: trump, rng: &rng))
                    }
                    for cards in candidates {
                        let plays = round.currentTrick + [Play(player: seat, cards: cards)]
                        let expected = Rules.winningIndex(plays, trump: trump) == round.currentTrick.count
                        XCTAssertEqual(judge.wins(cards), expected, "\(plays.map { $0.cards.shortText })")
                        judged += 1
                    }
                }
                BotHarness.step(&round, bots: bots, stats: &stats)
            }
            XCTAssertEqual(stats.problems, [])
        }
        XCTAssertGreaterThan(judged, 1500)
        XCTAssertGreaterThan(probed, 20_000)
    }

    /// The bots' cached display order must match `Trump.sortKey` exactly.
    func testCardOrderMatchesTrumpSortKey() {
        let suits: [Suit?] = [nil, .spades, .hearts, .clubs, .diamonds]
        for rank in Rank.allCases {
            for suit in suits {
                let trump = Trump(rank: rank, suit: suit)
                let order = CardOrder(trump)
                for card in Deck.double() { XCTAssertEqual(order.key(card), trump.sortKey(card)) }
                var rng = SeededGenerator(seed: UInt64(rank.rawValue))
                let cards = Array(Deck.shuffled(using: &rng).prefix(30))
                XCTAssertEqual(order.sorted(cards), trump.sorted(cards))
            }
        }
    }

    func testShowingOutMarksAVoidFromThenOn() throws {
        // South leads A♣; North has no clubs and plays a diamond, so North is out of clubs.
        let north = botCards("""
            3♦' 4♦' 6♦' 7♦' 8♦' 9♦' J♦' Q♦' K♦ A♦ 3♠' 4♠' 5♠' 8♠' 9♠' J♠' Q♠' K♠ A♠ 6♥ 7♥ 8♥ 9♥ J♥ Q♥
            """)
        let south = botCards("2♥ 3♥ 4♥ A♣ 4♣ 7♣ 8♣ 3♠ 5♠ 6♠ 8♠ 9♠ J♠ Q♠ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ 6♠' 7♠ 4♠")
        var round = BotScenario.round(rank: .two, dealer: 0, hands: [south, botCards("5♣"), north, botCards("6♣")])
        let declaration = Declaration(player: 0, cards: [botCard("2♥")], suit: .hearts, strength: 1)
        try BotScenario.start(&round, declare: declaration)
        XCTAssertEqual(BotKnowledge(round: round, seat: 1).voids, [[], [], [], []])
        try round.play(botCards("A♣"), by: 0)
        try round.play(botCards("5♣"), by: 1)
        try round.play(botCards("3♦'"), by: 2)
        // Visible mid-trick, to every seat.
        for seat in 0..<4 {
            let knowledge = BotKnowledge(round: round, seat: seat)
            XCTAssertEqual(knowledge.voids[2], [.plain(.clubs)])
            XCTAssertEqual(knowledge.voids[1], [])
        }
        try round.play(botCards("6♣"), by: 3)
        XCTAssertEqual(BotKnowledge(round: round, seat: 3).voids[2], [.plain(.clubs)])
    }
}
