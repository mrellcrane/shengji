import Foundation
import XCTest
@testable import ShengjiCore

final class SuggestedQuestionsTests: XCTestCase {
    private typealias Kit = CoachTestKit

    /// Phrases that would ask the coach for cards the learner can't see.
    private let hiddenCardRequests = [
        "East's hand", "West's hand", "Partner's hand", "partner's hand", "their hand", "their cards",
        "what does East have", "what does West have", "what does Partner have", "in the kitty", "kitty cards",
        "hidden", "other hands", "who has the",
    ]

    private func ids(_ chips: [SuggestedQuestion]) -> [String] { chips.map(\.id) }

    private func assertWellFormed(_ chips: [SuggestedQuestion], count range: ClosedRange<Int>, _ label: String,
                                  visible: Set<Face>? = nil, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(range.contains(chips.count), "\(label): \(chips.count) chips", file: file, line: line)
        XCTAssertEqual(Set(ids(chips)).count, chips.count, "\(label): duplicate ids \(ids(chips))", file: file, line: line)
        for chip in chips {
            XCTAssertFalse(chip.id.isEmpty, file: file, line: line)
            XCTAssertFalse(chip.label.isEmpty, file: file, line: line)
            XCTAssertLessThanOrEqual(chip.label.count, SuggestedQuestions.maxLabelLength, "\(label): \(chip.label)", file: file, line: line)
            XCTAssertLessThanOrEqual(chip.prompt.count, SuggestedQuestions.maxPromptLength, "\(label): \(chip.prompt)", file: file, line: line)
            XCTAssertGreaterThan(chip.prompt.count, 10, file: file, line: line)
            XCTAssertFalse(chip.label.contains(Kit.emDash) || chip.prompt.contains(Kit.emDash), file: file, line: line)
            XCTAssertFalse(chip.prompt.contains("**"), file: file, line: line)
            for phrase in hiddenCardRequests {
                XCTAssertFalse(chip.prompt.lowercased().contains(phrase.lowercased()), "\(label): \(chip.prompt)", file: file, line: line)
            }
            if let visible {
                for face in Kit.cardFaces(in: chip.label + "\n" + chip.prompt) {
                    XCTAssertTrue(visible.contains(face), "\(label): \(face) in \(chip.prompt)", file: file, line: line)
                }
            }
        }
    }

    // MARK: Table situations

