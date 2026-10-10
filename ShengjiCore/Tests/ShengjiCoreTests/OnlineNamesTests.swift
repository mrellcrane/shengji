import Foundation
import XCTest
@testable import ShengjiCore

/// Online tables label the seats with people's names ("Bo", "Tiger Bot"), never East or West. Hints,
/// the coach's context and its question chips must name players the same way there, and stay as they
/// are offline (where the table does say East and West).
final class OnlineNamesTests: XCTestCase {
    private typealias Kit = CoachTestKit
    private static let names = ["Ana", "Bo", "Cy", "Di"]
    private static let players = names.enumerated().map {
        SeatView.Player(name: $0.element, isBot: $0.offset != 0, userID: $0.offset == 0 ? "user-ana" : nil)
    }

    private func named(_ view: SeatView) -> SeatView {
        var view = view
        view.players = OnlineNamesTests.players
        return view
    }

    // MARK: Hints

    /// With `usesPlayerNames`, a hint names the opponents as the table shows them ("Bo's A♠" rather
    /// than "East's A♠"); you and your partner stay "you" and "your partner", and the rest is unchanged.
    func testOnlineHintsNameOpponentsAsTheTableDoes() throws {
        var renamed = 0
        var checked = 0
        for index in 0..<4 {
            var rng = SeededGenerator(seed: 64_000 + UInt64(index))
            var round = Round(trumpRank: Rank.allCases[index * 3], dealer: index % 4, rng: &rng)
            var stats = BotRunStats()
            let bots = (0..<4).map { Bot(seat: $0) }
            BotHarness.deal(&round, bots: bots, stats: &stats)
            BotHarness.bury(&round, bots: bots, stats: &stats)
            while round.phase == .playing, let turn = round.turn {
                let view = round.seatView(for: turn, players: OnlineNamesTests.players)
                for level in BotLevel.allCases {
                    let compass = try XCTUnwrap(Bot(seat: 0, level: level).decide(view: view))
                    var online = Bot(seat: 0, level: level)
                    online.usesPlayerNames = true
                    let hint = try XCTUnwrap(online.decide(view: view))
                    let expected = compass.reason
                        .replacingOccurrences(of: "East", with: view.players[1].name)
                        .replacingOccurrences(of: "West", with: view.players[3].name)
                    XCTAssertEqual(hint.cards, compass.cards)
                    XCTAssertEqual(hint.concept, compass.concept)
                    XCTAssertEqual(hint.nudge, compass.nudge)
                    XCTAssertEqual(hint.principle, compass.principle)
                    XCTAssertEqual(hint.reason, expected)
                    for word in ["South", "East", "North", "West"] {
                        XCTAssertFalse(hint.reason.contains(word), "\(word) in \(hint.reason)")
                    }
                    if hint.reason != compass.reason { renamed += 1 }
                    checked += 1
                }
                try round.play(bots[turn].decide(in: round).cards, by: turn)
            }
        }
        XCTAssertGreaterThan(checked, 300)
        XCTAssertGreaterThan(renamed, 30, "hints that name an opponent")
    }

    /// Offline the table says East and West, and so do the hints (the default).
    func testOfflineHintsKeepCompassNames() throws {
        var rng = SeededGenerator(seed: 64_100)
        var round = Round(trumpRank: .two, dealer: 0, rng: &rng)
        var stats = BotRunStats()
        let bots = (0..<4).map { Bot(seat: $0) }
        BotHarness.deal(&round, bots: bots, stats: &stats)
        BotHarness.bury(&round, bots: bots, stats: &stats)
        var online = Bot(seat: 0)
        online.usesPlayerNames = true
        while round.phase == .playing, let turn = round.turn {
            if turn == 0 {
                // The offline view's players carry the compass names, so naming them changes nothing.
                XCTAssertEqual(online.decide(view: round.seatView(for: 0)), bots[0].decide(in: round))
            }
            try round.play(bots[turn].decide(in: round).cards, by: turn)
        }
    }

    // MARK: Coach

    func testCoachContextSaysWhoIsWhoOnline() throws {
        let view = named(Kit.view(dealer: 2, defenderPoints: 35))
        let text = CoachContext.describe(view: view, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(text.contains("Names at this table: East is Bo, Partner (North) is Cy, West is Di."), text)

        let offline = CoachContext.describe(view: Kit.view(dealer: 2, defenderPoints: 35), hint: nil, selection: [], lastIllegal: nil)
        XCTAssertFalse(offline.contains("Names at this table"), offline)

        // Long names, a huge hint and a long history still fit the proxy's limit, names line included.
        for seed in UInt64(0)..<UInt64(60) {
            let state = try Kit.randomState(seed: seed &+ 7_000)
            var view = state.round.seatView(for: 0, players: (0..<4).map {
                SeatView.Player(name: String(repeating: "W", count: 24) + "\($0)", isBot: false)
            }, game: state.game)
            view.players[0].name = "Ana"
            let hand = view.hand
            let hint = Kit.ladder(cards: hand, steps: 3, reason: String(repeating: "Think about the points. ", count: 20))
            let attempt = IllegalAttempt(cards: hand, error: .illegalFollow(.mustFollowSuit(.trump)))
            let text = CoachContext.describe(view: view, hint: hint, selection: hand, lastIllegal: attempt)
            XCTAssertLessThanOrEqual(text.utf16.count, CoachContext.maxTableCharacters, "seed \(seed)")
            XCTAssertTrue(text.contains("Names at this table"), "seed \(seed)")
        }
    }

    func testChipsNamePlayersAsTheTableDoes() {
        let finished = Kit.trick([Play(player: 1, cards: [Kit.c(.three, .clubs)]), Play(player: 2, cards: [Kit.c(.four, .clubs)]),
                                  Play(player: 3, cards: [Kit.c(.ace, .clubs)]), Play(player: 0, cards: [Kit.c(.five, .clubs)])])
        let pause = named(Kit.view(hand: [Kit.c(.three, .spades)], leader: 3, turn: 3, tricks: [finished]))
        let chips = SuggestedQuestions.forTable(view: pause, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(chips.first?.label, "Why did Di win that?")
        XCTAssertEqual(chips.first?.prompt, "Why did Di win the last trick (Bo led 3♣)? Walk me through what beat what.")

        let lead = Play(player: 1, cards: Kit.pair(.king, .spades))
        let follow = named(Kit.view(hand: [Kit.c(.three, .spades)], currentTrick: [lead], leader: 1, turn: 0))
        let followChips = SuggestedQuestions.forTable(view: follow, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(followChips.contains { $0.prompt.hasPrefix("Bo led K♠ K♠.") }, "\(followChips.map(\.prompt))")

        let burying = named(Kit.view(phase: .burying, dealer: 3, turn: nil))
        let buryChips = SuggestedQuestions.forTable(view: burying, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertTrue(buryChips.contains { $0.prompt.hasPrefix("Di is burying cards now.") }, "\(buryChips.map(\.prompt))")

        // A name too long for a chip label: "they" instead of a cut-off name.
        var long = pause
        long.players[3].name = "Grandma Wilhelmina Rose"
        let longChips = SuggestedQuestions.forTable(view: long, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(longChips.first?.label, "Why did they win that?")
        XCTAssertTrue(longChips.first?.prompt.hasPrefix("Why did Grandma Wilhelmina Rose win the last trick") == true)

        // Offline the same chips keep the compass names the table shows.
        let offline = SuggestedQuestions.forTable(view: Kit.view(hand: [Kit.c(.three, .spades)], leader: 3, turn: 3, tricks: [finished]),
                                                  hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(offline.first?.label, "Why did West win that?")
    }
}
