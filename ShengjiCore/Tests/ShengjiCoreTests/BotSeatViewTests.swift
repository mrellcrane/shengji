import Foundation
import XCTest
@testable import ShengjiCore

/// Bots decide from a `SeatView` alone (DESIGN.md, Online multiplayer): the Round methods are thin
/// wrappers over the view methods, a view that went through JSON gives the same decision, and no
/// decision depends on a card the viewer cannot see.
final class BotSeatViewTests: XCTestCase {
    private static let names = ["Ana", "Bo", "Cy", "Di"]
    private static let players = names.enumerated().map {
        SeatView.Player(name: $0.element, isBot: $0.offset != 0, userID: $0.offset == 0 ? "user-ana" : nil)
    }

    /// `round.seatView(for: seat)` with named players and the game's levels, as the app and the server build it.
    private func view(_ round: Round, _ seat: Int, game: GameState? = nil) -> SeatView {
        round.seatView(for: seat, players: BotSeatViewTests.players, game: game)
    }

    /// `reason` written from `seat` (absolute compass names) rewritten from seat 0's side: the same
    /// player is "East" from South, "South" from West, and so on.
    private func fromSeatZero(_ reason: String, seat: Int) -> String {
        let compass = ["South", "East", "North", "West"]
        var text = reason
        for (absolute, name) in compass.enumerated() { text = text.replacingOccurrences(of: name, with: "<\(absolute)>") }
        for absolute in 0..<4 {
            text = text.replacingOccurrences(of: "<\(absolute)>", with: compass[(absolute - seat + 4) % 4])
        }
        return text
    }

    private func assertSameExceptNames(_ hint: BotDecision?, _ decision: BotDecision, seat: Int, _ message: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        guard let hint else { return XCTFail("no hint: \(message)", file: file, line: line) }
        XCTAssertEqual(hint.cards, decision.cards, message, file: file, line: line)
        XCTAssertEqual(hint.concept, decision.concept, message, file: file, line: line)
        XCTAssertEqual(hint.nudge, decision.nudge, message, file: file, line: line)
        XCTAssertEqual(hint.principle, decision.principle, message, file: file, line: line)
        XCTAssertEqual(hint.reason, fromSeatZero(decision.reason, seat: seat), message, file: file, line: line)
    }

    // MARK: Round path = SeatView path

