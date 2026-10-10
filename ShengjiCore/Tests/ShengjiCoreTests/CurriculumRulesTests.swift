import XCTest
@testable import ShengjiCore

/// Checks that every rule the lessons teach agrees with the engine (Rules, Scoring, Round, GameState).
/// These call engine code, so they only pass once the engine is implemented.
/// Integrity checks that need no engine live in `CurriculumTests`.
final class CurriculumRulesTests: XCTestCase {
    // MARK: Tricks

    func testTrickPageWinnersMatchRules() {
        for t in CurriculumScan.trickPages {
            let index = Rules.winningIndex(t.plays, trump: t.trump)
            XCTAssertTrue(t.plays.indices.contains(index), t.title)
            XCTAssertEqual(t.plays[index].player, t.winner, "\(t.lesson.id) \(t.title)")
        }
    }

    func testTrickPagesAreLegalPlays() {
        for t in CurriculumScan.trickPages {
            assertLegalTrick(t.plays, trump: t.trump, allowThrow: t.lesson.number == 11, context: "\(t.lesson.id) \(t.title)")
        }
    }

    func testPredictTricksAndSituationsAreLegalPlays() {
        for item in CurriculumScan.predicts {
            let q = item.question
            guard let trump = q.trump else { continue }
            switch q.visual {
            case let .trick(plays), let .situation(plays, _):
                assertLegalTrick(plays, trump: trump, allowThrow: false, context: q.id)
            default:
                break
            }
        }
    }

    func testWhoWinsPredictionsMatchRules() {
        let seatNames = Set(Seats.all.map(Seats.name))
        var checked = 0
        for item in CurriculumScan.predicts {
            let q = item.question
            guard case let .trick(plays) = q.visual, let trump = q.trump,
                  q.choices.allSatisfy({ seatNames.contains($0.label) }) else { continue }
            let index = Rules.winningIndex(plays, trump: trump)
            XCTAssertTrue(plays.indices.contains(index), q.id)
            XCTAssertEqual(CurriculumScan.correctLabel(q), plays.indices.contains(index) ? Seats.name(plays[index].player) : nil, q.id)
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 5)
    }

    func testWhichCardWinsPredictionsMatchRules() {
        var checked = 0
        for item in CurriculumScan.predicts {
            let q = item.question
            guard case let .trick(plays) = q.visual, let trump = q.trump, plays.count < 4,
                  q.choices.allSatisfy({ !$0.cards.isEmpty }), let lead = plays.first?.cards else { continue }
            for (i, choice) in q.choices.enumerated() {
                // The prompt says you are void in the led suit, so any single card is a legal play.
                XCTAssertNil(Rules.validateFollow(choice.cards, hand: choice.cards, lead: lead, trump: trump), "\(q.id): \(choice.label)")
                let trick = plays + [Play(player: Seats.human, cards: choice.cards)]
                let wins = Rules.winningIndex(trick, trump: trump) == plays.count
                XCTAssertEqual(wins, i == q.correctChoice, "\(q.id): \(choice.label)")
            }
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 1)
    }

    func testLegalFollowPredictionsMatchRules() {
        var checked = 0
        for item in CurriculumScan.predicts {
            let q = item.question
            guard case let .handAndLead(hand, lead, _) = q.visual, let trump = q.trump else { continue }
            for (i, choice) in q.choices.enumerated() {
                let legal = Rules.validateFollow(choice.cards, hand: hand, lead: lead, trump: trump) == nil
                XCTAssertEqual(legal, i == q.correctChoice, "\(q.id): \(choice.label)")
            }
            checked += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 2)
    }

