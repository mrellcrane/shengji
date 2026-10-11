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
        let body: String
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
                if case let .trick(title, body, plays, trump, winner) = page {
                    return TrickPage(lesson: lesson, title: title, body: body, plays: plays, trump: trump, winner: winner)
                }
                return nil
            }
        }
    }

    static func question(_ id: String) -> Question? {
        predicts.first { $0.question.id == id }?.question
    }

    /// The pages of lesson `number` (empty for an unknown lesson, so a bad lookup fails a test
    /// instead of crashing the test run).
    static func pages(ofLesson number: Int) -> [LessonPage] {
        Curriculum.lessons.first { $0.number == number }?.pages ?? []
    }

    /// The cards shown on a `.cards` page with the given title, in the given lesson.
    static func cardsPage(lesson: Int, title: String) -> (cards: [Card], trump: Trump?, body: String)? {
        for page in pages(ofLesson: lesson) {
            if case let .cards(t, body, cards, trump) = page, t == title { return (cards, trump, body) }
        }
        return nil
    }

    /// The body of a `.text` page with the given title, in the given lesson.
    static func textPage(lesson: Int, title: String) -> String? {
        for page in pages(ofLesson: lesson) {
            if case let .text(t, body) = page, t == title { return body }
        }
        return nil
    }

    /// The worked trick with the given title, in the given lesson.
    static func trickPage(lesson: Int, title: String) -> TrickPage? {
        trickPages.first { $0.lesson.number == lesson && $0.title == title }
    }

    /// The label of a question's right answer (nil if the index is out of range).
    static func correctLabel(_ q: Question) -> String? {
        q.choices.indices.contains(q.correctChoice) ? q.choices[q.correctChoice].label : nil
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

/// An independent referee written straight from DESIGN.md (§Following, §Winning a trick and
/// §Dealing & declaring) with only the card model (`Trump`, `Combos`), which is implemented now.
/// It lets `CurriculumTests` check every trick winner, follow and kitty flip in the content without
/// the engine, and it gives a second opinion next to the engine checks in `CurriculumRulesTests`.
enum ReferenceRules {
    /// How many components of each shape a play has (for a throw, its "multiset of shapes").
    static func shapeCounts(_ cards: [Card], trump: Trump) -> [ComboShape: Int] {
        var counts: [ComboShape: Int] = [:]
        for component in Combos.decompose(cards, trump: trump) { counts[component.shape, default: 0] += 1 }
        return counts
    }

    /// Index of the play winning a (possibly partial) trick; plays[0] is the lead. A play competes
    /// only if it is entirely the led group or entirely trump and has the lead's shapes; its key
    /// component (largest first) must be stronger, and trump beats non-trump. Ties go to the earlier play.
    /// Nil for an empty trick or a lead that mixes groups.
    static func winningIndex(_ plays: [Play], trump: Trump) -> Int? {
        guard let lead = plays.first?.cards, let leadGroup = Combos.group(of: lead, trump: trump),
              let leadKey = Combos.decompose(lead, trump: trump).first else { return nil }
        let leadShapes = shapeCounts(lead, trump: trump)
        var best = 0
        var bestIsTrump = leadGroup.isTrump
        var bestStrength = leadKey.topStrength
        for i in plays.indices.dropFirst() {
            let cards = plays[i].cards
            guard let group = Combos.group(of: cards, trump: trump), group == leadGroup || group.isTrump,
                  shapeCounts(cards, trump: trump) == leadShapes,
                  let key = Combos.decompose(cards, trump: trump).first else { continue }
            let beats = (group.isTrump && !bestIsTrump)
                || (group.isTrump == bestIsTrump && key.topStrength > bestStrength)
            if beats {
                best = i
                bestIsTrump = group.isTrump
                bestStrength = key.topStrength
            }
        }
        return best
    }

    /// Whether `cards` is a legal follow to `lead` from `hand` (DESIGN.md §Following): the same
    /// number of cards; all of the led group when you hold enough of it (else all you hold of it);
    /// and, with enough, the structure `Rules.followRequirement` describes.
    static func isLegalFollow(_ cards: [Card], hand: [Card], lead: [Card], trump: Trump) -> Bool {
        guard cards.count == lead.count, hand.containsAll(cards),
              let leadGroup = Combos.group(of: lead, trump: trump) else { return false }
        let held = Combos.cards(hand, in: leadGroup, trump: trump)
        let played = Combos.cards(cards, in: leadGroup, trump: trump)
        guard held.count >= lead.count else { return played.count == held.count }
        guard played.count == cards.count else { return false }

        // Walk the lead's components, largest first, over the follower's led-group cards.
        var remaining = held
        var tractorLengths: [Int] = []
        var totalPairs = 0
        for component in Combos.decompose(lead, trump: trump) {
            switch component.shape {
            case let .tractor(k):
                if let run = Combos.tractors(in: remaining, length: k, trump: trump).first {
                    tractorLengths.append(k)
                    totalPairs += k
                    remaining.remove(cards: run)
                } else {
                    let pairs = Combos.pairs(in: remaining, trump: trump).prefix(k)
                    totalPairs += pairs.count
                    for pair in pairs { remaining.remove(cards: pair) }
                }
            case .pair:
                if let pair = Combos.pairs(in: remaining, trump: trump).first {
                    totalPairs += 1
                    remaining.remove(cards: pair)
                }
            case .single, .set, .setTractor:
                break
            }
        }
        // The play must hold the required tractors (disjoint) and at least that many pairs.
        var rest = cards
        for k in tractorLengths.sorted(by: >) {
            guard let run = Combos.tractors(in: rest, length: k, trump: trump).first else { return false }
            rest.remove(cards: run)
        }
        return Combos.pairCount(in: cards) >= totalPairs
    }

    /// Nobody declared, so the kitty is flipped card by card: the first trump-rank card sets the suit,
    /// a joker first means no trump suit; with neither, the suit of the highest-ranked card (the first
    /// one if tied). Returns the suit (nil = no trump suit) and the card that fixed it.
    static func kittyFlip(_ kitty: [Card], rank: Rank) -> (suit: Suit?, card: Card)? {
        for card in kitty {
            if card.isJoker { return (nil, card) }
            if card.rank == rank { return (card.suit, card) }
        }
        var highest: Card?
        for card in kitty where (card.rank?.rawValue ?? 0) > (highest?.rank?.rawValue ?? 0) { highest = card }
        return highest.map { ($0.suit, $0) }
    }
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
            // Drawn high to low with no gaps: each card one step below the one before.
            let strengths = page.cards.map(trump.strength)
            XCTAssertEqual(zip(strengths, strengths.dropFirst()).map { $0 - $1 }, Array(repeating: 1, count: max(0, strengths.count - 1)),
                           "consecutive")
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

    // MARK: Rules, checked with the independent referee (no engine needed)

    func testReferenceRefereeBites() {
        // Known cases, so a broken referee can't wave wrong content through.
        let t = Trump(rank: .two, suit: .hearts)
        func p(_ seat: Int, _ cards: [Card]) -> Play { Play(player: seat, cards: cards) }
        let kingLead = p(0, [c(.king, .spades)])
        XCTAssertEqual(ReferenceRules.winningIndex([kingLead, p(1, [c(.ace, .clubs)])], trump: t), 0, "a discard never wins")
        XCTAssertEqual(ReferenceRules.winningIndex([kingLead, p(1, [c(.three, .hearts)])], trump: t), 1, "a trump ruffs")
        XCTAssertEqual(ReferenceRules.winningIndex([kingLead, p(1, [c(.ace, .spades)]), p(2, [c(.ace, .spades, 1)])], trump: t), 1,
                       "a tie goes to the earlier play")
        XCTAssertEqual(ReferenceRules.winningIndex([p(0, [c(.two, .spades)]), p(1, [c(.two, .clubs)])], trump: t), 0,
                       "equal rank cards tie")
        XCTAssertEqual(ReferenceRules.winningIndex([p(0, [c(.ace, .hearts)]), p(1, [c(.two, .clubs)]), p(2, [c(.two, .hearts)])], trump: t), 2)
        let pairLead = p(0, [c(.five, .spades), c(.five, .spades, 1)])
        XCTAssertEqual(ReferenceRules.winningIndex([pairLead, p(1, [.smallJoker(), .bigJoker()])], trump: t), 0,
                       "two trump singles can't beat a pair")
        XCTAssertEqual(ReferenceRules.winningIndex([pairLead, p(1, [c(.three, .hearts), c(.three, .hearts, 1)])], trump: t), 1)
        XCTAssertEqual(ReferenceRules.winningIndex([pairLead, p(1, [c(.ace, .spades), .bigJoker()])], trump: t), 0,
                       "a mixed play can't win")
        XCTAssertNil(ReferenceRules.winningIndex([], trump: t))

        // Following a pair: a held pair must be played; with too few cards of the suit, play them all.
        let lead = [c(.nine, .clubs), c(.nine, .clubs, 1)]
        let hand = [c(.jack, .clubs), c(.jack, .clubs, 1), c(.four, .clubs), c(.ace, .spades)]
        XCTAssertTrue(ReferenceRules.isLegalFollow([c(.jack, .clubs), c(.jack, .clubs, 1)], hand: hand, lead: lead, trump: t))
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.jack, .clubs), c(.four, .clubs)], hand: hand, lead: lead, trump: t))
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.four, .clubs), c(.ace, .spades)], hand: hand, lead: lead, trump: t))
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.jack, .clubs)], hand: hand, lead: lead, trump: t), "wrong count")
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.king, .clubs), c(.four, .clubs)], hand: hand, lead: lead, trump: t), "not in hand")
        let short = [c(.four, .clubs), c(.ace, .spades), c(.six, .diamonds)]
        XCTAssertTrue(ReferenceRules.isLegalFollow([c(.four, .clubs), c(.six, .diamonds)], hand: short, lead: lead, trump: t))
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.ace, .spades), c(.six, .diamonds)], hand: short, lead: lead, trump: t))
        // Following a tractor: a tractor if you have one, else as many pairs as you hold.
        let tractorLead = [c(.five, .clubs), c(.five, .clubs, 1), c(.six, .clubs), c(.six, .clubs, 1)]
        let pairHand = [c(.nine, .clubs), c(.nine, .clubs, 1), c(.king, .clubs), c(.three, .clubs), c(.ace, .clubs)]
        XCTAssertTrue(ReferenceRules.isLegalFollow([c(.nine, .clubs), c(.nine, .clubs, 1), c(.king, .clubs), c(.three, .clubs)],
                                                   hand: pairHand, lead: tractorLead, trump: t))
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.king, .clubs), c(.three, .clubs), c(.ace, .clubs), c(.nine, .clubs)],
                                                    hand: pairHand, lead: tractorLead, trump: t))
        let tractorHand = [c(.nine, .clubs), c(.nine, .clubs, 1), c(.ten, .clubs), c(.ten, .clubs, 1), c(.king, .clubs), c(.king, .clubs, 1)]
        XCTAssertFalse(ReferenceRules.isLegalFollow([c(.nine, .clubs), c(.nine, .clubs, 1), c(.king, .clubs), c(.king, .clubs, 1)],
                                                    hand: tractorHand, lead: tractorLead, trump: t), "must play the tractor")

        // Kitty flip: the first rank card, else a joker first means no trump, else the highest card.
        XCTAssertEqual(ReferenceRules.kittyFlip([c(.ace, .clubs), c(.two, .spades)], rank: .two)?.card, c(.two, .spades))
        let joker = ReferenceRules.kittyFlip([c(.ace, .clubs), .smallJoker(), c(.two, .spades)], rank: .two)
        XCTAssertEqual(joker?.card, .smallJoker())
        if let joker { XCTAssertNil(joker.suit) }
        XCTAssertEqual(ReferenceRules.kittyFlip([c(.nine, .hearts), c(.ace, .clubs), c(.ace, .spades)], rank: .two)?.card,
                       c(.ace, .clubs), "first of the tied highest cards")
    }

    func testTrickPageWinnersMatchReferenceRules() {
        let tricks = CurriculumScan.trickPages
        XCTAssertGreaterThanOrEqual(tricks.count, 8)
        for t in tricks {
            let index = ReferenceRules.winningIndex(t.plays, trump: t.trump)
            XCTAssertEqual(index.map { t.plays[$0].player }, t.winner, "\(t.lesson.id) \(t.title)")
        }
    }

    func testTricksArePlayableUnderReferenceRules() {
        for t in CurriculumScan.trickPages {
            assertReferenceLegal(t.plays, trump: t.trump, allowThrow: t.lesson.number == 11, context: "\(t.lesson.id) \(t.title)")
        }
        for item in CurriculumScan.predicts {
            guard let trump = item.question.trump else { continue }
            switch item.question.visual {
            case let .trick(plays), let .situation(plays, _):
                assertReferenceLegal(plays, trump: trump, allowThrow: false, context: item.question.id)
            default:
                break
            }
        }
    }

    func testRuleVisualsCarryATrump() {
        // Tricks and follows mean nothing without a trump, and the rules checks skip questions that lack one.
        for item in CurriculumScan.predicts {
            switch item.question.visual {
            case .trick, .handAndLead, .situation:
                XCTAssertNotNil(item.question.trump, item.question.id)
            case .none, .cards:
                break
            }
        }
    }

    func testPredictAnswersMatchReferenceRules() {
        let seatLabels = Set(Seats.all.map(Seats.name))
        var whoWins = 0, whichCard = 0, legalFollow = 0, situations = 0
        for item in CurriculumScan.predicts {
            let q = item.question
            guard let trump = q.trump else { continue }
            switch q.visual {
            case let .trick(plays) where q.choices.allSatisfy({ seatLabels.contains($0.label) }):
                let winner = ReferenceRules.winningIndex(plays, trump: trump).map { Seats.name(plays[$0].player) }
                XCTAssertEqual(winner, CurriculumScan.correctLabel(q), q.id)
                whoWins += 1
            case let .trick(plays):
                // "Which card beats it?": you play next, and exactly the right card takes the lead.
                for (i, choice) in q.choices.enumerated() {
                    let trick = plays + [Play(player: Seats.human, cards: choice.cards)]
                    let takesLead = ReferenceRules.winningIndex(trick, trump: trump) == plays.count
                    XCTAssertEqual(takesLead, i == q.correctChoice, "\(q.id): \(choice.label)")
                }
                whichCard += 1
            case let .handAndLead(hand, lead, _):
                for (i, choice) in q.choices.enumerated() {
                    let legal = ReferenceRules.isLegalFollow(choice.cards, hand: hand, lead: lead, trump: trump)
                    XCTAssertEqual(legal, i == q.correctChoice, "\(q.id): \(choice.label)")
                }
                legalFollow += 1
            case let .situation(plays, hand):
                guard let lead = plays.first?.cards else { XCTFail(q.id); continue }
                for choice in q.choices {
                    XCTAssertTrue(ReferenceRules.isLegalFollow(choice.cards, hand: hand, lead: lead, trump: trump), "\(q.id): \(choice.label)")
                }
                situations += 1
            case .none, .cards:
                break
            }
        }
        XCTAssertGreaterThanOrEqual(whoWins, 5)
        XCTAssertGreaterThanOrEqual(whichCard, 1)
        XCTAssertGreaterThanOrEqual(legalFollow, 2)
        XCTAssertGreaterThanOrEqual(situations, 1)
    }

    func testFeedingPredictionHasPartnerWinningWhateverYouPlay() {
        guard let q = CurriculumScan.question("lesson.12.predict.1"), let trump = q.trump,
              case let .situation(plays, _) = q.visual else {
            return XCTFail("lesson.12.predict.1 should be a situation")
        }
        for choice in q.choices {
            let trick = plays + [Play(player: Seats.human, cards: choice.cards)]
            let winner = ReferenceRules.winningIndex(trick, trump: trump).map { trick[$0].player }
            XCTAssertEqual(winner, Seats.partner(of: Seats.human), choice.label)
        }
        let correct = q.choices.indices.contains(q.correctChoice) ? q.choices[q.correctChoice].cards : []
        XCTAssertEqual(correct.points, q.choices.map(\.cards.points).max(), "feed the most points")
    }

    func testTrickBodiesStateTheRightPoints() {
        func points(_ lesson: Int, _ title: String, seat: Int? = nil) -> Int? {
            guard let t = CurriculumScan.trickPage(lesson: lesson, title: title) else {
                XCTFail("lesson.\(lesson) \(title) missing")
                return nil
            }
            return t.plays.filter { seat == nil || $0.player == seat }.flatMap(\.cards).points
        }
        XCTAssertEqual(points(5, "A simple trick", seat: 0), 10, "your King's 10 points")
        XCTAssertEqual(points(5, "Ruffing", seat: 3), 10, "West's K♦ gives their team 10 points")
        XCTAssertEqual(points(6, "A pair beats singles", seat: 2), 15, "Partner adds 15 points")
        XCTAssertEqual(points(8, "The higher pair wins"), 20, "20 points in the trick")
        XCTAssertEqual(points(8, "The higher pair wins", seat: 3), 20, "West's two Kings")
        XCTAssertEqual(points(8, "Over-ruffing", seat: 1), 20, "East's 20 points")
        XCTAssertEqual(points(10, "Winning the last trick"), 10, "the trick's 10 points")
        XCTAssertEqual(points(11, "A throw that stands"), 25, "you win 25 points")
        XCTAssertEqual(points(11, "A throw that stands", seat: 2), 15, "Partner adds the 10♣ and 5♣")
    }

    func testKittyFlipExamplesFollowTheDesignRule() {
        guard let q = CurriculumScan.question("lesson.9.predict.3"), case let .cards(flipped) = q.visual else {
            return XCTFail("lesson.9.predict.3 should show the flipped cards")
        }
        XCTAssertTrue(q.prompt.contains("rank 2"), q.prompt)
        let flip = ReferenceRules.kittyFlip(flipped, rank: .two)
        XCTAssertEqual(flip?.card, c(.two, .spades))
        XCTAssertEqual(flipped.last, flip?.card, "flipping stops at the card that fixes the suit")
        XCTAssertEqual(CurriculumScan.correctLabel(q), "♠ (spades)")

        guard let page = CurriculumScan.cardsPage(lesson: 9, title: "When nobody declares") else {
            return XCTFail("kitty flip page missing")
        }
        XCTAssertEqual(page.cards.count, Round.kittySize)
        // The example is only right at a known trump rank, and the page has no trump badge, so it says which.
        XCTAssertTrue(page.body.contains("rank 2"), page.body)
        XCTAssertEqual(ReferenceRules.kittyFlip(page.cards, rank: .two)?.card, c(.ace, .clubs))
        XCTAssertTrue(page.body.contains("A♣"), page.body)
    }

    func testFactClaimsMatchTheCardModel() {
        let hearts2 = Trump(rank: .two, suit: .hearts)
        // fact.skipRank: with rank 8, the 7♠ sits right below the 9♠.
        let rank8 = Trump(rank: .eight, suit: .hearts)
        XCTAssertEqual(rank8.strength(c(.nine, .spades)) - rank8.strength(c(.seven, .spades)), 1)
        XCTAssertEqual(answer("fact.skipRank"), "7♠")
        // fact.rankCardsEqual: 2♠ and 2♣ are equal; the 2♥ is higher.
        XCTAssertEqual(hearts2.strength(c(.two, .spades)), hearts2.strength(c(.two, .clubs)))
        XCTAssertGreaterThan(hearts2.strength(c(.two, .hearts)), hearts2.strength(c(.two, .spades)))
        XCTAssertEqual(answer("fact.rankCardsEqual"), "They are equal")
        // fact.pairIdentical: 2♠ 2♣ is not a pair.
        XCTAssertFalse(Combos.isPair([c(.two, .spades), c(.two, .clubs)]))
        XCTAssertTrue(answer("fact.pairIdentical").hasPrefix("No"))
        // fact.jokerTractor: two small plus two big jokers is a tractor, and the highest one.
        let jokers = [Card.smallJoker(), .smallJoker(copy: 1), .bigJoker(), .bigJoker(copy: 1)]
        XCTAssertEqual(Combos.shape(of: jokers, trump: hearts2), .tractor(2))
        XCTAssertTrue(answer("fact.jokerTractor").hasPrefix("Yes"))
        // fact.jokersTop: the big joker is the top trump, then the small joker.
        XCTAssertEqual(Array(hearts2.trumpFacesHighToLow.prefix(2)), [.bigJoker, .smallJoker])
        XCTAssertEqual(answer("fact.jokersTop"), "The big joker")
        // fact.noTrumpRound: only jokers and rank cards are trump with no trump suit.
        let noTrump = Trump(rank: .five, suit: nil)
        XCTAssertEqual(Set(Deck.double().filter(noTrump.isTrump).map(\.face)),
                       Set([Face.smallJoker, .bigJoker] + Suit.allCases.map { Face.regular($0, .five) }))
    }

    func testRequiredTopicsAreTaught() {
        func text(_ number: Int) -> String {
            guard let lesson = Curriculum.lessons.first(where: { $0.number == number }) else { return "" }
            return ([lesson.title, lesson.subtitle] + lesson.pages.flatMap(CurriculumScan.strings(of:))).joined(separator: " ")
        }
        // Lesson 1 says the game is also called Tractor, and why.
        XCTAssertTrue(text(1).contains("Tractor") && text(1).contains("拖拉机") && text(1).contains("pairs in a row"))
        // Lesson 12 covers every strategy point on the list.
        let strategy = text(12)
        for topic in ["Feed", "sure winners", "Count", "void", "partner's void", "save your high trumps",
                      "bury short suits", "avoid burying points", "draw"] {
            XCTAssertTrue(strategy.contains(topic), "lesson 12 should teach: \(topic)")
        }
        // Lessons 9, 10 and 11 each warn about house rules in exactly one sentence; the others don't.
        for number in 1...12 {
            let sentences = text(number).components(separatedBy: ". ")
            let warnings = sentences.filter { $0.contains("tables") || $0.contains("House rules") }.count
            XCTAssertEqual(warnings, [9, 10, 11].contains(number) ? 1 : 0, "lesson.\(number) house-rule sentences")
        }
    }

    // MARK: Wording defects found in review (each test guards a fix)

    func testPredictionsOnUnfinishedTricksDontPromiseTheTrick() {
        // With players still to come after you, no card is sure to win the trick (someone may
        // over-ruff), so the question must ask what beats the cards played so far.
        for item in CurriculumScan.predicts {
            let q = item.question
            let plays: [Play]
            switch q.visual {
            case let .trick(p), let .situation(p, _): plays = p
            default: continue
            }
            guard plays.count < 3, Seats.next(after: plays.last?.player ?? 0) == Seats.human else { continue }
            XCTAssertFalse(q.prompt.lowercased().contains("win the trick"), q.id)
        }
    }

    func testWorkedTricksThatRuffNameTheTrumpSuit() {
        // Lessons switch trump between examples; when a worked trick has someone play trump-suit
        // cards as trumps, the body names the suit so the reader isn't left guessing.
        for t in CurriculumScan.trickPages {
            guard let suit = t.trump.suit else { continue }
            let leadIsTrump = t.plays.first.map { $0.cards.allSatisfy(t.trump.isTrump) } ?? false
            let ruffsWithSuit = t.plays.dropFirst().contains { p in
                p.cards.contains { $0.suit == suit && $0.rank != t.trump.rank }
            }
            guard !leadIsTrump, ruffsWithSuit, t.body.contains("trump") else { continue }
            XCTAssertTrue(t.body.contains(suit.symbol), "\(t.lesson.id) \(t.title): name the trump suit")
        }
    }

    func testKittyBonusWordingIsExact() {
        // ×8 is right only for a two-pair tractor (three pairs give ×12), so name the tractor.
        for s in CurriculumScan.lessonAndFactStrings where s.contains("×8") {
            XCTAssertTrue(s.contains("two-pair tractor"), s)
        }
        // The last-trick example states the defenders' total, not just the kitty part.
        guard let t = CurriculumScan.trickPage(lesson: 10, title: "Winning the last trick"),
              let kitty = CurriculumScan.cardsPage(lesson: 10, title: "The kitty bonus") else {
            return XCTFail("lesson 10 examples missing")
        }
        let largest = Combos.decompose(t.plays[0].cards, trump: t.trump).map(\.shape.cardCount).max() ?? 0
        let total = t.plays.flatMap(\.cards).points + kitty.cards.points * 2 * largest
        XCTAssertEqual(total, 110)
        XCTAssertTrue(t.body.contains("**\(total)**"), t.body)
    }

    func testNoMisleadingPhrases() {
        let banned: [(phrase: String, why: String)] = [
            ("before the deal ends", "declaring stays open briefly after the last card"),
            ("second card of your suit", "reinforcing needs the matching rank card, not any card of the suit"),
            ("left out", "it means omitted; the card is still in other hands"),
            ("far more than in most", "a third of the deck is not far more than the usual quarter"),
            ("trick holding", "it reads as if you hold the points; the trick is worth them"),
            ("is the best spade", "the Q♠ is only the highest spade played"),
            ("higher card of the same shape", "a card has no shape; a part (single, pair, tractor) does"),
            ("Only then is the throw safe", "it is safe sooner: a K♠ pair is safe once one A♠ is gone"),
        ]
        for s in CurriculumScan.lessonAndFactStrings + CurriculumScan.glossaryStrings {
            for b in banned where s.contains(b.phrase) {
                XCTFail("\"\(b.phrase)\": \(b.why). In: \(s)")
            }
        }
        // Reinforcing means showing the same rank card again (DESIGN.md: same suit, single to pair).
        let reinforce = CurriculumScan.textPage(lesson: 9, title: "Reinforcing, and who deals")
        XCTAssertTrue(reinforce?.contains("matching rank card") == true, reinforce ?? "page missing")
        // "Spades are led" only pins down what you must play once spades are known not to be trump.
        XCTAssertTrue(Curriculum.fact(id: "fact.mustFollow")?.prompt.contains("Trump suit ♥") == true)
    }

    // MARK: Helpers

    /// Lead is one group (and one combination unless a throw is allowed); each follow is legal for a
    /// hand holding exactly the played cards (the most a learner can infer from the table).
    private func assertReferenceLegal(_ plays: [Play], trump: Trump, allowThrow: Bool, context: String) {
        guard let lead = plays.first?.cards else { return XCTFail("\(context): empty trick") }
        XCTAssertNotNil(Combos.group(of: lead, trump: trump), "\(context): the lead mixes suits")
        if !allowThrow {
            XCTAssertNotNil(Combos.shape(of: lead, trump: trump), "\(context): lead should be one combination")
        }
        for p in plays.dropFirst() {
            XCTAssertTrue(ReferenceRules.isLegalFollow(p.cards, hand: p.cards, lead: lead, trump: trump),
                          "\(context): \(Seats.name(p.player)) \(p.cards.shortText)")
        }
    }

    private func answer(_ factID: String) -> String {
        guard let fact = Curriculum.fact(id: factID), fact.choices.indices.contains(fact.correctChoice) else {
            XCTFail("missing or broken \(factID)")
            return ""
        }
        return fact.choices[fact.correctChoice]
    }
}
