import Foundation
import XCTest
@testable import ShengjiCore

/// Test-only helpers for the engine tests: deck building and a simple legal-move generator.
enum EngineTestSupport {
    /// Builds a 108-card deck in dealing order. `hands[seat]` lists cards that seat must receive
    /// (dealt first, in order); `kitty` lists kitty cards. Everything else is filled in from the
    /// remaining cards in a seeded random order.
    static func deck(hands spec: [[Card]] = [[], [], [], []], kitty kittySpec: [Card] = [],
                     firstSeat: Int = 0, seed: UInt64 = 1) -> [Card] {
        var hands = spec + Array(repeating: [Card](), count: max(0, 4 - spec.count))
        let used = Set(hands.flatMap { $0 }.map(\.id) + kittySpec.map(\.id))
        precondition(used.count == hands.flatMap { $0 }.count + kittySpec.count, "duplicate cards in spec")
        var rng = SeededGenerator(seed: seed)
        var rest = Deck.double().filter { !used.contains($0.id) }.shuffled(using: &rng)
        for seat in 0..<4 {
            while hands[seat].count < Round.handSize { hands[seat].append(rest.removeLast()) }
        }
        var kitty = kittySpec
        while kitty.count < Round.kittySize { kitty.append(rest.removeLast()) }
        precondition(rest.isEmpty && hands.allSatisfy { $0.count == Round.handSize })
        var deck: [Card] = []
        for index in 0..<100 {
            let seat = (firstSeat + index) % 4
            deck.append(hands[seat][index / 4])
        }
        return deck + kitty
    }

    /// Cards of `hand` split by suit group, in a fixed order (trumps first), each sorted by id.
    /// (Sorting by id keeps the generator fast and deterministic.)
    static func groups(_ hand: [Card], trump: Trump) -> [[Card]] {
        let order: [SuitGroup] = [.trump] + Suit.allCases.map { SuitGroup.plain($0) }
        let sortedHand = hand.sorted { $0.id < $1.id }
        return order.map { group in sortedHand.filter { trump.group($0) == group } }.filter { !$0.isEmpty }
    }

    /// A random lead: mostly singles and pairs, sometimes a tractor, sometimes a random throw attempt.
    static func randomLead<G: RandomNumberGenerator>(hand: [Card], trump: Trump, rng: inout G) -> [Card] {
        let byGroup = groups(hand, trump: trump)
        guard let groupCards = byGroup.randomElement(using: &rng), let pick = groupCards.randomElement(using: &rng) else {
            return []
        }
        let roll = Int.random(in: 0..<10, using: &rng)
        if roll < 3 {
            // Any tractor in the hand, of a random length.
            var tractors: [[Card]] = []
            for cards in byGroup {
                let longest = Combos.longestRun(in: cards, trump: trump)
                if longest >= 2 {
                    let length = Int.random(in: 2...longest, using: &rng)
                    tractors += Combos.tractors(in: cards, length: length, trump: trump)
                }
            }
            if let tractor = tractors.randomElement(using: &rng) { return tractor }
        }
        if roll < 5, let pair = Combos.pairs(in: groupCards, trump: trump).randomElement(using: &rng) {
            return pair
        }
        if roll == 5, groupCards.count >= 2 {
            let size = Int.random(in: 2...min(6, groupCards.count), using: &rng)
            return Array(groupCards.shuffled(using: &rng).prefix(size))
        }
        return [pick]
    }

    /// A legal follow built directly from the rules: the follow requirement first, then filler.
    static func legalFollow<G: RandomNumberGenerator>(hand: [Card], lead: [Card], trump: Trump,
                                                      rng: inout G) -> [Card] {
        guard let first = lead.first else { return [] }
        let n = lead.count
        let ledGroup = trump.group(first)
        let sortedHand = hand.sorted { $0.id < $1.id }
        let held = sortedHand.filter { trump.group($0) == ledGroup }
        let others = sortedHand.filter { trump.group($0) != ledGroup }
        if held.count <= n {
            return held + Array(others.shuffled(using: &rng).prefix(n - held.count))
        }
        let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
        guard let tractors = disjointTractors(in: held, lengths: requirement.tractorLengths, trump: trump) else {
            return []
        }
        var pool = held
        var play: [Card] = []
        for tractor in tractors {
            play += tractor
            pool.remove(cards: tractor)
        }
        var pairCount = requirement.tractorLengths.reduce(0, +)
        var pairs = Combos.pairs(in: pool, trump: trump).shuffled(using: &rng)
        while pairCount < requirement.totalPairs, let pair = pairs.popLast() {
            play += pair
            pool.remove(cards: pair)
            pairCount += 1
        }
        play += pool.shuffled(using: &rng).prefix(n - play.count)
        return play
    }

    /// Independent (non-optimised) search for disjoint tractors of the given lengths.
    static func disjointTractors(in cards: [Card], lengths: [Int], trump: Trump) -> [[Card]]? {
        guard let length = lengths.first else { return [] }
        for tractor in Combos.tractors(in: cards, length: length, trump: trump) {
            var rest = cards
            rest.remove(cards: tractor)
            if let more = disjointTractors(in: rest, lengths: Array(lengths.dropFirst()), trump: trump) {
                return [tractor] + more
            }
        }
        return nil
    }