    func testYourTurnToFollow() {
        let lead = Play(player: 1, cards: Kit.pair(.king, .spades))
        let hand = [Kit.c(.three, .spades), Kit.c(.nine, .spades), Kit.c(.four, .hearts)]
        let view = Kit.view(hand: hand, currentTrick: [lead, Play(player: 2, cards: Kit.pair(.five, .spades)),
                                                       Play(player: 3, cards: Kit.pair(.six, .spades))], turn: 0)
        let chips = SuggestedQuestions.forTable(view: view, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(Array(ids(chips).prefix(3)), ["table.whatToPlay", "table.whoIsWinning", "table.mustFollow"])
        XCTAssertEqual(chips[0].label, "What should I play?")
        XCTAssertEqual(chips[0].prompt, "East led K♠ K♠. What should I play from my hand, and why?")
        XCTAssertEqual(chips[2].prompt, "East led K♠ K♠ (pair of spades). What does the follow rule say I must play from my hand?")
        XCTAssertFalse(ids(chips).contains("table.ruffOrDiscard"), "you still hold spades")
        assertWellFormed(chips, count: 3...5, "follow")
    }

    func testOutOfTheLedSuitOffersTrumpOrDiscard() {
        let view = Kit.view(hand: [Kit.c(.four, .hearts), Kit.c(.three, .clubs)],
                            currentTrick: [Play(player: 1, cards: [Kit.c(.ace, .diamonds)])], turn: 0)
        let chips = SuggestedQuestions.forTable(view: view, hint: nil, selection: [], lastIllegal: nil)
        let ruff = chips.first { $0.id == "table.ruffOrDiscard" }
        XCTAssertEqual(ruff?.label, "Should I trump or discard?")
        XCTAssertEqual(ruff?.prompt, "I have no diamonds left. Should I trump this trick or throw away a low card?")
        // A trump lead never asks about trumping.
        let trumpLead = Kit.view(hand: [Kit.c(.three, .clubs)], currentTrick: [Play(player: 1, cards: [Kit.c(.ace, .hearts)])], turn: 0)
        XCTAssertFalse(ids(SuggestedQuestions.forTable(view: trumpLead, hint: nil, selection: [], lastIllegal: nil)).contains("table.ruffOrDiscard"))
    }

    func testYourTurnToLead() {
        let withAce = Kit.view(hand: [Kit.c(.three, .clubs), Kit.c(.ace, .clubs), Kit.c(.ace, .diamonds), Kit.c(.five, .hearts)],
                               leader: 0, turn: 0)
        let chips = SuggestedQuestions.forTable(view: withAce, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(ids(chips).first, "table.whatToLead")
        XCTAssertEqual(chips[0].label, "What should I lead?")
        // Plain suits in display order with ♥ trump: ♠, ♦, ♣, so the diamond ace is named.
        let safe = chips.first { $0.id == "table.isTopCardSafe" }
        XCTAssertEqual(safe?.label, "Is my A♦ safe to lead?")
        XCTAssertTrue(ids(chips).contains("table.leadTrumps"))
        assertWellFormed(chips, count: 3...5, "lead")

        // No plain ace: no ace chip. A trump ace (A♥) doesn't count.
        let noAce = Kit.view(hand: [Kit.c(.three, .clubs), Kit.c(.ace, .hearts)], leader: 0, turn: 0)
        XCTAssertFalse(ids(SuggestedQuestions.forTable(view: noAce, hint: nil, selection: [], lastIllegal: nil)).contains("table.isTopCardSafe"))

        // When aces are the trump rank, the top plain card is a king.
        let aceRank = Kit.view(trump: Trump(rank: .ace, suit: .hearts),
                               hand: [Kit.c(.ace, .spades), Kit.c(.king, .clubs)], leader: 0, turn: 0)
        let kingChip = SuggestedQuestions.forTable(view: aceRank, hint: nil, selection: [], lastIllegal: nil).first { $0.id == "table.isTopCardSafe" }
        XCTAssertEqual(kingChip?.label, "Is my K♣ safe to lead?")
    }

    func testIllegalAttemptComesFirst() {
        let hand = [Kit.c(.nine, .clubs), Kit.c(.three, .spades)]
        let view = Kit.view(hand: hand, currentTrick: [Play(player: 1, cards: [Kit.c(.four, .spades)])], turn: 0)
        let attempt = IllegalAttempt(cards: [hand[0]], error: .illegalFollow(.mustFollowSuit(.plain(.spades))))
        let hint = Kit.ladder(cards: [hand[1]], steps: 1)
        let chips = SuggestedQuestions.forTable(view: view, hint: hint, selection: [], lastIllegal: attempt)
        XCTAssertEqual(Array(ids(chips).prefix(3)), ["table.whyIllegal", "hint.why", "table.whatToPlay"])
        XCTAssertEqual(chips[0].label, "Why can't I play that?")
        XCTAssertEqual(chips[0].prompt, "I tried to play 9♣ but it wasn't allowed. Why not, and what can I play instead?")
        assertWellFormed(chips, count: 3...5, "illegal")
    }

    /// A rejected bury (the app reports those too) asks about burying, not playing.
    func testRejectedBuryAsksAboutBurying() throws {
        let deck = EngineTestSupport.deck(firstSeat: 0, seed: 41)
        var round = Round(trumpRank: .two, dealer: 0, deck: deck)
        round.dealAll()
        round.finishDealing()
        let seven = Array(round.trump.sorted(round.hands[0]).prefix(7))
        let attempt = IllegalAttempt(cards: seven, error: .invalidBury("Choose exactly 8 cards to bury (you chose 7)."))
        let chips = SuggestedQuestions.forTable(round: round, game: nil, hint: nil, selection: seven, lastIllegal: attempt)
        XCTAssertEqual(chips.first?.id, "table.whyIllegal")
        XCTAssertEqual(chips.first?.label, "Why can't I bury those?")
        XCTAssertEqual(chips.first?.prompt,
                       "I tried to bury \(round.trump.sorted(seven).shortText) but it wasn't allowed. Why not, and what should I bury instead?")
        assertWellFormed(chips, count: 3...5, "bury attempt", visible: Set(Kit.visibleCards(round).map(\.face)))

        let declaring = Kit.view(phase: .dealing, dealer: nil, hand: [Kit.c(.two, .spades)], turn: nil)
        let declared = SuggestedQuestions.forTable(view: declaring, hint: nil, selection: [],
                                                   lastIllegal: IllegalAttempt(cards: [Kit.c(.two, .spades)], error: .invalidDeclaration))
        XCTAssertEqual(declared.first?.label, "Why can't I declare that?")
        XCTAssertEqual(declared.first?.prompt, "I tried to declare with 2♠ but it wasn't allowed. Why not, and what could I declare instead?")
    }

    /// Once the game is over there is no next round to ask about.
    func testGameOverAsksHowTheGameWasWon() {
        let result = RoundResult(dealer: 0, declarerTeam: 0, trump: Kit.heartsTwo, trickPoints: 30, kittyPoints: 0, kittyMultiplier: 0,
                                 defenderPoints: 30, outcome: Scoring.outcome(defenderPoints: 30), kitty: [], lastTrickWinner: 0)
        var won = Kit.view(phase: .finished, dealer: 0, turn: nil, result: result, levels: [.ace, .nine])
        won.gameWinnerTeam = 0
        let chips = SuggestedQuestions.forTable(view: won, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertFalse(ids(chips).contains("table.whatNext"), "\(ids(chips))")
        let over = chips.first { $0.id == "table.gameOver" }
        XCTAssertEqual(over?.label, "How did we win the game?")
        XCTAssertEqual(over?.prompt, "My team just won the whole game. How does a team win the game in Shengji, and what decided it this round?")
        assertWellFormed(chips, count: 3...5, "game over")

        var lost = won
        lost.gameWinnerTeam = 1
        let lostChips = SuggestedQuestions.forTable(view: lost, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(lostChips.first { $0.id == "table.gameOver" }?.label, "How did they win the game?")

        // While the game goes on, the next round is the question.
        let ongoing = Kit.view(phase: .finished, dealer: 0, turn: nil, result: result)
        XCTAssertTrue(ids(SuggestedQuestions.forTable(view: ongoing, hint: nil, selection: [], lastIllegal: nil)).contains("table.whatNext"))
    }

    func testHintShowingComesFirst() {
        let hand = [Kit.c(.king, .spades), Kit.c(.three, .spades)]
        let view = Kit.view(hand: hand, currentTrick: [Play(player: 1, cards: [Kit.c(.four, .spades)])], turn: 0)
        let chips = SuggestedQuestions.forTable(view: view, hint: Kit.ladder(cards: [hand[0]], steps: 2), selection: [], lastIllegal: nil)
        XCTAssertEqual(ids(chips).first, "hint.why")
        XCTAssertEqual(chips[0].label, "Why is that the hint?")
        // A ladder with nothing shown yet adds no chip.
        let none = SuggestedQuestions.forTable(view: view, hint: Kit.ladder(cards: [hand[0]], steps: 0), selection: [], lastIllegal: nil)
        XCTAssertFalse(ids(none).contains("hint.why"))
    }

    func testSelectedCardsAreNamed() {
        let hand = [Kit.c(.king, .spades), Kit.c(.three, .spades), Kit.c(.five, .clubs)]
        let view = Kit.view(hand: hand, currentTrick: [Play(player: 1, cards: [Kit.c(.four, .spades)])], turn: 0)
        let chips = SuggestedQuestions.forTable(view: view, hint: nil, selection: [hand[0]], lastIllegal: nil)
        XCTAssertEqual(chips.first?.id, "table.isSelectionGood")
        XCTAssertEqual(chips.first?.label, "Is K♠ a good play?")
        XCTAssertEqual(chips.first?.prompt, "I'm thinking of playing K♠. Is that legal, and is it a good idea here?")
        // A long selection falls back to a generic label; cards not in hand are ignored.
        let many = Array(Deck.double().prefix(8))
        let wide = Kit.view(hand: many, leader: 0, turn: 0)
        let wideChips = SuggestedQuestions.forTable(view: wide, hint: nil, selection: many + [Kit.c(.ace, .hearts, 1)], lastIllegal: nil)
        XCTAssertEqual(wideChips.first?.label, "Is my selection a good play?")
        XCTAssertFalse(wideChips.first?.prompt.contains("A♥") ?? true)
    }

    func testDealingChips() throws {
        let mine = [Kit.c(.two, .spades), Kit.c(.two, .spades, 1)]
        let deck = EngineTestSupport.deck(hands: [mine, [], [], []], firstSeat: 0, seed: 3)
        var round = Round(trumpRank: .two, dealer: nil, deck: deck)
        for _ in 0..<8 { round.dealNext() }
        let chips = SuggestedQuestions.forTable(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(Array(ids(chips).prefix(2)), ["table.shouldDeclare", "table.whatDeclaringDoes"])
        XCTAssertEqual(chips[0].label, "Should I declare?")
        XCTAssertTrue(chips[0].prompt.hasPrefix("I could declare ♠ as trump by showing one 2♠, or ♠ as trump by showing a pair of 2♠."), chips[0].prompt)
        assertWellFormed(chips, count: 3...5, "dealing", visible: Set(Kit.visibleCards(round).map(\.face)))

        // Nothing to declare: the question still makes sense.
        var plain = Round(trumpRank: .two, dealer: nil, deck: EngineTestSupport.deck(hands: [[Kit.c(.three, .spades)], [], [], []], seed: 4))
        plain.dealNext()
        let plainChips = SuggestedQuestions.forTable(round: plain, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(plainChips.first?.prompt, "Should I declare trump with the cards I have so far? What would I need to declare?")
    }

    func testBuryingChips() throws {
        let deck = EngineTestSupport.deck(firstSeat: 0, seed: 6)
        var round = Round(trumpRank: .two, dealer: 0, deck: deck)
        round.dealAll()
        round.finishDealing()
        let mine = SuggestedQuestions.forTable(round: round, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(Array(ids(mine).prefix(2)), ["table.whatToBury", "table.whyBury"])
        XCTAssertEqual(mine[0].label, "What should I bury?")
        XCTAssertEqual(mine[1].label, "Why bury cards at all?")
        let picked = Array(round.hands[0].prefix(2))
        let withSelection = SuggestedQuestions.forTable(round: round, game: nil, hint: nil, selection: picked, lastIllegal: nil)
        XCTAssertEqual(withSelection.first?.label, "Are these good to bury?")
        // Its "Just tell me" follow-up is about burying, not playing.
        let followUps = SuggestedQuestions.followUps(after: withSelection.first)
        XCTAssertEqual(followUps.first?.label, "Just tell me")
        XCTAssertTrue(followUps.first?.prompt.contains("bury") ?? false, followUps.first?.prompt ?? "")
        XCTAssertFalse(followUps.first?.prompt.contains("play") ?? true, followUps.first?.prompt ?? "")

        var other = Round(trumpRank: .two, dealer: 3, deck: EngineTestSupport.deck(firstSeat: 3, seed: 6))
        other.dealAll()
        other.finishDealing()
        let theirs = SuggestedQuestions.forTable(round: other, game: nil, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(theirs.first?.id, "table.whileBurying")
        XCTAssertEqual(theirs.first?.prompt, "West is burying cards now. What are they doing, and why does the kitty matter to my team?")
        XCTAssertFalse(ids(theirs).contains("table.whatToBury"))
        assertWellFormed(theirs, count: 3...5, "burying other")
    }

    func testWaitingForBots() {
        let view = Kit.view(hand: [Kit.c(.three, .clubs)], currentTrick: [Play(player: 1, cards: [Kit.c(.four, .spades)])], turn: 2)
        let chips = SuggestedQuestions.forTable(view: view, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(Array(ids(chips).prefix(2)), ["table.whoIsWinning", "table.whatsTrump"])
        XCTAssertEqual(chips[0].label, "Who's winning this trick?")
        XCTAssertEqual(chips[1].label, "What's trump right now?")
        assertWellFormed(chips, count: 3...5, "waiting")
    }

    func testTrickPauseAsksWhyTheWinnerWon() {
        let finished = Kit.trick([Play(player: 1, cards: [Kit.c(.three, .clubs)]), Play(player: 2, cards: [Kit.c(.four, .clubs)]),
                                  Play(player: 3, cards: [Kit.c(.ace, .clubs)]), Play(player: 0, cards: [Kit.c(.five, .clubs)])])
        let pause = Kit.view(hand: [Kit.c(.three, .spades)], leader: 3, turn: 3, tricks: [finished])
        let chips = SuggestedQuestions.forTable(view: pause, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(chips.first?.id, "table.whyTrickWon")
        XCTAssertEqual(chips.first?.label, "Why did West win that?")
        XCTAssertEqual(chips.first?.prompt, "Why did West win the last trick (East led 3♣)? Walk me through what beat what.")

        // You won it and lead next: leading comes first, then the trick.
        let mine = Kit.trick([Play(player: 1, cards: [Kit.c(.three, .clubs)]), Play(player: 2, cards: [Kit.c(.four, .clubs)]),
                              Play(player: 3, cards: [Kit.c(.five, .clubs)]), Play(player: 0, cards: [Kit.c(.ace, .clubs)])])
        let lead = Kit.view(hand: [Kit.c(.three, .spades)], leader: 0, turn: 0, tricks: [mine])
        let leadChips = SuggestedQuestions.forTable(view: lead, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(Array(ids(leadChips).prefix(2)), ["table.whatToLead", "table.whyTrickWon"])
        XCTAssertEqual(leadChips[1].label, "Why did I win that?")
    }

    func testRoundOverChips() {
        func result(dealer: Int, defenders: Int, kittyPoints: Int, multiplier: Int) -> RoundResult {
            RoundResult(dealer: dealer, declarerTeam: Seats.team(of: dealer), trump: Kit.heartsTwo,
                        trickPoints: defenders - kittyPoints * multiplier, kittyPoints: kittyPoints, kittyMultiplier: multiplier,
                        defenderPoints: defenders, outcome: Scoring.outcome(defenderPoints: defenders), kitty: [],
                        lastTrickWinner: multiplier > 0 ? Seats.next(after: dealer) : dealer)
        }
        // We declared and held: a win, no kitty bonus.
        let held = Kit.view(phase: .finished, dealer: 0, turn: nil, result: result(dealer: 0, defenders: 40, kittyPoints: 15, multiplier: 0))
        let heldChips = SuggestedQuestions.forTable(view: held, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(heldChips.first?.label, "Why did we win that round?")
        XCTAssertFalse(ids(heldChips).contains("table.kittyScoring"))
        assertWellFormed(heldChips, count: 3...5, "held")

        // We declared, the defenders raided the kitty and took over: a loss with kitty scoring.
        let lost = Kit.view(phase: .finished, dealer: 2, turn: nil, result: result(dealer: 2, defenders: 100, kittyPoints: 20, multiplier: 4))
        let lostChips = SuggestedQuestions.forTable(view: lost, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(Array(ids(lostChips).prefix(2)), ["table.whyRoundResult", "table.kittyScoring"])
        XCTAssertEqual(lostChips[0].label, "Why did we lose that round?")
        XCTAssertEqual(lostChips[1].prompt, "The kitty held 20 points and counted ×4. How was that worked out?")

        // We defended and took over: a win.
        let won = Kit.view(phase: .finished, dealer: 1, turn: nil, result: result(dealer: 1, defenders: 120, kittyPoints: 0, multiplier: 2))
        let wonChips = SuggestedQuestions.forTable(view: won, hint: nil, selection: [], lastIllegal: nil)
        XCTAssertEqual(wonChips.first?.label, "Why did we win that round?")
        XCTAssertFalse(ids(wonChips).contains("table.kittyScoring"), "a kitty with no points needs no explaining")
    }

    func testEveryRandomStateGetsGoodChips() throws {
        var seen = Set<String>()
        for seed in UInt64(0)..<UInt64(300) {
            let state = try Kit.randomState(seed: seed &+ 7_000)
            let hand = state.round.hands[0]
            let hint = seed % 3 == 0 ? Kit.ladder(cards: Array(hand.prefix(1)), steps: Int(seed % 3) + 1) : nil
            let attempt = seed % 4 == 0 ? IllegalAttempt(cards: Array(hand.prefix(2)), error: .notYourTurn) : nil
            let selection = Array(hand.suffix(Int(seed % 3)))
            let chips = SuggestedQuestions.forTable(round: state.round, game: state.game, hint: hint, selection: selection, lastIllegal: attempt)
            assertWellFormed(chips, count: 3...5, "seed \(seed) \(state.label)", visible: Set(Kit.visibleCards(state.round).map(\.face)))
            if attempt != nil { XCTAssertEqual(chips.first?.id, "table.whyIllegal") }
            if attempt == nil, let hint, hint.step != nil { XCTAssertEqual(chips.first?.id, "hint.why") }
            // Deterministic.
            let again = SuggestedQuestions.forTable(round: state.round, game: state.game, hint: hint, selection: selection, lastIllegal: attempt)
            XCTAssertEqual(chips, again)
            seen.formUnion(ids(chips))
        }
        for id in ["table.whatToPlay", "table.whatToLead", "table.whoIsWinning", "table.shouldDeclare", "table.whatToBury",
                   "table.whyTrickWon", "table.whyRoundResult", "table.whyIllegal", "hint.why"] {
            XCTAssertTrue(seen.contains(id), "\(id) never offered")
        }
    }

    // MARK: Lessons, questions, follow-ups, hints

    func testLessonChips() {
        for lesson in Curriculum.lessons {
            for (index, page) in lesson.pages.enumerated() {
                for answered in [false, true] {
                    let chips = SuggestedQuestions.forLesson(lesson, pageIndex: index, answered: answered)
                    assertWellFormed(chips, count: 3...4, "\(lesson.id) page \(index)")
                    if case .predict = page {
                        if answered {
                            XCTAssertEqual(chips.first?.id, "lesson.whyAnswer")
                            XCTAssertEqual(chips.first?.label, "Why is that the answer?")
                            XCTAssertEqual(chips.count, 4)
                        } else {
                            XCTAssertEqual(chips.first?.id, "lesson.hint")
                            XCTAssertFalse(ids(chips).contains("lesson.whyAnswer"))
                            for chip in chips { XCTAssertFalse(chip.prompt.contains("right answer")) }
                        }
                    } else {
                        XCTAssertEqual(ids(chips), ["lesson.explainAgain", "lesson.example", "lesson.quiz"])
                        XCTAssertEqual(chips.map(\.label), ["Explain this another way", "Give me another example", "Quiz me on this"])
                    }
                }
            }
            assertWellFormed(SuggestedQuestions.forLesson(lesson, pageIndex: 500, answered: true), count: 3...4, "out of range")
        }
        let lesson5 = Curriculum.lessons[4]
        let explain = SuggestedQuestions.forLesson(lesson5, pageIndex: 2, answered: false)[0]
        XCTAssertEqual(explain.prompt, "Explain \"Follow suit\" from lesson 5, \"Following suit\" another way, with a different example.")
    }

    func testQuestionChips() {
        var rng = SeededGenerator(seed: 9)
        for fact in Curriculum.facts {
            let question = fact.question(rng: &rng)
            for answer in [nil, true, false] as [Bool?] {
                let chips = SuggestedQuestions.forQuestion(question, answeredCorrectly: answer)
                assertWellFormed(chips, count: 3...3, fact.id)
                if answer == nil {
                    XCTAssertEqual(chips.first?.label, "Give me a hint")
                    XCTAssertFalse(ids(chips).contains("question.why"))
                } else {
                    XCTAssertEqual(chips.map(\.label), ["Why?", "Give me a similar example", "What's the rule?"])
                }
            }
            let wrong = SuggestedQuestions.forQuestion(question, answeredCorrectly: false)[0]
            XCTAssertTrue(wrong.prompt.hasPrefix("I got this wrong"), wrong.prompt)
            let right = SuggestedQuestions.forQuestion(question, answeredCorrectly: true)[0]
            XCTAssertTrue(right.prompt.hasPrefix("I got this right"), right.prompt)
        }
    }

    func testFollowUps() {
        let play = SuggestedQuestion(id: "table.whatToPlay", label: "What should I play?", prompt: "What should I play?")
        XCTAssertEqual(SuggestedQuestions.followUps(after: play).map(\.label), ["Just tell me", "Why?", "Show an example"])
        for id in ["table.whatToLead", "table.whatToBury", "table.shouldDeclare", "table.isSelectionGood", "table.isBurySelectionGood"] {
            let question = SuggestedQuestion(id: id, label: "x", prompt: "x")
            XCTAssertEqual(SuggestedQuestions.followUps(after: question).count, 3, id)
        }
        for id in ["table.whoIsWinning", "lesson.quiz", "followUp.why"] {
            let question = SuggestedQuestion(id: id, label: "x", prompt: "x")
            XCTAssertEqual(SuggestedQuestions.followUps(after: question).map(\.label), ["Why?", "Show an example"], id)
        }
        XCTAssertEqual(SuggestedQuestions.followUps(after: nil).map(\.id), ["followUp.why", "followUp.example"])
        for chips in [SuggestedQuestions.followUps(after: play), SuggestedQuestions.followUps(after: nil)] {
            assertWellFormed(chips, count: 2...3, "follow-ups")
        }
    }

    func testExplainHintNamesStepAndText() {
        let king = Kit.c(.king, .spades)
        let nudge = SuggestedQuestions.explainHint(Kit.ladder(cards: [king], steps: 1))
        XCTAssertEqual(nudge.id, "hint.why")
        XCTAssertEqual(nudge.label, "Why is that the hint?")
        XCTAssertEqual(nudge.prompt, "My hint (step 1 of 3, what to notice) says: \"Look at who is winning this trick.\" Why does that matter here? Don't tell me the answer yet.")
        let principle = SuggestedQuestions.explainHint(Kit.ladder(cards: [king], steps: 2))
        XCTAssertEqual(principle.prompt, "My hint (step 2 of 3, the principle) says: \"When your partner is sure to win, give them points.\" Why does that principle apply here?")
        let show = SuggestedQuestions.explainHint(Kit.ladder(cards: [king], steps: 3))
        XCTAssertEqual(show.prompt, "My hint (step 3 of 3) points to K♠: \"Partner's ace is winning, so give them your king.\" Why is that the best choice here?")
        // The same chip sits under a bury hint, so it must not talk about playing the cards.
        let buryCards = Array(Deck.double().prefix(8))
        let bury = SuggestedQuestions.explainHint(Kit.ladder(cards: buryCards, steps: 3, reason: "Bury your short clubs to make a void."))
        XCTAssertFalse(bury.prompt.contains("play"), bury.prompt)
        XCTAssertTrue(bury.prompt.contains(buryCards.shortText), bury.prompt)
        let before = SuggestedQuestions.explainHint(Kit.ladder(cards: [king], steps: 0))
        XCTAssertEqual(before.label, "What should I notice?")
        // Very long hint text is cut to keep the prompt short; text without an end mark gets one.
        let long = SuggestedQuestions.explainHint(Kit.ladder(cards: [king], steps: 1, nudge: String(repeating: "Look closely ", count: 80)))
        XCTAssertLessThanOrEqual(long.prompt.count, SuggestedQuestions.maxPromptLength)
        let bare = SuggestedQuestions.explainHint(Kit.ladder(cards: [king], steps: 1, nudge: "Count the trumps"))
        XCTAssertTrue(bare.prompt.contains("\"Count the trumps.\" Why"), bare.prompt)
    }
}
