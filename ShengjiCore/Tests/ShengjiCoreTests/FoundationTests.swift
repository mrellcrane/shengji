import XCTest
@testable import ShengjiCore

/// Shorthand used across tests: c(.ace, .spades), c(.seven, .hearts, 1)
func c(_ r: Rank, _ s: Suit, _ copy: Int = 0) -> Card { Card(r, s, copy: copy) }
let sj0 = Card.smallJoker(copy: 0), sj1 = Card.smallJoker(copy: 1)
let bj0 = Card.bigJoker(copy: 0), bj1 = Card.bigJoker(copy: 1)

final class FoundationTests: XCTestCase {
    func testDeckHas108UniqueCardsAnd200Points() {
        let d = Deck.double()
        XCTAssertEqual(d.count, 108)
        XCTAssertEqual(Set(d.map(\.id)).count, 108)
        XCTAssertEqual(d.points, 200)
    }

    func testTrumpMembership() {
        let t = Trump(rank: .two, suit: .hearts)
        XCTAssertTrue(t.isTrump(c(.two, .spades)))
        XCTAssertTrue(t.isTrump(c(.five, .hearts)))
        XCTAssertTrue(t.isTrump(sj0))
        XCTAssertFalse(t.isTrump(c(.ace, .spades)))
        let nt = Trump(rank: .two, suit: nil)
        XCTAssertTrue(nt.isTrump(c(.two, .clubs)))
        XCTAssertFalse(nt.isTrump(c(.ace, .hearts)))
    }

    func testTrumpOrdering() {
        let t = Trump(rank: .two, suit: .hearts)
        let order = [c(.three, .hearts), c(.ace, .hearts), c(.two, .spades), c(.two, .hearts), sj0, bj0]
        let strengths = order.map { t.strength($0) }
        XCTAssertEqual(strengths, strengths.sorted())
        XCTAssertEqual(Set(strengths).count, strengths.count)
        XCTAssertEqual(t.strength(c(.two, .spades)), t.strength(c(.two, .clubs)))
    }

    func testPlainOrderSkipsTrumpRank() {
        let t = Trump(rank: .eight, suit: .hearts)
        XCTAssertEqual(t.strength(c(.nine, .spades)) - t.strength(c(.seven, .spades)), 1)
        XCTAssertEqual(t.strength(c(.ace, .clubs)), Trump.topPlainStrength)
    }

    func testPairs() {
        let t = Trump(rank: .two, suit: .hearts)
        XCTAssertTrue(Combos.isPair([c(.seven, .spades), c(.seven, .spades, 1)]))
        XCTAssertFalse(Combos.isPair([c(.two, .spades), c(.two, .clubs)]))
        XCTAssertEqual(Combos.shape(of: [c(.two, .spades), c(.two, .spades, 1)], trump: t), .pair)
        XCTAssertNil(Combos.shape(of: [c(.two, .spades), c(.two, .clubs)], trump: t))
    }

    func testTractorSkippingTrumpRank() {
        let t = Trump(rank: .eight, suit: .hearts)
        let cards = [c(.seven, .spades), c(.seven, .spades, 1), c(.nine, .spades), c(.nine, .spades, 1)]
        XCTAssertEqual(Combos.shape(of: cards, trump: t), .tractor(2))
    }

    func testTractorThroughRankCardsAndJokers() {
        let t = Trump(rank: .two, suit: .hearts)
        let aceToRank = [c(.ace, .hearts), c(.ace, .hearts, 1), c(.two, .spades), c(.two, .spades, 1)]
        XCTAssertEqual(Combos.shape(of: aceToRank, trump: t), .tractor(2))
        let rankToRank = [c(.two, .clubs), c(.two, .clubs, 1), c(.two, .hearts), c(.two, .hearts, 1)]
        XCTAssertEqual(Combos.shape(of: rankToRank, trump: t), .tractor(2))
        let sameLevel = [c(.two, .clubs), c(.two, .clubs, 1), c(.two, .spades), c(.two, .spades, 1)]
        XCTAssertNil(Combos.shape(of: sameLevel, trump: t))
        let jokers = [sj0, sj1, bj0, bj1]
        XCTAssertEqual(Combos.shape(of: jokers, trump: t), .tractor(2))
        let noTrump = Trump(rank: .two, suit: nil)
        XCTAssertEqual(Combos.shape(of: [c(.two, .clubs), c(.two, .clubs, 1), sj0, sj1], trump: noTrump), .tractor(2))
    }

    func testNonTrumpCardsDoNotFormTractorWithTrumps() {
        let t = Trump(rank: .two, suit: .hearts)
        // A♠A♠ is plain, 2♠2♠ is trump: different groups.
        let cards = [c(.ace, .spades), c(.ace, .spades, 1), c(.two, .spades), c(.two, .spades, 1)]
        XCTAssertNil(Combos.shape(of: cards, trump: t))
        XCTAssertNil(Combos.group(of: cards, trump: t))
    }

    func testDecomposeThrow() {
        let t = Trump(rank: .two, suit: .hearts)
        let cards = [c(.ace, .spades), c(.king, .spades), c(.king, .spades, 1), c(.queen, .spades), c(.queen, .spades, 1), c(.nine, .spades)]
        let comps = Combos.decompose(cards, trump: t)
        XCTAssertEqual(comps.map(\.shape), [.tractor(2), .single, .single])
        XCTAssertEqual(comps[1].cards, [c(.ace, .spades)])
    }

    func testTractorEnumeration() {
        let t = Trump(rank: .two, suit: .hearts)
        let cards = [c(.five, .clubs), c(.five, .clubs, 1), c(.six, .clubs), c(.six, .clubs, 1), c(.seven, .clubs), c(.seven, .clubs, 1)]
        XCTAssertEqual(Combos.tractors(in: cards, length: 2, trump: t).count, 2)
        XCTAssertEqual(Combos.tractors(in: cards, length: 3, trump: t).count, 1)
        XCTAssertEqual(Combos.longestRun(in: cards, trump: t), 3)
        // Rank level with two different off-suit rank pairs gives two choices.
        let multi = [c(.ace, .hearts), c(.ace, .hearts, 1), c(.two, .clubs), c(.two, .clubs, 1), c(.two, .spades), c(.two, .spades, 1)]
        XCTAssertEqual(Combos.tractors(in: multi, length: 2, trump: t).count, 2)
    }

    func testRankAdvanceCaps() {
        XCTAssertEqual(Rank.queen.advanced(by: 3), .ace)
        XCTAssertEqual(Rank.two.advanced(by: 2), .four)
        XCTAssertEqual(Rank.nine.advanced(by: 3, cap: .ten), .ten)
    }

    func testPlainSuitOrderAlternatesColours() {
        let t = Trump(rank: .two, suit: .hearts)
        let order = t.plainSuitOrder
        XCTAssertEqual(order.count, 3)
        XCTAssertNotEqual(order[0].isRed, order[1].isRed)
        XCTAssertNotEqual(order[1].isRed, order[2].isRed)
    }
}