    /// Deals every card, letting random players make random legal declarations along the way.
    /// Returns the number of declarations made.
    @discardableResult
    static func dealWithDeclarations<G: RandomNumberGenerator>(_ round: inout Round, rng: inout G,
                                                                chance: Int = 8) throws -> Int {
        var made = 0
        while round.dealNext() != nil {
            if Int.random(in: 0..<chance, using: &rng) == 0 {
                let seat = Int.random(in: 0..<4, using: &rng)
                if let option = round.availableDeclarations(for: seat).randomElement(using: &rng) {
                    try round.declare(option)
                    made += 1
                }
            }
        }
        return made
    }

    /// Plays one legal move for whoever's turn it is. Returns the cards attempted and the outcome.
    static func playOneMove<G: RandomNumberGenerator>(_ round: inout Round, rng: inout G) throws
        -> (player: Int, cards: [Card], outcome: PlayOutcome)? {
        guard let seat = round.turn else { return nil }
        let hand = round.hands[seat]
        let cards = round.currentTrick.isEmpty
            ? randomLead(hand: hand, trump: round.trump, rng: &rng)
            : legalFollow(hand: hand, lead: round.currentLead, trump: round.trump, rng: &rng)
        let outcome = try round.play(cards, by: seat)
        return (seat, cards, outcome)
    }

    /// Takes a fresh round through dealing, declaring and burying with random choices.
    static func prepare<G: RandomNumberGenerator>(_ round: inout Round, rng: inout G) throws {
        try dealWithDeclarations(&round, rng: &rng)
        round.finishDealing()
        guard let dealer = round.dealer else { return }
        let buried = Array(round.hands[dealer].shuffled(using: &rng).prefix(Round.kittySize))
        try round.bury(buried)
    }

    /// Plays the round to the end with random legal moves.
    static func playOut<G: RandomNumberGenerator>(_ round: inout Round, rng: inout G) throws {
        var guardCount = 0
        while round.phase == .playing && guardCount < 500 {
            _ = try playOneMove(&round, rng: &rng)
            guardCount += 1
        }
    }

    static func encode(_ round: Round) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(round)
    }

    // MARK: Independent reference implementations
    //
    // Deliberately naive versions of the rules, written straight from DESIGN.md with nothing but
    // `Combos` (foundation code), so the engine can be checked against something it doesn't share code with.

    /// Comparison key of `play` against `lead`, or nil if it doesn't match the lead's structure.
    /// Tries every way to give each pair/tractor of the lead its own component of the same shape in
    /// the play; the key is the top of the play's component given to the lead's largest component
    /// (the best over all ways). An all-singles lead just compares the highest card.
    static func referenceKey(_ play: [Card], lead: [Card], trump: Trump) -> Int? {
        guard play.count == lead.count, !play.isEmpty, Combos.group(of: play, trump: trump) != nil else { return nil }
        let components = Combos.decompose(lead, trump: trump)
        guard let largest = components.first else { return nil }
        if largest.shape == .single { return play.map { trump.strength($0) }.max() }
        let structured = components.filter { $0.shape != .single }
        var best: Int?
        func assign(_ index: Int, _ remaining: [Card], _ key: Int) {
            if index == structured.count {
                best = max(best ?? key, key)
                return
            }
            for component in Combos.components(of: structured[index].shape, in: remaining, trump: trump) {
                var left = remaining
                left.remove(cards: component.cards)
                assign(index + 1, left, index == 0 ? component.topStrength : key)
            }
        }
        assign(0, play, -1)
        return best
    }

    /// Winner of a (possibly partial) trick by the DESIGN.md rule, using `referenceKey`.
    static func referenceWinner(_ plays: [Play], trump: Trump) -> Int {
        guard let lead = plays.first?.cards, let first = lead.first,
              var bestKey = referenceKey(lead, lead: lead, trump: trump) else { return 0 }
        let ledGroup = trump.group(first)
        var best = 0
        var bestIsTrump = ledGroup.isTrump
        for index in plays.indices.dropFirst() {
            let cards = plays[index].cards
            guard let group = Combos.group(of: cards, trump: trump), group == ledGroup || group.isTrump,
                  let key = referenceKey(cards, lead: lead, trump: trump) else { continue }
            if group.isTrump && !bestIsTrump {
                (best, bestIsTrump, bestKey) = (index, true, key)
            } else if group.isTrump == bestIsTrump && key > bestKey {
                (best, bestKey) = (index, key)
            }
        }
        return best
    }

    /// The DESIGN.md follow walk, trying every choice (which tractor to take, which pairs to give up)
    /// and keeping the one that leaves the most tractors for the rest of the lead.
    static func referenceRequirement(lead: [Card], held: [Card], trump: Trump) -> FollowRequirement {
        guard lead.count >= 2 else { return FollowRequirement(tractorLengths: [], totalPairs: 0) }
        func better(_ a: [Int], _ b: [Int]) -> Bool {
            if a.count != b.count { return a.count > b.count }
            return a.reduce(0, +) > b.reduce(0, +)
        }
        func walk(_ components: ArraySlice<Component>, _ remaining: [Card]) -> (tractors: [Int], pairs: Int) {
            guard let component = components.first else { return ([], 0) }
            let rest = components.dropFirst()
            switch component.shape {
            case .single:
                return walk(rest, remaining)
            case .pair:
                guard let pair = Combos.pairs(in: remaining, trump: trump).first else { return walk(rest, remaining) }
                var left = remaining
                left.remove(cards: pair)
                let sub = walk(rest, left)
                return (sub.tractors, sub.pairs + 1)
            case let .tractor(length):
                // Either a tractor of that length is owed, or (without a long enough run) that many
                // pairs, or as many as are held. Every way of taking them out is tried.
                let hasRun = Combos.longestRun(in: remaining, trump: trump) >= length
                var options: [[Card]] = []
                let taken: Int
                if hasRun {
                    options = Combos.tractors(in: remaining, length: length, trump: trump)
                    taken = length
                } else {
                    let pairs = Combos.pairs(in: remaining, trump: trump)
                    taken = min(pairs.count, length)
                    func subsets(_ start: Int, _ chosen: [Card], _ size: Int) {
                        if size == 0 { options.append(chosen); return }
                        guard start < pairs.count else { return }
                        for index in start..<pairs.count { subsets(index + 1, chosen + pairs[index], size - 1) }
                    }
                    subsets(0, [], taken)
                }
                var best: (tractors: [Int], pairs: Int)?
                for option in options {
                    var left = remaining
                    left.remove(cards: option)
                    let sub = walk(rest, left)
                    if best == nil || better(sub.tractors, best?.tractors ?? []) { best = sub }
                }
                let chosen = best ?? ([], 0)
                return ((hasRun ? [length] : []) + chosen.tractors, chosen.pairs + taken)
            }
        }
        let result = walk(Combos.decompose(lead, trump: trump)[...], held)
        return FollowRequirement(tractorLengths: result.tractors, totalPairs: result.pairs)
    }

    /// True if every pair and tractor of `lead` can be given its own component of the same shape
    /// taken from `cards` (so a follower holding `cards` could copy the lead's structure exactly).
    static func referenceCanMatch(_ lead: [Card], within cards: [Card], trump: Trump) -> Bool {
        let structured = Combos.decompose(lead, trump: trump).filter { $0.shape != .single }
        func assign(_ index: Int, _ remaining: [Card]) -> Bool {
            if index == structured.count { return true }
            for component in Combos.components(of: structured[index].shape, in: remaining, trump: trump) {
                var left = remaining
                left.remove(cards: component.cards)
                if assign(index + 1, left) { return true }
            }
            return false
        }
        return assign(0, cards)
    }

    /// The throw rule of DESIGN.md: nil if the lead is not a throw or nobody can beat any part of it,
    /// else the shape and strength of the part that must be played and the first seat that can beat it.
    static func referenceThrowFailure(_ lead: [Card], leader: Int, hands: [[Card]], trump: Trump)
        -> (shape: ComboShape, topStrength: Int, blocker: Int)? {
        let components = Combos.decompose(lead, trump: trump)
        guard components.count > 1 else { return nil }
        func beats(_ component: Component, _ hand: [Card]) -> Bool {
            let sameGroup = Combos.cards(hand, in: component.group, trump: trump)
            return Combos.components(of: component.shape, in: sameGroup, trump: trump)
                .contains { $0.topStrength > component.topStrength }
        }
        let others = (1..<4).map { (leader + $0) % 4 }
        let beatable = components.filter { component in others.contains { beats(component, hands[$0]) } }
        guard let forced = beatable.min(by: {
            ($0.shape.cardCount, $0.topStrength) < ($1.shape.cardCount, $1.topStrength)
        }) else { return nil }
        guard let blocker = others.first(where: { beats(forced, hands[$0]) }) else { return nil }
        return (forced.shape, forced.topStrength, blocker)
    }
}

