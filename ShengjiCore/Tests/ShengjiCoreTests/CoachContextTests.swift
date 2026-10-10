import Foundation
import XCTest
@testable import ShengjiCore

/// Helpers shared by the coach and achievements tests: random rounds in every phase, what the human can
/// see, card tokens in text, and hand-built seat views and tricks.
enum CoachTestKit {
    static let heartsTwo = Trump(rank: .two, suit: .hearts)
    static let emDash: Character = "\u{2014}"

    struct TableState {
        var round: Round
        var game: GameState?
        var label: String
    }

    // MARK: Random states

    /// A game that has already played a few (synthetic) rounds, so levels differ.
    static func game(rounds: Int, seed: UInt64) -> GameState {
        var game = GameState()
        var rng = SeededGenerator(seed: seed)
        for _ in 0..<rounds {
            let dealer = game.nextDealer ?? Int.random(in: 0..<4, using: &rng)
            let points = 5 * Int.random(in: 0...40, using: &rng)
            let result = RoundResult(
                dealer: dealer, declarerTeam: Seats.team(of: dealer), trump: Trump(rank: game.nextTrumpRank, suit: .spades),
                trickPoints: points, kittyPoints: 0, kittyMultiplier: 0, defenderPoints: points,
                outcome: Scoring.outcome(defenderPoints: points), kitty: [], lastTrickWinner: dealer)
            game.record(result)
        }
        return game
    }

    /// A round (from a fresh deal) taken to a random point: mid-deal, deal complete, burying, any point of
    /// play (including trick pauses), or finished. Random legal moves for every seat.
    static func randomState(seed: UInt64) throws -> TableState {
        var rng = SeededGenerator(seed: seed &* 0x9E37_79B9 &+ 101)
        let withGame = seed % 3 != 0
        var game = withGame ? self.game(rounds: Int(seed % 5), seed: seed) : nil
        let dealers: [Int?] = [nil, 0, 1, 2, 3]
        let rank = Rank.allCases[Int(seed % 13)]
        var round: Round
        if let current = game, current.nextDealer != nil {
            round = current.makeRound(rng: &rng)
        } else {
            round = Round(trumpRank: rank, dealer: dealers[Int(seed % 5)], rng: &rng)
        }
        let stage = Int(seed % 9)
        // Dealing: deal part of the cards with random declarations.
        let toDeal = stage == 0 ? Int.random(in: 0...99, using: &rng) : 100
        for _ in 0..<toDeal {
            round.dealNext()
            if Int.random(in: 0..<6, using: &rng) == 0 {
                let seat = Int.random(in: 0..<4, using: &rng)
                if let option = round.availableDeclarations(for: seat).randomElement(using: &rng) {
                    try round.declare(option)
                }
            }
        }
        if stage <= 1 { return TableState(round: round, game: game, label: "dealing \(toDeal)") }
        round.finishDealing()
        if stage == 2 { return TableState(round: round, game: game, label: "burying") }
        guard let dealer = round.dealer else { return TableState(round: round, game: game, label: "no dealer") }
        try round.bury(Array(round.hands[dealer].shuffled(using: &rng).prefix(Round.kittySize)))
        if stage == 8 {
            try EngineTestSupport.playOut(&round, rng: &rng)
            if let result = round.result, seed % 2 == 0, game != nil {
                game?.record(result)
            }
            return TableState(round: round, game: game, label: "finished")
        }
        let moves = Int.random(in: 0...99, using: &rng)
        for _ in 0..<moves where round.phase == .playing {
            _ = try EngineTestSupport.playOneMove(&round, rng: &rng)
        }
        return TableState(round: round, game: game, label: "playing after \(moves) moves")
    }

    // MARK: What the human sees

    /// Every card `viewer` may know about: own hand, cards played, cards shown in declarations, the kitty card
    /// flipped to choose trump, and the kitty when the viewer is the dealer holding it or the round is over.
    static func visibleCards(_ round: Round, viewer: Int = Seats.human) -> [Card] {
        var cards = round.hands[viewer] + round.playedCards
        cards += round.declarationHistory.flatMap(\.cards)
        if let flipped = round.trumpFromKitty { cards.append(flipped) }
        switch round.phase {
        case .burying, .playing:
            if round.dealer == viewer { cards += round.kitty }
        case .finished:
            cards += round.kitty
        case .dealing:
            break
        }
        return cards
    }

    /// Faces of the cards written in `text` ("10♥", "A♠", "SJ", "BJ"). Lines that state the trump order
    /// (rules, not cards anyone holds) are skipped.
    static func cardFaces(in text: String) -> [Face] {
        var faces: [Face] = []
        for line in text.split(separator: "\n") where !line.hasPrefix("Trump order") {
            let chars = Array(line)
            for index in chars.indices {
                let ch = chars[index]
                if let suit = suit(for: ch) {
                    var rank: Rank?
                    if index >= 2 && chars[index - 2] == "1" && chars[index - 1] == "0" {
                        rank = .ten
                    } else if index >= 1 {
                        rank = self.rank(for: chars[index - 1])
                    }
                    if let rank { faces.append(.regular(suit, rank)) }
                }
                if (ch == "S" || ch == "B") && index + 1 < chars.count && chars[index + 1] == "J" {
                    let before = index == 0 || !chars[index - 1].isLetter
                    let after = index + 2 >= chars.count || !chars[index + 2].isLetter
                    if before && after { faces.append(ch == "S" ? .smallJoker : .bigJoker) }
                }
            }
        }
        return faces
    }

