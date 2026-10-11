import Foundation
import XCTest
@testable import ShengjiCore

/// Checks the drill generators (Learning/Drills.swift) over 1,000 seeds for every skill and difficulty.
///
/// Every answer is recomputed here from the question's own data (the numbers in the prompt, the cards in
/// the visual, the trump badge) with the engine (`Rules`, `Scoring`, `Combos`) and with small referees
/// written from DESIGN.md (`DrillJudge`, plus `ReferenceRules` and `EngineTestSupport` from the other test
/// files), never from the generator's own bookkeeping.
final class DrillsTests: XCTestCase {
    static let seedsPerLevel = 1_000
    static let levels = 1...3

    // MARK: Generation (shared by the tests; generation is deterministic)

    static func seed(_ skill: SkillID, level: Int, index: Int) -> UInt64 {
        let skillIndex = UInt64(SkillID.allCases.firstIndex(of: skill) ?? 0)
        return (skillIndex << 40) | (UInt64(level) << 32) | UInt64(index)
    }

    static func generate(_ skill: SkillID, level: Int, index: Int) -> Question {
        var rng = SeededGenerator(seed: seed(skill, level: level, index: index))
        return Drills.make(skill, difficulty: level, rng: &rng)
    }

    private static var cache: [String: [Question]] = [:]

    static func questions(_ skill: SkillID, level: Int) -> [Question] {
        let key = "\(skill.rawValue)#\(level)"
        if let cached = cache[key] { return cached }
        let made = (0..<seedsPerLevel).map { generate(skill, level: level, index: $0) }
        cache[key] = made
        return made
    }

    /// Every (skill, level, question) triple.
    static func all(_ skill: SkillID) -> [(level: Int, question: Question)] {
        levels.flatMap { level in questions(skill, level: level).map { (level, $0) } }
    }

    static func correctLabel(_ q: Question) -> String {
        q.choices.indices.contains(q.correctChoice) ? q.choices[q.correctChoice].label : "<none>"
    }

    // MARK: Titles

    func testTitlesAreShortUniqueAndPlain() {
        let expected: [SkillID: String] = [
            .pointValue: "Card points", .countPoints: "Count the points", .isTrump: "Spot the trumps",
            .trumpOrder: "Trump order", .cardBeats: "What beats what", .isPair: "Pairs", .isTractor: "Tractors",
            .trickWinner: "Who wins the trick", .legalFollow: "Legal plays", .levelOutcome: "Scoring a round",
            .kittyBonus: "The kitty bonus", .bestPlay: "Smart plays",
        ]
        for skill in SkillID.allCases {
            XCTAssertEqual(skill.title, expected[skill], "\(skill)")
            XCTAssertLessThanOrEqual(skill.title.count, 24, "\(skill)")
            XCTAssertFalse(skill.title.contains("\u{2014}"), "\(skill)")
        }
        XCTAssertEqual(Set(SkillID.allCases.map(\.title)).count, SkillID.allCases.count)
    }

    // MARK: Shape of every question

    func testEveryQuestionIsWellFormed() {
        let pinyin = Dictionary(uniqueKeysWithValues: Curriculum.glossary.map { ($0.chinese, $0.pinyin) })
        for skill in SkillID.allCases {
            for (level, q) in Self.all(skill) {
                let context = "\(skill) L\(level) \(q.id): \(q.prompt)"
                XCTAssertEqual(q.itemID, skill.itemID, context)
                XCTAssertTrue(q.id.hasPrefix(skill.rawValue + "."), context)
                XCTAssertEqual(q.difficulty, level, context)

                // Choices: 2 to 4, one correct, unique, captioned by their cards.
                XCTAssertTrue((2...4).contains(q.choices.count), context)
                XCTAssertTrue(q.choices.indices.contains(q.correctChoice), context)
                XCTAssertEqual(Set(q.choices.map(\.label)).count, q.choices.count, "\(context) repeats a label")
                let cardSets = q.choices.filter { !$0.cards.isEmpty }.map { $0.cards.map(\.id).sorted() }
                XCTAssertEqual(Set(cardSets).count, cardSets.count, "\(context) repeats a card choice")
                for choice in q.choices {
                    XCTAssertFalse(choice.label.isEmpty, context)
                    DrillJudge.checkVisualCards(choice.cards, context: "\(context) choice \(choice.label)")
                    if !choice.cards.isEmpty {
                        XCTAssertTrue(DrillJudge.captionMatches(choice), "\(context): caption \(choice.label)")
                    }
                }
                // All card choices or all text choices.
                let withCards = q.choices.filter { !$0.cards.isEmpty }.count
                XCTAssertTrue(withCards == 0 || withCards == q.choices.count, context)

                // Text: short, plain, no em-dash, balanced bold, Chinese with its pinyin.
                XCTAssertFalse(q.prompt.isEmpty, context)
                XCTAssertLessThanOrEqual(q.prompt.count, 120, context)
                XCTAssertFalse(q.explanation.isEmpty, context)
                XCTAssertLessThanOrEqual(CurriculumScan.words(q.explanation), 50, "\(context) -> \(q.explanation)")
                for text in [q.prompt, q.explanation] + q.choices.map(\.label) {
                    XCTAssertFalse(text.contains("\u{2014}"), "em-dash in \(text)")
                    XCTAssertFalse(text.contains("--"), "double hyphen in \(text)")
                    XCTAssertEqual((text.components(separatedBy: "**").count - 1) % 2, 0, "unbalanced bold in \(text)")
                    for run in CurriculumScan.chineseRuns(in: text) {
                        guard let expected = pinyin[run.term] else {
                            XCTFail("\(run.term) is not in the glossary: \(text)")
                            continue
                        }
                        XCTAssertTrue(run.after.hasPrefix(" (\(expected))"), "\(run.term) needs (\(expected)): \(text)")
                    }
                }

                // Trump badge whenever trump matters, and the prompt states it.
                switch skill {
                case .countPoints, .levelOutcome:
                    XCTAssertNil(q.trump, context)
                case .pointValue:
                    if let trump = q.trump {
                        XCTAssertTrue(q.prompt.hasPrefix(DrillJudge.trumpLine(trump)), context)
                    } else {
                        XCTAssertFalse(q.prompt.contains("rank"), context)
                    }
                case .kittyBonus:
                    XCTAssertNotNil(q.trump, context)
                default:
                    guard let trump = q.trump else {
                        XCTFail("\(context) needs a trump badge")
                        continue
                    }
                    XCTAssertTrue(q.prompt.hasPrefix(DrillJudge.trumpLine(trump)), context)
                }

                DrillJudge.checkVisual(q, context: context)
            }
        }
    }