/// Every observable field of a `Round`, for checking that rejected actions change nothing.
struct RoundSnapshot: Equatable {
    var trumpRank: Rank, dealer: Int?, phase: RoundPhase, hands: [[Card]], undealt: [Card], kitty: [Card]
    var declaration: Declaration?, declarationHistory: [Declaration], trump: Trump, nextToReceive: Int
    var currentTrick: [Play], tricks: [TrickRecord], leader: Int, defenderTrickPoints: Int
    var trumpFromKitty: Card?, result: RoundResult?

    init(_ r: Round) {
        (trumpRank, dealer, phase, hands, undealt, kitty) = (r.trumpRank, r.dealer, r.phase, r.hands, r.undealt, r.kitty)
        (declaration, declarationHistory, trump, nextToReceive) = (r.declaration, r.declarationHistory, r.trump, r.nextToReceive)
        (currentTrick, tricks, leader, defenderTrickPoints) = (r.currentTrick, r.tricks, r.leader, r.defenderTrickPoints)
        (trumpFromKitty, result) = (r.trumpFromKitty, r.result)
    }
}

final class EngineSimulationTests: XCTestCase {
    /// Winner of a trick of single cards, computed independently of `Rules.winningIndex`.
    private func simpleSingleWinner(_ plays: [Play], trump: Trump) -> Int {
        let ledGroup = trump.group(plays[0].cards[0])
        var best = 0
        for index in 1..<plays.count {
            let current = plays[best].cards[0], challenger = plays[index].cards[0]
            let currentGroup = trump.group(current), challengerGroup = trump.group(challenger)
            if challengerGroup.isTrump && !currentGroup.isTrump {
                best = index
            } else if challengerGroup == currentGroup, challengerGroup == ledGroup || challengerGroup.isTrump,
                      trump.strength(challenger) > trump.strength(current) {
                best = index
            }
        }
        return best
    }