    static func suit(for ch: Character) -> Suit? {
        switch ch {
        case "♠": return .spades
        case "♥": return .hearts
        case "♣": return .clubs
        case "♦": return .diamonds
        default: return nil
        }
    }

    static func rank(for ch: Character) -> Rank? {
        switch ch {
        case "A": return .ace
        case "K": return .king
        case "Q": return .queen
        case "J": return .jack
        default:
            guard let digit = Int(String(ch)), (2...9).contains(digit) else { return nil }
            return Rank(rawValue: digit)
        }
    }

    // MARK: Hand-built views and tricks

    static func view(phase: SeatView.Phase = .playing, trump: Trump = heartsTwo, dealer: Int? = 1,
                     hand: [Card] = [], handCounts: [Int]? = nil, currentTrick: [Play] = [], leader: Int = 1,
                     turn: Int? = 0, tricks: [TrickRecord] = [], defenderPoints: Int = 0, kitty: [Card]? = nil,
                     result: RoundResult? = nil, levels: [Rank] = [.two, .two], declaration: Declaration? = nil,
                     history: [Declaration] = [], trumpFromKitty: Card? = nil, summary: RoundSummary? = nil,
                     bidding: SeatView.Bidding? = nil, roundNumber: Int = 1) -> SeatView {
        let players = Seats.all.map { SeatView.Player(name: Seats.name($0), isBot: $0 != Seats.human) }
        return SeatView(
            players: players, teamLevels: levels, targetRank: .ace, roundNumber: roundNumber, phase: phase,
            trump: trump, trumpFromKitty: trumpFromKitty, dealer: dealer, hand: hand,
            handCounts: handCounts ?? [hand.count, hand.count, hand.count, hand.count],
            declaration: declaration ?? history.last, declarationHistory: history, bidding: bidding, kitty: kitty,
            currentTrick: currentTrick, leader: leader, turn: turn, tricks: tricks, defenderTrickPoints: defenderPoints,
            result: result, lastRoundSummary: summary, gameWinnerTeam: nil)
    }

    /// A finished trick with its real winner and points.
    static func trick(_ plays: [Play], trump: Trump = heartsTwo) -> TrickRecord {
        let index = Rules.winningIndex(plays, trump: trump)
        let points = plays.reduce(0) { $0 + $1.cards.points }
        return TrickRecord(plays: plays, winner: plays[index].player, points: points)
    }

    static func c(_ rank: Rank, _ suit: Suit, _ copy: Int = 0) -> Card { Card(rank, suit, copy: copy) }
    static func pair(_ rank: Rank, _ suit: Suit) -> [Card] { [Card(rank, suit, copy: 0), Card(rank, suit, copy: 1)] }

    static func ladder(cards: [Card], steps: Int, nudge: String = "Look at who is winning this trick.",
                       principle: String = "When your partner is sure to win, give them points.",
                       reason: String = "Partner's ace is winning, so give them your king.",
                       concept: String = "Feed points") -> HintLadder {
        let decision = BotDecision(cards: cards, reason: reason, concept: concept, nudge: nudge, principle: principle)
        var ladder = HintLadder(decision: decision)
        for _ in 0..<steps { ladder.advance() }
        return ladder
    }
}

final class CoachContextTests: XCTestCase {
    private typealias Kit = CoachTestKit
    private let trump = CoachTestKit.heartsTwo

    private func line(_ prefix: String, in text: String) -> String? {
        text.split(separator: "\n").map(String.init).first { $0.hasPrefix(prefix) }
    }

    // MARK: Privacy

    func testCardTokenizerFindsEveryCardWritten() {
        let text = "Hand: 10♥ A♠ 3♣ SJ BJ Q♦\nTrump order (high to low): K♥ > 5♥\nThe 2s are trumps, suit ♥, SJS"
        XCTAssertEqual(Kit.cardFaces(in: text), [.regular(.hearts, .ten), .regular(.spades, .ace), .regular(.clubs, .three),
                                                  .smallJoker, .bigJoker, .regular(.diamonds, .queen)])
    }

    func testRandomStatesNeverMentionHiddenCards() throws {
        var phases: [RoundPhase: Int] = [:]
        for seed in UInt64(0)..<UInt64(360) {
            let state = try Kit.randomState(seed: seed)
            let round = state.round
            phases[round.phase, default: 0] += 1
            let hand = round.hands[0]
            let hint = seed % 4 == 0 ? Kit.ladder(cards: Array(hand.prefix(1)), steps: Int(seed % 3) + 1) : nil
            let selection = Array(hand.suffix(Int(seed % 4)))
            let attempt = seed % 5 == 0 ? IllegalAttempt(cards: Array(hand.prefix(2)), error: .illegalFollow(.mustPlayPairs(required: 1))) : nil
            let text = CoachContext.describe(round: round, game: state.game, hint: hint, selection: selection, lastIllegal: attempt)
            let visible = Set(Kit.visibleCards(round).map(\.face))
            for face in Kit.cardFaces(in: text) {
                XCTAssertTrue(visible.contains(face), "seed \(seed) (\(state.label)): \(face) is not visible to you\n\(text)")
            }
            XCTAssertFalse(text.contains(Kit.emDash), "seed \(seed)")
        }
        for phase in [RoundPhase.dealing, .burying, .playing, .finished] {
            XCTAssertGreaterThan(phases[phase] ?? 0, 20, "too few \(phase) states")
        }
    }