    func testSituationChoicesAreLegalAndPartnerIsWinning() {
        guard let q = CurriculumScan.question("lesson.12.predict.1"), let trump = q.trump,
              case let .situation(plays, hand) = q.visual, let lead = plays.first?.cards else {
            return XCTFail("lesson.12.predict.1 should be a situation")
        }
        for choice in q.choices {
            XCTAssertNil(Rules.validateFollow(choice.cards, hand: hand, lead: lead, trump: trump), choice.label)
            let trick = plays + [Play(player: Seats.human, cards: choice.cards)]
            // Partner's ace wins whatever you play, which is why feeding points is right.
            let index = Rules.winningIndex(trick, trump: trump)
            XCTAssertEqual(trick.indices.contains(index) ? trick[index].player : nil, Seats.partner(of: Seats.human))
        }
        XCTAssertGreaterThan(q.choices[q.correctChoice].cards.points, 0)
    }

    // MARK: Scoring

    func testLevelTableTaughtInLesson10MatchesScoring() {
        // The table exactly as lesson 10 states it.
        func taught(_ p: Int) -> (hold: Bool, levels: Int) {
            switch p {
            case 0: return (true, 3)
            case 5...35: return (true, 2)
            case 40...75: return (true, 1)
            case 80...115: return (false, 0)
            case 120...155: return (false, 1)
            case 160...195: return (false, 2)
            default: return (false, 3 + (p - 200) / 40)
            }
        }
        for p in stride(from: 0, through: 400, by: 5) {
            let o = Scoring.outcome(defenderPoints: p)
            XCTAssertEqual(o.declarersHold, taught(p).hold, "\(p) points")
            XCTAssertEqual(o.levels, taught(p).levels, "\(p) points")
        }
    }

    func testScoringPredictionsMatchScoring() {
        let o45 = Scoring.outcome(defenderPoints: 45)
        XCTAssertTrue(o45.declarersHold)
        XCTAssertEqual(o45.levels, 1)
        XCTAssertEqual(correctLabel("lesson.10.predict.1"), "You keep the deal and climb 1 level")

        let o130 = Scoring.outcome(defenderPoints: 130)
        XCTAssertFalse(o130.declarersHold)
        XCTAssertEqual(o130.levels, 1)
        XCTAssertEqual(correctLabel("lesson.10.predict.2"), "They take over and climb 1 level")

        let o90 = Scoring.outcome(defenderPoints: 90)
        XCTAssertFalse(o90.declarersHold)
        XCTAssertEqual(o90.levels, 0)
        XCTAssertEqual(correctLabel("lesson.1.predict.2"), "The defenders take over the deal")

        let o0 = Scoring.outcome(defenderPoints: 0)
        XCTAssertTrue(o0.declarersHold)
        XCTAssertEqual(o0.levels, 3)
        XCTAssertEqual(factAnswer("fact.cleanSweep"), "The declarers climb 3 levels")
    }