    /// Winner of a trick led with a single pair, computed independently.
    private func simplePairWinner(_ plays: [Play], trump: Trump) -> Int {
        let ledGroup = trump.group(plays[0].cards[0])
        var best = 0
        for index in 1..<plays.count {
            let cards = plays[index].cards
            guard Combos.isPair(cards) else { continue }
            let group = trump.group(cards[0])
            guard group == ledGroup || group.isTrump else { continue }
            let bestGroup = trump.group(plays[best].cards[0])
            if group.isTrump && !bestGroup.isTrump {
                best = index
            } else if group == bestGroup && trump.strength(cards[0]) > trump.strength(plays[best].cards[0]) {
                best = index
            }
        }
        return best
    }

    func testRandomRoundsKeepInvariants() throws {
        var throwsTried = 0, throwsFailed = 0, kittyBonusRounds = 0, kittyFlipRounds = 0
        var declarationsMade = 0, tractorLeads = 0, structureChecks = 0
        for seed in UInt64(0)..<UInt64(320) {
            var rng = SeededGenerator(seed: seed &* 7919 &+ 17)
            let dealer: Int? = seed % 3 == 0 ? nil : Int(seed % 4)
            let rank = Rank.allCases[Int(seed % 13)]
            var round = Round(trumpRank: rank, dealer: dealer, rng: &rng)
            XCTAssertEqual(round.phase, .dealing)
            XCTAssertEqual(round.undealt.count, 100)

            // Dealing, with random declarations; trump suit follows the current declaration.
            // Every fifth deal nobody declares, so the kitty decides the trump suit.
            let declares = seed % 5 != 0
            while let dealt = round.dealNext() {
                XCTAssertEqual(round.hands[dealt.player].last, dealt.card)
                if declares && Int.random(in: 0..<8, using: &rng) == 0 {
                    let seat = Int.random(in: 0..<4, using: &rng)
                    if let option = round.availableDeclarations(for: seat).randomElement(using: &rng) {
                        try round.declare(option)
                        declarationsMade += 1
                    }
                }
                XCTAssertEqual(round.trump.suit, round.declaration?.suit)
            }
            XCTAssertTrue(round.isDealingComplete)
            XCTAssertEqual(round.hands.map(\.count), [25, 25, 25, 25], "seed \(seed)")
            XCTAssertEqual(round.kitty.count, 8)
            let hadDeclaration = round.declaration != nil

            round.finishDealing()
            XCTAssertEqual(round.phase, .burying)
            guard let roundDealer = round.dealer else { return XCTFail("dealer missing, seed \(seed)") }
            if let dealer = dealer { XCTAssertEqual(roundDealer, dealer) }
            else { XCTAssertEqual(roundDealer, round.declaration?.player ?? 0) }
            XCTAssertEqual(round.hands[roundDealer].count, 33, "seed \(seed)")
            XCTAssertEqual(Set(round.hands.flatMap { $0 }.map(\.id)).count, 108)
            if hadDeclaration {
                XCTAssertNil(round.trumpFromKitty)
                XCTAssertEqual(round.trump.suit, round.declaration?.suit)
            } else {
                guard let flipped = round.trumpFromKitty else { return XCTFail("no kitty flip, seed \(seed)") }
                XCTAssertTrue(round.kitty.contains(flipped))
                XCTAssertEqual(round.trump.suit, flipped.suit)
                kittyFlipRounds += 1
            }

            let buried = Array(round.hands[roundDealer].shuffled(using: &rng).prefix(8))
            try round.bury(buried)
            XCTAssertEqual(round.phase, .playing)
            XCTAssertEqual(round.kitty, buried)
            XCTAssertEqual(round.turn, roundDealer)
            XCTAssertEqual(round.hands.map(\.count), [25, 25, 25, 25])

            let trump = round.trump
            var moves = 0
            while round.phase == .playing {
                moves += 1
                guard moves < 500, let seat = round.turn else { return XCTFail("round stuck, seed \(seed)") }
                let hand = round.hands[seat]
                let tricksBefore = round.tricks.count
                if round.currentTrick.isEmpty {
                    let lead = EngineTestSupport.randomLead(hand: hand, trump: trump, rng: &rng)
                    XCTAssertNil(Rules.validateLead(lead, hand: hand, trump: trump))
                    let isThrow = Rules.isThrow(lead, trump: trump)
                    if Combos.shape(of: lead, trump: trump)?.isTractor == true { tractorLeads += 1 }
                    let expected = Rules.checkThrow(lead, leader: seat, hands: round.hands, trump: trump)
                    let reference = EngineTestSupport.referenceThrowFailure(lead, leader: seat, hands: round.hands, trump: trump)
                    let outcome = try round.play(lead, by: seat)
                    if isThrow { throwsTried += 1 }
                    switch outcome {
                    case .played:
                        XCTAssertNil(reference, "a throw that should fail went through, seed \(seed)")
                        XCTAssertEqual(expected, .ok)
                        XCTAssertEqual(round.currentTrick.last?.cards, lead)
                        XCTAssertEqual(round.hands[seat].count, hand.count - lead.count)
                    case let .throwFailed(forced, blocker):
                        throwsFailed += 1
                        XCTAssertTrue(isThrow)
                        guard case let .fails(component, expectedBlocker) = expected else {
                            return XCTFail("throw failed unexpectedly, seed \(seed)")
                        }
                        XCTAssertEqual(forced, component.cards)
                        XCTAssertEqual(blocker, expectedBlocker)
                        // Independent check: same size and strength of forced part, same blocker.
                        if let reference = reference {
                            XCTAssertEqual(component.shape, reference.shape, "seed \(seed)")
                            XCTAssertEqual(component.topStrength, reference.topStrength, "seed \(seed)")
                            XCTAssertEqual(blocker, reference.blocker, "seed \(seed)")
                        } else {
                            XCTFail("the reference says this throw succeeds, seed \(seed)")
                        }
                        XCTAssertNotEqual(blocker, seat)
                        XCTAssertTrue(Rules.canBeat(component, with: round.hands[blocker], trump: trump))
                        XCTAssertEqual(round.currentTrick.last?.cards, forced)
                        XCTAssertEqual(round.hands[seat].count, hand.count - forced.count)
                        XCTAssertTrue(lead.containsAll(forced))
                    }
                } else {
                    let lead = round.currentLead
                    let follow = EngineTestSupport.legalFollow(hand: hand, lead: lead, trump: trump, rng: &rng)
                    XCTAssertNil(Rules.validateFollow(follow, hand: hand, lead: lead, trump: trump),
                                 "generator built an illegal follow, seed \(seed)")
                    XCTAssertNil(round.legalityError(for: follow, by: seat))
                    structureChecks += checkRandomFollows(hand: hand, lead: lead, follow: follow, trump: trump, rng: &rng)
                    let outcome = try round.play(follow, by: seat)
                    XCTAssertEqual(outcome, .played)
                }

                if round.tricks.count > tricksBefore, let trick = round.tricks.last {
                    // A trick just completed.
                    XCTAssertTrue(round.currentTrick.isEmpty)
                    XCTAssertEqual(trick.plays.count, 4)
                    XCTAssertEqual(Set(trick.plays.map(\.player)).count, 4)
                    let sizes = Set(round.hands.map(\.count))
                    XCTAssertEqual(sizes.count, 1, "hand sizes differ after a trick, seed \(seed)")
                    let leadCount = trick.plays[0].cards.count
                    XCTAssertTrue(trick.plays.allSatisfy { $0.cards.count == leadCount })
                    let index = Rules.winningIndex(trick.plays, trump: trump)
                    XCTAssertEqual(trick.winner, trick.plays[index].player)
                    XCTAssertEqual(index, EngineTestSupport.referenceWinner(trick.plays, trump: trump),
                                   "trick \(trick.plays.map { $0.cards.shortText }), seed \(seed)")
                    XCTAssertEqual(round.leader, trick.winner)
                    XCTAssertEqual(trick.points, trick.plays.flatMap(\.cards).points)
                    if index > 0 {
                        let winning = trick.plays[index].cards
                        XCTAssertTrue(Rules.matchesStructure(winning, lead: trick.plays[0].cards, trump: trump))
                    }
                    if leadCount == 1 {
                        XCTAssertEqual(index, simpleSingleWinner(trick.plays, trump: trump), "seed \(seed)")
                    } else if Combos.isPair(trick.plays[0].cards) {
                        XCTAssertEqual(index, simplePairWinner(trick.plays, trump: trump), "seed \(seed)")
                    }
                }
            }

            // Round finished: check the result adds up.
            XCTAssertEqual(round.phase, .finished)
            XCTAssertNil(round.turn)
            XCTAssertTrue(round.hands.allSatisfy { $0.isEmpty })
            guard let result = round.result, let last = round.tricks.last else {
                return XCTFail("missing result, seed \(seed)")
            }
            let allCards = round.playedCards + round.kitty
            XCTAssertEqual(allCards.count, 108)
            XCTAssertEqual(Set(allCards.map(\.id)).count, 108)
            let defenderTricks = round.tricks.filter { round.isDefender($0.winner) }.reduce(0) { $0 + $1.points }
            let declarerTricks = round.tricks.filter { !round.isDefender($0.winner) }.reduce(0) { $0 + $1.points }
            XCTAssertEqual(defenderTricks + declarerTricks + round.kitty.points, Scoring.totalPoints)
            XCTAssertEqual(result.trickPoints, defenderTricks)
            XCTAssertEqual(round.defenderTrickPoints, defenderTricks)
            XCTAssertEqual(result.kittyPoints, round.kitty.points)
            XCTAssertEqual(result.kitty, round.kitty)
            XCTAssertEqual(result.lastTrickWinner, last.winner)
            XCTAssertEqual(result.dealer, roundDealer)
            XCTAssertEqual(result.declarerTeam, roundDealer % 2)
            XCTAssertEqual(result.trump, trump)
            let expectedMultiplier = round.isDefender(last.winner)
                ? Scoring.kittyMultiplier(lastLead: last.plays[0].cards, trump: trump) : 0
            XCTAssertEqual(result.kittyMultiplier, expectedMultiplier)
            XCTAssertEqual(result.defenderPoints, result.trickPoints + result.kittyPoints * result.kittyMultiplier)
            XCTAssertEqual(result.outcome, Scoring.outcome(defenderPoints: result.defenderPoints))
            if result.kittyMultiplier > 0 && result.kittyPoints > 0 { kittyBonusRounds += 1 }
            XCTAssertThrowsError(try round.play([], by: 0)) { error in
                XCTAssertEqual(error as? RoundError, .wrongPhase)
            }
        }
        // The random games must actually exercise the interesting paths.
        XCTAssertGreaterThan(throwsTried, 50)
        XCTAssertGreaterThan(throwsFailed, 20)
        XCTAssertGreaterThan(kittyBonusRounds, 10)
        XCTAssertGreaterThan(kittyFlipRounds, 10)
        XCTAssertGreaterThan(declarationsMade, 100)
        XCTAssertGreaterThan(tractorLeads, 30)
        XCTAssertGreaterThan(structureChecks, 1000)
    }