    /// Other hands and the kitty hold faces you never see; they must not appear until played or revealed.
    func testScriptedRoundKeepsOtherHandsAndKittyHidden() throws {
        let east = [Card.bigJoker(copy: 0), Card.bigJoker(copy: 1), Kit.c(.two, .hearts)]
        let west = Kit.pair(.ace, .spades)
        let partner = Kit.pair(.king, .hearts)
        let kitty = Kit.pair(.queen, .clubs)
        let deck = EngineTestSupport.deck(hands: [[], east, partner, west], kitty: kitty, firstSeat: 1, seed: 99)
        var round = Round(trumpRank: .two, dealer: 1, deck: deck)
        var rng = SeededGenerator(seed: 5)
        var checks = 0

        func check(_ label: String) {
            let text = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
            let mentioned = Set(Kit.cardFaces(in: text))
            let visible = Set(Kit.visibleCards(round).map(\.face))
            for face in [Face.bigJoker, .regular(.spades, .ace), .regular(.hearts, .king), .regular(.clubs, .queen)]
            where !visible.contains(face) {
                XCTAssertFalse(mentioned.contains(face), "\(label): \(face) leaked\n\(text)")
            }
            XCTAssertTrue(mentioned.isSubset(of: visible), "\(label): \(mentioned.subtracting(visible))")
            XCTAssertLessThanOrEqual(text.utf16.count, CoachContext.maxTableCharacters)
            checks += 1
        }

        while round.dealNext() != nil { check("dealing \(round.hands[0].count)") }
        guard let declaration = round.availableDeclarations(for: 1).first(where: { $0.suit == .hearts }) else {
            return XCTFail("East should be able to declare hearts")
        }
        try round.declare(declaration)
        check("declared")
        round.finishDealing()
        check("burying")
        let original = round.kitty
        try round.bury(original)
        check("buried")
        while round.phase == .playing {
            _ = try EngineTestSupport.playOneMove(&round, rng: &rng)
            check("play \(round.playedCards.count)")
        }
        // The kitty (with both Q♣) is revealed once the round is over.
        let final = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(final.contains("Q♣ Q♣"), final)
        XCTAssertGreaterThan(checks, 100)
    }

    func testDealerSeesTheKittyTheyHoldAndBuried() throws {
        let kitty = [Kit.c(.king, .clubs), Kit.c(.ten, .diamonds), Kit.c(.five, .spades)]
        let deck = EngineTestSupport.deck(hands: [[], [], [], []], kitty: kitty, firstSeat: 0, seed: 4)
        var round = Round(trumpRank: .three, dealer: 0, deck: deck)
        round.dealAll()
        round.finishDealing()
        let burying = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(burying.contains("You are the dealer"), burying)
        XCTAssertNotNil(line("Kitty cards you picked up", in: burying), burying)
        XCTAssertTrue(burying.contains("Your hand (33 cards"), burying)
        let buried = Array(round.trump.sorted(round.hands[0]).prefix(8))
        try round.bury(buried)
        let playing = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        guard let kittyLine = line("Kitty you buried", in: playing) else { return XCTFail(playing) }
        XCTAssertTrue(kittyLine.contains(round.trump.sorted(buried).shortText), kittyLine)
        XCTAssertTrue(kittyLine.contains("(\(buried.points) points)"), kittyLine)
    }

    func testOtherDealersKittyIsDescribedButNotShown() throws {
        let deck = EngineTestSupport.deck(firstSeat: 2, seed: 8)
        var round = Round(trumpRank: .two, dealer: 2, deck: deck)
        round.dealAll()
        round.finishDealing()
        let burying = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(burying.contains("Partner (the dealer) is burying"), burying)
        XCTAssertNil(line("Kitty cards you picked up", in: burying))
        try round.bury(Array(round.hands[2].prefix(8)))
        let playing = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertNotNil(line("Kitty: 8 cards buried face down by Partner", in: playing), playing)
        for card in round.kitty where !Kit.visibleCards(round).contains(where: { $0.face == card.face }) {
            XCTAssertFalse(Kit.cardFaces(in: playing).contains(card.face))
        }
    }

    func testSeatViewPathForAnotherViewerStaysPrivate() throws {
        for seed in UInt64(0)..<UInt64(120) {
            let state = try Kit.randomState(seed: seed)
            let viewer = Int(seed % 4)
            let view = state.round.seatView(for: viewer, game: state.game)
            let text = CoachContext.describe(view: view, hint: nil, selection: [], lastIllegal: nil)
            let visible = Set(Kit.visibleCards(state.round, viewer: viewer).map(\.face))
            for face in Kit.cardFaces(in: text) {
                XCTAssertTrue(visible.contains(face), "seed \(seed), viewer \(viewer): \(face)\n\(text)")
            }
            XCTAssertLessThanOrEqual(text.utf16.count, CoachContext.maxTableCharacters)
        }
    }

