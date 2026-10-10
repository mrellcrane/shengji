import Foundation
import XCTest
@testable import ShengjiCore

/// Cards from short text: "A♠ 10♥ SJ BJ". A trailing apostrophe picks the second copy ("A♠'").
func botCards(_ text: String) -> [Card] {
    var cards: [Card] = []
    for raw in text.split(separator: " ") {
        var token = String(raw)
        var copy = 0
        if token.hasSuffix("'") {
            copy = 1
            token.removeLast()
        }
        if token == "SJ" { cards.append(.smallJoker(copy: copy)); continue }
        if token == "BJ" { cards.append(.bigJoker(copy: copy)); continue }
        let symbol = String(token.removeLast())
        guard let suit = Suit.allCases.first(where: { $0.symbol == symbol }),
              let rank = Rank.allCases.first(where: { $0.label == token }) else {
            preconditionFailure("bad card token \(raw)")
        }
        cards.append(Card(rank, suit, copy: copy))
    }
    return cards
}

func botCard(_ text: String) -> Card { botCards(text)[0] }

/// Situations built by arranging the deck (card i goes to seat (dealer + i) % 4) and playing up to
/// the position under test. Trump rank 2 throughout; the dealer declares hearts with 2♥.
final class BotScenarioTests: XCTestCase {
    private let hearts2 = botCard("2♥")

    /// Deals the arranged deck, the dealer declares 2♥ (hearts trump), buries the original kitty,
    /// then the given plays are made in turn.
    private func table(dealer: Int, hands: [[Card]], plays: [[Card]] = [], seed: UInt64 = 3,
                       file: StaticString = #filePath, line: UInt = #line) throws -> Round {
        var round = BotScenario.round(rank: .two, dealer: dealer, hands: hands, seed: seed)
        let declaration = Declaration(player: dealer, cards: [hearts2], suit: .hearts, strength: 1)
        try BotScenario.start(&round, declare: declaration)
        XCTAssertEqual(round.trump, Trump(rank: .two, suit: .hearts), file: file, line: line)
        for cards in plays {
            guard let seat = round.turn else { throw RoundError.wrongPhase }
            let outcome = try round.play(cards, by: seat)
            XCTAssertEqual(outcome, .played, file: file, line: line)
        }
        return round
    }

    private func assertTexts(_ decision: BotDecision, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(BotHarness.textProblems(decision), [], file: file, line: line)
    }

    // A full 25-card hand for South with no spades and no trump-rank cards.
    private let southNoSpades = botCards("""
        3♥ 4♥ 6♥ 7♥ 8♥ 9♥ K♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ A♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ A♦
        """)

    // MARK: Following

