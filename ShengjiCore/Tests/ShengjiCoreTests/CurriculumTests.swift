import XCTest
@testable import ShengjiCore

/// Walks the curriculum content so tests can check every page, question and string.
/// Shared by `CurriculumTests` (integrity, runs now) and `CurriculumRulesTests` (needs the engine).
enum CurriculumScan {
    struct PredictItem {
        let lesson: Lesson
        let question: Question
    }

    struct TrickPage {
        let lesson: Lesson
        let title: String
        let plays: [Play]
        let trump: Trump
        let winner: Int
    }

    static var predicts: [PredictItem] {
        Curriculum.lessons.flatMap { lesson in
            lesson.pages.compactMap { page -> PredictItem? in
                if case let .predict(q) = page { return PredictItem(lesson: lesson, question: q) }
                return nil
            }
        }
    }

    static var trickPages: [TrickPage] {
        Curriculum.lessons.flatMap { lesson in
            lesson.pages.compactMap { page -> TrickPage? in
                if case let .trick(title, _, plays, trump, winner) = page {
                    return TrickPage(lesson: lesson, title: title, plays: plays, trump: trump, winner: winner)
                }
                return nil
            }
        }
    }

    static func question(_ id: String) -> Question? {
        predicts.first { $0.question.id == id }?.question
    }

    /// The cards shown on a `.cards` page with the given title, in the given lesson.
    static func cardsPage(lesson: Int, title: String) -> (cards: [Card], trump: Trump?)? {
        for page in Curriculum.lessons[lesson - 1].pages {
            if case let .cards(t, _, cards, trump) = page, t == title { return (cards, trump) }
        }
        return nil
    }

    static func words(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }

    static func strings(of question: Question) -> [String] {
        [question.prompt, question.explanation] + question.choices.map(\.label)
    }

    static func strings(of page: LessonPage) -> [String] {
        switch page {
        case let .text(title, body): return [title, body]
        case let .cards(title, body, _, _): return [title, body]
        case let .trick(title, body, _, _, _): return [title, body]
        case let .predict(q): return strings(of: q)
        case let .recap(points): return points
        }
    }

    /// Every learner-facing string in lessons and facts (not the glossary).
    static var lessonAndFactStrings: [String] {
        var out: [String] = []
        for lesson in Curriculum.lessons {
            out += [lesson.title, lesson.subtitle]
            if let term = lesson.chineseTerm { out.append(term) }
            for page in lesson.pages { out += strings(of: page) }
        }
        for fact in Curriculum.facts { out += [fact.prompt, fact.explanation] + fact.choices }
        return out
    }

    static var glossaryStrings: [String] {
        Curriculum.glossary.flatMap { [$0.english, $0.chinese, $0.pinyin, $0.meaning] }
    }

    /// Groups of cards that must each be free of duplicate (face, copy): every visual, every trick,
    /// and each card choice together with the cards already on the table.
    static func cardGroups(of page: LessonPage) -> [[Card]] {
        switch page {
        case .text, .recap:
            return []
        case let .cards(_, _, cards, _):
            return [cards]
        case let .trick(_, _, plays, _, _):
            return [plays.flatMap(\.cards)]
        case let .predict(q):
            let table: [Card]
            var groups: [[Card]] = []
            switch q.visual {
            case .none:
                table = []
            case let .cards(cards):
                table = []
                groups.append(cards)
            case let .trick(plays):
                table = plays.flatMap(\.cards)
                groups.append(table)
            case let .handAndLead(hand, lead, _):
                table = lead
                groups.append(hand + lead)
            case let .situation(plays, hand):
                table = plays.flatMap(\.cards)
                groups.append(table + hand)
            }
            for choice in q.choices where !choice.cards.isEmpty {
                groups.append(choice.cards + table)
            }
            return groups
        }
    }