    func testIdsAreUniquePerGeneration() {
        for skill in SkillID.allCases {
            let ids = Self.all(skill).map(\.question.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(skill)")
        }
        var rng = SeededGenerator(seed: 99)
        let a = Drills.make(.isTrump, difficulty: 2, rng: &rng)
        let b = Drills.make(.isTrump, difficulty: 2, rng: &rng)
        XCTAssertNotEqual(a.id, b.id, "consecutive questions from one generator get different ids")
    }

    // MARK: Determinism and speed

    func testSameSeedGivesTheSameQuestionAndGenerationIsFast() {
        let limit = 0.020
        for skill in SkillID.allCases {
            for level in Self.levels {
                let cached = Self.questions(skill, level: level)
                var slowest = 0.0
                for index in 0..<Self.seedsPerLevel {
                    var best = Double.infinity
                    var again: Question?
                    // A busy machine can stall one call: time it again before calling it slow.
                    for _ in 0..<3 where best >= limit {
                        let start = Date()
                        again = Self.generate(skill, level: level, index: index)
                        best = min(best, Date().timeIntervalSince(start))
                    }
                    slowest = max(slowest, best)
                    XCTAssertEqual(again, cached[index], "\(skill) L\(level) seed \(index) is not deterministic")
                }
                XCTAssertLessThan(slowest, limit, "\(skill) L\(level): slowest generation \(slowest * 1000) ms")
            }
        }
    }

    func testDifficultyIsClampedToOneToThree() {
        for skill in SkillID.allCases {
            var rng = SeededGenerator(seed: 5)
            XCTAssertEqual(Drills.make(skill, difficulty: 0, rng: &rng).difficulty, 1, "\(skill)")
            XCTAssertEqual(Drills.make(skill, difficulty: -4, rng: &rng).difficulty, 1, "\(skill)")
            XCTAssertEqual(Drills.make(skill, difficulty: 9, rng: &rng).difficulty, 3, "\(skill)")
        }
    }

    func testCurriculumAndPracticeSessionsServeEverySkill() {
        for skill in SkillID.allCases {
            for level in Self.levels {
                var rng = SeededGenerator(seed: UInt64(level))
                let q = Curriculum.question(for: skill.itemID, difficulty: level, rng: &rng)
                XCTAssertEqual(q?.itemID, skill.itemID)
                XCTAssertEqual(q?.difficulty, level)
            }
        }
        // A free-practice session over every skill draws real drill questions.
        PracticeSession.questionProvider = PracticeSession.curriculumQuestionProvider
        var rng = SeededGenerator(seed: 21)
        let progress = LearnerProgress()
        var session = PracticeSession(kind: .freePractice(skills: SkillID.allCases), progress: progress, now: Date(),
                                      maxItems: 12, rng: &rng)
        var seen: Set<String> = []
        while let q = session.next(progress: progress, rng: &rng) {
            XCTAssertNotNil(SkillID(itemID: q.itemID), q.itemID)
            XCTAssertTrue(q.choices.indices.contains(q.correctChoice))
            seen.insert(q.itemID)
            session.answer(correct: true)
        }
        XCTAssertEqual(seen.count, 12)
    }

    // MARK: Balance and variety

    func testCorrectAnswerPositionsAreBalanced() {
        for skill in SkillID.allCases {
            var counts: [Int: [Int]] = [:]
            for (_, q) in Self.all(skill) {
                var row = counts[q.choices.count] ?? Array(repeating: 0, count: q.choices.count)
                row[q.correctChoice] += 1
                counts[q.choices.count] = row
            }
            for (size, row) in counts {
                let total = row.reduce(0, +)
                guard total >= 300 else { continue }
                // An unbiased shuffle puts the answer in each position with chance 1/size: allow 4 standard
                // deviations (a ±25% band let a clearly favoured position through).
                let share = 1.0 / Double(size)
                let expected = Double(total) * share
                let spread = 4 * (Double(total) * share * (1 - share)).squareRoot()
                for (position, count) in row.enumerated() {
                    XCTAssertLessThanOrEqual(abs(Double(count) - expected), spread,
                                             "\(skill): \(size) choices, position \(position) \(row)")
                }
            }
        }
    }

    func testQuestionsVaryAcrossSeeds() {
        // Distinct situations (prompt, picture and set of answers), ignoring the order of the choices.
        let minimum: [SkillID: [Int]] = [
            .pointValue: [40, 100, 100], .countPoints: [400, 700, 800], .isTrump: [100, 150, 150],
            .trumpOrder: [150, 300, 300], .cardBeats: [400, 500, 500], .isPair: [100, 200, 200],
            .isTractor: [150, 250, 250], .trickWinner: [700, 800, 800], .legalFollow: [700, 800, 800],
            .levelOutcome: [60, 80, 120], .kittyBonus: [300, 600, 700], .bestPlay: [600, 700, 700],
        ]
        for skill in SkillID.allCases {
            for level in Self.levels {
                let signatures = Set(Self.questions(skill, level: level).map { q in
                    "\(q.prompt)|\(q.visual)|\(q.choices.map(\.label).sorted())"
                })
                let floor = minimum[skill]?[level - 1] ?? 300
                XCTAssertGreaterThanOrEqual(signatures.count, floor, "\(skill) L\(level): only \(signatures.count) distinct")
            }
        }
    }

    func testYesNoSkillsAreBalanced() {
        for skill in [SkillID.isTrump, .isPair, .isTractor] {
            for level in Self.levels {
                let qs = Self.questions(skill, level: level)
                let yes = qs.filter { ["Yes", "Trump"].contains(Self.correctLabel($0)) }.count
                let share = Double(yes) / Double(qs.count)
                XCTAssertTrue((0.35...0.65).contains(share), "\(skill) L\(level): \(share) answered yes")
            }
        }
    }

    // MARK: Card points

    func testPointValueAnswers() {
        for (level, q) in Self.all(.pointValue) {
            guard case let .cards(cards) = q.visual, cards.count == 1 else {
                XCTFail("pointValue shows one card: \(q.visual)")
                continue
            }
            XCTAssertEqual(Set(q.choices.map(\.label)), ["0", "5", "10"])
            XCTAssertEqual(Self.correctLabel(q), String(DrillJudge.points(cards[0])), "L\(level) \(cards[0])")
        }
        // The common point cards and their lookalikes both come up.
        let shown = Self.all(.pointValue).compactMap { item -> Rank? in
            if case let .cards(cards) = item.question.visual { return cards.first?.rank }
            return nil
        }
        for rank in [Rank.five, .ten, .king, .four, .six, .nine, .queen, .ace] {
            XCTAssertTrue(shown.contains(rank), "\(rank) never shown")
        }
    }

    func testCountPointsAnswers() {
        for (level, q) in Self.all(.countPoints) {
            guard case let .cards(cards) = q.visual else {
                XCTFail("countPoints shows cards")
                continue
            }
            let sizes: ClosedRange<Int> = level == 1 ? 3...4 : (level == 2 ? 4...6 : 5...7)
            XCTAssertTrue(sizes.contains(cards.count), "L\(level): \(cards.count) cards")
            let sum = cards.map(DrillJudge.points).reduce(0, +)
            XCTAssertEqual(Self.correctLabel(q), String(sum), "L\(level) \(cards.shortText)")
            // The worked sum lists exactly the point cards.
            if sum == 0 {
                XCTAssertTrue(q.explanation.contains("**0 points**"), q.explanation)
            } else {
                let terms = cards.filter { DrillJudge.points($0) > 0 }.map { "\($0.description) (\(DrillJudge.points($0)))" }
                XCTAssertTrue(q.explanation.contains(terms.joined(separator: " + ") + " = **\(sum)**"), q.explanation)
            }
            XCTAssertEqual(q.choices.count, 4)
            for choice in q.choices {
                guard let value = Int(choice.label) else {
                    XCTFail("not a number: \(choice.label)")
                    continue
                }
                XCTAssertTrue(value >= 0 && value % 5 == 0, choice.label)
                XCTAssertLessThanOrEqual(abs(value - sum), 40, "implausible distractor \(value) for \(sum)")
            }
        }
    }

    // MARK: Trumps

    func testIsTrumpAnswers() {
        for (level, q) in Self.all(.isTrump) {
            guard let trump = q.trump, case let .cards(cards) = q.visual, cards.count == 1 else {
                XCTFail("isTrump shows one card with a trump badge")
                continue
            }
            let card = cards[0]
            let isTrump = DrillJudge.isTrump(card, trump)
            XCTAssertEqual(isTrump, trump.isTrump(card))
            XCTAssertEqual(Set(q.choices.map(\.label)), ["Trump", "Not trump"])
            XCTAssertEqual(Self.correctLabel(q), isTrump ? "Trump" : "Not trump", "L\(level) \(trump) \(card)")
            XCTAssertTrue(q.explanation.hasPrefix(isTrump ? "Yes." : "No."), q.explanation)
            // The card shown is not one of yours: "the 7♠", never "your 7♠".
            XCTAssertFalse(q.explanation.contains("Your ") || q.explanation.contains(" your "), q.explanation)
            if level == 1 {
                XCTAssertNotNil(trump.suit)
                XCTAssertFalse(card.isJoker)
                XCTAssertFalse(card.rank == trump.rank && card.suit != trump.suit, "off-suit rank cards start at level 2")
            }
        }
        // The misconceptions all come up: off-suit rank cards, jokers, no-trump rounds.
        let level2 = Self.questions(.isTrump, level: 2).compactMap(DrillJudge.cardAndTrump)
        XCTAssertTrue(level2.contains { $0.card.rank == $0.trump.rank && $0.card.suit != $0.trump.suit })
        XCTAssertTrue(level2.contains { $0.card.isJoker })
        XCTAssertTrue(Self.questions(.isTrump, level: 3).contains { $0.trump?.suit == nil })
    }

    func testTrumpOrderAnswers() {
        for (level, q) in Self.all(.trumpOrder) {
            guard let trump = q.trump else {
                XCTFail("trumpOrder needs a trump")
                continue
            }
            XCTAssertTrue((3...4).contains(q.choices.count))
            let keys = q.choices.map { choice -> Int in
                guard choice.cards.count == 1, let key = DrillJudge.orderKey(choice.cards[0], trump) else {
                    XCTFail("L\(level): \(choice.label) is not a single trump with \(trump)")
                    return -1
                }
                return key
            }
            guard let top = keys.max() else { continue }
            XCTAssertEqual(keys.filter { $0 == top }.count, 1, "L\(level) \(trump): tie on top \(q.choices.map(\.label))")
            XCTAssertEqual(keys[q.correctChoice], top, "L\(level) \(trump): \(q.choices.map(\.label))")
            // The engine agrees.
            let strengths = q.choices.map { trump.strength($0.cards[0]) }
            XCTAssertEqual(strengths[q.correctChoice], strengths.max())
            if level == 1 { XCTAssertFalse(q.choices.contains { $0.cards[0].isJoker }) }
            // The explanation names the top card.
            XCTAssertTrue(q.explanation.contains(DrillJudge.spoken(q.choices[q.correctChoice].cards[0])), q.explanation)
        }
        XCTAssertTrue(Self.questions(.trumpOrder, level: 3).contains { $0.trump?.suit == nil })
    }

    // MARK: What beats what

    func testCardBeatsAnswers() {
        var kinds: Set<String> = []
        for (level, q) in Self.all(.cardBeats) {
            guard let trump = q.trump, case let .trick(plays) = q.visual, plays.count == 1, plays[0].player == 3,
                  plays[0].cards.count == 1 else {
                XCTFail("cardBeats shows West's single lead")
                continue
            }
            let lead = plays[0].cards
            let hand = q.choices.flatMap(\.cards)
            XCTAssertEqual(hand.count, 3)
            var winners: [Int] = []
            for (index, choice) in q.choices.enumerated() {
                XCTAssertEqual(choice.cards.count, 1)
                let legal = Rules.validateFollow(choice.cards, hand: hand, lead: lead, trump: trump) == nil
                XCTAssertEqual(legal, ReferenceRules.isLegalFollow(choice.cards, hand: hand, lead: lead, trump: trump))
                let trick = plays + [Play(player: Seats.human, cards: choice.cards)]
                let wins = Rules.winningIndex(trick, trump: trump) == 1
                XCTAssertEqual(wins, ReferenceRules.winningIndex(trick, trump: trump) == 1)
                if legal && wins { winners.append(index) }
            }
            XCTAssertEqual(winners, [q.correctChoice], "L\(level) \(q.prompt) \(q.choices.map(\.label))")
            XCTAssertTrue(q.explanation.lowercased().contains(Self.correctLabel(q).lowercased()), q.explanation)

            // Say so when you can't follow; and name a trump lead.
            let ledGroup = trump.group(lead[0])
            let holdsLed = hand.contains { trump.group($0) == ledGroup }
            if !ledGroup.isTrump {
                XCTAssertEqual(q.prompt.contains("you have no"), !holdsLed, q.prompt)
                kinds.insert(holdsLed ? "follow" : "void")
            } else {
                XCTAssertTrue(q.prompt.contains(", a trump"), q.prompt)
                kinds.insert("trump lead")
            }
            // Lookalike distractors: a trump-rank card that looks like the led suit.
            if q.choices.contains(where: { $0.cards[0].rank == trump.rank && $0.cards[0].suit == lead[0].suit }) {
                kinds.insert("rank card of the led suit")
            }
            if level == 1 {
                XCTAssertNotNil(trump.suit)
                XCTAssertFalse(ledGroup.isTrump)
            }
        }
        XCTAssertEqual(kinds, ["follow", "void", "trump lead", "rank card of the led suit"])
        XCTAssertTrue(Self.questions(.cardBeats, level: 3).contains { $0.trump?.suit == nil })
    }

    // MARK: Pairs and tractors

    func testIsPairAnswers() {
        for (level, q) in Self.all(.isPair) {
            guard let trump = q.trump, case let .cards(cards) = q.visual, cards.count == 2 else {
                XCTFail("isPair shows two cards")
                continue
            }
            let isPair = cards[0].face == cards[1].face && cards[0].copy != cards[1].copy
            XCTAssertEqual(isPair, Combos.shape(of: cards, trump: trump) == .pair)
            XCTAssertEqual(Self.correctLabel(q), isPair ? "Yes" : "No", "L\(level) \(cards.shortText)")
            XCTAssertTrue(q.explanation.hasPrefix(isPair ? "Yes." : "No."), q.explanation)
        }
        // Lookalikes: equal rank cards of two suits, and a small joker with a big joker.
        let level2 = Self.questions(.isPair, level: 2)
        XCTAssertTrue(level2.contains { q in
            guard case let .cards(c) = q.visual, let trump = q.trump else { return false }
            return c[0].rank == trump.rank && c[1].rank == trump.rank && c[0].suit != c[1].suit
        })
        XCTAssertTrue(level2.contains { q in
            guard case let .cards(c) = q.visual else { return false }
            return Set(c.map(\.face)) == [.smallJoker, .bigJoker]
        })
    }

    func testIsTractorAnswers() {
        var sizes: Set<Int> = []
        for (level, q) in Self.all(.isTractor) {
            guard let trump = q.trump, case let .cards(cards) = q.visual else {
                XCTFail("isTractor shows cards")
                continue
            }
            XCTAssertTrue(level == 3 ? [4, 6].contains(cards.count) : cards.count == 4, "L\(level) \(cards.count) cards")
            sizes.insert(cards.count)
            let isTractor = DrillJudge.isTractor(cards, trump: trump)
            XCTAssertEqual(isTractor, Combos.shape(of: cards, trump: trump) == .tractor(cards.count / 2))
            XCTAssertEqual(Self.correctLabel(q), isTractor ? "Yes" : "No", "L\(level) \(trump) \(cards.shortText)")
            XCTAssertTrue(q.explanation.hasPrefix(isTractor ? "Yes." : "No."), q.explanation)
        }
        XCTAssertEqual(sizes, [4, 6])
        // Key cases: across the skipped rank (yes), equal rank pairs (no), jokers (yes), no-trump rounds.
        let higher = Self.questions(.isTractor, level: 2) + Self.questions(.isTractor, level: 3)
        let pictures = higher.compactMap { q -> (cards: [Card], trump: Trump, yes: Bool)? in
            guard case let .cards(cards) = q.visual, let trump = q.trump else { return nil }
            return (cards, trump, Self.correctLabel(q) == "Yes")
        }
        XCTAssertTrue(pictures.contains { p in
            let ranks = Set(p.cards.compactMap(\.rank).map(\.rawValue))
            return p.yes && ranks.count == 2 && ranks.contains(p.trump.rank.rawValue - 1)
                && ranks.contains(p.trump.rank.rawValue + 1)
        }, "a tractor across the skipped trump rank")
        XCTAssertTrue(pictures.contains { p in
            !p.yes && p.cards.allSatisfy { $0.rank == p.trump.rank && $0.suit != p.trump.suit }
        }, "equal rank-card pairs")
        XCTAssertTrue(pictures.contains { p in p.yes && p.cards.contains { $0.isJoker } })
        XCTAssertTrue(pictures.contains { $0.trump.suit == nil })
    }

    // MARK: Tricks

    func testTrickWinnerAnswers() {
        var leadSizes: [Int: Set<Int>] = [:]
        var instructive: [Int: Int] = [:]
        for (level, q) in Self.all(.trickWinner) {
            guard let trump = q.trump, case let .trick(plays) = q.visual, plays.count == 4 else {
                XCTFail("trickWinner shows a full trick")
                continue
            }
            XCTAssertEqual(Set(q.choices.map(\.label)), Set(Seats.all.map(Seats.name)))
            let winner = Rules.winningIndex(plays, trump: trump)
            XCTAssertEqual(ReferenceRules.winningIndex(plays, trump: trump), winner, q.prompt)
            XCTAssertEqual(EngineTestSupport.referenceWinner(plays, trump: trump), winner, q.prompt)
            let name = Seats.name(plays[winner].player)
            XCTAssertEqual(Self.correctLabel(q), name, "L\(level) \(q.prompt) \(plays.map { $0.cards.shortText })")
            XCTAssertTrue(q.explanation.hasPrefix(name + " win"), q.explanation)

            let lead = plays[0].cards
            leadSizes[level, default: []].insert(lead.count)
            XCTAssertNotNil(Combos.shape(of: lead, trump: trump), "the lead is one single, pair or tractor")
            let ledGroup = Combos.group(of: lead, trump: trump)
            if level == 1 {
                XCTAssertNotNil(ledGroup?.plainSuit, "difficulty 1 leads a plain suit: \(q.prompt)")
                let offSuitRank = plays.flatMap(\.cards).filter { $0.rank == trump.rank && $0.suit != trump.suit }
                XCTAssertTrue(offSuitRank.isEmpty, "difficulty 1 keeps off-suit rank cards out: \(q.prompt)")
            }
            // A ruff with a rank card printed in the led suit says that card is a trump.
            if let ledSuit = ledGroup?.plainSuit,
               plays[winner].cards.contains(where: { $0.rank == trump.rank && $0.suit == ledSuit }) {
                XCTAssertTrue(q.explanation.contains("is a trump this round, not a \(ledSuit.singularName)"), q.explanation)
            }
            if DrillJudge.isInstructive(plays, trump: trump) { instructive[level, default: 0] += 1 }
        }
        XCTAssertEqual(leadSizes[1], [1, 2])
        XCTAssertEqual(leadSizes[2], [1, 2, 4])
        XCTAssertEqual(leadSizes[3], [1, 2, 4, 6])
        // Biased towards ruffs, over-ruffs, unmatched shapes, ties and discards.
        for level in Self.levels {
            XCTAssertGreaterThan(instructive[level] ?? 0, Self.seedsPerLevel / 2, "L\(level)")
        }
        XCTAssertTrue(Self.questions(.trickWinner, level: 3).contains { $0.trump?.suit == nil })
    }

    func testLegalFollowAnswers() {
        var leadSizes: [Int: Set<Int>] = [:]
        var violations: Set<String> = []
        var misreadShown = false
        for (level, q) in Self.all(.legalFollow) {
            guard let trump = q.trump, case let .handAndLead(hand, lead, leader) = q.visual else {
                XCTFail("legalFollow shows hand and lead")
                continue
            }
            XCTAssertTrue((8...12).contains(hand.count), "L\(level): hand of \(hand.count)")
            XCTAssertTrue((1...3).contains(leader))
            XCTAssertTrue((3...4).contains(q.choices.count), "\(q.choices.count) choices")
            leadSizes[level, default: []].insert(lead.count)
            var legal: [Int] = []
            for (index, choice) in q.choices.enumerated() {
                let violation = Rules.validateFollow(choice.cards, hand: hand, lead: lead, trump: trump)
                let referee = ReferenceRules.isLegalFollow(choice.cards, hand: hand, lead: lead, trump: trump)
                XCTAssertEqual(violation == nil, referee, "\(q.prompt) \(choice.label)")
                if let violation {
                    violations.insert(DrillJudge.kind(of: violation))
                } else {
                    legal.append(index)
                }
                if let ledSuit = lead.first.flatMap({ trump.group($0).plainSuit }),
                   choice.cards.contains(where: { $0.rank == trump.rank && $0.suit == ledSuit }) {
                    misreadShown = true
                }
            }
            XCTAssertEqual(legal, [q.correctChoice], "L\(level) \(q.prompt) hand \(hand.shortText) \(q.choices.map(\.label))")
        }
        XCTAssertEqual(leadSizes[1], [1, 2])
        XCTAssertTrue(leadSizes[3]?.contains(4) ?? false)
        // The distractors embody each common mistake.
        XCTAssertEqual(violations, ["follow suit", "pairs", "tractor"])
        XCTAssertTrue(misreadShown, "a rank card of the led suit's printed suit is offered")
    }

    // MARK: Scoring

    func testLevelOutcomeAnswers() {
        var largest = 0
        for (level, q) in Self.all(.levelOutcome) {
            guard let points = DrillJudge.firstNumber(in: q.prompt) else {
                XCTFail("no points in \(q.prompt)")
                continue
            }
            largest = max(largest, points)
            XCTAssertEqual(points % 5, 0)
            if level == 1 { XCTAssertLessThanOrEqual(points, 155) }
            let expected = DrillJudge.outcomeText(points)
            XCTAssertEqual(Self.correctLabel(q), expected, "L\(level) \(points)")
            let outcome = Scoring.outcome(defenderPoints: points)
            XCTAssertEqual(DrillJudge.outcomeText(hold: outcome.declarersHold, levels: outcome.levels), expected)
            XCTAssertEqual(q.choices.count, 4)
            for choice in q.choices {
                XCTAssertTrue(DrillJudge.allOutcomeTexts.contains(choice.label), choice.label)
            }
            // The explanation names the band the points fall in.
            if points == 0 {
                XCTAssertTrue(q.explanation.contains("**0**"), q.explanation)
            } else {
                let bands = DrillJudge.captureAll(#"\*\*(\d+) to (\d+)\*\*"#, in: q.explanation)
                XCTAssertEqual(bands.count, 1, q.explanation)
                if let band = bands.first, let low = Int(band[0]), let high = Int(band[1]) {
                    XCTAssertTrue((low...high).contains(points), "\(points): \(q.explanation)")
                    XCTAssertEqual(DrillJudge.outcomeText(low), expected, q.explanation)
                    XCTAssertEqual(DrillJudge.outcomeText(high), expected, q.explanation)
                }
            }
            // Tricks hold only 200 points: more than that needs the kitty bonus, so nobody "captures" it.
            if points > Scoring.totalPoints {
                XCTAssertFalse(q.prompt.contains("captures"), q.prompt)
            }
        }
        XCTAssertGreaterThanOrEqual(largest, 200)
        // Boundaries come up often.
        let boundaries: Set<Int> = [0, 35, 40, 75, 80, 115, 120, 155]
        let onBoundary = Self.questions(.levelOutcome, level: 2).filter { q in
            DrillJudge.firstNumber(in: q.prompt).map(boundaries.contains) ?? false
        }
        XCTAssertGreaterThan(onBoundary.count, Self.seedsPerLevel / 3)
    }

    func testKittyBonusAnswers() {
        var shapes: Set<Int> = []
        var throwShown = false
        for (level, q) in Self.all(.kittyBonus) {
            guard let trump = q.trump, case let .cards(lead) = q.visual, let kitty = DrillJudge.firstNumber(in: q.prompt) else {
                XCTFail("kittyBonus states the kitty and shows the lead")
                continue
            }
            let defendersWin = q.prompt.hasPrefix("Defenders win the last trick")
            XCTAssertNotEqual(defendersWin, q.prompt.hasPrefix("Declarers win the last trick"), q.prompt)
            // Short enough to read at a glance (the brief's 90-character ideal).
            XCTAssertLessThanOrEqual(q.prompt.count, 90, q.prompt)
            XCTAssertGreaterThan(kitty, 0)
            let multiplier = DrillJudge.kittyMultiplier(lead, trump: trump)
            XCTAssertEqual(multiplier, Scoring.kittyMultiplier(lastLead: lead, trump: trump))
            let expected = defendersWin ? kitty * multiplier : 0
            XCTAssertEqual(Self.correctLabel(q), String(expected), "L\(level) \(q.prompt) \(lead.shortText)")
            XCTAssertNotNil(Combos.group(of: lead, trump: trump), "a lead is all one suit or all trump: \(lead.shortText)")
            if defendersWin {
                XCTAssertTrue(q.explanation.contains("**×\(multiplier)**"), q.explanation)
                XCTAssertTrue(q.explanation.contains("\(kitty) × \(multiplier) = **\(expected)**"), q.explanation)
            } else {
                XCTAssertTrue(q.explanation.contains("**0**") && q.explanation.contains("**last trick**"), q.explanation)
            }
            XCTAssertEqual(q.choices.count, 4)
            shapes.insert(multiplier)
            if Combos.decompose(lead, trump: trump).count > 1 { throwShown = true }
            if level == 1 { XCTAssertTrue([2, 4].contains(multiplier)) }
        }
        XCTAssertEqual(shapes, [2, 4, 8, 12])
        XCTAssertTrue(throwShown, "a throw's largest part sets the multiplier")
    }

    // MARK: Smart plays

    func testBestPlayAnswers() {
        var principles: [Int: Set<String>] = [:]
        for (level, q) in Self.all(.bestPlay) {
            guard let trump = q.trump else {
                XCTFail("bestPlay needs a trump badge: \(q.prompt)")
                continue
            }
            XCTAssertTrue((2...3).contains(q.choices.count))
            let correct = q.choices[q.correctChoice].cards
            switch q.visual {
            case let .situation(plays, hand):
                XCTAssertEqual(plays.count, 3, "you play last")
                let lead = plays[0].cards
                for choice in q.choices {
                    XCTAssertNil(Rules.validateFollow(choice.cards, hand: hand, lead: lead, trump: trump), choice.label)
                }
                // No rank card printed in the led suit anywhere: it would look like a card you could follow with.
                if let ledSuit = Combos.group(of: lead, trump: trump)?.plainSuit {
                    let shown: [Card] = plays.flatMap(\.cards) + hand
                    let lookalikes = shown.filter { card in card.rank == trump.rank && card.suit == ledSuit }
                    XCTAssertTrue(lookalikes.isEmpty, "\(q.prompt) \(lookalikes.shortText)")
                }
                // The best play by the standard measure: points your team takes (or gives away), then the
                // cheapest card (a plain card before a trump, a low card before a high one).
                let values = q.choices.map { DrillJudge.followValue($0.cards, plays: plays, trump: trump) }
                let best = values.max { a, b in a.points != b.points ? a.points < b.points : a.cost > b.cost }
                XCTAssertEqual(values.filter { $0 == best }.count, 1, "\(q.prompt) \(q.choices.map(\.label))")
                XCTAssertEqual(values[q.correctChoice], best, "L\(level) \(q.prompt) \(q.choices.map(\.label))")
            case let .cards(hand):
                XCTAssertTrue(q.prompt.contains("on lead"))
                for choice in q.choices {
                    XCTAssertNil(Rules.validateLead(choice.cards, hand: hand, trump: trump), choice.label)
                }
                // Lead the top card of a plain suit (nobody can beat it in that suit), not a lone King or 10.
                XCTAssertTrue(DrillJudge.isTopPlainCard(correct[0], trump: trump), q.choices.map(\.label).description)
                for (index, choice) in q.choices.enumerated() where index != q.correctChoice {
                    XCTAssertFalse(DrillJudge.isTopPlainCard(choice.cards[0], trump: trump))
                }
                XCTAssertEqual(hand.filter { DrillJudge.isTopPlainCard($0, trump: trump) }.count, 1)
            default:
                XCTFail("bestPlay shows a situation or a hand")
            }
            XCTAssertTrue(q.explanation.contains(DrillJudge.spoken(correct[0])), q.explanation)
            if let principle = q.explanation.components(separatedBy: "**").dropFirst().first {
                principles[level, default: []].insert(principle)
            }
        }
        XCTAssertEqual(principles[1], ["Feed points", "Duck low", "Lead sure winners"])
        XCTAssertEqual(principles[2], ["Feed points", "Win cheaply", "Ruff low", "Duck low", "Lead sure winners"])
    }

    // MARK: Prompts and explanations state true facts
    //
    // Each claim a prompt or an explanation makes about the cards ("Partner is winning", "West ruffed
    // first", "15 points are on the table", "You hold only one club") is checked against the cards shown.

    func testCardBeatsAsksWhichCardYouCanPlay() {
        var lookalikes = 0
        for (level, q) in Self.all(.cardBeats) {
            guard let trump = q.trump, case let .trick(plays) = q.visual else { continue }
            // A trump-rank card printed in the led suit beats the lead if played, but you may not play it
            // while you can follow, so the prompt must ask what you can play, not just what beats it.
            var beatIfPlayed = 0
            for choice in q.choices {
                let trick = plays + [Play(player: Seats.human, cards: choice.cards)]
                if Rules.winningIndex(trick, trump: trump) == 1 { beatIfPlayed += 1 }
            }
            if beatIfPlayed > 1 {
                lookalikes += 1
                XCTAssertTrue(q.prompt.contains("can you play"), "L\(level) \(q.prompt) \(q.choices.map(\.label))")
            }
            // The lead and the choices are one set of physical cards.
            DrillJudge.checkVisualCards(plays.flatMap(\.cards) + q.choices.flatMap(\.cards), context: q.prompt)
        }
        XCTAssertGreaterThan(lookalikes, 100, "the rank-card lookalike comes up often")
    }

    func testBestPlayClaimsAreTrue() {
        var fired: Set<String> = []
        for (level, q) in Self.all(.bestPlay) {
            guard let trump = q.trump else {
                XCTFail("bestPlay needs a trump badge")
                continue
            }
            let context = "L\(level) \(q.prompt) | \(q.explanation)"
            let answer = q.choices[q.correctChoice].cards
            guard case let .situation(plays, hand) = q.visual else {
                // On lead: "A lone K" would mean the King is your only card of that suit.
                if case let .cards(hand) = q.visual,
                   let king = DrillJudge.capture(#"lone (\S+)"#, in: q.explanation).first,
                   let card = hand.first(where: { $0.description == king }) {
                    let sameSuit = hand.filter { !trump.isTrump($0) && $0.suit == card.suit }
                    XCTAssertEqual(sameSuit.count, 1, "\(context): the \(king) is not alone in \(hand.shortText)")
                }
                continue
            }
            let lead = plays[0].cards
            let current = plays[Rules.winningIndex(plays, trump: trump)].player
            let table = plays.flatMap(\.cards).map(DrillJudge.points).reduce(0, +)
            let legal = hand.filter { Rules.validateFollow([$0], hand: hand, lead: lead, trump: trump) == nil }
            func winner(after card: Card) -> Int {
                let trick = plays + [Play(player: Seats.human, cards: [card])]
                return trick[Rules.winningIndex(trick, trump: trump)].player
            }
            func card(named name: String) -> Card? {
                (hand + plays.flatMap(\.cards)).first { DrillJudge.spoken($0) == name }
            }

            for seat in [1, 2, 3] where q.prompt.contains("\(Seats.name(seat)) is winning") {
                fired.insert("is winning")
                XCTAssertEqual(current, seat, context)
            }
            if q.prompt.contains("West has ruffed") {
                fired.insert("has ruffed")
                XCTAssertTrue(trump.isTrump(plays[2].cards[0]) && !trump.isTrump(lead[0]), context)
            }
            if q.prompt.contains("You have no") || q.explanation.contains("you have no") {
                fired.insert("you have no")
                XCTAssertFalse(hand.contains { trump.group($0) == trump.group(lead[0]) }, context)
            }
            // "X's card wins whatever you play": true for every card you may play.
            if let name = DrillJudge.capture(#"(Your|East's|Partner's|West's) [^,.]+ wins whatever you play"#,
                                             in: q.explanation).first {
                fired.insert("wins whatever")
                let seat = DrillJudge.seat(possessive: name)
                for card in legal { XCTAssertEqual(winner(after: card), seat, "\(context): \(card) changes the winner") }
            }
            for value in DrillJudge.capture(#"(\d+) points are on the table"#, in: q.explanation)
                + DrillJudge.capture(#"take the (\d+) points"#, in: q.explanation) {
                fired.insert("points")
                XCTAssertEqual(Int(value), table, context)
            }
            if let name = DrillJudge.capture(#"Partner's (\S+) is winning"#, in: q.explanation).first {
                fired.insert("partner winning")
                XCTAssertEqual(current, 2, context)
                XCTAssertEqual(plays[1].cards.first.map(DrillJudge.spoken), name, context)
            }
            // "your lowest non-point card" / "your lowest plain card": nothing lower qualifies.
            if let name = DrillJudge.capture(#"lowest non-point card, the ([^\s,.]+)"#, in: q.explanation).first {
                fired.insert("lowest non-point")
                XCTAssertEqual(DrillJudge.spoken(answer[0]), name, context)
                let options = legal.filter { DrillJudge.points($0) == 0 }
                XCTAssertEqual(options.map { trump.strength($0) }.min(), trump.strength(answer[0]), context)
            }
            if let name = DrillJudge.capture(#"lowest plain card, the ([^\s,.]+)"#, in: q.explanation).first {
                fired.insert("lowest plain")
                XCTAssertEqual(DrillJudge.spoken(answer[0]), name, context)
                let plain = hand.filter { !trump.isTrump($0) }
                XCTAssertEqual(plain.map { trump.strength($0) }.min(), trump.strength(answer[0]), context)
            }
            // "The least you can" must really be your lowest card.
            if q.explanation.contains("the least you can") {
                XCTAssertEqual(legal.map { trump.strength($0) }.min(), trump.strength(answer[0]), "\(context): a lower card exists")
            }
            // Win cheaply: the answer is your lowest card that takes the trick; the kept card wins too;
            // the low card loses.
            if let pair = DrillJudge.captureAll(#"your (\S+) is enough to beat the (\S+)"#, in: q.explanation).first {
                fired.insert("enough to beat")
                XCTAssertEqual(DrillJudge.spoken(answer[0]), pair[0], context)
                XCTAssertEqual(current, DrillJudge.seat(holding: pair[1], in: plays), context)
                let winning = legal.filter { Seats.team(of: winner(after: $0)) == 0 }
                XCTAssertEqual(winning.map { trump.strength($0) }.min(), trump.strength(answer[0]), context)
                // A point card that wins scores for your team too: say so, or it looks like giving points away.
                let own = DrillJudge.points(answer[0])
                if own > 0 {
                    XCTAssertTrue(q.explanation.contains("plus \(own) for the \(answer[0].description) itself"), context)
                }
            }
            if let kept = DrillJudge.capture(#"Keep the (\S+) for later"#, in: q.explanation).first, let card = card(named: kept) {
                fired.insert("keep")
                XCTAssertEqual(winner(after: card), Seats.human, context)
            }
            if let low = DrillJudge.capture(#"the (\S+) would let the opponents win"#, in: q.explanation).first,
               let card = card(named: low) {
                fired.insert("let the opponents win")
                XCTAssertEqual(Seats.team(of: winner(after: card)), 1, context)
            }
            if let pair = DrillJudge.captureAll(#"your ([^.,]+?) wins as surely as the ([^.,]+?)\."#, in: q.explanation).first {
                fired.insert("as surely")
                for name in pair {
                    guard let card = card(named: name) else {
                        XCTFail("\(context): no \(name)")
                        continue
                    }
                    XCTAssertEqual(winner(after: card), Seats.human, context)
                }
            }
            if let name = DrillJudge.capture(#"your ([^.,]+?) can't beat it"#, in: q.explanation).first, let card = card(named: name) {
                fired.insert("can't beat")
                XCTAssertEqual(winner(after: card), current, context)
            }
        }
        // Every kind of claim came up, so none of these checks is silently skipped.
        XCTAssertEqual(fired, ["is winning", "has ruffed", "you have no", "wins whatever", "points", "partner winning",
                               "lowest non-point", "lowest plain", "enough to beat", "keep", "let the opponents win",
                               "as surely", "can't beat"])
    }

    func testTrickWinnerClaimsAreTrue() {
        var fired: Set<String> = []
        for (level, q) in Self.all(.trickWinner) {
            guard let trump = q.trump, case let .trick(plays) = q.visual else { continue }
            let context = "L\(level) \(q.prompt) \(plays.map { $0.cards.shortText }) | \(q.explanation)"
            let lead = plays[0].cards
            let ledGroup = Combos.group(of: lead, trump: trump)
            let winner = Rules.winningIndex(plays, trump: trump)
            let format = Rules.LeadFormat(lead, trump: trump)
            let winningKey = Rules.structureKey(plays[winner].cards, format: format, trump: trump)
            func play(_ seat: Int) -> (index: Int, cards: [Card])? {
                guard let index = plays.firstIndex(where: { $0.player == seat }) else { return nil }
                return (index, plays[index].cards)
            }
            func isAllTrump(_ cards: [Card]) -> Bool { Combos.group(of: cards, trump: trump) == .trump }

            // A lone card is "the 8♥" or "the small joker", as in the prompt.
            XCTAssertFalse(q.explanation.contains("with small joker") || q.explanation.contains("with big joker"), context)
            if level == 1 {
                XCTAssertFalse(plays.contains { $0.cards.contains { $0.isJoker } }, "jokers start at level 2: \(context)")
            }
            for name in DrillJudge.capture(#"(You|East|Partner|West) (?:was|were) out of \w+ and ruffed"#, in: q.explanation) {
                fired.insert("ruffed")
                XCTAssertEqual(play(DrillJudge.seat(name: name))?.index, winner, context)
                XCTAssertTrue(ledGroup?.isTrump == false && isAllTrump(plays[winner].cards), context)
            }
            for pair in DrillJudge.captureAll(#"(You|East|Partner|West) ruffed first, but (you|East|Partner|West) over-ruffed"#,
                                              in: q.explanation) {
                guard let first = play(DrillJudge.seat(name: pair[0])), let second = play(DrillJudge.seat(name: pair[1])) else {
                    XCTFail(context)
                    continue
                }
                fired.insert("over-ruffed")
                XCTAssertEqual(second.index, winner, context)
                XCTAssertTrue(first.index < winner && isAllTrump(first.cards), context)
                XCTAssertNotNil(Rules.structureKey(first.cards, format: format, trump: trump), context)
            }
            for name in DrillJudge.capture(#"(Your|East's|Partner's|West's) trump(?: \w+)? was lower"#, in: q.explanation) {
                guard let lower = play(DrillJudge.seat(possessive: name)),
                      let key = Rules.structureKey(lower.cards, format: format, trump: trump), let top = winningKey else {
                    XCTFail(context)
                    continue
                }
                fired.insert("was lower")
                XCTAssertTrue(isAllTrump(lower.cards) && key < top, context)
            }
            if q.explanation.contains("Nobody played a higher") || q.explanation.contains("Nobody matched it") {
                fired.insert("nobody")
                XCTAssertEqual(winner, 0, context)
            }
            if q.explanation.contains("It is the highest") || q.explanation.contains("Same shape,") {
                fired.insert("highest")
                XCTAssertNotEqual(winner, 0, context)
                XCTAssertEqual(Combos.group(of: plays[winner].cards, trump: trump), ledGroup, context)
            }
            if q.explanation.contains("nobody ruffed") {
                fired.insert("nobody ruffed")
                XCTAssertFalse(plays.dropFirst().contains { isAllTrump($0.cards) }, context)
            }
            for pair in DrillJudge.captureAll(#"(Your|East's|Partner's|West's) ([^.]+?) only tied"#, in: q.explanation) {
                guard let tie = play(DrillJudge.seat(possessive: pair[0])) else {
                    XCTFail(context)
                    continue
                }
                fired.insert("tied")
                XCTAssertEqual(DrillJudge.listing(tie.cards), pair[1], context)
                XCTAssertTrue(tie.index > winner, context)
                XCTAssertEqual(Rules.structureKey(tie.cards, format: format, trump: trump), winningKey, context)
            }
            for pair in DrillJudge.captureAll(#"(Your|East's|Partner's|West's) ([^.]+?) are not a (?:pair|tractor)"#, in: q.explanation) {
                guard let other = play(DrillJudge.seat(possessive: pair[0])) else {
                    XCTFail(context)
                    continue
                }
                fired.insert("not a pair")
                XCTAssertEqual(DrillJudge.listing(other.cards), pair[1], context)
                XCTAssertFalse(Rules.matchesStructure(other.cards, lead: lead, trump: trump), context)
            }
            for name in DrillJudge.capture(#"(You|East|Partner|West) mixed suits"#, in: q.explanation) {
                guard let mixed = play(DrillJudge.seat(name: name)) else {
                    XCTFail(context)
                    continue
                }
                fired.insert("mixed")
                XCTAssertNil(Combos.group(of: mixed.cards, trump: trump), context)
                // A rank card printed in the led suit makes a play look all one suit: say it is a trump.
                if let ledSuit = ledGroup?.plainSuit,
                   let lookalike = mixed.cards.first(where: { $0.rank == trump.rank && $0.suit == ledSuit }) {
                    fired.insert("mixed lookalike")
                    XCTAssertTrue(q.explanation.contains("\(lookalike.description) is a trump"), context)
                }
            }
            for name in DrillJudge.capture(#"(You|East|Partner|West) discarded"#, in: q.explanation) {
                guard let discard = play(DrillJudge.seat(name: name)), let group = Combos.group(of: discard.cards, trump: trump) else {
                    XCTFail(context)
                    continue
                }
                fired.insert("discarded")
                XCTAssertTrue(!group.isTrump && group != ledGroup, context)
            }
            for pair in DrillJudge.captureAll(#"The (\S+) is a trump this round, not a (\w+)"#, in: q.explanation) {
                fired.insert("rank card")
                let card = plays.flatMap(\.cards).first { $0.description == pair[0] }
                XCTAssertEqual(card?.rank, trump.rank, context)
                XCTAssertEqual(card?.suit?.singularName, pair[1], context)
            }
        }
        XCTAssertEqual(fired, ["ruffed", "over-ruffed", "was lower", "nobody", "highest", "nobody ruffed", "tied",
                               "not a pair", "mixed", "mixed lookalike", "discarded", "rank card"])
    }

    func testLegalFollowClaimsAreTrue() {
        var fired: Set<String> = []
        for (level, q) in Self.all(.legalFollow) {
            guard let trump = q.trump, case let .handAndLead(hand, lead, _) = q.visual,
                  let ledGroup = Combos.group(of: lead, trump: trump) else { continue }
            let context = "L\(level) \(q.prompt) hand \(hand.shortText) | \(q.explanation)"
            let held = hand.filter { trump.group($0) == ledGroup }
            let answer = q.choices[q.correctChoice].cards
            func cards(_ text: String) -> [Card]? {
                var pool = hand
                var found: [Card] = []
                for name in text.split(separator: " ").map(String.init) {
                    guard let index = pool.firstIndex(where: { $0.description == name }) else { return nil }
                    found.append(pool.remove(at: index))
                }
                return found
            }

            for pair in DrillJudge.captureAll(#"You hold only one (\w+), the (\S+),"#, in: q.explanation) {
                fired.insert("only one")
                XCTAssertEqual(held.map(\.description), [pair[1]], context)
                XCTAssertEqual(ledGroup.plainSuit?.singularName, pair[0], context)
            }
            if !DrillJudge.capture(#"but no (\w+) pair"#, in: q.explanation).isEmpty {
                fired.insert("no pair")
                XCTAssertEqual(Combos.pairCount(in: held), 0, context)
                XCTAssertGreaterThanOrEqual(held.count, lead.count, context)
            }
            if let name = DrillJudge.capture(#"your only trump is the \*\*(.+?)\*\*"#, in: q.explanation).first {
                fired.insert("only trump")
                let trumps = hand.filter { trump.isTrump($0) }
                XCTAssertEqual(trumps.map(DrillJudge.spoken), [name], context)
            }
            if let text = DrillJudge.capture(#"you hold a \*\*\w+ pair\*\*, (.+?), so you must play it"#, in: q.explanation).first {
                fired.insert("hold a pair")
                let pair = cards(text) ?? []
                XCTAssertTrue(Combos.isPair(pair) && trump.group(pair[0]) == ledGroup, context)
                XCTAssertEqual(DrillJudge.sorted(pair), DrillJudge.sorted(answer), context)
            }
            if !DrillJudge.capture(#"You have no (\w+) tractor"#, in: q.explanation).isEmpty {
                fired.insert("no tractor")
                XCTAssertLessThan(Combos.longestRun(in: held, trump: trump), 2, context)
            }
            if !DrillJudge.capture(#"but one (\w+) pair"#, in: q.explanation).isEmpty {
                fired.insert("one pair")
                XCTAssertEqual(Combos.pairCount(in: held), 1, context)
            }
            if q.explanation.contains("as many") {
                fired.insert("as many")
                XCTAssertEqual(Combos.pairCount(in: held), 2, context)
            }
            if let text = DrillJudge.capture(#"you hold one in \w+, (.+?), so you must play it"#, in: q.explanation).first {
                fired.insert("hold a tractor")
                let tractor = cards(text) ?? []
                XCTAssertEqual(Combos.shape(of: tractor, trump: trump), .tractor(2), context)
                XCTAssertEqual(DrillJudge.sorted(tractor), DrillJudge.sorted(answer), context)
            }
            if let text = DrillJudge.capture(#"so (.+?) is a \w+ tractor, and you must play it"#, in: q.explanation).first {
                fired.insert("tractor across the rank")
                XCTAssertEqual(Combos.shape(of: cards(text) ?? [], trump: trump), .tractor(2), context)
            }
            for pair in DrillJudge.captureAll(#"The (\S+) is a trump(?: this round)?, not a (\w+)"#, in: q.explanation) {
                fired.insert("rank card")
                let card = hand.first { $0.description == pair[0] }
                XCTAssertEqual(card?.rank, trump.rank, context)
                XCTAssertEqual(card?.suit?.singularName, pair[1], context)
            }
            if let text = DrillJudge.capture(#"Your (.+?) are trumps, not"#, in: q.explanation).first {
                fired.insert("rank pair")
                XCTAssertTrue((cards(text) ?? []).allSatisfy { $0.rank == trump.rank }, context)
            }
            if let text = DrillJudge.capture(#"your (.+?) is a \*\*trump pair\*\*"#, in: q.explanation).first {
                fired.insert("trump pair")
                let pair = cards(text) ?? []
                XCTAssertTrue(Combos.isPair(pair) && trump.isTrump(pair[0]), context)
            }
            if let name = DrillJudge.capture(#"Your \*\*(\S+)\*\* is a trump: every"#, in: q.explanation).first {
                fired.insert("rank single")
                XCTAssertEqual(answer.map(\.description), [name], context)
                XCTAssertEqual(answer.first?.rank, trump.rank, context)
            }
        }
        XCTAssertEqual(fired, ["only one", "no pair", "only trump", "hold a pair", "no tractor", "one pair", "as many",
                               "hold a tractor", "tractor across the rank", "rank card", "rank pair", "trump pair",
                               "rank single"])
    }
}

/// Small referees written from DESIGN.md with only the card model, to check answers independently.
enum DrillJudge {
    static func trumpLine(_ trump: Trump) -> String {
        if let suit = trump.suit { return "Trump suit \(suit.symbol), rank \(trump.rank.label)." }
        return "No trump suit, rank \(trump.rank.label)."
    }

    /// How explanations name a card: "10♥", or "small joker" / "big joker".
    static func spoken(_ card: Card) -> String {
        switch card.face {
        case .smallJoker: return "small joker"
        case .bigJoker: return "big joker"
        case .regular: return card.description
        }
    }

    /// 5s are worth 5, 10s and Kings 10, everything else 0.
    static func points(_ card: Card) -> Int {
        switch card.rank {
        case .five?: return 5
        case .ten?, .king?: return 10
        default: return 0
        }
    }

    /// Jokers, every card of the trump rank, every card of the trump suit.
    static func isTrump(_ card: Card, _ trump: Trump) -> Bool {
        if card.isJoker || card.rank == trump.rank { return true }
        guard let suit = trump.suit else { return false }
        return card.suit == suit
    }

    /// Trump order key (higher is stronger), nil for a plain card: big joker > small joker > the trump
    /// suit's rank card > other rank cards (equal; all equal with no trump suit) > trump suit by rank.
    static func orderKey(_ card: Card, _ trump: Trump) -> Int? {
        switch card.face {
        case .bigJoker: return 400
        case .smallJoker: return 300
        case let .regular(suit, rank):
            if rank == trump.rank { return trump.suit != nil && suit == trump.suit ? 200 : 100 }
            if suit == trump.suit { return rank.rawValue }
            return nil
        }
    }

    /// Two or more pairs, all one suit group, of consecutive strength.
    static func isTractor(_ cards: [Card], trump: Trump) -> Bool {
        guard cards.count >= 4, cards.count % 2 == 0, Set(cards.map(\.id)).count == cards.count,
              Set(cards.map { trump.group($0) }).count == 1 else { return false }
        let counts = cards.faceCounts
        guard counts.values.allSatisfy({ $0 == 2 }) else { return false }
        let strengths = counts.keys.map { trump.strength($0) }.sorted()
        guard Set(strengths).count == strengths.count else { return false }
        for (low, high) in zip(strengths, strengths.dropFirst()) where high != low + 1 { return false }
        return true
    }

    /// 2 × the cards in the lead's largest part: the longest run of pairs, else a pair, else a single.
    static func kittyMultiplier(_ lead: [Card], trump: Trump) -> Int {
        var byGroup: [SuitGroup: [Int]] = [:]
        for (face, count) in lead.faceCounts where count >= 2 {
            byGroup[trump.group(face), default: []].append(trump.strength(face))
        }
        var longest = 0
        for strengths in byGroup.values {
            let levels = Set(strengths)
            for start in levels where !levels.contains(start - 1) {
                var length = 0
                while levels.contains(start + length) { length += 1 }
                longest = max(longest, length)
            }
        }
        let largestCards = longest >= 2 ? 2 * longest : (longest == 1 ? 2 : 1)
        return 2 * largestCards
    }

    static func outcomeText(hold: Bool, levels: Int) -> String {
        let count = levels == 1 ? "1 level" : "\(levels) levels"
        if hold { return "The declarers keep the deal and climb \(count)" }
        if levels == 0 { return "The defenders take over but don't climb" }
        return "The defenders take over and climb \(count)"
    }

    /// The level table from DESIGN.md.
    static func outcomeText(_ points: Int) -> String {
        switch points {
        case ..<1: return outcomeText(hold: true, levels: 3)
        case 1..<40: return outcomeText(hold: true, levels: 2)
        case 40..<80: return outcomeText(hold: true, levels: 1)
        default: return outcomeText(hold: false, levels: (points - 80) / 40)
        }
    }

    static let allOutcomeTexts: Set<String> = Set((1...3).map { outcomeText(hold: true, levels: $0) }
        + (0...6).map { outcomeText(hold: false, levels: $0) })

    static func firstNumber(in text: String) -> Int? {
        var digits = ""
        for ch in text {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }

    static func kind(of violation: FollowViolation) -> String {
        switch violation {
        case .mustFollowSuit: return "follow suit"
        case .mustPlayPairs: return "pairs"
        case .mustPlayTractor, .mustPlaySetTractor: return "tractor"
        case .mustPlaySets: return "sets"
        case .wrongCount: return "count"
        case .cardsNotInHand: return "not in hand"
        }
    }

    static func cardAndTrump(_ q: Question) -> (card: Card, trump: Trump)? {
        guard let trump = q.trump, case let .cards(cards) = q.visual, let card = cards.first else { return nil }
        return (card, trump)
    }

    /// For a follow when you play last: the points your team gains (positive) or hands over (negative),
    /// and what the card costs you (any trump costs more than any plain card; higher costs more).
    static func followValue(_ cards: [Card], plays: [Play], trump: Trump) -> FollowValue {
        let trick = plays + [Play(player: Seats.human, cards: cards)]
        let winner = trick[Rules.winningIndex(trick, trump: trump)].player
        let points = trick.flatMap(\.cards).map(DrillJudge.points).reduce(0, +)
        let ours = Seats.team(of: winner) == Seats.team(of: Seats.human)
        let cost = cards.map { (isTrump($0, trump) ? 100 : 0) + trump.strength($0) }.reduce(0, +)
        return FollowValue(points: ours ? points : -points, cost: cost)
    }

    struct FollowValue: Equatable {
        var points: Int
        var cost: Int
    }

    /// The highest card of a plain suit this round (nobody can play a higher card of that suit).
    static func isTopPlainCard(_ card: Card, trump: Trump) -> Bool {
        guard !isTrump(card, trump), let rank = card.rank else { return false }
        let higher = Rank.allCases.filter { $0 > rank && $0 != trump.rank }
        return higher.isEmpty
    }

    /// A ruff, a discard or mixed play, a play of the wrong shape, or a tie with the winner.
    static func isInstructive(_ plays: [Play], trump: Trump) -> Bool {
        guard let lead = plays.first?.cards, let ledGroup = Combos.group(of: lead, trump: trump) else { return false }
        let winner = Rules.winningIndex(plays, trump: trump)
        let winningGroup = Combos.group(of: plays[winner].cards, trump: trump)
        let winningTop = plays[winner].cards.map { trump.strength($0) }.max()
        for (index, play) in plays.enumerated().dropFirst() {
            let group = Combos.group(of: play.cards, trump: trump)
            let matches = Rules.matchesStructure(play.cards, lead: lead, trump: trump)
            let top = play.cards.map { trump.strength($0) }.max()
            // Trumps on a plain lead, another plain suit, or a mix of suits.
            let leftTheSuit = group != ledGroup
            let wrongShape = lead.count > 1 && !matches
            let tie = index > winner && group == winningGroup && matches && top == winningTop
            if leftTheSuit || wrongShape || tie { return true }
        }
        return false
    }

    /// No (face, copy) twice; copies are 0 or 1.
    static func checkVisualCards(_ cards: [Card], context: String) {
        let keys = cards.map { "\($0.face)#\($0.copy)" }
        XCTAssertEqual(Set(keys).count, keys.count, "\(context) repeats a card: \(cards.shortText)")
        XCTAssertTrue(cards.allSatisfy { (0...1).contains($0.copy) }, context)
    }

    /// A card choice is captioned with its cards ("9♣ 9♣"), or "Small joker" / "Big joker" for one joker.
    static func captionMatches(_ choice: Choice) -> Bool {
        if choice.cards.count == 1, let card = choice.cards.first, card.isJoker {
            return choice.label == (card.face == .smallJoker ? "Small joker" : "Big joker")
        }
        return choice.label == choice.cards.shortText
    }

    // MARK: Reading claims out of text

    /// The first capture group of every match of `pattern` in `text`.
    static func capture(_ pattern: String, in text: String) -> [String] {
        captureAll(pattern, in: text).compactMap(\.first)
    }

    /// Every capture group of every match of `pattern` in `text`.
    static func captureAll(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            XCTFail("bad pattern \(pattern)")
            return []
        }
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: whole).map { match in
            (1..<match.numberOfRanges).compactMap { group in
                Range(match.range(at: group), in: text).map { String(text[$0]) }
            }
        }
    }

    /// "You" / "you" → 0, "East" → 1, "Partner" → 2, "West" → 3.
    static func seat(name: String) -> Int {
        Seats.all.first { Seats.name($0).lowercased() == name.lowercased() } ?? -1
    }

    /// "Your" → 0, "East's" → 1, "Partner's" → 2, "West's" → 3.
    static func seat(possessive: String) -> Int {
        if possessive.lowercased() == "your" { return Seats.human }
        return seat(name: String(possessive.dropLast(2)))
    }

    /// The seat whose play contains the card named `name`.
    static func seat(holding name: String, in plays: [Play]) -> Int? {
        plays.first { $0.cards.contains { spoken($0) == name } }?.player
    }

    /// How explanations list a play: "8♥", "small joker", "two small jokers", "9♣ 9♣".
    static func listing(_ cards: [Card]) -> String {
        if cards.count == 1, let only = cards.first { return spoken(only) }
        if cards.count == 2, cards[0].face == cards[1].face, cards[0].isJoker { return "two \(spoken(cards[0]))s" }
        return cards.shortText
    }

    static func sorted(_ cards: [Card]) -> [Int] {
        cards.map(\.id).sorted()
    }

    static func inSeatOrder(_ plays: [Play]) -> Bool {
        guard let first = plays.first else { return false }
        return plays.enumerated().allSatisfy { $0.element.player == (first.player + $0.offset) % 4 }
    }

    static func checkVisual(_ q: Question, context: String) {
        switch q.visual {
        case .none:
            break
        case let .cards(cards):
            XCTAssertFalse(cards.isEmpty, context)
            checkVisualCards(cards, context: context)
        case let .trick(plays):
            XCTAssertTrue((1...4).contains(plays.count), context)
            XCTAssertTrue(inSeatOrder(plays), context)
            let size = plays.first?.cards.count ?? 0
            XCTAssertTrue(size > 0 && plays.allSatisfy { $0.cards.count == size }, context)
            checkVisualCards(plays.flatMap(\.cards), context: context)
        case let .handAndLead(hand, lead, leader):
            XCTAssertNotEqual(leader, Seats.human, context)
            checkVisualCards(hand + lead, context: context)
            for choice in q.choices {
                XCTAssertEqual(choice.cards.count, lead.count, context)
                XCTAssertTrue(hand.containsAll(choice.cards), "\(context): \(choice.label) not in hand")
            }
        case let .situation(plays, hand):
            XCTAssertTrue((1...3).contains(plays.count), context)
            XCTAssertTrue(inSeatOrder(plays), context)
            XCTAssertEqual(plays.last.map { Seats.next(after: $0.player) }, Seats.human, context)
            checkVisualCards(plays.flatMap(\.cards) + hand, context: context)
            for choice in q.choices {
                XCTAssertEqual(choice.cards.count, plays.first?.cards.count, context)
                XCTAssertTrue(hand.containsAll(choice.cards), "\(context): \(choice.label) not in hand")
            }
        }
    }
}