    /// Samples random plays from the led group and checks `validateFollow` agrees with an
    /// independent check of the follow requirement. Returns the number of samples checked.
    private func checkRandomFollows<G: RandomNumberGenerator>(hand: [Card], lead: [Card], follow: [Card], trump: Trump,
                                                               rng: inout G) -> Int {
        guard let first = lead.first else { return 0 }
        let n = lead.count
        let held = Combos.cards(hand, in: trump.group(first), trump: trump)
        guard held.count >= n else { return 0 }
        let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
        // The requirement can always be met with the cards held.
        XCTAssertNotNil(EngineTestSupport.disjointTractors(in: held, lengths: requirement.tractorLengths, trump: trump))
        XCTAssertLessThanOrEqual(2 * requirement.totalPairs, n)
        XCTAssertLessThanOrEqual(requirement.totalPairs, Combos.pairCount(in: held))
        XCTAssertGreaterThanOrEqual(requirement.totalPairs, requirement.tractorLengths.reduce(0, +))
        // Owed pairs: every pair the lead has (inside tractors too), or every pair held if fewer.
        let ledPairs = Combos.decompose(lead, trump: trump).reduce(0) { $0 + $1.shape.pairCount }
        XCTAssertEqual(requirement.totalPairs, min(ledPairs, Combos.pairCount(in: held)))
        // Same as the exhaustive reference walk (tractor count and size; the order may differ on ties).
        let reference = EngineTestSupport.referenceRequirement(lead: lead, held: held, trump: trump)
        XCTAssertEqual(requirement.tractorLengths.count, reference.tractorLengths.count,
                       "lead \(lead.shortText) held \(held.shortText)")
        XCTAssertEqual(requirement.tractorLengths.reduce(0, +), reference.tractorLengths.reduce(0, +))
        XCTAssertEqual(requirement.totalPairs, reference.totalPairs)
        // If the follower could copy the lead's structure, every legal follow must copy it.
        let canCopy = EngineTestSupport.referenceCanMatch(lead, within: held, trump: trump)
        if canCopy {
            XCTAssertNotNil(EngineTestSupport.referenceKey(follow, lead: lead, trump: trump),
                            "lead \(lead.shortText) follow \(follow.shortText)")
        }
        for _ in 0..<3 {
            let sample = Array(held.shuffled(using: &rng).prefix(n))
            let independentOK = EngineTestSupport.disjointTractors(
                in: sample, lengths: requirement.tractorLengths, trump: trump) != nil
                && Combos.pairCount(in: sample) >= requirement.totalPairs
            let violation = Rules.validateFollow(sample, hand: hand, lead: lead, trump: trump)
            XCTAssertEqual(violation == nil, independentOK, "lead \(lead.shortText) play \(sample.shortText)")
            if canCopy && violation == nil {
                XCTAssertNotNil(EngineTestSupport.referenceKey(sample, lead: lead, trump: trump),
                                "lead \(lead.shortText) accepted \(sample.shortText)")
            }
            if let violation = violation {
                switch violation {
                case .mustPlayTractor, .mustPlayPairs: break
                default: XCTFail("unexpected violation \(violation)")
                }
            }
        }
        return 3
    }