    /// Whole games: at every decision point, the view of every seat gives the Round method's decision
    /// to the seat that must act and nil to everyone else. `Bot(seat: 0)` (hints) differs only in the
    /// compass names: the viewer is South.
    func testViewDecisionsAtEverySeatMatchTheRound() throws {
        var checked = (declarations: 0, burials: 0, plays: 0, named: 0)
        for index in 0..<6 {
            var rng = SeededGenerator(seed: 61_000 + UInt64(index))
            var game = GameState()
            for _ in 0..<3 where game.winner == nil {
                var round = game.makeRound(rng: &rng)
                let levels: [BotLevel] = (0..<4).map { (index + $0) % 3 == 0 ? .beginner : .standard }
                let bots = (0..<4).map { Bot(seat: $0, level: levels[$0]) }
                var dealt = 0
                while let card = round.dealNext() {
                    dealt += 1
                    if dealt % 9 == 0 || round.isDealingComplete {
                        for seat in 0..<4 {
                            for level in BotLevel.allCases {
                                let bot = Bot(seat: seat, level: level)
                                let available = round.availableDeclarations(for: seat).map { $0.withPlayer(0) }
                                let fromView = bot.declaration(view: view(round, seat, game: game), available: available)
                                XCTAssertEqual(fromView?.withPlayer(seat), bot.declaration(in: round))
                                if let fromView {
                                    XCTAssertEqual(fromView.player, 0)
                                    XCTAssertTrue(available.contains(fromView))
                                }
                                checked.declarations += 1
                            }
                        }
                    }
                    if let declaration = bots[card.player].declaration(in: round) { try round.declare(declaration) }
                }
                for seat in [1, 2, 3, 0] {
                    if let declaration = bots[seat].declaration(in: round) { try round.declare(declaration) }
                }
                round.finishDealing()
                let dealer = try XCTUnwrap(round.dealer)
                for seat in 0..<4 {
                    for level in BotLevel.allCases {
                        let bot = Bot(seat: seat, level: level)
                        let fromView = bot.cardsToBury(view: view(round, seat, game: game))
                        // The view's one decision method buries too (online hints); the Round one only plays.
                        XCTAssertEqual(bot.decide(view: view(round, seat, game: game)), fromView)
                        XCTAssertEqual(bot.decide(in: round), BotText.waiting())
                        if seat == dealer {
                            XCTAssertEqual(fromView, bot.cardsToBury(in: round))
                            assertSameExceptNames(Bot(seat: 0, level: level).cardsToBury(view: view(round, seat)),
                                                  bot.cardsToBury(in: round), seat: seat, "bury")
                            checked.burials += 1
                        } else {
                            XCTAssertNil(fromView)
                            XCTAssertEqual(bot.cardsToBury(in: round), BotText.notBurying())
                        }
                    }
                }
                try round.bury(bots[dealer].cardsToBury(in: round).cards)
                while round.phase == .playing, let turn = round.turn {
                    for seat in 0..<4 {
                        for level in BotLevel.allCases {
                            let bot = Bot(seat: seat, level: level)
                            let fromView = bot.decide(view: view(round, seat, game: game))
                            if seat == turn {
                                let decision = bot.decide(in: round)
                                XCTAssertEqual(fromView, decision)
                                let hint = Bot(seat: 0, level: level).decide(view: view(round, seat, game: game))
                                assertSameExceptNames(hint, decision, seat: seat, "seat \(seat)")
                                if ["South", "East", "North", "West"].contains(where: decision.reason.contains) {
                                    checked.named += 1
                                }
                                checked.plays += 1
                            } else {
                                XCTAssertNil(fromView)
                                XCTAssertEqual(bot.decide(in: round), BotText.waiting())
                            }
                        }
                    }
                    try round.play(bots[turn].decide(in: round).cards, by: turn)
                }
                let result = try XCTUnwrap(round.result)
                game.record(result)
                // Finished: nobody acts.
                for seat in 0..<4 { XCTAssertNil(Bot(seat: seat).decide(view: view(round, seat, game: game))) }
            }
        }
        XCTAssertGreaterThan(checked.declarations, 1500)
        XCTAssertGreaterThan(checked.burials, 30)
        XCTAssertGreaterThan(checked.plays, 2500)
        XCTAssertGreaterThan(checked.named, 200, "reasons naming other players")
    }

    /// `BotKnowledge(view:)` is `BotKnowledge(round:seat:)` with the seats rotated.
    func testKnowledgeFromTheViewIsTheRoundKnowledgeRotated() throws {
        var checks = 0
        for index in 0..<6 {
            var rng = SeededGenerator(seed: 62_000 + UInt64(index))
            var round = Round(trumpRank: Rank.allCases[index * 2], dealer: index % 4, rng: &rng)
            var stats = BotRunStats()
            let bots = (0..<4).map { Bot(seat: $0) }
            BotHarness.deal(&round, bots: bots, stats: &stats)
            BotHarness.bury(&round, bots: bots, stats: &stats)
            while round.phase != .finished {
                for seat in 0..<4 {
                    let fromRound = BotKnowledge(round: round, seat: seat)
                    let fromView = BotKnowledge(view: round.seatView(for: seat))
                    XCTAssertEqual(fromView.seat, 0)
                    XCTAssertEqual(fromView.trump, fromRound.trump)
                    XCTAssertEqual(fromView.unseen, fromRound.unseen)
                    for relative in 0..<4 { XCTAssertEqual(fromView.voids[relative], fromRound.voids[(relative + seat) % 4]) }
                    checks += 1
                }
                BotHarness.step(&round, bots: bots, stats: &stats)
            }
            // Once finished everyone sees the kitty, but only the dealer knows it was buried: same as offline.
            for seat in 0..<4 {
                XCTAssertNotNil(round.seatView(for: seat).kitty)
                XCTAssertEqual(BotKnowledge(view: round.seatView(for: seat)).unseen, BotKnowledge(round: round, seat: seat).unseen)
            }
            XCTAssertEqual(stats.problems, [])
        }
        XCTAssertGreaterThan(checks, 1500)
    }