    func testSelectionHintAndAttemptCardsOutsideYourHandAreDropped() {
        let hand = [Kit.c(.three, .spades), Kit.c(.king, .spades)]
        let view = Kit.view(hand: hand, leader: 0, turn: 0)
        let stranger = Kit.c(.ace, .diamonds)
        let hint = Kit.ladder(cards: [stranger], steps: 3)
        let attempt = IllegalAttempt(cards: [stranger], error: .illegalLead(.cardsNotInHand))
        let text = CoachContext.describe(view: view, hint: hint, selection: [stranger, hand[1]], lastIllegal: attempt)
        XCTAssertFalse(Kit.cardFaces(in: text).contains(stranger.face), text)
        XCTAssertEqual(line("Cards you have selected", in: text), "Cards you have selected (not played yet): K♠.")
        XCTAssertNotNil(line("Your last attempt was not allowed", in: text), text)
    }

    // MARK: Size

    func testContextStaysWithinLimitsForEveryRandomState() throws {
        var longest = 0
        for seed in UInt64(0)..<UInt64(300) {
            let state = try Kit.randomState(seed: seed &+ 1_000)
            let hand = state.round.hands[0]
            let hint = Kit.ladder(cards: hand, steps: 3, reason: String(repeating: "Think about the points. ", count: 20))
            let attempt = IllegalAttempt(cards: hand, error: .illegalFollow(.mustFollowSuit(.trump)))
            let text = CoachContext.describe(round: state.round, game: state.game, hint: hint, selection: hand, lastIllegal: attempt)
            longest = max(longest, text.utf16.count)
            XCTAssertLessThanOrEqual(text.utf16.count, CoachContext.maxTableCharacters, "seed \(seed)")
            XCTAssertNotNil(line("Phase:", in: text), "seed \(seed)")
        }
        XCTAssertLessThanOrEqual(longest, 6_000)
    }

    func testWorstCaseThirtyThreeCardHandAndLongHistoryFit() throws {
        // You deal and hold 33 cards; a huge hint and explanation are attached.
        let deck = EngineTestSupport.deck(firstSeat: 0, seed: 12)
        var round = Round(trumpRank: .ten, dealer: 0, deck: deck)
        round.dealAll()
        round.finishDealing()
        let hand = round.hands[0]
        let huge = String(repeating: "Count the trumps that are still out before you lead. ", count: 100)
        let hint = Kit.ladder(cards: Array(hand.prefix(8)), steps: 3, reason: huge)
        let attempt = IllegalAttempt(cards: Array(hand.prefix(8)), error: .invalidBury(huge))
        let burying = CoachContext.describe(round: round, game: Kit.game(rounds: 6, seed: 3), hint: hint,
                                            selection: hand, lastIllegal: attempt)
        XCTAssertLessThanOrEqual(burying.utf16.count, CoachContext.maxTableCharacters)
        XCTAssertNotNil(line("Your hand (33 cards", in: burying), burying)
        XCTAssertNotNil(line("Hint shown to you", in: burying), burying)

        // Late in a round: 24 tricks of history.
        try round.bury(Array(hand.prefix(8)))
        var rng = SeededGenerator(seed: 77)
        while round.phase == .playing && round.hands[0].count > 1 {
            _ = try EngineTestSupport.playOneMove(&round, rng: &rng)
        }
        let late = CoachContext.describe(round: round, game: nil, hint: hint, selection: round.hands[0], lastIllegal: attempt)
        XCTAssertLessThanOrEqual(late.utf16.count, CoachContext.maxTableCharacters)
        XCTAssertNotNil(line("Phase:", in: late))
    }

    func testOverflowingTextDropsLowPriorityLinesFirst() {
        // A long history, a long hint and an attempt, squeezed into a small budget: the played-cards detail and
        // other extras go first, while the phase, hand, current trick, hint and attempt stay.
        var tricks: [TrickRecord] = []
        let deck = Deck.double().filter { !Kit.heartsTwo.isTrump($0) }
        var index = 0
        while index + 4 <= min(deck.count, 72) {
            let plays = (0..<4).map { Play(player: ($0 + 1) % 4, cards: [deck[index + $0]]) }
            tricks.append(Kit.trick(plays))
            index += 4
        }
        let hand = Array(Deck.double().filter { Kit.heartsTwo.isTrump($0) }.prefix(12))
        let hint = Kit.ladder(cards: hand, steps: 3, reason: String(repeating: "x", count: 3_000))
        let view = Kit.view(hand: hand, currentTrick: [Play(player: 1, cards: [Kit.c(.ace, .clubs, 1)])], tricks: tricks)
        let attempt = IllegalAttempt(cards: [hand[0]], error: .invalidBury(String(repeating: "y", count: 3_000)))
        let table = TableDescription(view: view, levelsKnown: true, available: nil, dealingComplete: true)
        let full = table.text(hint: hint, selection: hand, lastIllegal: attempt)
        XCTAssertNotNil(line("Played so far (", in: full), full)
        XCTAssertNotNil(line("Cards still out", in: full), full)

        let squeezed = table.text(hint: hint, selection: hand, lastIllegal: attempt, limit: 2_200)
        XCTAssertLessThanOrEqual(squeezed.utf16.count, 2_200)
        XCTAssertNil(line("Played so far (", in: squeezed), squeezed)
        XCTAssertNil(line("Cards still out", in: squeezed), squeezed)
        for prefix in ["Phase:", "Your hand", "Current trick", "Hint shown to you", "You just tried", "Cards you have selected"] {
            XCTAssertNotNil(line(prefix, in: squeezed), "\(prefix) missing\n\(squeezed)")
        }

        // Even an impossible budget gives text within it.
        let tiny = table.text(hint: hint, selection: hand, lastIllegal: attempt, limit: 300)
        XCTAssertLessThanOrEqual(tiny.utf16.count, 300)
        XCTAssertTrue(tiny.hasPrefix("Phase:"), tiny)
    }

