import XCTest
@testable import ShengjiCore

final class CardIDTests: XCTestCase {
    func testInitFromIDRoundTripsEveryCard() {
        for card in Deck.double() {
            XCTAssertEqual(Card(id: card.id), card)
        }
        XCTAssertEqual((0..<108).compactMap { Card(id: $0) }.map(\.id), Array(0..<108))
    }

    func testInitFromIDKnownValues() {
        XCTAssertEqual(Card(id: 0), c(.two, .spades))
        XCTAssertEqual(Card(id: 12), c(.ace, .spades))
        XCTAssertEqual(Card(id: 13), c(.two, .hearts))
        XCTAssertEqual(Card(id: 51), c(.ace, .diamonds))
        XCTAssertEqual(Card(id: 52), sj0)
        XCTAssertEqual(Card(id: 53), bj0)
        XCTAssertEqual(Card(id: 54), c(.two, .spades, 1))
        XCTAssertEqual(Card(id: 106), sj1)
        XCTAssertEqual(Card(id: 107), bj1)
    }

    func testInitFromIDRejectsOutOfRange() {
        XCTAssertNil(Card(id: -1))
        XCTAssertNil(Card(id: 108))
        XCTAssertNil(Card(id: Int.max))
        XCTAssertNil(Card(id: Int.min))
    }
}