    func testCodableRoundTripMidGame() throws {
        for seed in UInt64(1)...UInt64(12) {
            var rng = SeededGenerator(seed: seed)
            var round = Round(trumpRank: .seven, dealer: seed % 2 == 0 ? nil : 1, rng: &rng)
            try EngineTestSupport.prepare(&round, rng: &rng)
            // Play into the middle of a trick.
            for _ in 0..<(30 + Int(seed)) { _ = try EngineTestSupport.playOneMove(&round, rng: &rng) }
            XCTAssertEqual(round.phase, .playing)

            let data = try EngineTestSupport.encode(round)
            var copy = try JSONDecoder().decode(Round.self, from: data)
            XCTAssertEqual(try EngineTestSupport.encode(copy), data)
            XCTAssertEqual(copy.hands, round.hands)
            XCTAssertEqual(copy.currentTrick, round.currentTrick)
            XCTAssertEqual(copy.tricks, round.tricks)
            XCTAssertEqual(copy.turn, round.turn)
            XCTAssertEqual(copy.trump, round.trump)
            XCTAssertEqual(copy.declaration, round.declaration)
            XCTAssertEqual(copy.defenderTrickPoints, round.defenderTrickPoints)

            // Both copies finish identically when given the same moves.
            var rngA = rng, rngB = rng
            try EngineTestSupport.playOut(&round, rng: &rngA)
            try EngineTestSupport.playOut(&copy, rng: &rngB)
            XCTAssertEqual(round.phase, .finished)
            XCTAssertNotNil(round.result)
            XCTAssertEqual(round.result, copy.result)
        }
    }

    func testCodableRoundTripDuringDealing() throws {
        var rng = SeededGenerator(seed: 99)
        var round = Round(trumpRank: .three, dealer: nil, rng: &rng)
        for _ in 0..<57 { round.dealNext() }
        let data = try EngineTestSupport.encode(round)
        let copy = try JSONDecoder().decode(Round.self, from: data)
        XCTAssertEqual(copy.undealt, round.undealt)
        XCTAssertEqual(copy.nextToReceive, round.nextToReceive)
        XCTAssertEqual(copy.phase, .dealing)
        XCTAssertNil(copy.dealer)
    }