    // MARK: Content

    func testPhaseLinesForEachSituation() {
        let lead = Play(player: 1, cards: [Kit.c(.king, .spades)])
        XCTAssertEqual(line("Phase:", in: CoachContext.describe(view: Kit.view(leader: 0, turn: 0), hint: nil, selection: [], lastIllegal: nil)),
                       "Phase: playing, trick 1. Your turn to lead.")
        let follow = Kit.view(currentTrick: [lead, Play(player: 2, cards: [Kit.c(.three, .spades)]),
                                             Play(player: 3, cards: [Kit.c(.four, .spades)])], leader: 1, turn: 0)
        XCTAssertEqual(line("Phase:", in: CoachContext.describe(view: follow, hint: nil, selection: [], lastIllegal: nil)),
                       "Phase: playing, trick 1. Your turn to follow.")
        let waiting = Kit.view(currentTrick: [lead], leader: 1, turn: 2)
        XCTAssertEqual(line("Phase:", in: CoachContext.describe(view: waiting, hint: nil, selection: [], lastIllegal: nil)),
                       "Phase: playing, trick 1. Waiting for Partner to play.")
        let pause = Kit.view(leader: 3, turn: 3, tricks: [Kit.trick([Play(player: 1, cards: [Kit.c(.three, .clubs)]),
                                                                     Play(player: 2, cards: [Kit.c(.four, .clubs)]),
                                                                     Play(player: 3, cards: [Kit.c(.ace, .clubs)]),
                                                                     Play(player: 0, cards: [Kit.c(.five, .clubs)])])])
        let pauseText = CoachContext.describe(view: pause, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Phase:", in: pauseText), "Phase: playing, trick 2. Waiting for West to lead.")
        XCTAssertEqual(line("Trick just finished", in: pauseText),
                       "Trick just finished (#1): East led 3♣ (single club). Partner played 4♣. West played A♣. You played 5♣. West won it (5 points).")
        let bidding = Kit.view(phase: .bidding, trump: Trump(rank: .two, suit: nil), dealer: nil, turn: nil,
                               bidding: SeatView.Bidding(turn: 0, history: [], available: []))
        XCTAssertEqual(line("Phase:", in: CoachContext.describe(view: bidding, hint: nil, selection: [], lastIllegal: nil)),
                       "Phase: declaring. Your turn to declare trump or pass.")
    }

    func testTrumpLinesGiveTheFullOrder() {
        let text = CoachContext.describe(view: Kit.view(), hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Trump order", in: text),
                       "Trump order (high to low): BJ > SJ > 2♥ > 2♠ = 2♣ = 2♦ > A♥ > K♥ > Q♥ > J♥ > 10♥ > 9♥ > 8♥ > 7♥ > 6♥ > 5♥ > 4♥ > 3♥.")
        XCTAssertEqual(line("Plain suits", in: text), "Plain suits rank A K Q J 10 9 8 7 6 5 4 3 (the 2s are trumps).")
        XCTAssertEqual(line("Trump:", in: text), "Trump: suit ♥ (hearts), rank 2. Trumps are all four jokers, every 2 and every heart.")

        let noTrump = CoachContext.describe(view: Kit.view(trump: Trump(rank: .ace, suit: nil)), hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Trump order", in: noTrump), "Trump order (high to low): BJ > SJ > A♠ = A♥ = A♣ = A♦.")
        XCTAssertEqual(line("Plain suits", in: noTrump), "Plain suits rank K Q J 10 9 8 7 6 5 4 3 2 (the aces are trumps).")
        XCTAssertTrue(noTrump.contains("Trump: no trump suit this round, rank A. Only the jokers and the aces are trumps."), noTrump)
    }

    func testDealingShowsDeclarationsYouCouldMake() throws {
        let mine = [Kit.c(.five, .spades), Kit.c(.five, .spades, 1), Kit.c(.five, .hearts)]
        let deck = EngineTestSupport.deck(hands: [mine, [], [], []], firstSeat: 0, seed: 21)
        var round = Round(trumpRank: .five, dealer: nil, deck: deck)
        for _ in 0..<40 { round.dealNext() }
        let text = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(text.contains("Phase: dealing. Cards are still arriving (you have 10 of 25)."), text)
        XCTAssertTrue(text.contains("Trump suit: not declared yet."), text)
        XCTAssertTrue(text.contains("Dealer: not decided yet."), text)
        XCTAssertTrue(text.contains("You could declare: ♠ as trump by showing one 5♠"), text)
        XCTAssertTrue(text.contains("♠ as trump by showing a pair of 5♠"), text)
        XCTAssertNil(line("Trump order", in: text), "no order before anyone declares")

        let declaration = try XCTUnwrap(round.availableDeclarations(for: 0).first { $0.strength == 2 })
        try round.declare(declaration)
        let after = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(after.contains("Current declaration: You declare ♠ (pair of 5♠), so ♠ would be the trump suit."), after)
        XCTAssertNotNil(line("Trump order", in: after))
        XCTAssertTrue(after.contains("You can't declare right now"), after)
    }

    func testTeamsLevelsAndPoints() {
        let view = Kit.view(dealer: 2, defenderPoints: 35, levels: [.four, .seven], roundNumber: 3)
        let text = CoachContext.describe(view: view, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(text.contains("Round 3 of this game. Levels: your team 4, East and West 7"), text)
        XCTAssertTrue(text.contains("Dealer: Partner. Your team are the declarers; East and West are the defenders."), text)
        XCTAssertTrue(text.contains("Points: the defenders (East and West) have 35 so far; 80 takes over the deal (45 more needed)."), text)

        let defending = Kit.view(dealer: 3, defenderPoints: 90)
        let defendingText = CoachContext.describe(view: defending, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(defendingText.contains("East and West are the declarers; your team are the defenders."), defendingText)
        XCTAssertTrue(defendingText.contains("your team (the defenders) have 90 so far; 80 takes over the deal (already reached)."), defendingText)

        // Without a game, levels are unknown and left out.
        let deck = EngineTestSupport.deck(seed: 2)
        var round = Round(trumpRank: .two, dealer: 1, deck: deck)
        round.dealAll()
        XCTAssertNil(line("Round", in: CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)))
    }

    func testHandIsGroupedBySuitWithTrumpsLast() {
        let hand = [Kit.c(.king, .spades), Kit.c(.three, .spades), Kit.c(.two, .clubs), Kit.c(.ace, .hearts),
                    Card.bigJoker(), Kit.c(.seven, .diamonds), Kit.c(.seven, .diamonds, 1), Kit.c(.eight, .diamonds),
                    Kit.c(.eight, .diamonds, 1)]
        let text = CoachContext.describe(view: Kit.view(hand: hand, leader: 0, turn: 0), hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Your hand", in: text),
                       "Your hand (9 cards, low to high): Spades (2): 3♠ K♠ | Diamonds (4): 7♦ 7♦ 8♦ 8♦ | Clubs: none | Trumps (3): A♥ 2♣ BJ")
        XCTAssertEqual(line("Your combinations", in: text), "Your combinations: tractors 7♦ 7♦ 8♦ 8♦; no other pairs.")
    }

    func testCurrentTrickNamesPlaysAndWhoIsWinning() {
        let plays = [Play(player: 1, cards: Kit.pair(.king, .spades)),
                     Play(player: 2, cards: [Kit.c(.ace, .spades), Kit.c(.three, .spades)]),
                     Play(player: 3, cards: Kit.pair(.five, .spades))]
        let view = Kit.view(hand: [Kit.c(.seven, .spades), Kit.c(.nine, .spades)], currentTrick: plays, leader: 1, turn: 0)
        let text = CoachContext.describe(view: view, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Current trick", in: text),
                       "Current trick (30 points so far): East led K♠ K♠ (pair of spades). Partner played 3♠ A♠ (not the same shape as the lead, can't win). West played 5♠ 5♠. Winning now: East with K♠ K♠ (nobody has beaten the lead). Still to play: You.")

        let ruffed = [Play(player: 3, cards: [Kit.c(.ace, .clubs)]), Play(player: 0, cards: [Kit.c(.four, .hearts)]),
                      Play(player: 1, cards: [Kit.c(.seven, .diamonds)])]
        let ruffText = CoachContext.describe(view: Kit.view(currentTrick: ruffed, leader: 3, turn: 2), hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Current trick", in: ruffText),
                       "Current trick (0 points so far): West led A♣ (single club). You played 4♥ (trumped in). East played 7♦ (discard, can't win). Winning now: you with 4♥ (a trump beats any club, and it is the highest trump play). Still to play: Partner.")
    }

    func testPlayedCardsStillOutAndVoids() {
        let first = Kit.trick([Play(player: 1, cards: [Kit.c(.three, .clubs)]), Play(player: 2, cards: [Kit.c(.king, .clubs)]),
                               Play(player: 3, cards: [Kit.c(.seven, .diamonds)]), Play(player: 0, cards: [Kit.c(.ace, .clubs)])])
        let second = Kit.trick([Play(player: 0, cards: [Kit.c(.ten, .spades)]), Play(player: 1, cards: [Kit.c(.five, .hearts)]),
                                Play(player: 2, cards: [Kit.c(.jack, .spades)]), Play(player: 3, cards: [Kit.c(.two, .spades)])])
        let hand = [Kit.c(.four, .spades), Kit.c(.six, .hearts)]
        let view = Kit.view(hand: hand, leader: second.winner, turn: second.winner == 0 ? 0 : second.winner, tricks: [first, second])
        let text = CoachContext.describe(view: view, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Played so far", in: text),
                       "Played so far (8 cards, high to low): Spades (2): J♠ 10♠ | Diamonds (1): 7♦ | Clubs (3): A♣ K♣ 3♣ | Trumps (2): 2♠ 5♥")
        XCTAssertEqual(line("Cards still out", in: text),
                       "Cards still out (in the other hands or the kitty): Spades 21, Diamonds 23, Clubs 21, Trumps 33.")
        XCTAssertEqual(line("Known to be out of a suit", in: text),
                       "Known to be out of a suit: East has no spades; West has no spades and clubs.")
        XCTAssertEqual(line("Tricks won so far", in: text), "Tricks won so far: You 1 trick (10 points), West 1 trick (15 points).")
    }

    func testHintLineFollowsTheLadder() {
        let king = Kit.c(.king, .spades)
        let view = Kit.view(hand: [king, Kit.c(.three, .spades)], currentTrick: [Play(player: 1, cards: [Kit.c(.four, .spades)])], turn: 2)
        let nudge = CoachContext.describe(view: view, hint: Kit.ladder(cards: [king], steps: 1), selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Hint shown", in: nudge),
                       "Hint shown to you (step 1 of 3, what to notice): Look at who is winning this trick.")
        let principle = CoachContext.describe(view: view, hint: Kit.ladder(cards: [king], steps: 2), selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Hint shown", in: principle),
                       "Hint shown to you (step 2 of 3, the principle): When your partner is sure to win, give them points. Concept: Feed points.")
        let show = CoachContext.describe(view: view, hint: Kit.ladder(cards: [king], steps: 3), selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Hint shown", in: show),
                       "Hint shown to you (step 3 of 3, the suggested play): Partner's ace is winning, so give them your king. Concept: Feed points. Suggested cards: K♠.")
        let none = CoachContext.describe(view: view, hint: Kit.ladder(cards: [king], steps: 0), selection: [], lastIllegal: nil)
        XCTAssertNil(line("Hint shown", in: none))
    }

    func testIllegalAttemptIncludesTheRule() {
        let hand = [Kit.c(.nine, .clubs), Kit.c(.three, .spades)]
        let error = RoundError.illegalFollow(.mustFollowSuit(.plain(.spades)))
        let view = Kit.view(hand: hand, currentTrick: [Play(player: 1, cards: [Kit.c(.four, .spades)])], turn: 0)
        let text = CoachContext.describe(view: view, hint: nil, selection: [], lastIllegal: IllegalAttempt(cards: [hand[0]], error: error))
        XCTAssertEqual(line("You just tried", in: text),
                       "You just tried to play 9♣ and it was not allowed. Reason: " + error.explanation)
    }

    func testFinishedRoundShowsResultKittyAndNextStep() throws {
        var rng = SeededGenerator(seed: 31)
        var game = GameState()
        var round = game.makeRound(rng: &rng)
        try EngineTestSupport.prepare(&round, rng: &rng)
        try EngineTestSupport.playOut(&round, rng: &rng)
        let result = try XCTUnwrap(round.result)
        let before = CoachContext.describe(round: round, game: game, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(line("Phase:", in: before), "Phase: the round is over.")
        guard let resultLine = line("Result:", in: before) else { return XCTFail(before) }
        XCTAssertTrue(resultLine.contains("the defenders scored \(result.defenderPoints)"), resultLine)
        XCTAssertTrue(resultLine.contains(round.trump.sorted(result.kitty).shortText), resultLine)
        XCTAssertTrue(resultLine.contains(result.outcome.summary), resultLine)
        XCTAssertFalse(resultLine.contains("What happens next"))
        XCTAssertNil(line("Your hand", in: before))
        XCTAssertNil(line("Known to be out", in: before))
        let summary = game.record(result)
        let after = CoachContext.describe(round: round, game: game, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(after.contains("What happens next: " + summary.explanation), after)
    }

    func testKittyFlipIsExplained() throws {
        // Nobody declares: the kitty decides trump.
        let deck = EngineTestSupport.deck(firstSeat: 0, seed: 50)
        var round = Round(trumpRank: .two, dealer: nil, deck: deck)
        round.dealAll()
        round.finishDealing()
        let flipped = try XCTUnwrap(round.trumpFromKitty)
        let text = CoachContext.describe(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(text.contains("Nobody declared, so the kitty was flipped: the \(flipped.description) set the trump."), text)
    }

    func testTableTextHasNoMarkdownOrEmDash() throws {
        for seed in UInt64(0)..<UInt64(60) {
            let state = try Kit.randomState(seed: seed &+ 500)
            let text = CoachContext.describe(round: state.round, game: state.game, hint: nil, selection: [], lastIllegal: nil)
            XCTAssertFalse(text.contains("**"))
            XCTAssertFalse(text.contains(Kit.emDash))
            XCTAssertFalse(text.contains("\n\n"), "no blank lines")
        }
    }

    func testDescribeIsFast() throws {
        var states: [CoachTestKit.TableState] = []
        for seed in UInt64(0)..<UInt64(40) { states.append(try Kit.randomState(seed: seed &+ 3_000)) }
        let start = Date()
        for state in states {
            _ = CoachContext.describe(round: state.round, game: state.game, hint: nil, selection: [], lastIllegal: nil)
            _ = SuggestedQuestions.forTable(round: state.round, game: state.game, hint: nil, selection: [], lastIllegal: nil)
        }
        let average = Date().timeIntervalSince(start) / Double(states.count)
        XCTAssertLessThan(average, 0.02, "describe + chips should take well under 20 ms")
    }

    // MARK: Lessons and questions

    func testEveryLessonPageDescribesWithinLimits() {
        for lesson in Curriculum.lessons {
            for index in lesson.pages.indices {
                for answer in [nil, 0, 1] as [Int?] {
                    let text = CoachContext.describe(lesson: lesson, pageIndex: index, chosenAnswer: answer)
                    XCTAssertLessThanOrEqual(text.utf16.count, CoachContext.maxLessonCharacters, "\(lesson.id) page \(index)")
                    XCTAssertTrue(text.hasPrefix("Where: lesson \(lesson.number) of 12, \"\(lesson.title)\""), text)
                    XCTAssertTrue(text.contains("Page \(index + 1) of \(lesson.pages.count)"), text)
                    XCTAssertFalse(text.contains("**"), "\(lesson.id) page \(index)")
                    XCTAssertFalse(text.contains(Kit.emDash))
                }
            }
            // Out of range: no crash, still useful.
            let outside = CoachContext.describe(lesson: lesson, pageIndex: 99, chosenAnswer: nil)
            XCTAssertTrue(outside.contains("Page: not open"), outside)
            XCTAssertFalse(CoachContext.describe(lesson: lesson, pageIndex: -1, chosenAnswer: nil).isEmpty)
        }
    }

    func testPredictPagesHideTheAnswerUntilAnswered() throws {
        var checked = 0
        for lesson in Curriculum.lessons {
            for (index, page) in lesson.pages.enumerated() {
                guard case let .predict(question) = page else { continue }
                let correct = question.choices[question.correctChoice]
                let open = CoachContext.describe(lesson: lesson, pageIndex: index, chosenAnswer: nil)
                XCTAssertTrue(open.contains("has not answered yet"), open)
                XCTAssertFalse(open.contains("Explanation shown"), open)
                XCTAssertFalse(open.contains("right answer"), open)
                XCTAssertFalse(open.contains("Winner:"), open)
                let wrongIndex = question.correctChoice == 0 ? 1 : 0
                let wrong = CoachContext.describe(lesson: lesson, pageIndex: index, chosenAnswer: wrongIndex)
                XCTAssertTrue(wrong.contains("which is not correct"), wrong)
                XCTAssertTrue(wrong.contains("The right answer is \(question.correctChoice + 1)) \(CoachText.choiceText(correct))."), wrong)
                XCTAssertTrue(wrong.contains("Explanation shown:"), wrong)
                let right = CoachContext.describe(lesson: lesson, pageIndex: index, chosenAnswer: question.correctChoice)
                XCTAssertTrue(right.contains("which is correct"), right)
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 12)
    }

    func testWorkedTrickPageNamesTheWinner() throws {
        let lesson = Curriculum.lessons[4]
        let index = try XCTUnwrap(lesson.pages.firstIndex { if case .trick = $0 { return true } else { return false } })
        let text = CoachContext.describe(lesson: lesson, pageIndex: index, chosenAnswer: nil)
        XCTAssertTrue(text.contains("Trick shown: You led K♠ (single spade). East played 4♠. Partner played A♠. West played 9♠. Winner: Partner."), text)
        XCTAssertNotNil(line("Trump order", in: text))
    }

    func testPracticeQuestionContext() {
        var rng = SeededGenerator(seed: 4)
        for fact in Curriculum.facts {
            let question = fact.question(rng: &rng)
            let open = CoachContext.describe(question: question, chosenAnswer: nil)
            XCTAssertTrue(open.hasPrefix("Where: a practice question (a fact from lesson"), open)
            XCTAssertTrue(open.contains("Question: " + CoachText.plain(question.prompt)), open)
            XCTAssertFalse(open.contains("Explanation shown"), open)
            XCTAssertLessThanOrEqual(open.utf16.count, CoachContext.maxLessonCharacters)
            let answered = CoachContext.describe(question: question, chosenAnswer: question.correctChoice)
            XCTAssertTrue(answered.contains("which is correct"), answered)
            XCTAssertTrue(answered.contains("Explanation shown"), answered)
            // An index that is not a choice counts as not answered.
            XCTAssertTrue(CoachContext.describe(question: question, chosenAnswer: 42).contains("has not answered yet"))
            XCTAssertTrue(CoachContext.describe(question: question, chosenAnswer: -1).contains("has not answered yet"))
        }
    }

    func testQuestionVisualsAreWrittenOut() {
        let lead = Kit.pair(.nine, .clubs)
        let hand = Kit.pair(.jack, .clubs) + [Kit.c(.four, .clubs)]
        let visuals: [(QuestionVisual, String)] = [
            (.cards([Kit.c(.seven, .clubs)]), "Cards shown: 7♣."),
            (.trick([Play(player: 1, cards: [Kit.c(.ace, .clubs)]), Play(player: 2, cards: [Kit.c(.seven, .clubs)])]),
             "Trick shown: East led A♣. Partner played 7♣."),
            (.handAndLead(hand: hand, lead: lead, leader: 1), "Lead: East led 9♣ 9♣. The learner's hand: 4♣ J♣ J♣."),
            (.situation(plays: [Play(player: 2, cards: [Kit.c(.ace, .spades)])], hand: [Kit.c(.king, .spades)]),
             "Trick so far: Partner led A♠. The learner's hand: K♠."),
        ]
        for (visual, expected) in visuals {
            let question = Question(id: "q", itemID: SkillID.legalFollow.itemID, prompt: "Which play is legal?", trump: CoachTestKit.heartsTwo,
                                    visual: visual, choices: [Choice("J♣ J♣", cards: Kit.pair(.jack, .clubs)), Choice("Pass")],
                                    correctChoice: 0, explanation: "You must play a **pair**.", difficulty: 1)
            let text = CoachContext.describe(question: question, chosenAnswer: 1)
            XCTAssertTrue(text.contains(expected), "\(expected)\n\(text)")
            XCTAssertTrue(text.contains("Where: a practice question (skill: which follow is legal)."), text)
            XCTAssertTrue(text.contains("Choices: 1) J♣ J♣; 2) Pass."), text)
            XCTAssertTrue(text.contains("The right answer is 1) J♣ J♣."), text)
            XCTAssertTrue(text.contains("Explanation shown: You must play a pair."), text)
        }
    }
}