    static func isCJK(_ ch: Character) -> Bool {
        ch.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// Each run of Chinese characters in `s`, with the text that follows it.
    static func chineseRuns(in s: String) -> [(term: String, after: Substring)] {
        var out: [(String, Substring)] = []
        var i = s.startIndex
        while i < s.endIndex {
            if isCJK(s[i]) {
                var j = i
                while j < s.endIndex, isCJK(s[j]) { j = s.index(after: j) }
                out.append((String(s[i..<j]), s[j...]))
                i = j
            } else {
                i = s.index(after: i)
            }
        }
        return out
    }

    /// Plays follow seat order from the leader: leader, leader+1, ... (mod 4).
    static func inSeatOrder(_ plays: [Play]) -> Bool {
        guard let first = plays.first else { return false }
        return plays.enumerated().allSatisfy { $0.element.player == (first.player + $0.offset) % 4 }
    }

    static func faceKey(_ card: Card) -> String { "\(card.face)#\(card.copy)" }
}

final class CurriculumTests: XCTestCase {
    // MARK: Lessons

    func testTwelveLessonsNumberedInOrder() {
        let lessons = Curriculum.lessons
        XCTAssertEqual(lessons.count, 12)
        for (i, lesson) in lessons.enumerated() {
            XCTAssertEqual(lesson.number, i + 1)
            XCTAssertEqual(lesson.id, "lesson.\(i + 1)")
            XCTAssertEqual(Curriculum.lesson(id: lesson.id)?.number, i + 1)
        }
        XCTAssertEqual(Set(lessons.map(\.id)).count, 12)
        XCTAssertNil(Curriculum.lesson(id: "lesson.13"))
    }

    func testLessonShapeFollowsTheTeachingPattern() {
        for lesson in Curriculum.lessons {
            let pages = lesson.pages
            XCTAssertTrue((5...9).contains(pages.count), "\(lesson.id) has \(pages.count) pages")
            XCTAssertTrue((2...4).contains(lesson.estimatedMinutes), lesson.id)
            XCTAssertFalse(lesson.title.isEmpty)
            XCTAssertFalse(lesson.subtitle.isEmpty)
            if case .text = pages.first {} else { XCTFail("\(lesson.id) should open with a hook text page") }
            guard case let .recap(points) = pages.last else {
                XCTFail("\(lesson.id) should end with a recap")
                continue
            }
            XCTAssertTrue((3...5).contains(points.count), "\(lesson.id) recap has \(points.count) points")
            let predictCount = pages.filter { if case .predict = $0 { return true } else { return false } }.count
            XCTAssertGreaterThanOrEqual(predictCount, 1, "\(lesson.id) needs a predict page")
            let visualCount = pages.filter {
                switch $0 {
                case .cards, .trick: return true
                default: return false
                }
            }.count
            XCTAssertGreaterThanOrEqual(visualCount, 1, "\(lesson.id) needs a card visual")
            XCTAssertEqual(pages.filter { if case .recap = $0 { return true } else { return false } }.count, 1)
        }
    }

    func testSkillsMatchDesignAndCoverEverySkillExactlyOnce() {
        let expected: [Int: [SkillID]] = [
            1: [], 2: [.pointValue, .countPoints], 3: [.isTrump], 4: [.trumpOrder], 5: [.cardBeats],
            6: [.isPair, .legalFollow], 7: [.isTractor], 8: [.trickWinner], 9: [],
            10: [.levelOutcome, .kittyBonus], 11: [], 12: [.bestPlay],
        ]
        for lesson in Curriculum.lessons {
            XCTAssertEqual(lesson.skills, expected[lesson.number], lesson.id)
        }
        let all = Curriculum.lessons.flatMap(\.skills)
        XCTAssertEqual(all.count, SkillID.allCases.count)
        XCTAssertEqual(Set(all), Set(SkillID.allCases))
    }

    func testItemIDsAreSkillsThenFacts() {
        for lesson in Curriculum.lessons {
            XCTAssertEqual(lesson.itemIDs, lesson.skills.map(\.itemID) + lesson.factIDs)
            XCTAssertEqual(Set(lesson.itemIDs).count, lesson.itemIDs.count)
        }
        // Lessons that unlock no skill rely on facts.
        for n in [1, 9, 11] {
            XCTAssertGreaterThanOrEqual(Curriculum.lessons[n - 1].factIDs.count, 4, "lesson.\(n)")
        }
    }