    func testFullGamesProgressToAWinner() throws {
        var finishedGames = 0
        for seed in UInt64(0)..<UInt64(6) {
            var rng = SeededGenerator(seed: 500 + seed)
            var game = GameState(settings: GameSettings(startRank: .queen, targetRank: .ace))
            var rounds = 0
            while game.winner == nil && rounds < 80 {
                let expectedRank = game.nextTrumpRank
                let expectedDealer = game.nextDealer
                var round = game.makeRound(rng: &rng)
                XCTAssertEqual(round.trumpRank, expectedRank)
                XCTAssertEqual(round.dealer, expectedDealer)
                try EngineTestSupport.prepare(&round, rng: &rng)
                try EngineTestSupport.playOut(&round, rng: &rng)
                guard let result = round.result else { return XCTFail("round did not finish") }

                let before = game.levels
                let summary = game.record(result)
                rounds += 1
                XCTAssertEqual(game.roundsPlayed, rounds)
                XCTAssertEqual(summary.levelsBefore, before)
                XCTAssertEqual(summary.levelsAfter, game.levels)
                for team in 0..<2 {
                    XCTAssertGreaterThanOrEqual(game.levels[team], before[team])
                    XCTAssertLessThanOrEqual(game.levels[team], .ace)
                }
                let expectedNext = result.outcome.declarersHold
                    ? Seats.partner(of: result.dealer) : Seats.next(after: result.dealer)
                XCTAssertEqual(game.nextDealer, expectedNext)
                XCTAssertEqual(game.nextTrumpRank, game.levels[expectedNext % 2])
                if let winner = summary.gameWinner {
                    XCTAssertTrue(result.outcome.declarersHold)
                    XCTAssertEqual(winner, result.declarerTeam)
                    XCTAssertEqual(before[winner], .ace)
                }
                XCTAssertFalse(summary.explanation.contains("\u{2014}"))
            }
            if game.winner != nil { finishedGames += 1 }
        }
        XCTAssertGreaterThan(finishedGames, 0)
    }
}

/// Checks the rules engine against the naive reference implementations in `EngineTestSupport`
/// on situations that random deals rarely produce: long tractors, multi-tractor throws, ruffs with
/// tractors, the trump-rank level (three off-suit rank pairs at one strength) and no-trump rounds.
final class EngineCrossCheckTests: XCTestCase {
    /// Up to `count` cards from `faces` in order, usually as pairs, so runs and tractors are common.
    private func structured<G: RandomNumberGenerator>(_ faces: [Face], count: Int, rng: inout G) -> [Card] {
        var cards: [Card] = []
        for face in faces where cards.count < count {
            cards.append(Card(face, copy: 0))
            if cards.count < count && Int.random(in: 0..<4, using: &rng) > 0 { cards.append(Card(face, copy: 1)) }
        }
        return cards
    }

    private func trump(_ index: Int) -> Trump {
        Trump(rank: Rank.allCases[index % 13], suit: index % 4 == 0 ? nil : Suit.allCases[index % 4])
    }

    private let allFaces = (0..<54).compactMap { Face(index: $0) }

    func testWinnerMatchesReferenceOnStructuredTricks() {
        var rng = SeededGenerator(seed: 1234)
        var checked = 0, ruffsWon = 0
        for index in 0..<1500 {
            let trump = trump(index)
            let trumpFaces = allFaces.filter { trump.isTrump($0) }.shuffled(using: &rng)
            let suitFaces = allFaces.filter { trump.group($0) == .plain(.spades) }.shuffled(using: &rng)
            let n = Int.random(in: 2...10, using: &rng)
            let leadFaces = Array((Bool.random(using: &rng) ? trumpFaces : suitFaces).prefix(n))
            let lead = structured(leadFaces, count: n, rng: &rng)
            guard lead.count == n else { continue }
            var plays = [Play(player: 0, cards: lead)]
            var used = Set(leadFaces)
            for player in 1..<4 {
                let pool = (Bool.random(using: &rng) ? trumpFaces : suitFaces).filter { !used.contains($0) }
                let cards = structured(pool.shuffled(using: &rng), count: n, rng: &rng)
                guard cards.count == n else { break }
                used.formUnion(cards.map(\.face))
                plays.append(Play(player: player, cards: cards))
            }
            let winner = Rules.winningIndex(plays, trump: trump)
            XCTAssertEqual(winner, EngineTestSupport.referenceWinner(plays, trump: trump),
                           "\(trump): \(plays.map { $0.cards.shortText })")
            for play in plays.dropFirst() {
                XCTAssertEqual(Rules.matchesStructure(play.cards, lead: lead, trump: trump),
                               EngineTestSupport.referenceKey(play.cards, lead: lead, trump: trump) != nil,
                               "\(trump): lead \(lead.shortText) play \(play.cards.shortText)")
            }
            checked += 1
            if winner > 0 && trump.group(plays[winner].cards[0]).isTrump && !trump.group(lead[0]).isTrump {
                ruffsWon += 1
            }
        }
        XCTAssertGreaterThan(checked, 1000)
        XCTAssertGreaterThan(ruffsWon, 100)
    }