    func testKittyMultipliersMatchScoring() {
        let t = Trump(rank: .two, suit: .hearts)
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: [c(.ace, .spades)], trump: t), 2)
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: [c(.ace, .spades), c(.ace, .spades, 1)], trump: t), 4)
        let tractor = [c(.five, .clubs), c(.five, .clubs, 1), c(.six, .clubs), c(.six, .clubs, 1)]
        XCTAssertEqual(Scoring.kittyMultiplier(lastLead: tractor, trump: t), 8)
        // lesson.10.predict.3: 15 kitty points after a two-pair tractor lead.
        XCTAssertEqual(String(15 * Scoring.kittyMultiplier(lastLead: tractor, trump: t)), correctLabel("lesson.10.predict.3"))
    }

    func testLastTrickExampleInLesson10() {
        guard let t = CurriculumScan.trickPages.first(where: { $0.lesson.number == 10 }),
              let kitty = CurriculumScan.cardsPage(lesson: 10, title: "The kitty bonus")?.cards else {
            return XCTFail("lesson 10 trick or kitty missing")
        }
        let multiplier = Scoring.kittyMultiplier(lastLead: t.plays[0].cards, trump: t.trump)
        XCTAssertEqual(multiplier, 4)
        XCTAssertEqual(t.plays.flatMap(\.cards).points, 10)
        XCTAssertEqual(kitty.points * multiplier, 100)
        // The body states the defenders' total: the trick's points plus the multiplied kitty.
        let total = t.plays.flatMap(\.cards).points + kitty.points * multiplier
        XCTAssertTrue(t.body.contains("**\(total)**"), t.body)
        // West is a defender when your team declares.
        XCTAssertNotEqual(Seats.team(of: t.winner), Seats.team(of: Seats.human))
    }

    func testNextDealerAndGameWinMatchGameState() {
        let trump = Trump(rank: .two, suit: .hearts)
        func result(dealer: Int, defenderPoints: Int) -> RoundResult {
            RoundResult(dealer: dealer, declarerTeam: Seats.team(of: dealer), trump: trump,
                        trickPoints: defenderPoints, kittyPoints: 0, kittyMultiplier: 0,
                        defenderPoints: defenderPoints, outcome: Scoring.outcome(defenderPoints: defenderPoints),
                        kitty: [], lastTrickWinner: dealer)
        }
        var hold = GameState()
        XCTAssertEqual(hold.record(result(dealer: 0, defenderPoints: 45)).nextDealer, Seats.partner(of: 0))
        XCTAssertEqual(factAnswer("fact.nextDealer"), "The dealer's partner")

        var takeover = GameState()
        XCTAssertEqual(takeover.record(result(dealer: 0, defenderPoints: 90)).nextDealer, Seats.next(after: 0))

        // "Win a round as declarers while at level A to win the game."
        var finalRound = GameState(settings: GameSettings(startRank: .ace, targetRank: .ace))
        XCTAssertEqual(finalRound.record(result(dealer: 0, defenderPoints: 45)).gameWinner, 0)
        XCTAssertEqual(factAnswer("fact.gameGoal"), "Win a round as declarers while at level A")
    }

    // MARK: Throws

    func testFailedThrowExamplesMatchRules() {
        let hearts = Trump(rank: .two, suit: .hearts)

        // lesson.11.predict.1: A♣ Q♣ against West's K♣ → only the Q♣ is played.
        let clubs = [c(.ace, .clubs), c(.queen, .clubs)]
        let p1 = Rules.checkThrow(clubs, leader: 0, hands: [clubs, [c(.three, .clubs)], [c(.four, .clubs)], [c(.king, .clubs)]], trump: hearts)
        if case let .fails(forced, blocker) = p1 {
            XCTAssertEqual(forced.cards, [c(.queen, .clubs)])
            XCTAssertEqual(blocker, 3)
        } else {
            XCTFail("A♣ Q♣ should fail against K♣")
        }
        XCTAssertEqual(correctLabel("lesson.11.predict.1"), "It fails: you play only the Q♣")

        // lesson.11.predict.2: Q♠ Q♠ A♠ against East's K♠ K♠ → only the queens are played.
        let spades = [c(.queen, .spades), c(.queen, .spades, 1), c(.ace, .spades)]
        let p2 = Rules.checkThrow(spades, leader: 0,
                                  hands: [spades, [c(.king, .spades), c(.king, .spades, 1)], [c(.three, .spades)], [c(.four, .spades)]],
                                  trump: hearts)
        if case let .fails(forced, blocker) = p2 {
            XCTAssertEqual(Set(forced.cards), Set([c(.queen, .spades), c(.queen, .spades, 1)]))
            XCTAssertEqual(blocker, 1)
            if let q = CurriculumScan.question("lesson.11.predict.2") {
                XCTAssertEqual(Set(q.choices[q.correctChoice].cards), Set(forced.cards))
            }
        } else {
            XCTFail("Q♠ Q♠ A♠ should fail against K♠ K♠")
        }

        // "Which part is forced?": K♦ K♦ J♦ against A♦ A♦ and Q♦ → the smaller shape, the single J♦.
        let diamonds = [c(.king, .diamonds), c(.king, .diamonds, 1), c(.jack, .diamonds)]
        let p3 = Rules.checkThrow(diamonds, leader: 0,
                                  hands: [diamonds, [c(.ace, .diamonds), c(.ace, .diamonds, 1)], [c(.three, .diamonds)], [c(.queen, .diamonds)]],
                                  trump: Trump(rank: .two, suit: .spades))
        if case let .fails(forced, _) = p3 {
            XCTAssertEqual(forced.cards, [c(.jack, .diamonds)])
        } else {
            XCTFail("K♦ K♦ J♦ should fail")
        }
    }

    func testSafeThrowExamplesMatchRules() {
        let hearts = Trump(rank: .two, suit: .hearts)
        // A♠ A♠ K♠ can't be beaten by any card left in the deck.
        let safe = [c(.ace, .spades), c(.ace, .spades, 1), c(.king, .spades)]
        var pool = Deck.double()
        pool.remove(cards: safe)
        XCTAssertTrue(Rules.isThrow(safe, trump: hearts))
        XCTAssertEqual(Rules.checkThrow(safe, against: pool, trump: hearts), .ok)

        // "A throw that stands": A♣ K♣ once the other A♣ has been played.
        guard let t = CurriculumScan.trickPages.first(where: { $0.lesson.number == 11 }) else {
            return XCTFail("lesson 11 trick missing")
        }
        var unseen = Deck.double()
        unseen.remove(cards: t.plays[0].cards + [c(.ace, .clubs, 1)])
        XCTAssertTrue(Rules.isThrow(t.plays[0].cards, trump: t.trump))
        XCTAssertEqual(Rules.checkThrow(t.plays[0].cards, against: unseen, trump: t.trump), .ok)
        XCTAssertEqual(t.plays.flatMap(\.cards).points, 25)
    }

    // MARK: Declaring and the kitty

    func testKittyFlipExamplesMatchRound() {
        // lesson.9.predict.3: the kitty shows 6♣, Q♦, 2♠: the first rank card makes ♠ trump.
        let flip = [c(.six, .clubs), c(.queen, .diamonds), c(.two, .spades), c(.nine, .hearts),
                    c(.four, .diamonds), c(.seven, .clubs), c(.jack, .spades), c(.three, .hearts)]
        var round = Round(trumpRank: .two, dealer: nil, deck: deck(kitty: flip))
        round.dealAll()
        round.finishDealing()
        XCTAssertEqual(round.trump.suit, .spades)
        XCTAssertEqual(round.trumpFromKitty, c(.two, .spades))
        XCTAssertEqual(round.dealer, Seats.human, "first round, nobody declared: South deals")
        XCTAssertEqual(correctLabel("lesson.9.predict.3"), "♠ (spades)")

        // "When nobody declares": no rank card, so the highest card (A♣) sets the suit.
        guard let shown = CurriculumScan.cardsPage(lesson: 9, title: "When nobody declares")?.cards else {
            return XCTFail("kitty example missing")
        }
        var noRank = Round(trumpRank: .two, dealer: nil, deck: deck(kitty: shown))
        noRank.dealAll()
        noRank.finishDealing()
        XCTAssertEqual(noRank.trump.suit, .clubs)
        XCTAssertEqual(noRank.trumpFromKitty, c(.ace, .clubs))
    }

    func testDeclaringStrengthMatchesRound() throws {
        // You (seat 0) get 2♦ 2♦, East (seat 1) gets 2♣ 2♣; the jokers are all in the kitty.
        var slots = [Card?](repeating: nil, count: 108)
        slots[0] = c(.two, .diamonds)
        slots[4] = c(.two, .diamonds, 1)
        slots[1] = c(.two, .clubs)
        slots[5] = c(.two, .clubs, 1)
        let jokers = [smallJoker(0), smallJoker(1), bigJoker(0), bigJoker(1)]
        for (i, j) in jokers.enumerated() { slots[100 + i] = j }
        var rest = Deck.double()
        rest.remove(cards: slots.compactMap { $0 })
        for i in slots.indices where slots[i] == nil { slots[i] = rest.removeFirst() }
        var round = Round(trumpRank: .two, dealer: nil, deck: slots.compactMap { $0 })
        round.dealAll()

        // East declares ♣ with one 2♣ (strength 1).
        let eastSingle = try XCTUnwrap(round.availableDeclarations(for: 1).first { $0.suit == .clubs && $0.strength == 1 })
        try round.declare(eastSingle)

        // lesson.9.predict.2: your pair of 2♦ overrides a single.
        let yourPair = try XCTUnwrap(round.availableDeclarations(for: 0).first { $0.suit == .diamonds && $0.strength == 2 })
        try round.declare(yourPair)
        XCTAssertEqual(correctLabel("lesson.9.predict.2"), "Yes: a pair beats a single")

        // East's own pair of 2♣ is only equal, so it can't take it back.
        XCTAssertFalse(round.availableDeclarations(for: 1).contains { $0.strength <= 2 })

        // First round: the winning declarer deals.
        round.finishDealing()
        XCTAssertEqual(round.dealer, Seats.human)
        XCTAssertEqual(round.trump.suit, .diamonds)
    }

    func testReinforcingMatchesRound() throws {
        var slots = [Card?](repeating: nil, count: 108)
        slots[0] = c(.two, .hearts)
        slots[4] = c(.two, .hearts, 1)
        slots[8] = c(.two, .spades)
        slots[12] = c(.two, .spades, 1)
        let jokers = [smallJoker(0), smallJoker(1), bigJoker(0), bigJoker(1)]
        for (i, j) in jokers.enumerated() { slots[100 + i] = j }
        var rest = Deck.double()
        rest.remove(cards: slots.compactMap { $0 })
        for i in slots.indices where slots[i] == nil { slots[i] = rest.removeFirst() }
        var round = Round(trumpRank: .two, dealer: nil, deck: slots.compactMap { $0 })
        round.dealAll()

        let single = try XCTUnwrap(round.availableDeclarations(for: 0).first { $0.suit == .hearts && $0.strength == 1 })
        try round.declare(single)
        // fact.reinforceOnly: holding the declaration, you may only strengthen it in the same suit,
        // even though your 2♠ 2♠ would otherwise be a stronger declaration.
        let options = round.availableDeclarations(for: 0)
        XCTAssertTrue(options.contains { $0.suit == .hearts && $0.strength == 2 })
        XCTAssertFalse(options.contains { $0.suit != .hearts })
        XCTAssertTrue(factAnswer("fact.reinforceOnly")?.hasPrefix("Reinforce") == true)
    }

    // MARK: The engine and the lessons' referee agree

    /// The lessons are checked against `ReferenceRules` (CurriculumTests); here the engine is checked
    /// against the same referee on random deals, so the in-game coach can't contradict what the
    /// lessons teach about following and winning tricks with singles, pairs and tractors.
    func testEngineAgreesWithTheLessonsRefereeOnRandomTricks() {
        var rng = SeededGenerator(seed: 2024)
        var tricks = 0
        for _ in 0..<1500 {
            let trump = Trump(rank: Rank(rawValue: Int.random(in: 2...14, using: &rng)) ?? .two,
                              suit: Bool.random(using: &rng) ? nil : Suit(rawValue: Int.random(in: 0...3, using: &rng)))
            let deck = Deck.shuffled(using: &rng)
            let hands = (0..<4).map { Array(deck[($0 * 25)..<($0 * 25 + 25)]) }
            let leader = Int.random(in: 0..<4, using: &rng)
            guard let lead = randomLead(from: hands[leader], trump: trump, rng: &rng) else { continue }
            var plays = [Play(player: leader, cards: lead)]
            for k in 1..<4 {
                let seat = (leader + k) % 4
                var chosen: [Card]?
                for candidate in candidateFollows(hand: hands[seat], lead: lead, trump: trump, rng: &rng) {
                    let engine = Rules.validateFollow(candidate, hand: hands[seat], lead: lead, trump: trump) == nil
                    let referee = ReferenceRules.isLegalFollow(candidate, hand: hands[seat], lead: lead, trump: trump)
                    XCTAssertEqual(engine, referee, "follow \(candidate.shortText) to \(lead.shortText) from \(hands[seat].shortText), \(trump)")
                    if engine, chosen == nil { chosen = candidate }
                }
                guard let play = chosen else { break }
                plays.append(Play(player: seat, cards: play))
                XCTAssertEqual(Rules.winningIndex(plays, trump: trump), ReferenceRules.winningIndex(plays, trump: trump),
                               "\(plays.map { "\(Seats.name($0.player)): \($0.cards.shortText)" }), \(trump)")
            }
            tricks += 1
        }
        XCTAssertGreaterThan(tricks, 1000)
    }

    /// A single, a pair or a two-pair tractor from `hand`, whichever the dice pick and the hand allows.
    private func randomLead(from hand: [Card], trump: Trump, rng: inout SeededGenerator) -> [Card]? {
        let kind = Int.random(in: 0..<3, using: &rng)
        if kind == 2, let tractor = Combos.tractors(in: hand, length: 2, trump: trump).randomElement(using: &rng) {
            return tractor
        }
        if kind >= 1, let pair = Combos.pairs(in: hand, trump: trump).randomElement(using: &rng) { return pair }
        return hand.randomElement(using: &rng).map { [$0] }
    }

    /// A spread of plays of the lead's size: structured ones from the led group (tractors and pairs
    /// first), loose ones from the group, and random ones from the whole hand.
    private func candidateFollows(hand: [Card], lead: [Card], trump: Trump, rng: inout SeededGenerator) -> [[Card]] {
        guard let first = lead.first else { return [] }
        let group = trump.group(first)
        let inGroup = hand.filter { trump.group($0) == group }.shuffled(using: &rng)
        let others = hand.filter { trump.group($0) != group }.shuffled(using: &rng)
        func fill(_ base: [Card]) -> [Card] {
            var play = Array(base.prefix(lead.count))
            for card in inGroup + others where play.count < lead.count && !play.contains(card) { play.append(card) }
            return play
        }
        var bases: [[Card]] = Combos.tractors(in: inGroup, length: 2, trump: trump).shuffled(using: &rng).prefix(2).map { $0 }
        let pairs = Combos.pairs(in: inGroup, trump: trump).shuffled(using: &rng)
        bases += pairs.prefix(3).map { $0 }
        if pairs.count >= 2 { bases.append(pairs[0] + pairs[1]) }
        bases.append([])
        var candidates = bases.map(fill)
        for _ in 0..<4 { candidates.append(Array(hand.shuffled(using: &rng).prefix(lead.count))) }
        return candidates
    }

    // MARK: Helpers

    /// Lead legal for a hand of exactly the led cards; each follow legal for a hand of exactly the
    /// played cards (the most a learner can infer from the table).
    private func assertLegalTrick(_ plays: [Play], trump: Trump, allowThrow: Bool, context: String) {
        guard let lead = plays.first?.cards else { return XCTFail("\(context): empty trick") }
        XCTAssertNil(Rules.validateLead(lead, hand: lead, trump: trump), context)
        if !allowThrow {
            XCTAssertFalse(Rules.isThrow(lead, trump: trump), "\(context): lead should be one combination")
        }
        for p in plays.dropFirst() {
            XCTAssertNil(Rules.validateFollow(p.cards, hand: p.cards, lead: lead, trump: trump), "\(context): \(Seats.name(p.player))")
        }
    }

    /// The full deck with `kitty` as its last 8 cards (nobody declares in these tests).
    private func deck(kitty: [Card]) -> [Card] {
        var rest = Deck.double()
        rest.remove(cards: kitty)
        return rest + kitty
    }

    private func smallJoker(_ copy: Int) -> Card { Card.smallJoker(copy: copy) }
    private func bigJoker(_ copy: Int) -> Card { Card.bigJoker(copy: copy) }

    private func correctLabel(_ questionID: String) -> String? {
        CurriculumScan.question(questionID).flatMap(CurriculumScan.correctLabel)
    }

    private func factAnswer(_ factID: String) -> String? {
        guard let fact = Curriculum.fact(id: factID), fact.choices.indices.contains(fact.correctChoice) else { return nil }
        return fact.choices[fact.correctChoice]
    }
}