    // MARK: JSON

    /// A view sent as JSON (the online wire format) and decoded gives the same decision.
    func testViewsDecodedFromJSONGiveTheSameDecision() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var checked = 0
        for index in 0..<8 {
            var rng = SeededGenerator(seed: 63_000 + UInt64(index))
            var round = Round(trumpRank: Rank.allCases[(index * 5) % 13], dealer: index % 4, rng: &rng)
            var stats = BotRunStats()
            let bots = (0..<4).map { Bot(seat: $0, level: index % 2 == 0 ? .standard : .beginner) }
            BotHarness.deal(&round, bots: bots, stats: &stats)
            let dealer = try XCTUnwrap(round.dealer)
            func roundTrip(_ view: SeatView) throws -> SeatView {
                let decoded = try decoder.decode(SeatView.self, from: encoder.encode(view))
                XCTAssertEqual(decoded, view)
                return decoded
            }
            let burying = view(round, dealer)
            XCTAssertEqual(Bot(seat: 0).cardsToBury(view: try roundTrip(burying)), Bot(seat: 0).cardsToBury(view: burying))
            BotHarness.bury(&round, bots: bots, stats: &stats)
            while round.phase == .playing, let turn = round.turn {
                let original = view(round, turn)
                let decoded = try roundTrip(original)
                for level in BotLevel.allCases {
                    let bot = Bot(seat: 0, level: level)
                    let decision = try XCTUnwrap(bot.decide(view: original))
                    XCTAssertEqual(bot.decide(view: decoded), decision)
                    checked += 1
                }
                BotHarness.step(&round, bots: bots, stats: &stats)
            }
            XCTAssertEqual(stats.problems, [])
        }
        XCTAssertGreaterThan(checked, 1000)
    }

    /// Hand-written JSON as the server may send it (optionals omitted or null) decodes and decides.
    func testMinimalServerJSONDecides() throws {
        let json = """
            {"players":[{"name":"You","isBot":false},{"name":"East","isBot":true},{"name":"North","isBot":true},
            {"name":"West","isBot":true}],"teamLevels":[2,2],"targetRank":14,"roundNumber":1,"phase":"playing",
            "trump":{"rank":2,"suit":1},"dealer":0,"hand":[0,1,13,14,26,27],"handCounts":[6,6,6,6],
            "declaration":null,"declarationHistory":[],"bidding":null,"kitty":null,"currentTrick":[],
            "leader":0,"turn":0,"tricks":[],"defenderTrickPoints":0}
            """
        let view = try JSONDecoder().decode(SeatView.self, from: Data(json.utf8))
        let decision = try XCTUnwrap(Bot(seat: 0).decide(view: view))
        XCTAssertFalse(decision.cards.isEmpty)
        XCTAssertTrue(view.hand.containsAll(decision.cards))
        XCTAssertEqual(BotHarness.textProblems(decision), [])
    }

    // MARK: Privacy

    private enum Action {
        case deal
        case declare(Declaration)
        case finish
        case bury([Card])
        case play([Card], seat: Int)
    }

    /// One bot round with every action recorded.
    private struct Script {
        var rank: Rank
        var dealer: Int
        var deck: [Card]
        var actions: [Action] = []
    }

    private func recordRound(seed: UInt64, levels: [BotLevel]) throws -> Script {
        var rng = SeededGenerator(seed: seed)
        let deck = Deck.shuffled(using: &rng)
        var script = Script(rank: Rank.allCases[Int(seed % 13)], dealer: Int(seed % 4), deck: deck)
        var round = Round(trumpRank: script.rank, dealer: script.dealer, deck: deck)
        let bots = (0..<4).map { Bot(seat: $0, level: levels[$0]) }
        while let card = round.dealNext() {
            script.actions.append(.deal)
            if let declaration = bots[card.player].declaration(in: round) {
                try round.declare(declaration)
                script.actions.append(.declare(declaration))
            }
        }
        for seat in [1, 2, 3, 0] {
            if let declaration = bots[seat].declaration(in: round) {
                try round.declare(declaration)
                script.actions.append(.declare(declaration))
            }
        }
        round.finishDealing()
        script.actions.append(.finish)
        let burial = bots[script.dealer].cardsToBury(in: round).cards
        try round.bury(burial)
        script.actions.append(.bury(burial))
        while round.phase == .playing, let turn = round.turn {
            let cards = bots[turn].decide(in: round).cards
            // An illegal play throws and ends the test (the round would never move on).
            let outcome = try round.play(cards, by: turn)
            XCTAssertEqual(outcome, .played)
            script.actions.append(.play(cards, seat: turn))
        }
        return script
    }

    /// Replays the first `count` actions from `deck`; nil if any of them goes differently (a throw that
    /// stood may fail once the hidden cards have moved).
    private func replay(_ script: Script, deck: [Card], count: Int, burial: [Card]? = nil) -> Round? {
        var round = Round(trumpRank: script.rank, dealer: script.dealer, deck: deck)
        for action in script.actions.prefix(count) {
            switch action {
            case .deal: round.dealNext()
            case let .declare(declaration): guard (try? round.declare(declaration)) != nil else { return nil }
            case .finish: round.finishDealing()
            case let .bury(cards): guard (try? round.bury(burial ?? cards)) != nil else { return nil }
            case let .play(cards, seat): guard (try? round.play(cards, by: seat)) == .played else { return nil }
            }
        }
        return round
    }

    /// Another deal with the same public history: every card `viewer` cannot know about is moved
    /// between the places it could be (other hands, the undealt cards, a kitty the viewer didn't pick
    /// up). The viewer's own cards (and the kitty if they dealt), played cards, declared cards and
    /// (when nobody declared) the kitty that was turned up stay put, and no card lands in a hand that
    /// has shown out of its suit. Also returns a burial for the dealer when the viewer didn't deal (the
    /// cards actually buried may have moved). Nil when no such burial exists.
    private func hiddenShuffled(_ script: Script, at round: Round, viewer: Int, count: Int,
                                rng: inout SeededGenerator) -> (deck: [Card], burial: [Card]?)? {
        var fixed = Set<Int>()
        let dealt = script.actions.prefix(count).filter { if case .deal = $0 { return true } else { return false } }.count
        for position in 0..<dealt where (script.dealer + position) % 4 == viewer { fixed.insert(script.deck[position].id) }
        let finished = round.phase != .dealing
        if finished && (viewer == script.dealer || round.declarationHistory.isEmpty) {
            for card in script.deck.suffix(Round.kittySize) { fixed.insert(card.id) }
        }
        for card in round.playedCards { fixed.insert(card.id) }
        for declaration in round.declarationHistory { for card in declaration.cards { fixed.insert(card.id) } }

        // Random swaps between hidden places, never giving a player a suit they have shown out of
        // (the dealer may bury such cards, so their places take anything).
        let voids = BotKnowledge(round: round, seat: viewer).voids
        func owner(_ position: Int) -> Int { position < 100 ? (script.dealer + position) % 4 : script.dealer }
        func fits(_ card: Card, _ position: Int) -> Bool {
            let seat = owner(position)
            return seat == script.dealer || !voids[seat].contains(round.trump.group(card))
        }
        let movable = script.deck.indices.filter { !fixed.contains(script.deck[$0].id) }
        var deck = script.deck
        if movable.count >= 2 {
            for _ in 0..<(8 * movable.count) {
                let first = movable[Int.random(in: 0..<movable.count, using: &rng)]
                let second = movable[Int.random(in: 0..<movable.count, using: &rng)]
                guard fits(deck[second], first), fits(deck[first], second) else { continue }
                deck.swapAt(first, second)
            }
        }

        guard finished, viewer != script.dealer else { return (deck, nil) }
        // The dealer's cards in the new deal (the 25 dealt to them plus the kitty). Buried: the cards
        // that must have been (public ones never played), then cards of suits the dealer has shown out
        // of, then the lowest ids.
        var dealerCards: [Card] = []
        for position in 0..<100 where (script.dealer + position) % 4 == script.dealer { dealerCards.append(deck[position]) }
        dealerCards += deck.suffix(Round.kittySize)
        let dealerVoids = voids[script.dealer]
        var buried = round.kitty.filter { fixed.contains($0.id) }
        let spare = dealerCards.filter { !fixed.contains($0.id) }.sorted { a, b in
            let voidA = dealerVoids.contains(round.trump.group(a)), voidB = dealerVoids.contains(round.trump.group(b))
            return voidA != voidB ? voidA : a.id < b.id
        }
        buried += spare.prefix(Round.kittySize - buried.count)
        let kept = dealerCards.filter { !buried.contains($0) && !round.playedCards.contains($0) }
        guard !kept.contains(where: { dealerVoids.contains(round.trump.group($0)) }) else { return nil }
        return (deck, buried)
    }

    /// Moving the cards the viewer cannot see (other hands, the undealt cards, a kitty they didn't
    /// pick up) while keeping everything public leaves the view, and so every decision, unchanged.
    func testDecisionsNeverDependOnHiddenCards() throws {
        var compared = (declaring: 0, burying: 0, playing: 0), skipped = 0, moved = 0
        for index in 0..<24 {
            let seed = 64_000 + UInt64(index)
            let levels: [BotLevel] = (0..<4).map { (index >> $0) & 1 == 0 ? .standard : .beginner }
            let script = try recordRound(seed: seed, levels: levels)
            var rng = SeededGenerator(seed: seed &* 31)
            let finish = script.actions.firstIndex { if case .finish = $0 { return true } else { return false } } ?? 0
            // Checkpoints: during the deal, the deal complete, burying, and a spread of plays.
            var checkpoints = [Int.random(in: 30..<finish, using: &rng), finish, finish + 1]
            checkpoints += (0..<12).map { _ in Int.random(in: (finish + 2)..<script.actions.count, using: &rng) }
            for count in checkpoints {
                let original = try XCTUnwrap(replay(script, deck: script.deck, count: count))
                // While playing, mostly the seat on turn (the others only check that the view is unchanged).
                let viewers = original.turn.map { [$0, $0, $0, ($0 + 1) % 4, ($0 + 2) % 4] } ?? [0, 0, 1, 1, 2, 2, 3, 3]
                for viewer in viewers {
                    // Some arrangements contradict the history in ways the swaps don't check (a follow that
                    // shows no pair, a throw that stood): try again.
                    var found: Round?
                    for _ in 0..<12 where found == nil {
                        guard let arranged = hiddenShuffled(script, at: original, viewer: viewer, count: count,
                                                            rng: &rng) else { continue }
                        found = replay(script, deck: arranged.deck, count: count, burial: arranged.burial)
                    }
                    guard let other = found else {
                        skipped += 1
                        continue
                    }
                    if other.hands != original.hands || other.kitty != original.kitty { moved += 1 }
                    XCTAssertEqual(other.seatView(for: viewer), original.seatView(for: viewer), "seed \(seed) at \(count)")
                    for level in BotLevel.allCases {
                        let bot = Bot(seat: viewer, level: level)
                        switch original.phase {
                        case .dealing:
                            XCTAssertEqual(bot.declaration(in: other), bot.declaration(in: original))
                            compared.declaring += 1
                        case .burying:
                            XCTAssertEqual(bot.cardsToBury(in: other), bot.cardsToBury(in: original))
                            compared.burying += 1
                        case .playing, .finished:
                            XCTAssertEqual(bot.decide(in: other), bot.decide(in: original))
                            if original.turn == viewer { compared.playing += 1 }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(compared.declaring, 600)
        XCTAssertGreaterThan(compared.burying, 300)
        XCTAssertGreaterThan(compared.playing, 1200)
        XCTAssertGreaterThan(moved, 1800, "replays with hidden cards in other places")
        XCTAssertLessThan(skipped, 40, "no arrangement with the same history found")
    }

    // MARK: Online bidding

    /// Online bidding (server/README.md): all cards dealt, then from the first bidder each seat in turn
    /// declares or passes until three pass after a declaration, or all four pass. Each seat's view has
    /// phase `.bidding`, its turn, the bids so far and what it may declare.
    private func bid(_ round: inout Round, firstBidder: Int, levels: [BotLevel],
                     onTurn: (Int, SeatView, Declaration?) -> Void) throws {
        var history: [SeatView.Bid] = []
        var seat = firstBidder
        var passes = 0
        while passes < (round.declaration == nil ? 4 : 3) {
            let available = round.availableDeclarations(for: seat).map { $0.withPlayer(0) }
            var view = round.seatView(for: seat)
            view.phase = .bidding
            view.turn = nil
            let seen = history.map { bid in
                let player = (bid.player - seat + 4) % 4
                return SeatView.Bid(player: player, declaration: bid.declaration?.withPlayer(player))
            }
            view.bidding = SeatView.Bidding(turn: 0, history: seen, available: available)
            let choice = Bot(seat: seat, level: levels[seat]).declaration(view: view, available: available)
            onTurn(seat, view, choice)
            if let choice {
                let declaration = choice.withPlayer(seat)
                try round.declare(declaration)
                history.append(SeatView.Bid(player: seat, declaration: declaration))
                passes = 0
            } else {
                history.append(SeatView.Bid(player: seat, declaration: nil))
                passes += 1
            }
            seat = (seat + 1) % 4
        }
    }

    func testBiddingHintsDeclareOrPassWithTexts() throws {
        var concepts: [String: Int] = [:]
        var turns = 0
        for index in 0..<300 {
            var rng = SeededGenerator(seed: 65_000 + UInt64(index))
            var round = Round(trumpRank: Rank.allCases[index % 13], dealer: index % 4, rng: &rng)
            round.dealAll()
            let levels: [BotLevel] = (0..<4).map { (index + $0) % 4 == 0 ? .beginner : .standard }
            try bid(&round, firstBidder: index % 4, levels: levels) { seat, view, choice in
                turns += 1
                let bot = Bot(seat: 0, level: levels[seat])
                guard let hint = bot.bid(view: view) else { return XCTFail("no bidding hint") }
                XCTAssertEqual(hint.cards, choice?.cards ?? [], hint.reason)
                if let choice {
                    XCTAssertEqual(choice.player, 0)
                    XCTAssertTrue(view.bidding?.available.contains(choice) == true)
                    XCTAssertNotEqual(view.declaration?.player, 2, "overrode the partner")
                    XCTAssertNotEqual(hint.concept, "Pass")
                } else {
                    XCTAssertEqual(hint.concept, "Pass")
                }
                XCTAssertEqual(BotHarness.textProblems(hint), [], "\(hint)")
                XCTAssertTrue(hint.reason.hasSuffix("."), hint.reason)
                XCTAssertFalse(hint.reason.contains("  "), hint.reason)
                concepts[hint.concept, default: 0] += 1
                // Only the bidder gets a hint, and only while bidding.
                var waiting = view
                waiting.bidding?.turn = 1
                XCTAssertNil(bot.bid(view: waiting))
                var dealing = view
                dealing.phase = .dealing
                XCTAssertNil(bot.bid(view: dealing))
            }
            round.finishDealing()
            XCTAssertEqual(round.phase, .burying)
        }
        XCTAssertGreaterThan(turns, 1000)
        for concept in ["Declare", "Pass", "Override", "No trump"] {
            XCTAssertGreaterThan(concepts[concept] ?? 0, 0, "never: \(concept) in \(concepts)")
        }
    }

    /// Every pass reason and the rarer declarations, from hands built for them (trump rank 2).
    func testBiddingHintCases() throws {
        let south = botCards("2♥ 2♥' 3♥ 4♥ 5♥ 6♥ 7♥ 8♥ 9♥ 10♥ J♥ Q♥ K♥ A♥ 3♠ 4♠ 5♠ 6♠ 7♠ 3♣ 4♣ 5♣ 3♦ 4♦ 5♦")
        // Jokers and rank cards make a fifth of East's hand and no suit is long: no trump suits East.
        let east = botCards("2♠ 2♣ 2♦ SJ SJ' 3♥' 4♥' 8♠ 9♠ 10♠ J♠ Q♠ K♠ 6♣ 7♣ 8♣ 9♣ 10♣ J♣ 6♦ 7♦ 8♦ 9♦ 10♦ J♦")
        let north = botCards("""
            BJ BJ' 2♠' 2♣' 2♦' 9♥' 10♥' J♥' Q♥' K♥' A♥' A♠ J♠' Q♠' K♠' A♠' Q♣ K♣ A♣ 10♣' J♣' Q♦ K♦ A♦ 9♦'
            """)
        let west = botCards("""
            5♥' 6♥' 7♥' 8♥' 3♠' 4♠' 5♠' 6♠' 7♠' 8♠' 9♠' 10♠' 3♣' 4♣' 5♣' 6♣' 7♣' 8♣' 9♣' 3♦' 4♦' 5♦' 6♦' 7♦' 8♦'
            """)
        var round = Round(trumpRank: .two, dealer: 0,
                          deck: EngineTestSupport.deck(hands: [south, east, north, west], firstSeat: 0, seed: 66_000))
        round.dealAll()
        XCTAssertEqual(round.hands[0], south)
        func hint(_ seat: Int, level: BotLevel = .standard) throws -> BotDecision {
            var view = round.seatView(for: seat)
            view.phase = .bidding
            view.turn = nil
            let available = round.availableDeclarations(for: seat).map { $0.withPlayer(0) }
            view.bidding = SeatView.Bidding(turn: 0, history: [], available: available)
            let decision = try XCTUnwrap(Bot(seat: seat, level: level).bid(view: view))
            XCTAssertEqual(BotHarness.textProblems(decision), [], "\(decision)")
            XCTAssertEqual(decision.cards, Bot(seat: seat, level: level).declaration(view: view, available: available)?.cards ?? [])
            return decision
        }

        // Nobody has declared yet.
        let opening = try hint(0)
        XCTAssertEqual(opening.cards, botCards("2♥ 2♥'"))
        XCTAssertEqual(opening.concept, "Declare")
        XCTAssertEqual(opening.reason, "Declare 2♥ 2♥: with hearts as trumps, 14 of your 25 cards would be trumps. "
                       + "A pair is hard to override.")
        let noTrump = try hint(1)
        XCTAssertEqual(noTrump.cards, botCards("SJ SJ'"))
        XCTAssertEqual(noTrump.concept, "No trump")
        XCTAssertTrue(noTrump.reason.contains("5 of your 25 cards are jokers or rank cards"), noTrump.reason)
        let nothing = try hint(3)
        XCTAssertEqual(nothing.cards, [])
        XCTAssertEqual(nothing.reason, "You have no rank cards or joker pairs to declare with, so pass.")
        let beginner = try hint(0, level: .beginner)
        XCTAssertEqual(beginner.concept, "Declare")
        XCTAssertEqual(beginner.cards, botCards("2♥ 2♥'"))
        XCTAssertEqual(try hint(3, level: .beginner).reason, "You have no rank cards or joker pairs to declare with, so pass.")

        // South holds a single 2♥.
        try round.declare(Declaration(player: 0, cards: botCards("2♥"), suit: .hearts, strength: 1))
        let reinforce = try hint(0)
        XCTAssertEqual(reinforce.concept, "Reinforce")
        XCTAssertEqual(reinforce.cards, botCards("2♥ 2♥'"))
        let partner = try hint(2)
        XCTAssertEqual(partner.cards, [])
        XCTAssertEqual(partner.reason, "Your partner holds the declaration, so pass: their trump suit works for your side too.")
        let block = try hint(1)
        XCTAssertEqual(block.concept, "Block")
        XCTAssertEqual(block.cards, botCards("SJ SJ'"))
        XCTAssertEqual(block.reason, "South's declaration would leave you only 7 trumps, so declare SJ SJ for no trump "
                       + "suit and block it.")
        XCTAssertEqual(try hint(3).reason, "Nothing you hold beats the current declaration, so pass.")
        // Hints read from the viewer's side: East's hint calls South (on East's left) West.
        var eastView = round.seatView(for: 1)
        eastView.phase = .bidding
        eastView.bidding = SeatView.Bidding(turn: 0, history: [],
                                            available: round.availableDeclarations(for: 1).map { $0.withPlayer(0) })
        XCTAssertTrue(try XCTUnwrap(Bot(seat: 0).bid(view: eastView)).reason.hasPrefix("West's declaration"))

        // East holds the small jokers: North's big jokers take the declaration back for North and South.
        try round.declare(Declaration(player: 1, cards: botCards("SJ SJ'"), suit: nil, strength: 3))
        let back = try hint(2)
        XCTAssertEqual(back.concept, "Override")
        XCTAssertEqual(back.cards, botCards("BJ BJ'"))
        XCTAssertEqual(back.reason, "Your BJ BJ beats East's jokers, so declare it and take the declaration for your "
                       + "side. There is still no trump suit.")
        XCTAssertEqual(try hint(0).reason, "Nothing you hold beats the current declaration, so pass.")
        XCTAssertEqual(try hint(0, level: .beginner).concept, "Pass")
        // West can't declare anything, but the reason to pass is that their partner East holds it.
        XCTAssertEqual(try hint(3).reason, "Your partner holds the declaration, so pass: their trump suit works for "
                       + "your side too.")
    }

    // MARK: Speed

    /// Building the view is a small part of each decision: decisions stay far below 20 ms (p99, debug).
    func testBuildingTheViewIsCheap() throws {
        var viewTimes: [Double] = [], decisionTimes: [Double] = []
        func time<T>(_ times: inout [Double], _ body: () -> T) -> T {
            let start = DispatchTime.now().uptimeNanoseconds
            let value = body()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            return value
        }
        for index in 0..<20 {
            var rng = SeededGenerator(seed: 67_000 + UInt64(index))
            var round = Round(trumpRank: Rank.allCases[index % 13], dealer: index % 4, rng: &rng)
            var stats = BotRunStats()
            let bots = (0..<4).map { Bot(seat: $0) }
            BotHarness.deal(&round, bots: bots, stats: &stats)
            BotHarness.bury(&round, bots: bots, stats: &stats)
            while round.phase == .playing, let turn = round.turn {
                let view = time(&viewTimes) { round.seatView(for: turn) }
                let decision = time(&decisionTimes) { Bot(seat: turn).decide(view: view) }
                try round.play(try XCTUnwrap(decision).cards, by: turn)
            }
        }
        func p99(_ values: [Double]) -> Double { values.sorted()[Int(Double(values.count - 1) * 0.99)] }
        let viewTotal = viewTimes.reduce(0, +), decisionTotal = decisionTimes.reduce(0, +)
        XCTAssertLessThan(p99(decisionTimes), 20, "p99 decision ms")
        XCTAssertLessThan(p99(viewTimes), 2, "p99 view ms")
        XCTAssertLessThan(viewTotal, decisionTotal / 3, "views \(viewTotal) ms, decisions \(decisionTotal) ms")
    }
}