    // MARK: Facts

    func testFactIDsResolveAndBelongToTheirLesson() {
        let lessonIDs = Set(Curriculum.lessons.map(\.id))
        for lesson in Curriculum.lessons {
            for id in lesson.factIDs {
                let fact = Curriculum.fact(id: id)
                XCTAssertNotNil(fact, "\(lesson.id) lists unknown fact \(id)")
                XCTAssertEqual(fact?.lessonID, lesson.id)
            }
        }
        let listed = Curriculum.lessons.flatMap(\.factIDs)
        XCTAssertEqual(listed.count, Curriculum.facts.count)
        for fact in Curriculum.facts {
            XCTAssertTrue(lessonIDs.contains(fact.lessonID), "\(fact.id) has unknown lesson \(fact.lessonID)")
            XCTAssertTrue(listed.contains(fact.id), "\(fact.id) is not introduced by any lesson")
        }
    }

    func testFactIDsUniqueAndWellFormed() {
        let ids = Curriculum.facts.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue((28...40).contains(ids.count), "\(ids.count) facts")
        for id in ids {
            XCTAssertNotNil(id.range(of: #"^fact\.[a-z][A-Za-z]*$"#, options: .regularExpression), id)
            XCTAssertNil(SkillID(itemID: id))
        }
        for lesson in Curriculum.lessons where !lesson.factIDs.isEmpty {
            XCTAssertTrue((2...6).contains(lesson.factIDs.count), "\(lesson.id) has \(lesson.factIDs.count) facts")
        }
    }

    func testFactChoicesAreValid() {
        for fact in Curriculum.facts {
            XCTAssertTrue((3...4).contains(fact.choices.count), fact.id)
            XCTAssertTrue(fact.choices.indices.contains(fact.correctChoice), fact.id)
            XCTAssertEqual(Set(fact.choices).count, fact.choices.count, "\(fact.id) repeats a choice")
            XCTAssertFalse(fact.choices.contains { $0.isEmpty }, fact.id)
            XCTAssertFalse(fact.prompt.isEmpty, fact.id)
            XCTAssertFalse(fact.explanation.isEmpty, fact.id)
            XCTAssertLessThanOrEqual(CurriculumScan.words(fact.prompt), 30, fact.id)
            XCTAssertLessThanOrEqual(CurriculumScan.words(fact.explanation), 45, fact.id)
            for choice in fact.choices {
                XCTAssertLessThanOrEqual(CurriculumScan.words(choice), 12, "\(fact.id): \(choice)")
            }
        }
    }

    func testFactQuestionKeepsTheRightAnswerAfterShuffling() {
        for fact in Curriculum.facts {
            var positions = Set<Int>()
            var ids = Set<String>()
            for seed in 0..<200 {
                var rng = SeededGenerator(seed: UInt64(seed))
                let q = fact.question(rng: &rng)
                XCTAssertEqual(q.itemID, fact.id)
                XCTAssertTrue(q.id.hasPrefix(fact.id + "."), q.id)
                XCTAssertNotNil(UInt64(q.id.dropFirst(fact.id.count + 1)), q.id)
                XCTAssertNil(q.trump)
                XCTAssertEqual(q.visual, .none)
                XCTAssertEqual(q.difficulty, 1)
                XCTAssertEqual(q.prompt, fact.prompt)
                XCTAssertEqual(q.explanation, fact.explanation)
                XCTAssertEqual(q.choices.count, fact.choices.count)
                XCTAssertEqual(Set(q.choices.map(\.label)), Set(fact.choices))
                XCTAssertTrue(q.choices.allSatisfy { $0.cards.isEmpty })
                XCTAssertTrue(q.choices.indices.contains(q.correctChoice))
                XCTAssertEqual(q.choices[q.correctChoice].label, fact.choices[fact.correctChoice], fact.id)
                positions.insert(q.correctChoice)
                ids.insert(q.id)
            }
            XCTAssertEqual(positions.count, fact.choices.count, "\(fact.id): the answer should move around")
            XCTAssertGreaterThan(ids.count, 190, "\(fact.id): question ids should vary")
        }
    }

    func testFactQuestionIsDeterministicForASeed() {
        guard let fact = Curriculum.facts.first else { return XCTFail("no facts") }
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        XCTAssertEqual(fact.question(rng: &a), fact.question(rng: &b))
    }

    func testCurriculumQuestionResolvesFactIDs() {
        var rng = SeededGenerator(seed: 7)
        for fact in Curriculum.facts {
            let q = Curriculum.question(for: fact.id, difficulty: 2, rng: &rng)
            XCTAssertEqual(q?.itemID, fact.id)
        }
        XCTAssertNil(Curriculum.question(for: "fact.noSuchFact", difficulty: 1, rng: &rng))
        XCTAssertNil(Curriculum.question(for: "lesson.1", difficulty: 1, rng: &rng))
        XCTAssertNil(Curriculum.question(for: "", difficulty: 1, rng: &rng))
    }

    // MARK: Predict pages

    func testPredictQuestionsAreWellFormed() {
        for lesson in Curriculum.lessons {
            var k = 0
            for page in lesson.pages {
                guard case let .predict(q) = page else { continue }
                k += 1
                XCTAssertEqual(q.id, "\(lesson.id).predict.\(k)")
                XCTAssertEqual(q.itemID, lesson.id)
                XCTAssertTrue((2...4).contains(q.choices.count), q.id)
                XCTAssertTrue(q.choices.indices.contains(q.correctChoice), q.id)
                XCTAssertEqual(Set(q.choices.map(\.label)).count, q.choices.count, "\(q.id) repeats a label")
                XCTAssertFalse(q.choices.contains { $0.label.isEmpty }, q.id)
                XCTAssertFalse(q.prompt.isEmpty, q.id)
                XCTAssertFalse(q.explanation.isEmpty, q.id)
                XCTAssertEqual(q.difficulty, 1, q.id)
                XCTAssertLessThanOrEqual(CurriculumScan.words(q.prompt), 40, q.id)
                XCTAssertLessThanOrEqual(CurriculumScan.words(q.explanation), 60, q.id)
            }
        }
        let ids = CurriculumScan.predicts.map(\.question.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testPredictPagesComeBeforeTheRecap() {
        for lesson in Curriculum.lessons {
            guard let firstPredict = lesson.pages.firstIndex(where: { if case .predict = $0 { return true } else { return false } })
            else { continue }
            // At least one prediction comes in the first half, before most of the explanation.
            XCTAssertLessThanOrEqual(firstPredict, lesson.pages.count / 2, lesson.id)
        }
    }

    func testHandAndSituationChoicesComeFromTheHand() {
        for item in CurriculumScan.predicts {
            let q = item.question
            switch q.visual {
            case let .handAndLead(hand, lead, leader):
                XCTAssertTrue((0...3).contains(leader), q.id)
                XCTAssertNotEqual(leader, Seats.human, q.id)
                for choice in q.choices {
                    XCTAssertEqual(choice.cards.count, lead.count, "\(q.id): \(choice.label)")
                    XCTAssertTrue(hand.containsAll(choice.cards), "\(q.id): \(choice.label)")
                }
            case let .situation(plays, hand):
                XCTAssertTrue((1...3).contains(plays.count), q.id)
                XCTAssertTrue(CurriculumScan.inSeatOrder(plays), q.id)
                XCTAssertEqual(plays.last.map { Seats.next(after: $0.player) }, Seats.human, q.id)
                for choice in q.choices {
                    XCTAssertEqual(choice.cards.count, plays[0].cards.count, "\(q.id): \(choice.label)")
                    XCTAssertTrue(hand.containsAll(choice.cards), "\(q.id): \(choice.label)")
                }
            default:
                break
            }
        }
    }

    // MARK: Cards and tricks

    func testCardVisualsNeverRepeatACardAndPairsUseBothCopies() {
        for lesson in Curriculum.lessons {
            for (index, page) in lesson.pages.enumerated() {
                for group in CurriculumScan.cardGroups(of: page) {
                    XCTAssertFalse(group.isEmpty, "\(lesson.id) page \(index + 1) has an empty visual")
                    let keys = group.map(CurriculumScan.faceKey)
                    XCTAssertEqual(Set(keys).count, keys.count, "\(lesson.id) page \(index + 1) repeats a card: \(group.shortText)")
                    XCTAssertTrue(group.allSatisfy { $0.copy == 0 || $0.copy == 1 }, "\(lesson.id) page \(index + 1)")
                    // A face shown twice is always copy 0 + copy 1.
                    for (face, count) in group.faceCounts where count == 2 {
                        XCTAssertEqual(Set(group.filter { $0.face == face }.map(\.copy)), [0, 1])
                    }
                }
            }
        }
    }

    func testChoicesThatShowPairsUseBothCopies() {
        for item in CurriculumScan.predicts {
            for choice in item.question.choices {
                let keys = choice.cards.map(CurriculumScan.faceKey)
                XCTAssertEqual(Set(keys).count, keys.count, "\(item.question.id): \(choice.label)")
            }
        }
    }

    func testTrickPagesHaveFourEqualPlaysInSeatOrder() {
        let tricks = CurriculumScan.trickPages
        XCTAssertGreaterThanOrEqual(tricks.count, 8)
        for t in tricks {
            XCTAssertEqual(t.plays.count, 4, t.title)
            XCTAssertTrue(CurriculumScan.inSeatOrder(t.plays), t.title)
            let size = t.plays.first?.cards.count ?? 0
            XCTAssertGreaterThan(size, 0, t.title)
            XCTAssertTrue(t.plays.allSatisfy { $0.cards.count == size }, "\(t.title): plays differ in size")
            XCTAssertTrue(t.plays.map(\.player).contains(t.winner), t.title)
        }
    }

    func testPredictTricksAreInSeatOrderWithEqualPlays() {
        for item in CurriculumScan.predicts {
            let q = item.question
            guard case let .trick(plays) = q.visual else { continue }
            XCTAssertTrue((1...4).contains(plays.count), q.id)
            XCTAssertTrue(CurriculumScan.inSeatOrder(plays), q.id)
            let size = plays.first?.cards.count ?? 0
            XCTAssertTrue(plays.allSatisfy { $0.cards.count == size }, q.id)
            XCTAssertNotNil(q.trump, "\(q.id): tricks need a trump badge")
            let seatLabels = Set(Seats.all.map(Seats.name))
            if q.choices.allSatisfy({ seatLabels.contains($0.label) }) {
                // "Who wins?" questions name seats that actually played.
                let playerNames = Set(plays.map { Seats.name($0.player) })
                XCTAssertTrue(q.choices.allSatisfy { playerNames.contains($0.label) }, q.id)
            } else {
                // "Which card would win?" questions: you play next, one card choice the size of the lead.
                XCTAssertLessThan(plays.count, 4, q.id)
                XCTAssertEqual(plays.last.map { Seats.next(after: $0.player) }, Seats.human, q.id)
                XCTAssertTrue(q.choices.allSatisfy { $0.cards.count == size }, q.id)
            }
        }
    }

    // MARK: Text

    func testTextStaysShort() {
        for lesson in Curriculum.lessons {
            XCTAssertLessThanOrEqual(CurriculumScan.words(lesson.title), 6, lesson.id)
            XCTAssertLessThanOrEqual(CurriculumScan.words(lesson.subtitle), 10, lesson.id)
            for page in lesson.pages {
                switch page {
                case let .text(title, body), let .cards(title, body, _, _), let .trick(title, body, _, _, _):
                    XCTAssertFalse(title.isEmpty, lesson.id)
                    XCTAssertLessThanOrEqual(CurriculumScan.words(title), 6, "\(lesson.id): \(title)")
                    XCTAssertLessThanOrEqual(CurriculumScan.words(body), 60, "\(lesson.id): \(title)")
                    XCTAssertGreaterThanOrEqual(CurriculumScan.words(body), 15, "\(lesson.id): \(title)")
                case let .recap(points):
                    for p in points {
                        XCTAssertLessThanOrEqual(CurriculumScan.words(p), 20, "\(lesson.id): \(p)")
                    }
                case .predict:
                    break
                }
            }
        }
    }

    func testNoEmDashAnywhere() {
        for s in CurriculumScan.lessonAndFactStrings + CurriculumScan.glossaryStrings {
            XCTAssertFalse(s.contains("\u{2014}"), "em-dash in: \(s)")
            XCTAssertFalse(s.contains("--"), "double hyphen in: \(s)")
        }
    }

    func testBoldMarkupIsBalanced() {
        for s in CurriculumScan.lessonAndFactStrings {
            let count = s.components(separatedBy: "**").count - 1
            XCTAssertEqual(count % 2, 0, "unbalanced ** in: \(s)")
            XCTAssertFalse(s.contains("****"), "empty bold in: \(s)")
        }
    }

    func testChineseTermsAlwaysComeWithMatchingPinyin() {
        let pinyin = Dictionary(uniqueKeysWithValues: Curriculum.glossary.map { ($0.chinese, $0.pinyin) })
        var seen = Set<String>()
        for s in CurriculumScan.lessonAndFactStrings {
            for run in CurriculumScan.chineseRuns(in: s) {
                seen.insert(run.term)
                guard let expected = pinyin[run.term] else {
                    XCTFail("\(run.term) is not in the glossary (in: \(s))")
                    continue
                }
                XCTAssertTrue(run.after.hasPrefix(" (\(expected))"), "\(run.term) should be followed by (\(expected)) in: \(s)")
            }
        }
        // Every glossary term is taught somewhere in the lessons or facts.
        for entry in Curriculum.glossary {
            XCTAssertTrue(seen.contains(entry.chinese), "\(entry.chinese) never appears in a lesson or fact")
        }
    }

    // MARK: Glossary

    func testGlossaryHasTheCoreTermsWithAccuratePinyin() {
        let required: [String: String] = [
            "升级": "shēngjí", "拖拉机": "tuōlājī", "主牌": "zhǔpái", "副牌": "fùpái", "庄家": "zhuāngjiā",
            "闲家": "xiánjiā", "底牌": "dǐpái", "扣底": "kòudǐ", "亮主": "liàngzhǔ", "反主": "fǎnzhǔ",
            "对子": "duìzi", "甩牌": "shuǎipái", "毙": "bì", "垫牌": "diànpái", "分": "fēn", "大王": "dàwáng",
            "小王": "xiǎowáng", "级": "jí", "无主": "wúzhǔ", "抠底": "kōudǐ", "级牌": "jípái", "跟牌": "gēnpái",
        ]
        let glossary = Curriculum.glossary
        XCTAssertTrue((20...26).contains(glossary.count), "\(glossary.count) entries")
        XCTAssertEqual(Set(glossary.map(\.id)).count, glossary.count)
        XCTAssertEqual(Set(glossary.map(\.chinese)).count, glossary.count)
        for (chinese, py) in required {
            let entry = glossary.first { $0.chinese == chinese }
            XCTAssertNotNil(entry, chinese)
            XCTAssertEqual(entry?.pinyin, py, chinese)
        }
        for entry in glossary {
            XCTAssertFalse(entry.english.isEmpty)
            XCTAssertFalse(entry.meaning.isEmpty, entry.english)
            XCTAssertLessThanOrEqual(CurriculumScan.words(entry.meaning), 25, entry.english)
            XCTAssertTrue(entry.chinese.allSatisfy(CurriculumScan.isCJK), entry.english)
            XCTAssertTrue(entry.pinyin.allSatisfy { $0.isLetter && !CurriculumScan.isCJK($0) }, entry.english)
        }
    }

    // MARK: Content that can be checked with the card model (implemented now)

    func testPointClaimsMatchCardValues() {
        XCTAssertEqual(CurriculumScan.cardsPage(lesson: 1, title: "The 80-point line")?.cards.points, Scoring.takeoverThreshold)
        XCTAssertEqual(CurriculumScan.cardsPage(lesson: 2, title: "Counting a trick")?.cards.points, 25)
        XCTAssertEqual(CurriculumScan.cardsPage(lesson: 10, title: "The kitty bonus")?.cards.points, 25)
        XCTAssertEqual(CurriculumScan.cardsPage(lesson: 10, title: "The kitty bonus")?.cards.count, Round.kittySize)
        XCTAssertEqual(CurriculumScan.cardsPage(lesson: 9, title: "Burying the kitty")?.cards.count, Round.kittySize)
        XCTAssertEqual(CurriculumScan.cardsPage(lesson: 9, title: "Burying the kitty")?.cards.points, 0)

        let q1 = CurriculumScan.question("lesson.2.predict.1")
        XCTAssertEqual(q1?.choices.filter { $0.cards.points > 0 }.count, 1)
        if let q1 { XCTAssertGreaterThan(q1.choices[q1.correctChoice].cards.points, 0) }

        if let q2 = CurriculumScan.question("lesson.2.predict.2"), case let .cards(cards) = q2.visual {
            XCTAssertEqual(String(cards.points), q2.choices[q2.correctChoice].label)
        } else {
            XCTFail("lesson.2.predict.2 should show cards")
        }
    }

    func testDeckFactsMatchTheDeck() {
        let deck = Deck.double()
        XCTAssertEqual(answer("fact.deckSize").hasPrefix("\(deck.count)"), true)
        XCTAssertEqual(answer("fact.totalPoints"), "\(deck.points)")
        XCTAssertEqual(answer("fact.threshold"), "\(Scoring.takeoverThreshold)")
        XCTAssertEqual(answer("fact.kittySize"), "\(Round.kittySize)")
        XCTAssertEqual(answer("fact.startingLevel"), Rank.two.label)
        // "About a third of the deck is trump" (lesson 3).
        let trump = Trump(rank: .seven, suit: .hearts)
        XCTAssertEqual(deck.filter { trump.isTrump($0) }.count * 3, deck.count)
    }

    func testTrumpQuestionsMatchTrumpMembership() {
        if let q = CurriculumScan.question("lesson.3.predict.1"), let trump = q.trump {
            let trumps = q.choices.indices.filter { q.choices[$0].cards.allSatisfy(trump.isTrump) }
            XCTAssertEqual(trumps, [q.correctChoice])
        } else {
            XCTFail("lesson.3.predict.1 missing")
        }
        if let q = CurriculumScan.question("lesson.3.predict.2"), let trump = q.trump, case let .cards(cards) = q.visual {
            XCTAssertEqual(String(cards.filter(trump.isTrump).count), q.choices[q.correctChoice].label)
        } else {
            XCTFail("lesson.3.predict.2 missing")
        }
        if let q = CurriculumScan.question("lesson.3.predict.3"), let trump = q.trump, case let .cards(cards) = q.visual {
            XCTAssertTrue(cards.allSatisfy(trump.isTrump))
            XCTAssertTrue(q.choices[q.correctChoice].label.contains("trump"))
        } else {
            XCTFail("lesson.3.predict.3 missing")
        }
        // Visual pages that list trumps only show trumps.
        for title in ["Three kinds of trump", "Where trump comes from", "No trump suit"] {
            guard let page = CurriculumScan.cardsPage(lesson: 3, title: title), let trump = page.trump else {
                XCTFail(title)
                continue
            }
            XCTAssertTrue(page.cards.allSatisfy(trump.isTrump), title)
        }
    }

    func testTrumpOrderQuestionsMatchStrength() {
        for id in ["lesson.4.predict.1", "lesson.4.predict.2", "lesson.4.predict.3"] {
            guard let q = CurriculumScan.question(id), let trump = q.trump else {
                XCTFail("\(id) missing")
                continue
            }
            let cardChoices = q.choices.filter { $0.cards.count == 1 }
            let best = cardChoices.map { trump.strength($0.cards[0]) }.max()
            let correct = q.choices[q.correctChoice]
            XCTAssertEqual(correct.cards.count, 1, id)
            XCTAssertEqual(correct.cards.first.map(trump.strength), best, id)
            XCTAssertEqual(cardChoices.filter { trump.strength($0.cards[0]) == best }.count, 1, "\(id): highest must be unique")
        }
        // The order page is drawn high to low.
        if let page = CurriculumScan.cardsPage(lesson: 4, title: "The order, high to low"), let trump = page.trump {
            let strengths = page.cards.map(trump.strength)
            XCTAssertEqual(strengths, strengths.sorted(by: >))
        } else {
            XCTFail("order page missing")
        }
        if let page = CurriculumScan.cardsPage(lesson: 4, title: "Skipping the rank"), let trump = page.trump {
            let strengths = page.cards.map(trump.strength)
            XCTAssertEqual(strengths, Array((strengths.last ?? 0)...(strengths.first ?? 0)).reversed(), "consecutive")
        } else {
            XCTFail("skip page missing")
        }
    }

    func testPairAndTractorQuestionsMatchCombos() {
        if let q = CurriculumScan.question("lesson.6.predict.1") {
            let pairs = q.choices.indices.filter { Combos.isPair(q.choices[$0].cards) }
            XCTAssertEqual(pairs, [q.correctChoice])
        } else {
            XCTFail("lesson.6.predict.1 missing")
        }
        if let q = CurriculumScan.question("lesson.7.predict.1"), let trump = q.trump {
            let tractors = q.choices.indices.filter {
                Combos.shape(of: q.choices[$0].cards, trump: trump)?.isTractor == true
            }
            XCTAssertEqual(tractors, [q.correctChoice])
        } else {
            XCTFail("lesson.7.predict.1 missing")
        }
        for id in ["lesson.7.predict.2", "lesson.7.predict.3"] {
            guard let q = CurriculumScan.question(id), let trump = q.trump, case let .cards(cards) = q.visual else {
                XCTFail("\(id) missing")
                continue
            }
            let isTractor = Combos.shape(of: cards, trump: trump)?.isTractor == true
            XCTAssertEqual(q.choices[q.correctChoice].label, isTractor ? "Yes" : "No", id)
        }
        for title in ["Pairs in a row", "Skipping the trump rank", "Trump tractors"] {
            guard let page = CurriculumScan.cardsPage(lesson: 7, title: title), let trump = page.trump else {
                XCTFail(title)
                continue
            }
            XCTAssertEqual(Combos.shape(of: page.cards, trump: trump), .tractor(2), title)
        }
        if let page = CurriculumScan.cardsPage(lesson: 6, title: "What makes a pair"), let trump = page.trump {
            XCTAssertEqual(Combos.decompose(page.cards, trump: trump).map(\.shape), [.pair, .pair])
        } else {
            XCTFail("pair page missing")
        }
    }

    func testJokerCountingQuestion() {
        guard let q = CurriculumScan.question("lesson.12.predict.2"), case let .cards(cards) = q.visual else {
            return XCTFail("lesson.12.predict.2 missing")
        }
        // Both big jokers and one small joker are gone: the other small joker is the top card left.
        XCTAssertEqual(cards.filter { $0.face == .bigJoker }.count, 2)
        XCTAssertEqual(cards.filter { $0.face == .smallJoker }.count, 1)
        XCTAssertTrue(q.choices[q.correctChoice].label.hasPrefix("No"))
    }

    private func answer(_ factID: String) -> String {
        guard let fact = Curriculum.fact(id: factID) else {
            XCTFail("missing \(factID)")
            return ""
        }
        return fact.choices[fact.correctChoice]
    }
}