    func testFollowRequirementMatchesExhaustiveReference() {
        var rng = SeededGenerator(seed: 77)
        var checked = 0, multiTractor = 0
        for index in 0..<700 {
            let trump = trump(index)
            let leadFromTrumps = index % 3 != 0
            let faces = allFaces.filter { leadFromTrumps ? trump.isTrump($0) : trump.group($0) == .plain(.hearts) }
                .shuffled(using: &rng)
            guard faces.count >= 8 else { continue }
            // The leader holds only pairs (often in runs); the follower holds what is left, mostly as pairs.
            let leadFaces = Array(faces.prefix(Int.random(in: 3...min(8, faces.count - 3), using: &rng)))
            let lead = leadFaces.flatMap { [Card($0, copy: 0), Card($0, copy: 1)] }
            let held = structured(Array(faces.dropFirst(leadFaces.count)).shuffled(using: &rng),
                                  count: Int.random(in: lead.count...(lead.count + 6), using: &rng), rng: &rng)
            guard held.count >= lead.count else { continue }
            let components = Combos.decompose(lead, trump: trump)
            if components.filter({ $0.shape.isTractor }).count >= 2 { multiTractor += 1 }
            let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
            let reference = EngineTestSupport.referenceRequirement(lead: lead, held: held, trump: trump)
            let message = "\(trump): lead \(lead.shortText) held \(trump.sorted(held).shortText)"
            XCTAssertEqual(requirement.tractorLengths.count, reference.tractorLengths.count, message)
            XCTAssertEqual(requirement.tractorLengths.reduce(0, +), reference.tractorLengths.reduce(0, +), message)
            XCTAssertEqual(requirement.totalPairs, reference.totalPairs, message)
            // Whenever the follower could copy the lead's structure, a legal follow must copy it.
            if EngineTestSupport.referenceCanMatch(lead, within: held, trump: trump) {
                let follow = EngineTestSupport.legalFollow(hand: held, lead: lead, trump: trump, rng: &rng)
                XCTAssertNil(Rules.validateFollow(follow, hand: held, lead: lead, trump: trump), message)
                XCTAssertNotNil(EngineTestSupport.referenceKey(follow, lead: lead, trump: trump), message)
            }
            checked += 1
        }
        XCTAssertGreaterThan(checked, 400)
        XCTAssertGreaterThan(multiTractor, 100)
    }

    /// Random, mostly illegal input: nothing crashes, every rejection leaves the round exactly as it
    /// was and carries a learner-facing explanation, and `legalityError` predicts what `play` does.
    func testRandomInputNeverCorruptsARound() throws {
        var accepted = 0, rejected = 0, finished = 0
        for seed in UInt64(0)..<40 {
            var rng = SeededGenerator(seed: seed &* 31 &+ 5)
            var round = Round(trumpRank: Rank.allCases[Int(seed % 13)], dealer: seed % 2 == 0 ? nil : Int(seed % 4),
                              rng: &rng)
            var steps = 0
            while round.phase != .finished && steps < 6000 {
                steps += 1
                let before = RoundSnapshot(round)
                let roll = Int.random(in: 0..<10, using: &rng)
                let player = Int.random(in: -1...4, using: &rng)
                do {
                    switch round.phase {
                    case .dealing:
                        if roll < 6 {
                            round.dealNext()
                        } else if roll < 8 {
                            let seat = max(0, min(3, player))
                            let count = Int.random(in: 0...2, using: &rng)
                            let cards = Array(round.hands[seat].shuffled(using: &rng).prefix(count))
                            let suit = Bool.random(using: &rng) ? nil : Suit.allCases.randomElement(using: &rng)
                            try round.declare(Declaration(player: player, cards: cards, suit: suit,
                                                          strength: Int.random(in: 0...5, using: &rng)))
                        } else if roll == 8, Seats.all.contains(player),
                                  let option = round.availableDeclarations(for: player).randomElement(using: &rng) {
                            try round.declare(option)
                        } else {
                            round.finishDealing()
                        }
                    case .burying:
                        let dealer = round.dealer ?? 0
                        let pool = roll < 5 ? round.hands[dealer] : round.hands.flatMap { $0 }
                        let size = roll < 8 ? Round.kittySize : Int.random(in: 0...9, using: &rng)
                        try round.bury(Array(pool.shuffled(using: &rng).prefix(size)))
                    case .playing:
                        let seat = roll < 7 ? (round.turn ?? 0) : player
                        let hand = round.hands.indices.contains(seat) ? round.hands[seat] : []
                        let count = round.currentLead.isEmpty ? Int.random(in: 0...4, using: &rng) : round.currentLead.count
                        let pool = roll < 9 ? hand : round.hands.flatMap { $0 }
                        let cards = Array(pool.shuffled(using: &rng).prefix(count))
                        let predicted = round.legalityError(for: cards, by: seat)
                        do {
                            try round.play(cards, by: seat)
                            XCTAssertNil(predicted)
                            accepted += 1
                        } catch {
                            XCTAssertEqual(error as? RoundError, predicted)
                            throw error
                        }
                    case .finished:
                        break
                    }
                } catch {
                    rejected += 1
                    XCTAssertEqual(RoundSnapshot(round), before, "a rejected action changed the round, seed \(seed)")
                    let explanation = (error as? RoundError)?.explanation ?? ""
                    XCTAssertFalse(explanation.isEmpty)
                    XCTAssertFalse(explanation.contains("\u{2014}"))
                }
                if round.phase == .playing && round.currentTrick.isEmpty {
                    XCTAssertEqual(Set(round.hands.map(\.count)).count, 1, "seed \(seed)")
                }
            }
            if round.phase == .finished {
                finished += 1
                XCTAssertEqual(round.playedCards.count + round.kitty.count, 108)
            }
        }
        XCTAssertEqual(finished, 40)
        XCTAssertGreaterThan(accepted, 1000)
        XCTAssertGreaterThan(rejected, 1000)
    }
}