    func testFeedsPointCardWhenPartnerWinsAndYouPlayLast() throws {
        let south = botCards("K♠ 7♠ 8♠ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦")
        let round = try table(dealer: 1, hands: [south, botCards("2♥ 3♠"), botCards("A♠"), botCards("4♠")],
                              plays: [botCards("3♠"), botCards("A♠"), botCards("4♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("K♠"))
        XCTAssertEqual(decision.concept, "Feed points")
        XCTAssertTrue(decision.reason.contains("K♠"))
        assertTexts(decision)
    }

    func testFeedsWhenPartnerHoldsTheTopCardEvenBeforeTheLastPlayer() throws {
        // Partner leads A♠, the other A♠ is in South's own hand, so nobody after South can beat it.
        let south = botCards("A♠' 10♠ 4♠ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦")
        let round = try table(dealer: 2, hands: [south, [], botCards("2♥ A♠"), botCards("3♠ 5♠ 6♠ 7♠")],
                              plays: [botCards("A♠"), botCards("3♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("10♠"))
        XCTAssertEqual(decision.concept, "Feed points")
        assertTexts(decision)
    }

    func testDoesNotFeedWhenAnOpponentAfterYouCanStillWin() throws {
        // Partner leads Q♠; East plays after South and may hold A♠ or K♠.
        let south = botCards("10♠ 4♠ 6♠ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦")
        let round = try table(dealer: 2, hands: [south, botCards("A♠"), botCards("2♥ Q♠"), botCards("3♠")],
                              plays: [botCards("Q♠"), botCards("3♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("4♠"))
        XCTAssertEqual(decision.cards.points, 0)
        XCTAssertEqual(decision.concept, "Duck low")
        assertTexts(decision)
    }

    func testRuffsATrickWithPointsWhenVoid() throws {
        let round = try table(dealer: 1, hands: [southNoSpades, botCards("2♥ A♠"), botCards("10♠"), botCards("5♠")],
                              plays: [botCards("A♠"), botCards("10♠"), botCards("5♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("3♥"), "the cheapest trump is enough as the last player")
        XCTAssertEqual(decision.concept, "Ruff")
        assertTexts(decision)
    }

    func testDoesNotWasteATrumpOnATrickWithoutPoints() throws {
        let round = try table(dealer: 1, hands: [southNoSpades, botCards("2♥ A♠"), botCards("3♠"), botCards("4♠")],
                              plays: [botCards("A♠"), botCards("3♠"), botCards("4♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertFalse(decision.cards.contains { round.trump.isTrump($0) })
        XCTAssertEqual(decision.cards.points, 0)
        XCTAssertEqual(decision.concept, "Discard low")
        assertTexts(decision)
    }

    func testOverruffsAnOpponentsTrump() throws {
        // East leads K♠, partner follows, West (out of spades) trumps with 4♥, South (also out) beats it.
        let west = botCards("4♥ 3♣' 4♣' 6♣' 7♣' 8♣' 9♣' J♣' Q♣' 3♦' 4♦' 6♦' 7♦' 8♦' 9♦' J♦' Q♦' 10♣ 10♦ K♣ K♦ 5♣ 5♦ 10♥ J♥")
        let south = botCards("3♥ 6♥ 7♥ 8♥ 9♥ A♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ A♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ A♦ 5♥")
        let round = try table(dealer: 1, hands: [south, botCards("2♥ K♠"), botCards("3♠"), west],
                              plays: [botCards("K♠"), botCards("3♠"), botCards("4♥")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards.count, 1)
        XCTAssertEqual(decision.concept, "Overruff")
        let card = decision.cards[0]
        XCTAssertTrue(round.trump.isTrump(card))
        XCTAssertGreaterThan(round.trump.strength(card), round.trump.strength(botCard("4♥")))
        // The cheapest trump that wins: 6♥, or 5♥ (it carries 5 points into a trick you win).
        XCTAssertTrue([botCard("6♥"), botCard("5♥")].contains(card), "played \(card)")
        assertTexts(decision)
    }

    func testRuffsHighWhenTheNextOpponentIsAlsoOutOfTheSuit() throws {
        // Trick 1: North (dealer) leads A♠; South and East both show out of spades. North wins.
        // Trick 2: North leads 10♠, West plays K♠ (20 points), South is out of spades and East, still to
        // play, can trump too: South should trump high, not with the 3♥.
        let south = botCards("3♥ 6♥ A♥ 2♣ SJ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ A♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ A♦ 7♥ 8♥")
        let east = botCards("""
            4♥' 9♥' 3♣' 4♣' 6♣' 7♣' 8♣' 9♣' J♣' Q♣' 3♦' 4♦' 6♦' 7♦' 8♦' 9♦' J♦' Q♦' 10♣ 10♦ K♣ K♦ 5♣ 5♦ J♥
            """)
        let round = try table(dealer: 2, hands: [south, east, botCards("2♥ A♠ 10♠"), botCards("4♠ K♠")],
                              plays: [botCards("A♠"), botCards("4♠"), botCards("3♣"), botCards("3♦'"),
                                      botCards("10♠"), botCards("K♠")])
        XCTAssertEqual(round.turn, 0)
        XCTAssertTrue(BotKnowledge(round: round, seat: 0).voids[1].contains(.plain(.spades)))
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.concept, "Ruff")
        XCTAssertEqual(decision.cards.count, 1)
        let card = decision.cards[0]
        XCTAssertTrue(round.trump.isTrump(card))
        XCTAssertGreaterThanOrEqual(round.trump.strength(card), Trump.topPlainStrength, "trumped with \(card)")
        XCTAssertTrue(decision.reason.contains("East"))
        assertTexts(decision)
    }

    func testPlaysLowestNonPointCardWhenItCannotWin() throws {
        let south = botCards("K♠ 10♠ 5♠ 7♠ 9♠ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦")
        let round = try table(dealer: 1, hands: [south, botCards("2♥ A♠"), botCards("3♠"), botCards("4♠")],
                              plays: [botCards("A♠"), botCards("3♠"), botCards("4♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("7♠"))
        XCTAssertEqual(decision.concept, "Duck low")
        assertTexts(decision)
    }

    func testFollowsAPairLeadWithAPairAndKeepsPoints() throws {
        // East leads A♠ A♠; South must play a pair if it has one: 6♠ 6♠, not K♠ K♠.
        let south = botCards("K♠ K♠' 6♠ 6♠' 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦")
        let round = try table(dealer: 1, hands: [south, botCards("2♥ A♠ A♠'"), botCards("3♠ 3♠'"),
                                                 botCards("7♠ 7♠'")],
                              plays: [botCards("A♠ A♠'"), botCards("3♠ 3♠'"), botCards("7♠ 7♠'")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(Set(decision.cards), Set(botCards("6♠ 6♠'")))
        assertTexts(decision)
    }

    func testWinsCheaplyAsTheLastPlayer() throws {
        // East leads 9♠ with 10 points on the table; South is last with J♠ and A♠: J♠ is enough.
        let south = botCards("J♠ A♠ 3♠ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦")
        let round = try table(dealer: 1, hands: [south, botCards("2♥ 9♠"), botCards("4♠"), botCards("10♠")],
                              plays: [botCards("9♠"), botCards("4♠"), botCards("10♠")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("J♠"))
        XCTAssertEqual(decision.concept, "Win cheaply")
        assertTexts(decision)
    }

    func testRuffsAPointTrickWithTheCheapestPairThatIsWorthIt() throws {
        // West leads K♠ K♠ (20 points). South, a defender out of spades, plays second and holds two
        // trump pairs: K♥ K♥ and 8♥ 8♥. Counting the points they bring back, K♥ K♥ comes first, but it
        // costs too much; 8♥ 8♥ is well worth 20 points. South must not give up the ruff altogether.
        let south = botCards("K♥ K♥' 8♥ 8♥' 3♥ 4♥ 6♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ A♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ A♦")
        let round = try table(dealer: 3, hands: [south, [], [], botCards("2♥ K♠ K♠'")], plays: [botCards("K♠ K♠'")])
        XCTAssertEqual(round.turn, 0)
        XCTAssertTrue(round.isDefender(0))
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(Set(decision.cards), Set(botCards("8♥ 8♥'")), "played \(decision.cards.shortText)")
        XCTAssertEqual(decision.concept, "Ruff")
        XCTAssertTrue(decision.reason.contains("20 points"), decision.reason)
        assertTexts(decision)
    }

    func testTrumpsWhenPartnerLeadsIntoYourKnownVoid() throws {
        // Trick 1: North leads A♠ and South shows out of spades. Trick 2: North leads 6♠ so that South
        // can trump it. West's 7♠ is winning a trick with no points yet, but East plays last and would
        // win it or add points to it, so South trumps.
        let south = botCards("3♥ 4♥ 6♥ 7♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ A♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ A♦ 3♣' 4♣' 6♣'")
        let round = try table(dealer: 2, hands: [south, botCards("3♠ 8♠"), botCards("2♥ A♠ 6♠"), botCards("4♠ 7♠")],
                              plays: [botCards("A♠"), botCards("4♠"), botCards("3♣"), botCards("3♠"),
                                      botCards("6♠"), botCards("7♠")])
        XCTAssertEqual(round.turn, 0)
        XCTAssertTrue(BotKnowledge(round: round, seat: 2).voids[0].contains(.plain(.spades)), "North knows")
        XCTAssertEqual(round.currentTrick.reduce(0) { $0 + $1.cards.points }, 0)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards.count, 1)
        XCTAssertTrue(decision.cards.allSatisfy { round.trump.isTrump($0) }, "played \(decision.cards.shortText)")
        XCTAssertEqual(decision.concept, "Ruff")
        XCTAssertTrue(decision.reason.contains("Your partner led spades"), decision.reason)
        assertTexts(decision)
    }

    func testThirdHandWinsWithASureWinnerBeforeTheLastPlayerCanAddPoints() throws {
        // Trick 1: North leads A♠ and everyone follows. Trick 2: North leads 3♠ and West plays Q♠.
        // South holds the last A♠. No points are on the table yet, but East plays last and would feed
        // points to West's Q♠, so South takes the trick now ("third hand high").
        let south = botCards("A♠' 4♠ 7♠ 3♥ 4♥ 6♥ 7♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ A♣ A♦")
        let round = try table(dealer: 2, hands: [south, botCards("6♠ 9♠"), botCards("2♥ A♠ 3♠"), botCards("8♠ Q♠")],
                              plays: [botCards("A♠"), botCards("8♠"), botCards("7♠"), botCards("6♠"),
                                      botCards("3♠"), botCards("Q♠")])
        XCTAssertEqual(round.turn, 0)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("A♠'"))
        XCTAssertEqual(decision.concept, "Sure winner")
        XCTAssertTrue(decision.reason.contains("only a trump can beat it"), decision.reason)
        XCTAssertTrue(decision.reason.contains("East"), "names the last player: \(decision.reason)")
        XCTAssertFalse(decision.reason.contains("for sure"), "a spade can still be trumped: \(decision.reason)")
        assertTexts(decision)
    }

    // MARK: Leading

    func testDoesNotLeadABeatablePointTrumpWhileHoldingATrumpWithoutPoints() throws {
        // South (a defender) wins trick 1 with A♠ and must lead. Every plain card is a point card and
        // no lead is a sure winner. Of the loose trumps, 5♥ is the cheapest card but gives away 5
        // points to anyone with a higher trump; the jokers give away nothing.
        let south = botCards("""
            A♠ K♣ K♣' 10♣ 10♣' 5♣ 5♣' K♦ K♦' 10♦ 10♦' 5♦ 5♦' K♠ 10♠ 10♠' 5♠ 5♠' K♥ K♥' 5♥ 10♥ 10♥' SJ BJ
            """)
        var round = try table(dealer: 1, hands: [south, botCards("2♥ 3♠"), botCards("4♠"), botCards("6♠")],
                              plays: [botCards("3♠"), botCards("4♠"), botCards("6♠"), botCards("A♠")])
        XCTAssertEqual(round.turn, 0)
        XCTAssertTrue(round.isDefender(0))
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards.count, 1)
        XCTAssertEqual(decision.cards.points, 0, "led \(decision.cards.shortText)")
        XCTAssertTrue(decision.cards[0].isJoker, "led \(decision.cards.shortText)")
        XCTAssertFalse(decision.reason.contains("a low trump"), decision.reason)
        assertTexts(decision)
        XCTAssertEqual(try round.play(decision.cards, by: 0), .played)
    }

    /// South deals and leads; `south` must be all 25 cards (South buries the kitty it picked up).
    private func southLeads(_ south: [Card], others: [[Card]] = [[], [], []]) throws -> Round {
        try table(dealer: 0, hands: [south] + others)
    }

    func testLeadsASureWinningAce() throws {
        let south = botCards("2♥ A♠ 4♠ 7♠ 3♥ 6♥ 9♥ 4♥ 8♥ 3♣ 4♣ 6♣ 7♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦")
        let round = try southLeads(south)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("A♠"))
        XCTAssertEqual(decision.concept, "Sure winner")
        assertTexts(decision)
    }

    func testNeverLeadsALoneKingThatIsNotASureWinner() throws {
        // Both A♠ are elsewhere, so South's lone K♠ can be beaten.
        let south = botCards("2♥ K♠ 3♥ 6♥ 9♥ 4♥ 3♣ 5♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 9♦ J♦ Q♦ 6♣ 7♣ 8♦ 4♣ 7♥ 8♥")
        let round = try southLeads(south, others: [botCards("A♠"), [], botCards("A♠'")])
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertFalse(decision.cards.contains(botCard("K♠")))
        XCTAssertEqual(decision.cards.points, 0)
        XCTAssertEqual(decision.concept, "Lead low")
        assertTexts(decision)
    }

    func testThrowsAGuaranteedThrow() throws {
        // A♠ A♠ K♠: nobody can beat the pair (both aces are South's) or the K♠ (no ace is left out).
        let south = botCards("2♥ A♠ A♠' K♠ 3♠ 3♥ 6♥ 9♥ 4♥ 3♣ 5♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 9♦ J♦ Q♦ 6♣ 7♣ 8♦")
        var round = try southLeads(south)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(Set(decision.cards), Set(botCards("A♠ A♠' K♠")))
        XCTAssertEqual(decision.concept, "Throw")
        XCTAssertTrue(Rules.isThrow(decision.cards, trump: round.trump))
        assertTexts(decision)
        XCTAssertEqual(try round.play(decision.cards, by: 0), .played, "the throw must stand")
    }

    func testDoesNotThrowWhenAnUnseenCardCouldBeatPartOfIt() throws {
        // A♠ K♠ Q♠ with the other A♠ out: K♠ and Q♠ can be beaten, so lead the sure A♠ alone.
        let south = botCards("2♥ A♠ K♠ Q♠ 3♥ 6♥ 9♥ 4♥ 3♣ 5♣ 8♣ 9♣ J♣ Q♣ 3♦ 4♦ 6♦ 7♦ 9♦ J♦ Q♦ 6♣ 7♣ 8♦ 4♣")
        let round = try southLeads(south)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("A♠"))
        XCTAssertFalse(Rules.isThrow(decision.cards, trump: round.trump))
        assertTexts(decision)
    }

    func testLeadsASuitPartnerIsOutOf() throws {
        // Trick 1: South leads A♣, North shows out of clubs, South wins. Trick 2: lead a club for
        // North to trump. South has few trumps, so it isn't drawing trumps.
        let south = botCards("2♥ 3♥ 4♥ A♣ 4♣ 7♣ 8♣ 3♠ 5♠ 6♠ 8♠ 9♠ J♠ Q♠ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ 6♠' 7♠ 4♠")
        let north = botCards("""
            3♦' 4♦' 6♦' 7♦' 8♦' 9♦' J♦' Q♦' K♦ A♦ 3♠' 4♠' 5♠' 8♠' 9♠' J♠' Q♠' K♠ A♠ 6♥ 7♥ 8♥ 9♥ J♥ Q♥
            """)
        var round = try southLeads(south, others: [botCards("5♣"), north, botCards("6♣")])
        try round.play(botCards("A♣"), by: 0)
        try round.play(botCards("5♣"), by: 1)
        try round.play(botCards("3♦'"), by: 2)
        try round.play(botCards("6♣"), by: 3)
        XCTAssertEqual(round.turn, 0)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.cards, botCards("4♣"))
        XCTAssertEqual(decision.concept, "Partner's void")
        assertTexts(decision)
    }

    func testDeclarerWithManyTrumpsDrawsTrumps() throws {
        let south = botCards("2♥ 2♠ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ J♥ Q♥ K♥ A♥ 3♣ 4♣ 6♣ 7♣ 8♣ 3♦ 4♦ 6♦ 7♦ 8♦ 3♠ 4♠ 6♠")
        let round = try southLeads(south)
        let decision = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(decision.concept, "Draw trumps")
        XCTAssertTrue(decision.cards.allSatisfy { round.trump.isTrump($0) })
        XCTAssertEqual(decision.cards.points, 0)
        assertTexts(decision)
    }

    // MARK: Burying

    func testBuriesToVoidAShortSuit() throws {
        let south = botCards("""
            4♣ 7♣ 9♣ A♠ K♠ K♠' Q♠ J♠ 10♠ 9♠ 8♠ A♦ Q♦ J♦ 9♦ 8♦ 7♦ 2♥ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ J♥
            """)
        let kitty = botCards("3♦ 4♦ 6♦ 6♠ 7♠ BJ Q♥ K♥")
        var round = BotScenario.round(rank: .two, dealer: 0, hands: [south], kitty: kitty)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [hearts2], suit: .hearts, strength: 1))
        round.finishDealing()
        XCTAssertEqual(round.phase, .burying)
        let decision = Bot(seat: 0).cardsToBury(in: round)
        XCTAssertEqual(decision.cards.count, 8)
        XCTAssertTrue(round.hands[0].containsAll(decision.cards))
        XCTAssertTrue(decision.cards.containsAll(botCards("4♣ 7♣ 9♣")), "buried \(decision.cards.shortText)")
        XCTAssertFalse(decision.cards.contains { round.trump.isTrump($0) })
        XCTAssertFalse(decision.cards.contains { $0.rank == .ace })
        XCTAssertEqual(decision.cards.points, 0)
        XCTAssertEqual(decision.concept, "Create a void")
        assertTexts(decision)
        try round.bury(decision.cards)
        XCTAssertTrue(Combos.cards(round.hands[0], in: .plain(.clubs), trump: round.trump).isEmpty)
    }

    func testBuriesLowSinglesAndKeepsPairsAcesAndPoints() throws {
        // Every plain suit is long, so no void is possible: bury the lowest singles.
        let south = botCards("""
            3♣ 4♣ 6♣ 6♣' 9♣ K♣ A♣ 3♠ 4♠ 8♠ 10♠ Q♠ A♠ 3♦ 4♦ 7♦ 7♦' 10♦ K♦ 2♥ 3♥ 4♥ 6♥ 7♥ 8♥
            """)
        let kitty = botCards("5♣ J♣ 5♠ 9♠ 5♦ 8♦ 9♥ 10♥")
        var round = BotScenario.round(rank: .two, dealer: 0, hands: [south], kitty: kitty)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [hearts2], suit: .hearts, strength: 1))
        round.finishDealing()
        let decision = Bot(seat: 0).cardsToBury(in: round)
        XCTAssertEqual(Set(decision.cards), Set(botCards("3♣ 4♣ 3♠ 4♠ 8♠ 3♦ 4♦ 8♦")))
        XCTAssertEqual(decision.cards.points, 0)
        XCTAssertFalse(decision.cards.contains { $0.rank == .ace })
        XCTAssertFalse(decision.cards.contains { $0.rank == .six || $0.rank == .seven }, "keeps the pairs")
        XCTAssertEqual(decision.concept, "Bury low")
        assertTexts(decision)
    }

    func testBeginnerBuriesItsLowestNonTrumps() throws {
        let south = botCards("""
            3♣ 4♣ 6♣ 6♣' 9♣ K♣ A♣ 3♠ 4♠ 8♠ 10♠ Q♠ A♠ 3♦ 4♦ 7♦ 7♦' 10♦ K♦ 2♥ 3♥ 4♥ 6♥ 7♥ 8♥
            """)
        let kitty = botCards("5♣ 8♣ 5♠ 9♠ 5♦ 8♦ 9♥ 10♥")
        var round = BotScenario.round(rank: .two, dealer: 0, hands: [south], kitty: kitty)
        round.dealAll()
        try round.declare(Declaration(player: 0, cards: [hearts2], suit: .hearts, strength: 1))
        round.finishDealing()
        let decision = Bot(seat: 0, level: .beginner).cardsToBury(in: round)
        XCTAssertEqual(decision.cards.count, 8)
        XCTAssertFalse(decision.cards.contains { round.trump.isTrump($0) })
        let plain = round.hands[0].filter { !round.trump.isTrump($0) }
        let highestBuried = decision.cards.map { round.trump.strength($0) }.max() ?? 0
        let kept = plain.filter { !decision.cards.contains($0) }
        XCTAssertTrue(kept.allSatisfy { round.trump.strength($0) >= highestBuried })
        assertTexts(decision)
    }

    // MARK: Declaring

    /// Deals one card at a time; after each card South receives, asks South's bot to declare.
    /// Returns the first declaration and how many cards South had then.
    private func firstDeclaration(south: [Card], others: [[Card]] = [[], [], []], bot: Bot = Bot(seat: 0),
                                  before: ((inout Round) throws -> Void)? = nil) throws -> (Declaration, Int)? {
        let deck = EngineTestSupport.deck(hands: [south] + others, firstSeat: 0, seed: 11)
        var round = Round(trumpRank: .two, dealer: nil, deck: deck)
        while let dealt = round.dealNext() {
            if let before = before { try before(&round) }
            guard dealt.player == 0, let choice = bot.declaration(in: round) else { continue }
            XCTAssertTrue(round.availableDeclarations(for: 0).contains(choice))
            return (choice, round.hands[0].count)
        }
        return nil
    }

    func testDeclaresWithAStrongSuit() throws {
        let south = botCards("2♥ A♥ K♥ Q♥ J♥ 10♥ 3♠ 4♣ 9♥ 8♥ 6♠ 7♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ 3♣ 4♠ 6♣ 7♠ 8♣")
        let found = try firstDeclaration(south: south)
        let (declaration, received) = try XCTUnwrap(found)
        XCTAssertEqual(declaration.suit, .hearts)
        XCTAssertEqual(declaration.player, 0)
        XCTAssertEqual(received, 6, "declares as soon as six cards are in")
    }

    func testDoesNotDeclareAWeakSuit() throws {
        // One 2♥ and nothing else trump-like.
        let south = botCards("2♥ 3♠ 4♣ 6♦ 7♠ 8♣ 9♦ J♠ Q♣ K♦ 3♣ 4♠ 6♣ 7♦ 8♠ 9♣ J♦ Q♠ K♣ 3♦ 4♦ 6♠ 7♣ 8♦ 9♠")
        XCTAssertNil(try firstDeclaration(south: south))
    }

    func testDeclaresNoTrumpWithJokersAndRankCardsButNoLongSuit() throws {
        // After six cards: a pair of small jokers, one 2 and three different plain suits.
        let south = botCards("SJ SJ' 2♠ 3♥ 4♣ 6♦ 7♠ 8♥ 9♣ 10♦ J♠ Q♥ K♣ 3♦ 4♠ 6♥ 7♣ 8♦ 9♠ J♥ Q♣ K♦ 3♠ 4♥ 6♣")
        let found = try firstDeclaration(south: south)
        let (declaration, received) = try XCTUnwrap(found)
        XCTAssertNil(declaration.suit)
        XCTAssertEqual(declaration.strength, 3)
        XCTAssertEqual(received, 6)
    }

    func testPrefersALongSuitOverNoTrump() throws {
        // A joker pair, but also a long heart suit with its 2: declare hearts.
        let south = botCards("SJ SJ' 2♥ A♥ K♥ Q♥ J♥ 10♥ 3♠ 4♣ 6♦ 7♠ 8♣ 9♦ 3♥ 4♥ 6♥ 7♥ 8♥ 9♥ 3♣ 4♠ 6♣ 7♦ 8♠")
        let found = try firstDeclaration(south: south)
        let (declaration, _) = try XCTUnwrap(found)
        XCTAssertEqual(declaration.suit, .hearts)
    }

    func testBeginnerDeclaresOnlyWithAPair() throws {
        let strongSingle = botCards("2♥ A♥ K♥ Q♥ J♥ 10♥ 3♠ 4♣ 9♥ 8♥ 6♠ 7♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ 3♣ 4♠ 6♣ 7♠ 8♣")
        XCTAssertNil(try firstDeclaration(south: strongSingle, bot: Bot(seat: 0, level: .beginner)))
        let pair = botCards("3♠ 2♦ 4♣ 2♦' 6♠ 7♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ 3♣ 4♠ 6♣ 7♠ 8♣ 9♠ J♣ Q♠ K♣ 8♠ 9♣")
        let found = try firstDeclaration(south: pair, bot: Bot(seat: 0, level: .beginner))
        let (declaration, received) = try XCTUnwrap(found)
        XCTAssertEqual(declaration.strength, 2)
        XCTAssertEqual(declaration.suit, .diamonds)
        XCTAssertEqual(received, 4)
    }

    func testNeverOverridesPartner() throws {
        // North declares spades early; South later holds a strong hearts hand with a pair of 2♥.
        let south = botCards("3♠ 4♣ 2♥ 2♥' A♥ K♥ Q♥ J♥ 10♥ 9♥ 8♥ 7♥ 6♥ 4♥ 3♥ 5♥ 6♣ 7♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦")
        let north = botCards("2♠ 3♠' 4♠ 5♠ 6♠")
        var overrode = false
        let deck = EngineTestSupport.deck(hands: [south, [], north, []], firstSeat: 0, seed: 5)
        var round = Round(trumpRank: .two, dealer: nil, deck: deck)
        while let dealt = round.dealNext() {
            if dealt.player == 2, round.declaration == nil, round.hands[2].contains(botCard("2♠")) {
                try round.declare(Declaration(player: 2, cards: [botCard("2♠")], suit: .spades, strength: 1))
            }
            if dealt.player == 0 {
                XCTAssertNil(Bot(seat: 0).declaration(in: round), "overrode partner after \(round.hands[0].count) cards")
                if !round.availableDeclarations(for: 0).isEmpty { overrode = true }
            }
        }
        XCTAssertTrue(overrode, "South could have overridden, so the test means something")
        XCTAssertNil(Bot(seat: 0).declaration(in: round))
        XCTAssertNil(Bot(seat: 0, level: .beginner).declaration(in: round))
    }

    func testOverridesAnOpponentOnlyWithAClearlyGoodSuit() throws {
        let strong = botCards("3♠ 4♣ 2♥ 2♥' A♥ K♥ Q♥ J♥ 10♥ 9♥ 8♥ 7♥ 6♥ 4♥ 3♥ 5♥ 6♣ 7♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦")
        let weak = botCards("3♠ 4♣ 2♥ 2♥' 6♣ 7♣ 3♦ 4♦ 6♦ 7♦ 8♦ 9♦ J♦ Q♦ 3♣ 4♠ 8♣ 7♠ 9♣ J♣ 8♠ 9♠ J♠ Q♠ Q♣")
        for (south, expectOverride) in [(strong, true), (weak, false)] {
            let deck = EngineTestSupport.deck(hands: [south, botCards("2♠ 3♠' 4♠'")], firstSeat: 0, seed: 5)
            var round = Round(trumpRank: .two, dealer: nil, deck: deck)
            round.dealAll()
            try round.declare(Declaration(player: 1, cards: [botCard("2♠")], suit: .spades, strength: 1))
            let choice = Bot(seat: 0).declaration(in: round)
            if expectOverride {
                XCTAssertEqual(choice?.suit, .hearts)
                XCTAssertEqual(choice?.strength, 2)
            } else {
                XCTAssertNil(choice, "overrode with a weak hand")
            }
        }
    }

    func testReinforcesItsOwnSingleWithAPair() throws {
        let deck = EngineTestSupport.deck(hands: [botCards("2♥ A♥ K♥ Q♥ J♥ 10♥ 2♥'")], firstSeat: 0, seed: 2)
        var round = Round(trumpRank: .two, dealer: nil, deck: deck)
        var declared: [Declaration] = []
        while let dealt = round.dealNext() {
            guard dealt.player == 0, let choice = Bot(seat: 0).declaration(in: round) else { continue }
            try round.declare(choice)
            declared.append(choice)
        }
        XCTAssertEqual(declared.map(\.strength), [1, 2])
        XCTAssertEqual(declared.map(\.suit), [.hearts, .hearts])
    }

    // MARK: Odd calls

    func testOutOfTurnCallsDoNotCrashAndStillExplain() throws {
        var rng = SeededGenerator(seed: 4)
        var round = Round(trumpRank: .two, dealer: 1, rng: &rng)
        for _ in 0..<10 { round.dealNext() }
        let early = Bot(seat: 0).decide(in: round)
        XCTAssertEqual(early.cards, [])
        XCTAssertFalse(early.reason.isEmpty || early.nudge.isEmpty || early.principle.isEmpty || early.concept.isEmpty)
        XCTAssertEqual(Bot(seat: 0).cardsToBury(in: round).cards, [])
        round.dealAll()
        round.finishDealing()
        XCTAssertNil(Bot(seat: 1).declaration(in: round), "no declaring after the deal closes")
        XCTAssertEqual(Bot(seat: 0).cardsToBury(in: round).cards, [], "only the dealer buries")
        XCTAssertEqual(Bot(seat: 1).cardsToBury(in: round).cards.count, 8)
        // Seats outside 0...3 are normalised rather than crashing.
        XCTAssertEqual(Bot(seat: 5).cardsToBury(in: round).cards.count, 8)

        // During play only the seat whose turn it is gets cards; everyone else gets the waiting text.
        try round.bury(Bot(seat: 1).cardsToBury(in: round).cards)
        XCTAssertEqual(round.turn, 1)
        for seat in [0, 2, 3] {
            let waiting = Bot(seat: seat).decide(in: round)
            XCTAssertEqual(waiting.cards, [])
            XCTAssertEqual(BotHarness.textProblems(waiting), [])
        }
        XCTAssertNil(Bot(seat: 2).declaration(in: round))
        XCTAssertEqual(Bot(seat: 1).cardsToBury(in: round).cards, [], "the kitty is already buried")

        // After the last trick nobody has anything to play.
        let bots = (0..<4).map { Bot(seat: $0) }
        var stats = BotRunStats()
        BotHarness.playOut(&round, bots: bots, stats: &stats)
        XCTAssertEqual(stats.problems, [])
        XCTAssertEqual(round.phase, .finished)
        for seat in 0..<4 {
            XCTAssertEqual(Bot(seat: seat).decide(in: round).cards, [])
            XCTAssertEqual(Bot(seat: seat, level: .beginner).decide(in: round).cards, [])
            XCTAssertEqual(Bot(seat: seat).cardsToBury(in: round).cards, [])
        }
    }
}
