import Foundation

/// Practice skills. Each skill is a *generator* of fresh questions, so spaced review never
/// degenerates into memorising specific answers (variable practice).
public enum SkillID: String, CaseIterable, Codable, Hashable, Sendable {
    /// "How many points is this card worth?"
    case pointValue
    /// "How many points are in these cards?"
    case countPoints
    /// "Trump is 7♥. Is this card a trump?"
    case isTrump
    /// "Which of these trumps is highest?"
    case trumpOrder
    /// "♠ was led. Which of these single cards would win?" (follow, ruff, or discard)
    case cardBeats
    /// "Is this a pair?" (e.g. 2♠ 2♣ with rank 2 is not)
    case isPair
    /// "Is this a tractor?" (consecutive pairs, skipping the trump rank)
    case isTractor
    /// Full trick shown: "Who wins this trick?"
    case trickWinner
    /// "Here's your hand and the lead. Which play is legal?"
    case legalFollow
    /// "Defenders scored 95. What happens?"
    case levelOutcome
    /// "Defenders win the last trick with a pair. Kitty holds 25 points. How many do they get?"
    case kittyBonus
    /// "Partner is winning with the top card. What should you play?" (strategy judgement)
    case bestPlay

    /// Item id used by the scheduler: "skill.<rawValue>".
    public var itemID: String { "skill." + rawValue }

    public init?(itemID: String) {
        guard itemID.hasPrefix("skill.") else { return nil }
        self.init(rawValue: String(itemID.dropFirst(6)))
    }

    /// Short title for progress screens, e.g. "Spot the trumps".
    public var title: String {
        switch self {
        case .pointValue: return "Card points"
        case .countPoints: return "Count the points"
        case .isTrump: return "Spot the trumps"
        case .trumpOrder: return "Trump order"
        case .cardBeats: return "What beats what"
        case .isPair: return "Pairs"
        case .isTractor: return "Tractors"
        case .trickWinner: return "Who wins the trick"
        case .legalFollow: return "Legal plays"
        case .levelOutcome: return "Scoring a round"
        case .kittyBonus: return "The kitty bonus"
        case .bestPlay: return "Smart plays"
        }
    }
}

/// One answer option. Rendered as cards when `cards` is non-empty (with `label` as caption), else as text.
public struct Choice: Hashable, Sendable {
    public var label: String
    public var cards: [Card]

    public init(_ label: String, cards: [Card] = []) {
        self.label = label
        self.cards = cards
    }
}

/// What to draw above the choices.
public enum QuestionVisual: Hashable, Sendable {
    case none
    /// A row of cards.
    case cards([Card])
    /// A trick laid out around the table (plays in order; plays[0] is the lead). May be partial (1 to 4 plays).
    case trick([Play])
    /// The learner's hand plus the cards that were led (for "what may/should you play" questions).
    case handAndLead(hand: [Card], lead: [Card], leader: Int)
    /// A trick in progress (1 to 3 plays, the human to play next) plus the learner's hand
    /// (for strategy questions: "what should you play here?").
    case situation(plays: [Play], hand: [Card])
}

/// A single retrieval-practice question with elaborative feedback.
public struct Question: Identifiable, Hashable, Sendable {
    public var id: String
    /// Scheduler item this question exercises ("skill.isTrump", "fact.kittySize", ...).
    public var itemID: String
    public var prompt: String
    /// Trump context to show as a badge (nil if irrelevant).
    public var trump: Trump?
    public var visual: QuestionVisual
    public var choices: [Choice]
    public var correctChoice: Int
    /// Shown after answering, right or wrong: explains WHY (the rule), not just the answer.
    public var explanation: String
    /// 1 (easiest) ... 3.
    public var difficulty: Int

    public init(id: String, itemID: String, prompt: String, trump: Trump?, visual: QuestionVisual,
                choices: [Choice], correctChoice: Int, explanation: String, difficulty: Int) {
        self.id = id
        self.itemID = itemID
        self.prompt = prompt
        self.trump = trump
        self.visual = visual
        self.choices = choices
        self.correctChoice = correctChoice
        self.explanation = explanation
        self.difficulty = difficulty
    }
}

public enum Drills {
    /// A fresh, randomly generated question for `skill`. Must always have exactly one correct choice,
    /// 2–4 choices in shuffled order, and an explanation that states the underlying rule.
    /// `difficulty` 1...3 widens the variety (e.g. no-trump rounds, rank cards, tractors across the rank).
    ///
    /// Everything random comes from one value drawn from `rng`, so a seed always gives the same question;
    /// that value also makes the question id ("<skill>.<number>").
    public static func make<G: RandomNumberGenerator>(_ skill: SkillID, difficulty: Int, rng: inout G) -> Question {
        let seed = rng.next()
        var dice = DrillDice(seed: seed)
        let level = min(3, max(1, difficulty))
        let draft: DrillDraft
        switch skill {
        case .pointValue: draft = BasicDrills.pointValue(level: level, dice: &dice)
        case .countPoints: draft = BasicDrills.countPoints(level: level, dice: &dice)
        case .isTrump: draft = TrumpDrills.isTrump(level: level, dice: &dice)
        case .trumpOrder: draft = TrumpDrills.trumpOrder(level: level, dice: &dice)
        case .cardBeats: draft = CardBeatsDrill.make(level: level, dice: &dice)
        case .isPair: draft = ShapeDrills.isPair(level: level, dice: &dice)
        case .isTractor: draft = ShapeDrills.isTractor(level: level, dice: &dice)
        case .trickWinner: draft = TrickDrill.make(level: level, dice: &dice)
        case .legalFollow: draft = FollowDrill.make(level: level, dice: &dice)
        case .levelOutcome: draft = ScoringDrills.levelOutcome(level: level, dice: &dice)
        case .kittyBonus: draft = ScoringDrills.kittyBonus(level: level, dice: &dice)
        case .bestPlay: draft = StrategyDrill.make(level: level, dice: &dice)
        }
        return draft.question(id: "\(skill.rawValue).\(seed)", itemID: skill.itemID, difficulty: level, dice: &dice)
    }
}

// MARK: - Shared building blocks
//
// Everything below is private to this file. Card conventions match the lessons: a lone card is copy 0,
// a pair is copy 0 + copy 1, and no (face, copy) appears twice in one question (DrillPool enforces it).

/// All randomness in a drill comes from here, seeded once from the caller's generator.
private struct DrillDice {
    private var generator: SeededGenerator

    init(seed: UInt64) {
        generator = SeededGenerator(seed: seed)
    }

    /// A number in 0..<count (0 when count < 2).
    mutating func below(_ count: Int) -> Int {
        guard count > 1 else { return 0 }
        return Int.random(in: 0..<count, using: &generator)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &generator)
    }

    /// True `percent` times out of 100.
    mutating func chance(_ percent: Int) -> Bool {
        below(100) < percent
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[below(items.count)]
    }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        items.shuffled(using: &generator)
    }

    /// An index chosen with the given relative weights (zero weights are never chosen).
    mutating func weighted(_ weights: [Int]) -> Int {
        var total = 0
        for weight in weights where weight > 0 { total += weight }
        guard total > 0 else { return 0 }
        var roll = below(total)
        for (index, weight) in weights.enumerated() where weight > 0 {
            if roll < weight { return index }
            roll -= weight
        }
        return 0
    }
}

/// Hands out physical cards so that no (face, copy) is used twice in one question.
private struct DrillPool {
    private var used: Set<Int> = []

    func freeCopies(_ face: Face) -> Int {
        var count = 0
        for copy in 0..<2 where !used.contains(Card(face, copy: copy).id) { count += 1 }
        return count
    }

    /// The first free copy of `face` (copy 0 before copy 1), or nil when both are in use.
    mutating func take(_ face: Face) -> Card? {
        for copy in 0..<2 {
            let card = Card(face, copy: copy)
            if !used.contains(card.id) {
                used.insert(card.id)
                return card
            }
        }
        return nil
    }

    /// Both copies of `face` (a pair), or nil when either is in use.
    mutating func takePair(_ face: Face) -> [Card]? {
        guard freeCopies(face) == 2 else { return nil }
        let pair = [Card(face, copy: 0), Card(face, copy: 1)]
        mark(pair)
        return pair
    }

    func isFree(_ card: Card) -> Bool {
        !used.contains(card.id)
    }

    mutating func mark(_ cards: [Card]) {
        for card in cards { used.insert(card.id) }
    }

    /// Every card not handed out yet, in a fixed order.
    func freeCards() -> [Card] {
        Deck.double().filter { !used.contains($0.id) }
    }
}

/// A question before its choices are shuffled. `answer` is the one correct choice.
private struct DrillDraft {
    var prompt: String
    var trump: Trump?
    var visual: QuestionVisual
    var answer: Choice
    var wrong: [Choice]
    var explanation: String

    /// Drops repeated choices, keeps at most 4, and shuffles them.
    func question(id: String, itemID: String, difficulty: Int, dice: inout DrillDice) -> Question {
        var options: [Choice] = [answer]
        for choice in wrong where options.count < 4 {
            let repeats = options.contains { existing in
                existing.label == choice.label || (!choice.cards.isEmpty && DrillText.sameCards(existing.cards, choice.cards))
            }
            if !repeats { options.append(choice) }
        }
        let order = dice.shuffled(Array(options.indices))
        let choices: [Choice] = order.map { options[$0] }
        let correct = order.firstIndex(of: 0) ?? 0
        return Question(id: id, itemID: itemID, prompt: prompt, trump: trump, visual: visual, choices: choices,
                        correctChoice: correct, explanation: explanation, difficulty: difficulty)
    }
}

/// Learner-facing wording shared by the drills.
private enum DrillText {
    /// "Trump suit ♥, rank 2." or "No trump suit, rank 5."
    static func trumpLine(_ trump: Trump) -> String {
        if let suit = trump.suit { return "Trump suit \(suit.symbol), rank \(trump.rank.label)." }
        return "No trump suit, rank \(trump.rank.label)."
    }

    /// "10♥", "small joker".
    static func name(_ card: Card) -> String {
        switch card.face {
        case .smallJoker: return "small joker"
        case .bigJoker: return "big joker"
        case .regular: return card.description
        }
    }

    /// Cards in running text: "9♣ 9♣", "two small jokers", a lone card by its name.
    static func list(_ cards: [Card]) -> String {
        if cards.count == 1, let only = cards.first { return name(only) }
        if cards.count == 2, cards[0].face == cards[1].face, cards[0].isJoker { return "two \(name(cards[0]))s" }
        return cards.map(\.description).joined(separator: " ")
    }

    /// Caption of a card choice: "9♣ 9♣", or "Small joker" for a lone joker.
    static func label(_ cards: [Card]) -> String {
        if cards.count == 1, let only = cards.first, only.isJoker { return capitalized(name(only)) }
        return cards.map(\.description).joined(separator: " ")
    }

    static func cardChoice(_ cards: [Card], trump: Trump?) -> Choice {
        let shown = trump.map { $0.sorted(cards) } ?? cards
        return Choice(label(shown), cards: shown)
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    /// "7", "Jack", "King", "ace".
    static func rankWord(_ rank: Rank) -> String {
        switch rank {
        case .jack: return "Jack"
        case .queen: return "Queen"
        case .king: return "King"
        case .ace: return "ace"
        default: return rank.label
        }
    }

    /// "7s", "Kings", "aces".
    static func rankPlural(_ rank: Rank) -> String {
        rankWord(rank) + "s"
    }

    /// "Your", "East's", "Partner's".
    static func possessive(_ seat: Int) -> String {
        seat == Seats.human ? "Your" : Seats.name(seat) + "'s"
    }

    static func sameCards(_ a: [Card], _ b: [Card]) -> Bool {
        a.map(\.id).sorted() == b.map(\.id).sorted()
    }

    /// "1 level", "2 levels".
    static func levels(_ count: Int) -> String {
        count == 1 ? "1 level" : "\(count) levels"
    }

    /// "a pair", "a tractor" for the shape of a lead.
    static func shapeWord(_ shape: ComboShape) -> String {
        switch shape {
        case .single: return "card"
        case .pair: return "pair"
        case .tractor: return "tractor"
        }
    }
}

/// Card and suit helpers that depend on the trump context.
private enum DrillDeck {
    /// The ranks that are not the trump rank, low to high: the order of every suit this round.
    static func ranks(_ trump: Trump) -> [Rank] {
        Rank.allCases.filter { $0 != trump.rank }
    }

    /// Suits that are not the trump suit (all four in a no-trump round).
    static func plainSuits(_ trump: Trump) -> [Suit] {
        Suit.allCases.filter { $0 != trump.suit }
    }

    static func otherPlainSuits(_ trump: Trump, except suit: Suit) -> [Suit] {
        plainSuits(trump).filter { $0 != suit }
    }

    /// The other suit of the same colour.
    static func sameColour(_ suit: Suit) -> Suit {
        switch suit {
        case .spades: return .clubs
        case .clubs: return .spades
        case .hearts: return .diamonds
        case .diamonds: return .hearts
        }
    }

    static func pair(_ face: Face) -> [Card] {
        [Card(face, copy: 0), Card(face, copy: 1)]
    }

    static func pair(_ rank: Rank, _ suit: Suit) -> [Card] {
        pair(.regular(suit, rank))
    }

    static func randomTrump(_ dice: inout DrillDice, noTrumpPercent: Int) -> Trump {
        let rank = dice.pick(Rank.allCases) ?? .two
        if dice.chance(noTrumpPercent) { return Trump(rank: rank, suit: nil) }
        return Trump(rank: rank, suit: dice.pick(Suit.allCases) ?? .hearts)
    }

    /// Every face of a suit group, from lowest to highest strength.
    static func faces(in group: SuitGroup, trump: Trump) -> [Face] {
        switch group {
        case let .plain(suit): return ranks(trump).map { Face.regular(suit, $0) }
        case .trump: return Array(trump.trumpFacesHighToLow.reversed())
        }
    }

    /// A random single (pairs 0), pair (pairs 1) or tractor (pairs ≥ 2) from `group`, its top
    /// strength above `above` when given, using only faces `allowing` accepts. Taken from the pool;
    /// nil if none is free.
    static func combo(in group: SuitGroup, pairs: Int, above: Int?, trump: Trump, pool: inout DrillPool,
                      dice: inout DrillDice, allowing: (Face) -> Bool = { _ in true }) -> [Card]? {
        let all = faces(in: group, trump: trump).filter(allowing)
        if pairs <= 0 {
            let options = all.filter { face in
                pool.freeCopies(face) > 0 && (above.map { trump.strength(face) > $0 } ?? true)
            }
            guard let face = dice.pick(options), let card = pool.take(face) else { return nil }
            return [card]
        }
        let pairable = all.filter { pool.freeCopies($0) == 2 }
        if pairs == 1 {
            let options = pairable.filter { face in above.map { trump.strength(face) > $0 } ?? true }
            guard let face = dice.pick(options) else { return nil }
            return pool.takePair(face)
        }
        var strengths: [Int] = []
        for face in pairable where !strengths.contains(trump.strength(face)) {
            strengths.append(trump.strength(face))
        }
        var starts: [Int] = []
        for start in strengths {
            var complete = true
            for step in 0..<pairs where !strengths.contains(start + step) { complete = false }
            let top = start + pairs - 1
            if complete && (above.map { top > $0 } ?? true) { starts.append(start) }
        }
        guard let start = dice.pick(starts) else { return nil }
        var cards: [Card] = []
        for level in start..<(start + pairs) {
            let options = pairable.filter { trump.strength($0) == level }
            guard let face = dice.pick(options), let pair = pool.takePair(face) else { return nil }
            cards += pair
        }
        return cards
    }

    /// `base` plus random free cards accepted by `allow`, up to `size` cards (fewer only if the pool runs dry).
    static func fill(_ base: [Card], to size: Int, pool: inout DrillPool, dice: inout DrillDice,
                     allow: (Card) -> Bool) -> [Card] {
        var hand = base
        // Draw at random; most draws succeed, so this is quick.
        var attempts = 0
        while hand.count < size && attempts < 300 {
            attempts += 1
            let id = dice.below(108)
            guard let face = Face(index: id % 54) else { continue }
            let card = Card(face, copy: id / 54)
            guard pool.isFree(card), allow(card) else { continue }
            pool.mark([card])
            hand.append(card)
        }
        // Rarely, few cards qualify: pick from all of them.
        if hand.count < size {
            let candidates = pool.freeCards().filter(allow)
            let chosen = Array(dice.shuffled(candidates).prefix(size - hand.count))
            pool.mark(chosen)
            hand += chosen
        }
        return hand
    }

    /// `count` cards of distinct faces from `group` (so no pairs among them).
    static func distinctFaces(in group: SuitGroup, count: Int, trump: Trump, pool: inout DrillPool,
                              dice: inout DrillDice, allowing: (Face) -> Bool = { _ in true }) -> [Card] {
        let options = faces(in: group, trump: trump).filter { pool.freeCopies($0) == 2 && allowing($0) }
        var cards: [Card] = []
        for face in dice.shuffled(options).prefix(count) {
            if let card = pool.take(face) { cards.append(card) }
        }
        return cards
    }
}

// MARK: - Card points

private enum BasicDrills {
    static func pointValue(level: Int, dice: inout DrillDice) -> DrillDraft {
        let suit = dice.pick(Suit.allCases) ?? .spades
        let kind = dice.weighted([45, 35, level == 1 ? 4 : 12, 8])
        let face: Face
        switch kind {
        case 0: face = .regular(suit, dice.pick([Rank.five, .ten, .king]) ?? .five)
        case 1: face = .regular(suit, dice.pick([Rank.four, .six, .nine, .jack, .queen, .ace]) ?? .ace)
        case 2: face = dice.chance(50) ? .smallJoker : .bigJoker
        default: face = .regular(suit, dice.pick([Rank.two, .three, .seven, .eight]) ?? .three)
        }
        let card = Card(face, copy: 0)

        // From difficulty 2, sometimes make the card a trump: trumps still score only by rank.
        var trump: Trump?
        if level >= 2 && dice.chance(level == 2 ? 30 : 45) {
            if let rank = face.rank, let cardSuit = face.suit {
                if dice.chance(50) {
                    trump = Trump(rank: rank, suit: dice.pick(Suit.allCases))
                } else {
                    let otherRank = dice.pick(Rank.allCases.filter { $0 != rank }) ?? .two
                    trump = Trump(rank: otherRank, suit: cardSuit)
                }
            } else {
                trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 20)
            }
        }

        var explanation = pointExplanation(face)
        if trump != nil { explanation += " Being a trump changes what a card beats, not what it scores." }
        let lead = trump.map { DrillText.trumpLine($0) + " " } ?? ""
        let answer = String(card.points)
        let wrong = ["0", "5", "10"].filter { $0 != answer }.map { Choice($0) }
        return DrillDraft(prompt: lead + "How many points is this card worth?", trump: trump,
                          visual: .cards([card]), answer: Choice(answer), wrong: wrong, explanation: explanation)
    }

    private static func pointExplanation(_ face: Face) -> String {
        let scoring = "Only 5s (5 points), 10s and Kings (10 points) carry points."
        guard let rank = face.rank else {
            return "Jokers win tricks but score **nothing**. " + scoring
        }
        switch rank {
        case .five:
            return "A **5** is worth **5 points**. Only three ranks score: 5s are worth 5, and 10s and Kings are worth 10."
        case .ten:
            return "A **10** is worth **10 points**, just like a King. 5s are worth 5, and every other card scores nothing."
        case .king:
            return "A **King** is worth **10 points**, just like a 10. 5s are worth 5, and every other card scores nothing."
        case .ace:
            return "An **ace** wins tricks but scores **0**. " + scoring
        case .four, .six:
            return "A **\(rank.label)** scores **0**, even though it sits next to the 5. " + scoring
        case .nine:
            return "A **9** scores **0**, even though it sits next to the 10. " + scoring
        case .jack, .queen:
            return "A **\(DrillText.rankWord(rank))** scores **0**, unlike the King. " + scoring
        default:
            return "A **\(rank.label)** scores **0**. " + scoring
        }
    }

    static func countPoints(level: Int, dice: inout DrillDice) -> DrillDraft {
        let count: Int
        switch level {
        case 1: count = dice.int(3...4)
        case 2: count = dice.int(4...6)
        default: count = dice.int(5...7)
        }
        var pool = DrillPool()
        var cards: [Card] = []
        var attempts = 0
        while cards.count < count && attempts < 80 {
            attempts += 1
            let suit = dice.pick(Suit.allCases) ?? .spades
            let kind = dice.weighted([50, 35, level == 1 ? 0 : 5, 10])
            let face: Face
            switch kind {
            case 0: face = .regular(suit, dice.pick([Rank.five, .ten, .king]) ?? .five)
            case 1: face = .regular(suit, dice.pick([Rank.four, .six, .nine, .jack, .queen, .ace]) ?? .ace)
            case 2: face = dice.chance(50) ? .smallJoker : .bigJoker
            default: face = .regular(suit, dice.pick([Rank.two, .three, .seven, .eight]) ?? .three)
            }
            if let card = pool.take(face) { cards.append(card) }
        }

        let sum = cards.points
        let fives = cards.filter { $0.rank == .five }.count
        let kings = cards.filter { $0.rank == .king }.count
        let aces = cards.filter { $0.rank == .ace }.count
        // Distractors from real mistakes first (5s missed or counted as 10, Kings forgotten, aces counted),
        // then near misses.
        let mistakes: [Int] = [sum - 5 * fives, sum + 5 * fives, sum - 10 * kings, sum + 10 * aces]
        let nearby: [Int] = [sum + 5, sum - 5, sum + 10, sum - 10]
        var values: [Int] = []
        func consider(_ value: Int) {
            if value >= 0 && value != sum && !values.contains(value) { values.append(value) }
        }
        for value in dice.shuffled(mistakes) where values.count < 2 { consider(value) }
        for value in dice.shuffled(nearby) where values.count < 3 { consider(value) }
        for value in [sum + 15, sum + 20, sum + 25] where values.count < 3 { consider(value) }

        let explanation: String
        let pointCards = cards.filter { $0.points > 0 }
        if pointCards.isEmpty {
            explanation = "Only 5s, 10s and Kings score, and there are none here: **0 points**. "
                + "Aces, Queens and jokers win tricks but carry no points."
        } else {
            let terms = pointCards.map { "\($0.description) (\($0.points))" }.joined(separator: " + ")
            let rest = pointCards.count < cards.count ? " The other cards score nothing." : ""
            explanation = "Only 5s, 10s and Kings score. Here: \(terms) = **\(sum)**.\(rest)"
        }
        return DrillDraft(prompt: "How many points are in these cards?", trump: nil, visual: .cards(cards),
                          answer: Choice(String(sum)), wrong: values.map { Choice(String($0)) },
                          explanation: explanation)
    }
}

// MARK: - Trumps

private enum TrumpDrills {
    private enum TrumpCase {
        case suitCard, suitRank, offRank, joker, plain, sameColour, nearRank, noTrumpRank, noTrumpPlain
    }

    static func isTrump(level: Int, dice: inout DrillDice) -> DrillDraft {
        let noTrump = level == 3 && dice.chance(40)
        let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: noTrump ? 100 : 0)
        let wantTrump = dice.chance(50)
        let kind: TrumpCase
        if trump.suit == nil {
            kind = wantTrump ? (dice.chance(70) ? .noTrumpRank : .joker) : .noTrumpPlain
        } else if wantTrump {
            let options: [TrumpCase] = [.suitCard, .suitRank, .offRank, .joker]
            let weights = level == 1 ? [80, 20, 0, 0] : [25, 10, 45, 20]
            kind = options[dice.weighted(weights)]
        } else {
            let options: [TrumpCase] = [.plain, .sameColour, .nearRank]
            let weights = level == 1 ? [60, 40, 0] : [35, 30, 35]
            kind = options[dice.weighted(weights)]
        }
        let card = isTrumpCard(kind, trump: trump, dice: &dice)
        let isTrump = trump.isTrump(card)
        let explanation = isTrumpExplanation(kind, card: card, trump: trump, isTrump: isTrump)
        let yes = Choice("Trump")
        let no = Choice("Not trump")
        return DrillDraft(prompt: DrillText.trumpLine(trump) + " Is this card a trump?", trump: trump,
                          visual: .cards([card]), answer: isTrump ? yes : no, wrong: [isTrump ? no : yes],
                          explanation: explanation)
    }

    private static func isTrumpCard(_ kind: TrumpCase, trump: Trump, dice: inout DrillDice) -> Card {
        let ranks = DrillDeck.ranks(trump)
        let trumpSuit = trump.suit ?? .hearts
        let plain = DrillDeck.plainSuits(trump)
        // High cards tempt learners to call a plain card a trump.
        let high = Array(ranks.suffix(3))
        switch kind {
        case .suitCard:
            return Card(dice.pick(ranks) ?? .three, trumpSuit)
        case .suitRank:
            return Card(trump.rank, trumpSuit)
        case .offRank:
            return Card(trump.rank, dice.pick(plain) ?? .spades)
        case .joker:
            return dice.chance(50) ? .smallJoker() : .bigJoker()
        case .noTrumpRank:
            return Card(trump.rank, dice.pick(Suit.allCases) ?? .spades)
        case .plain, .noTrumpPlain:
            let rank = dice.chance(50) ? (dice.pick(high) ?? .ace) : (dice.pick(ranks) ?? .three)
            if kind == .noTrumpPlain && dice.chance(40), let near = nearRank(trump, dice: &dice) {
                return Card(near, dice.pick(plain) ?? .spades)
            }
            return Card(rank, dice.pick(plain) ?? .spades)
        case .sameColour:
            let suit = DrillDeck.sameColour(trumpSuit)
            return Card(dice.pick(ranks) ?? .ace, suit)
        case .nearRank:
            let rank = nearRank(trump, dice: &dice) ?? (dice.pick(ranks) ?? .three)
            return Card(rank, dice.pick(plain) ?? .spades)
        }
    }

    /// A rank next to the trump rank (a lookalike rank card).
    private static func nearRank(_ trump: Trump, dice: inout DrillDice) -> Rank? {
        let below = Rank(rawValue: trump.rank.rawValue - 1)
        let above = Rank(rawValue: trump.rank.rawValue + 1)
        return dice.pick([below, above].compactMap { $0 })
    }

    private static func isTrumpExplanation(_ kind: TrumpCase, card: Card, trump: Trump, isTrump: Bool) -> String {
        let rankWord = DrillText.rankWord(trump.rank)
        let shown = DrillText.name(card)
        let cardSuit = card.suit ?? .spades
        guard let trumpSuit = trump.suit else {
            if card.isJoker {
                return "Yes. The **jokers** are always trumps, even in a round with no trump suit."
            }
            if isTrump {
                return "Yes. With **no trump suit**, the jokers and **every \(rankWord)** are still trumps."
            }
            return "No. With **no trump suit**, only the jokers and the \(DrillText.rankPlural(trump.rank)) are trumps. "
                + "All four suits are plain, so the \(shown) is a plain card."
        }
        let trumpSet = "Trumps are the jokers, every **\(rankWord)** and every **\(trumpSuit.symbol)**."
        switch kind {
        case .joker:
            return "Yes. The **jokers** are always trumps, in every round, whatever the trump suit and rank."
        case .suitRank:
            return "Yes. The \(shown) is the trump rank **and** the trump suit: the highest trump after the two jokers."
        case .offRank:
            return "Yes. **Every \(rankWord)** is a trump this round, whatever its suit: \(trump.rank.label) is the trump rank. "
                + "Your \(shown) isn't a \(cardSuit.singularName) now."
        case .suitCard:
            return "Yes. \(trumpSuit.symbol) is the trump suit, so every \(trumpSuit.singularName) is a trump, "
                + "from the ace down. The jokers and every \(rankWord) are trumps too."
        case .sameColour:
            let colour = cardSuit.isRed ? "red" : "black"
            return "No. Only \(trumpSuit.symbol) is the trump suit; \(cardSuit.symbol) is a plain suit, even though it's "
                + "\(colour) too. " + trumpSet
        case .nearRank:
            let cardRank = card.rank ?? .two
            return "No. Only the **\(DrillText.rankPlural(trump.rank))** are rank cards this round, not the "
                + "\(DrillText.rankPlural(cardRank)). The \(shown) is a plain \(cardSuit.singularName)."
        default:
            let highCard = (card.rank?.rawValue ?? 0) >= Rank.queen.rawValue
            let tail = highCard ? ": high, but not a trump." : ", not a trump."
            return "No. " + trumpSet + " The \(shown) is a plain \(cardSuit.singularName)\(tail)"
        }
    }

    // MARK: Trump order

    static func trumpOrder(level: Int, dice: inout DrillDice) -> DrillDraft {
        let noTrump = level == 3 && dice.chance(35)
        let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: noTrump ? 100 : 0)
        let all = trump.trumpFacesHighToLow
        let suitFaces: [Face] = all.filter { !$0.isJoker && $0.rank != trump.rank }
        let offRanks: [Face] = all.filter { $0.rank == trump.rank && $0.suit != trump.suit }
        let suitRank: Face? = trump.suit.map { Face.regular($0, trump.rank) }

        // 0 big joker, 1 small joker, 2 trump suit's rank card, 3 another rank card, 4 a trump-suit card.
        let weights: [Int]
        if trump.suit == nil {
            weights = [40, 60, 0, 0, 0]
        } else if level == 1 {
            weights = [0, 0, 35, 35, 30]
        } else if level == 2 {
            weights = [15, 25, 25, 25, 10]
        } else {
            weights = [10, 20, 30, 30, 10]
        }
        let kind = dice.weighted(weights)
        var top: Face = .bigJoker
        var lookalike: Face?
        switch kind {
        case 0:
            top = .bigJoker
            lookalike = .smallJoker
        case 1:
            top = .smallJoker
            let preferSuitRank = dice.chance(50)
            let offRank = dice.pick(offRanks)
            lookalike = preferSuitRank ? (suitRank ?? offRank) : offRank
        case 2:
            top = suitRank ?? .smallJoker
            lookalike = dice.pick(offRanks)
        case 3:
            top = dice.pick(offRanks) ?? .smallJoker
            lookalike = suitFaces.first
        default:
            let index = dice.below(min(5, max(1, suitFaces.count - 2)))
            top = suitFaces.indices.contains(index) ? suitFaces[index] : .smallJoker
            lookalike = suitFaces.indices.contains(index + 1) ? suitFaces[index + 1] : nil
        }

        let topStrength = trump.strength(top)
        let lower = all.filter { trump.strength($0) < topStrength }
        let count = level == 1 ? 3 : (level == 2 ? dice.int(3...4) : 4)
        var picks: [Face] = [top]
        if let face = lookalike, lower.contains(face) { picks.append(face) }
        // The rest come from just below the top, where the order is easiest to mix up.
        for face in dice.shuffled(Array(lower.prefix(6))) where picks.count < count && !picks.contains(face) {
            picks.append(face)
        }
        for face in lower where picks.count < count && !picks.contains(face) { picks.append(face) }

        let cards = picks.map { Card($0, copy: 0) }
        let topCard = Card(top, copy: 0)
        let explanation = trumpOrderExplanation(kind: kind, top: topCard, lookalike: lookalike.map { Card($0, copy: 0) },
                                                trump: trump)
        return DrillDraft(prompt: DrillText.trumpLine(trump) + " Which trump is highest?", trump: trump,
                          visual: .none, answer: DrillText.cardChoice([topCard], trump: nil),
                          wrong: cards.dropFirst().map { DrillText.cardChoice([$0], trump: nil) },
                          explanation: explanation)
    }

    private static func trumpOrderExplanation(kind: Int, top: Card, lookalike: Card?, trump: Trump) -> String {
        let shown = DrillText.name(top)
        let plural = DrillText.rankPlural(trump.rank)
        let order: String
        if let suit = trump.suit {
            let highest = trump.rank == .ace ? "King" : "ace"
            order = "Trumps run: big joker, small joker, \(trump.rank.label)\(suit.symbol), the other \(plural) (all equal), "
                + "then \(suit.symbol) from the \(highest) down."
        } else {
            order = "With no trump suit: big joker, small joker, then all the \(plural), which are equal."
        }
        let tip: String
        switch kind {
        case 0:
            tip = "The **big joker** 大王 (dàwáng) is the highest card in the game."
        case 1:
            tip = "Only the big joker beats the **small joker** 小王 (xiǎowáng)."
        case 2:
            tip = "The **\(shown)**, the trump suit's rank card, beats the other \(plural) and every other "
                + "\(trump.suit?.singularName ?? "trump")."
        case 3:
            let other = lookalike.map { " beats the \(DrillText.name($0))" } ?? " is highest"
            tip = "**Every rank card** outranks the trump suit's ordinary cards, so the \(shown)\(other)."
        default:
            tip = "In the trump suit, higher ranks win, skipping the rank: the **\(shown)** is highest here."
        }
        return tip + " " + order
    }
}

// MARK: - What beats what

private enum CardBeatsDrill {
    static let leader = 3

    static func make(level: Int, dice: inout DrillDice) -> DrillDraft {
        let noTrump = level == 3 && dice.chance(30)
        let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: noTrump ? 100 : 0)
        let weights: [Int]
        switch level {
        case 1: weights = [60, 40, 0]
        case 2: weights = [35, 40, 25]
        default: weights = [35, 35, 30]
        }
        let mode = dice.weighted(weights)
        let draft: DrillDraft?
        switch mode {
        case 0: draft = follow(level: level, trump: trump, dice: &dice)
        case 1: draft = void(level: level, trump: trump, dice: &dice)
        default: draft = trumpLead(level: level, trump: trump, dice: &dice)
        }
        return draft ?? fallback()
    }

    private static func prompt(_ trump: Trump, _ lead: Card, extra: String) -> String {
        "\(DrillText.trumpLine(trump)) West leads the \(DrillText.name(lead))\(extra). Which of your cards beats it?"
    }

    private static func draft(trump: Trump, lead: Card, extra: String, answer: Card, wrong: [Card],
                              explanation: String) -> DrillDraft {
        DrillDraft(prompt: prompt(trump, lead, extra: extra), trump: trump,
                   visual: .trick([Play(player: leader, cards: [lead])]),
                   answer: DrillText.cardChoice([answer], trump: nil),
                   wrong: wrong.map { DrillText.cardChoice([$0], trump: nil) }, explanation: explanation)
    }

    /// You hold the led suit: only a higher card of that suit wins.
    private static func follow(level: Int, trump: Trump, dice: inout DrillDice) -> DrillDraft? {
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
        let ranks = DrillDeck.ranks(trump)
        let wantMisread = level >= 2 && dice.chance(50)
        var leadOptions = Array(1...(ranks.count - 2))
        if wantMisread {
            let looksHigher = leadOptions.filter { ranks[$0].rawValue < trump.rank.rawValue }
            if !looksHigher.isEmpty { leadOptions = looksHigher }
        }
        guard let leadIndex = dice.pick(leadOptions) else { return nil }
        let leadRank = ranks[leadIndex]
        let higherRank = ranks[dice.int((leadIndex + 1)...(ranks.count - 1))]
        let lowerRank = ranks[dice.int(0...(leadIndex - 1))]
        let lead = Card(leadRank, suit)
        let higher = Card(higherRank, suit)
        let lower = Card(lowerRank, suit)
        let plural = suit.name.lowercased()
        let singular = suit.singularName

        var third: Card
        var note: String
        if wantMisread && trump.rank.rawValue > leadRank.rawValue {
            third = Card(trump.rank, suit)
            note = " The \(third.description) is a trump this round, not a \(singular), so you can't play it while you hold \(plural)."
        } else {
            let others = DrillDeck.otherPlainSuits(trump, except: suit)
            let bigger = ranks.filter { $0.rawValue > leadRank.rawValue }
            let rank = dice.pick(Array(bigger.suffix(3))) ?? .ace
            third = Card(rank, dice.pick(others) ?? .clubs)
            note = " The \(third.description) can't be played while you hold \(plural), and a discard never wins."
        }
        let explanation = "You hold \(plural), so you must **follow suit**, and the higher \(singular) wins. "
            + "Your **\(higher.description)** beats the \(lead.description); the \(lower.description) is too low." + note
        return draft(trump: trump, lead: lead, extra: "", answer: higher, wrong: [lower, third], explanation: explanation)
    }

    /// You are out of the led suit: any trump wins, a discard never does.
    private static func void(level: Int, trump: Trump, dice: inout DrillDice) -> DrillDraft? {
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
        let ranks = DrillDeck.ranks(trump)
        let lead = Card(dice.pick(Array(ranks.suffix(5))) ?? .ace, suit)
        let others = DrillDeck.otherPlainSuits(trump, except: suit)

        // 0 low trump-suit card, 1 the rank card of the led suit, 2 another rank card, 3 a joker.
        let weights: [Int]
        if trump.suit == nil {
            weights = [0, 40, 30, 30]
        } else if level == 1 {
            weights = [100, 0, 0, 0]
        } else {
            weights = [35, 25, 20, 20]
        }
        let kind = dice.weighted(weights)
        let answer: Card
        switch kind {
        case 0:
            answer = Card(dice.pick(Array(ranks.prefix(6))) ?? .three, trump.suit ?? .hearts)
        case 1:
            answer = Card(trump.rank, suit)
        case 2:
            let rankSuits = Suit.allCases.filter { $0 != suit }
            answer = Card(trump.rank, dice.pick(rankSuits) ?? .hearts)
        default:
            answer = dice.chance(50) ? .smallJoker() : .bigJoker()
        }
        // Two tempting discards: high cards of other plain suits.
        var discards: [Card] = []
        for other in dice.shuffled(others) where discards.count < 2 {
            discards.append(Card(dice.pick(Array(ranks.suffix(3))) ?? .ace, other))
        }
        if discards.count < 2, let other = others.first {
            discards.append(Card(ranks[ranks.count - 4], other))
        }
        guard discards.count == 2 else { return nil }

        let plural = suit.name.lowercased()
        var explanation = "You have no \(plural), so you may **ruff**: any trump beats a plain card, even an ace. "
            + "Your **\(DrillText.name(answer))** is a trump; the \(discards[0].description) and "
            + "\(discards[1].description) would be discards, and a discard never wins."
        if kind == 1 {
            explanation += " The \(answer.description) isn't a \(suit.singularName) this round: \(trump.rank.label) is the trump rank."
        }
        return draft(trump: trump, lead: lead, extra: " and you have no \(plural)", answer: answer, wrong: discards,
                     explanation: explanation)
    }

    /// A trump was led: you must play a trump, and only a higher one wins.
    private static func trumpLead(level: Int, trump: Trump, dice: inout DrillDice) -> DrillDraft? {
        let ascending = Array(trump.trumpFacesHighToLow.reversed())
        let ranks = DrillDeck.ranks(trump)
        let plainAce = Card(ranks.last ?? .ace, dice.pick(DrillDeck.plainSuits(trump)) ?? .spades)
        let offRanks = ascending.filter { $0.rank == trump.rank && $0.suit != trump.suit }

        guard let trumpSuit = trump.suit else {
            // No trump suit: the rank cards are equal, and only a joker beats one.
            guard let leadFace = dice.pick(ascending.filter { !$0.isJoker }) else { return nil }
            let lead = Card(leadFace, copy: 0)
            let tie = Card(dice.pick(ascending.filter { !$0.isJoker && $0 != leadFace }) ?? .smallJoker, copy: 0)
            let answer: Card = dice.chance(50) ? .smallJoker() : .bigJoker()
            let explanation = "A trump was led, so you must play a trump if you have one. With no trump suit the "
                + "\(DrillText.rankPlural(trump.rank)) are equal, so your \(tie.description) only ties, and a tie goes to "
                + "the earlier play. Your **\(DrillText.name(answer))** wins."
            return draft(trump: trump, lead: lead, extra: ", a trump", answer: answer, wrong: [tie, plainAce],
                         explanation: explanation)
        }

        // 0 a trump-suit card, 1 an off-suit rank card, 2 the small joker.
        let weights = level == 2 ? [70, 30, 0] : [30, 45, 25]
        let kind = dice.weighted(weights)
        let leadFace: Face
        switch kind {
        case 0:
            let suitFaces = ascending.filter { $0.suit == trumpSuit && $0.rank != trump.rank }
            leadFace = suitFaces[dice.int(1...(suitFaces.count - 2))]
        case 1:
            leadFace = dice.pick(offRanks) ?? .regular(trumpSuit, ranks[5])
        default:
            leadFace = .smallJoker
        }
        let leadStrength = trump.strength(leadFace)
        let higher = ascending.filter { trump.strength($0) > leadStrength }
        let lower = ascending.filter { trump.strength($0) < leadStrength }.reversed()
        guard let answerFace = dice.pick(Array(higher.prefix(3))),
              let lowerFace = dice.pick(Array(lower.prefix(3))) else { return nil }
        let lead = Card(leadFace, copy: 0)
        let answer = Card(answerFace, copy: 0)
        let low = Card(lowerFace, copy: 0)

        var third = plainAce
        var note = " The \(plainAce.description) is a plain card, so you can't play it while you hold trumps."
        let ties = offRanks.filter { $0 != leadFace }
        if kind == 1 && level == 3 && dice.chance(60), let tieFace = dice.pick(ties) {
            third = Card(tieFace, copy: 0)
            note = " The \(third.description) only ties the \(lead.description), and a tie goes to the earlier play."
        }
        let explanation = "A trump was led and you hold trumps, so you must play one, and the higher trump wins. "
            + "Your **\(DrillText.name(answer))** beats the \(DrillText.name(lead)); the \(DrillText.name(low)) is lower."
            + note
        return draft(trump: trump, lead: lead, extra: ", a trump", answer: answer, wrong: [low, third],
                     explanation: explanation)
    }

    /// Lesson 5's example, used only if a random build ever fails.
    private static func fallback() -> DrillDraft {
        let trump = Trump(rank: .two, suit: .hearts)
        let lead = Card(.king, .spades)
        return draft(trump: trump, lead: lead, extra: " and you have no spades", answer: Card(.three, .hearts),
                     wrong: [Card(.ace, .clubs), Card(.queen, .diamonds)],
                     explanation: "You have no spades, so you may **ruff**: any trump beats a plain card, even an ace. "
                        + "Your **3♥** is a trump; the A♣ and Q♦ would be discards, and a discard never wins.")
    }
}

// MARK: - Pairs and tractors

private enum ShapeDrills {
    private enum PairCase {
        case identicalPlain, identicalTrumpSuit, identicalRank, identicalJoker, noTrumpIdentical
        case sameRankOtherSuit, neighbours, equalRankCards, jokerMix, rankCardsOfTwoStrengths, noTrumpRankCards
    }

    static func isPair(level: Int, dice: inout DrillDice) -> DrillDraft {
        let cases: [PairCase] = [.identicalPlain, .identicalTrumpSuit, .identicalRank, .identicalJoker, .noTrumpIdentical,
                                 .sameRankOtherSuit, .neighbours, .equalRankCards, .jokerMix,
                                 .rankCardsOfTwoStrengths, .noTrumpRankCards]
        let weights: [Int]
        switch level {
        case 1: weights = [30, 20, 0, 0, 0, 30, 20, 0, 0, 0, 0]
        case 2: weights = [12, 10, 16, 12, 0, 14, 6, 18, 12, 0, 0]
        default: weights = [8, 6, 14, 8, 14, 0, 0, 14, 8, 14, 14]
        }
        let kind = cases[dice.weighted(weights)]
        let noTrump = kind == .noTrumpIdentical || kind == .noTrumpRankCards
        var trump = DrillDeck.randomTrump(&dice, noTrumpPercent: noTrump ? 100 : 0)
        if !noTrump && trump.suit == nil { trump.suit = .hearts }
        let trumpSuit = trump.suit ?? .hearts
        let ranks = DrillDeck.ranks(trump)
        let plain = DrillDeck.plainSuits(trump)
        let offSuits = Suit.allCases.filter { $0 != trump.suit }

        var cards: [Card]
        var explanation: String
        switch kind {
        case .identicalPlain, .identicalTrumpSuit:
            let suit = kind == .identicalPlain ? (dice.pick(plain) ?? .spades) : trumpSuit
            cards = DrillDeck.pair(dice.pick(ranks) ?? .nine, suit)
            explanation = "Yes. A pair, 对子 (duìzi), is **two identical cards**: same rank and same suit. "
                + "With two decks, every card exists twice."
        case .identicalRank, .noTrumpIdentical:
            cards = DrillDeck.pair(trump.rank, dice.pick(offSuits) ?? .spades)
            explanation = "Yes. Two \(cards[0].description) are identical cards, so they are a pair: a **trump pair** this "
                + "round, because \(trump.rank.label) is the trump rank."
        case .identicalJoker:
            let face: Face = dice.chance(50) ? .smallJoker : .bigJoker
            cards = DrillDeck.pair(face)
            explanation = "Yes. \(DrillText.capitalized(DrillText.list(cards))) are identical cards, so they make a pair: "
                + "one of the strongest pairs in the game."
        case .sameRankOtherSuit:
            let rank = dice.pick(ranks) ?? .nine
            let suits = dice.shuffled(Suit.allCases)
            cards = [Card(rank, suits[0]), Card(rank, suits[1])]
            explanation = "No. A pair needs **two identical cards**: same rank **and** same suit. "
                + "\(cards[0].description) and \(cards[1].description) are two singles."
        case .neighbours:
            let suit = dice.pick(Suit.allCases) ?? .clubs
            let index = dice.below(ranks.count - 1)
            cards = [Card(ranks[index], suit), Card(ranks[index + 1], suit)]
            explanation = "No. \(cards[0].description) and \(cards[1].description) are neighbours, not identical. "
                + "A pair needs two identical cards, like \(cards[0].description) \(cards[0].description)."
        case .equalRankCards, .noTrumpRankCards:
            let suits = dice.shuffled(offSuits)
            cards = [Card(trump.rank, suits[0]), Card(trump.rank, suits[1])]
            let equal = noTrump ? "With no trump suit all the \(DrillText.rankPlural(trump.rank)) are equal trumps"
                : "\(cards[0].description) and \(cards[1].description) are **equal in strength** this round"
            explanation = "No. \(equal), but they are different cards. A pair needs **two identical cards**."
        case .jokerMix:
            cards = [.smallJoker(), .bigJoker()]
            explanation = "No. The small and big joker are different cards. Two small jokers, or two big jokers, "
                + "make a pair."
        case .rankCardsOfTwoStrengths:
            let other = dice.pick(offSuits) ?? .spades
            cards = dice.chance(50) ? [Card(trump.rank, trumpSuit), Card(trump.rank, other)]
                : [Card(trump.rank, other), Card(trump.rank, trumpSuit)]
            explanation = "No. Both are trumps, but they are different cards, and the "
                + "\(trump.rank.label)\(trumpSuit.symbol) is even higher. A pair needs **two identical cards**."
        }
        let isPair = Combos.isPair(cards)
        let yes = Choice("Yes")
        let no = Choice("No")
        return DrillDraft(prompt: DrillText.trumpLine(trump) + " Is this a pair?", trump: trump, visual: .cards(cards),
                          answer: isPair ? yes : no, wrong: [isPair ? no : yes], explanation: explanation)
    }

    // MARK: Tractors

    private enum TractorCase {
        case plainRun, skipRun, trumpSuitRun, aceAndRank, rankAndSuitRank, jokers, suitRankAndJoker, noTrumpRankAndJoker
        case gap, twoSuits, plainAndTrump, rankLookalike, equalRankPairs, offRankAndJoker, noTrumpEqual, notAPair
        case run3, trumpRun3, jokerRun3, gap3, equal3
    }

    private struct TractorDraft {
        var trump: Trump
        var cards: [Card]
        var explanation: String
    }

    static func isTractor(level: Int, dice: inout DrillDice) -> DrillDraft {
        let fourCard: [(TractorCase, [Int])] = [
            (.plainRun, [45, 12, 0]), (.skipRun, [0, 10, 14]), (.trumpSuitRun, [0, 8, 0]), (.aceAndRank, [0, 10, 8]),
            (.rankAndSuitRank, [0, 8, 8]), (.jokers, [0, 6, 4]), (.suitRankAndJoker, [0, 0, 8]),
            (.noTrumpRankAndJoker, [0, 0, 6]),
            (.gap, [20, 10, 10]), (.twoSuits, [15, 5, 0]), (.plainAndTrump, [10, 8, 0]), (.rankLookalike, [0, 12, 12]),
            (.equalRankPairs, [0, 11, 10]), (.offRankAndJoker, [0, 0, 10]), (.noTrumpEqual, [0, 0, 10]),
            (.notAPair, [10, 0, 0]),
        ]
        let sixCard: [(TractorCase, [Int])] = [
            (.run3, [0, 0, 25]), (.trumpRun3, [0, 0, 15]), (.jokerRun3, [0, 0, 10]), (.gap3, [0, 0, 25]), (.equal3, [0, 0, 25]),
        ]
        let table = level == 3 && dice.chance(40) ? sixCard : fourCard
        let column = level - 1
        var built: TractorDraft?
        var attempts = 0
        while built == nil && attempts < 12 {
            attempts += 1
            let weights = table.map { $0.1[column] }
            let kind = table[dice.weighted(weights)].0
            if let candidate = tractor(kind, dice: &dice) {
                // The wording assumes the case's answer; keep it only if the rules agree.
                let expected = expectsTractor(kind)
                let actual = Combos.shape(of: candidate.cards, trump: candidate.trump) == .tractor(candidate.cards.count / 2)
                if expected == actual { built = candidate }
            }
        }
        let final = built ?? TractorDraft(
            trump: Trump(rank: .eight, suit: .hearts),
            cards: DrillDeck.pair(.seven, .spades) + DrillDeck.pair(.nine, .spades),
            explanation: "Yes. The 8s are trumps this round, so **7♠ and 9♠ are neighbours** in spades. Two pairs in a row: a tractor.")
        let isTractor = Combos.shape(of: final.cards, trump: final.trump) == .tractor(final.cards.count / 2)
        let yes = Choice("Yes")
        let no = Choice("No")
        return DrillDraft(prompt: DrillText.trumpLine(final.trump) + " Is this a tractor?", trump: final.trump,
                          visual: .cards(final.cards), answer: isTractor ? yes : no, wrong: [isTractor ? no : yes],
                          explanation: final.explanation)
    }

    private static func expectsTractor(_ kind: TractorCase) -> Bool {
        switch kind {
        case .plainRun, .skipRun, .trumpSuitRun, .aceAndRank, .rankAndSuitRank, .jokers, .suitRankAndJoker,
             .noTrumpRankAndJoker, .run3, .trumpRun3, .jokerRun3:
            return true
        default:
            return false
        }
    }

    /// Start indices in `ranks` of `length` ranks that are printed neighbours (no rank skipped between them).
    private static func printedRuns(_ ranks: [Rank], length: Int) -> [Int] {
        guard ranks.count >= length else { return [] }
        var starts: [Int] = []
        for start in 0...(ranks.count - length) {
            var ok = true
            for step in 1..<length where ranks[start + step].rawValue != ranks[start].rawValue + step { ok = false }
            if ok { starts.append(start) }
        }
        return starts
    }

    private static func suited(_ dice: inout DrillDice, rank: Rank? = nil) -> Trump {
        var trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 0)
        if let rank { trump.rank = rank }
        return trump
    }

    private static func tractor(_ kind: TractorCase, dice: inout DrillDice) -> TractorDraft? {
        switch kind {
        case .plainRun, .twoSuits, .notAPair, .plainAndTrump:
            let trump = suited(&dice)
            let ranks = DrillDeck.ranks(trump)
            guard let start = dice.pick(printedRuns(ranks, length: 2)),
                  let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let low = ranks[start], high = ranks[start + 1]
            switch kind {
            case .plainRun:
                let cards = DrillDeck.pair(low, suit) + DrillDeck.pair(high, suit)
                return TractorDraft(trump: trump, cards: cards,
                                    explanation: "Yes. \(cards.shortText) is two pairs of **consecutive** rank in one suit: "
                                        + "a tractor, 拖拉机 (tuōlājī). Only a higher tractor can beat it.")
            case .twoSuits:
                guard let other = dice.pick(DrillDeck.otherPlainSuits(trump, except: suit)) else { return nil }
                let first = DrillDeck.pair(low, suit), second = DrillDeck.pair(high, other)
                return TractorDraft(trump: trump, cards: first + second,
                                    explanation: "No. A tractor needs consecutive pairs in **one suit**. "
                                        + "\(first.shortText) and \(second.shortText) are two separate pairs.")
            case .notAPair:
                guard let other = dice.pick(DrillDeck.otherPlainSuits(trump, except: suit)) else { return nil }
                let odd = [Card(high, suit), Card(high, other)]
                return TractorDraft(trump: trump, cards: DrillDeck.pair(low, suit) + odd,
                                    explanation: "No. \(odd[0].description) and \(odd[1].description) are different cards, "
                                        + "so they aren't a pair. A tractor needs two or more **pairs** in a row.")
            default:
                guard let trumpSuit = trump.suit else { return nil }
                let plainFirst = dice.chance(50)
                let plainPair = DrillDeck.pair(plainFirst ? low : high, suit)
                let trumpPair = DrillDeck.pair(plainFirst ? high : low, trumpSuit)
                let cards = plainFirst ? plainPair + trumpPair : trumpPair + plainPair
                return TractorDraft(trump: trump, cards: cards,
                                    explanation: "No. \(trumpSuit.symbol) is trump, so \(trumpPair.shortText) are trumps while "
                                        + "\(plainPair.shortText) are \(suit.name.lowercased()). A tractor must be all one suit.")
            }

        case .skipRun:
            let rank = dice.pick(Rank.allCases.filter { $0 != .two && $0 != .ace }) ?? .eight
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 15)
            let round = Trump(rank: rank, suit: trump.suit)
            guard let below = Rank(rawValue: rank.rawValue - 1), let above = Rank(rawValue: rank.rawValue + 1),
                  let suit = dice.pick(DrillDeck.plainSuits(round)) else { return nil }
            let cards = DrillDeck.pair(below, suit) + DrillDeck.pair(above, suit)
            return TractorDraft(trump: round, cards: cards,
                                explanation: "Yes. The \(DrillText.rankPlural(rank)) are trumps this round, so "
                                    + "**\(below.label)\(suit.symbol) and \(above.label)\(suit.symbol) are neighbours** in "
                                    + "\(suit.name.lowercased()). Two pairs in a row: a tractor.")

        case .trumpSuitRun:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit, let start = dice.pick(printedRuns(DrillDeck.ranks(trump), length: 2)) else {
                return nil
            }
            let ranks = DrillDeck.ranks(trump)
            let cards = DrillDeck.pair(ranks[start], trumpSuit) + DrillDeck.pair(ranks[start + 1], trumpSuit)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. Consecutive pairs in the trump suit make a **trump tractor**: "
                                    + "\(cards.shortText). It beats any plain tractor.")

        case .aceAndRank:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit, let top = DrillDeck.ranks(trump).last,
                  let other = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let cards = DrillDeck.pair(top, trumpSuit) + DrillDeck.pair(trump.rank, other)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. Trump tractors follow the trump order: the other "
                                    + "\(DrillText.rankPlural(trump.rank)) sit **just above** the \(top.label)\(trumpSuit.symbol), "
                                    + "so \(cards.shortText) is a tractor.")

        case .rankAndSuitRank:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit, let other = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let cards = DrillDeck.pair(trump.rank, other) + DrillDeck.pair(trump.rank, trumpSuit)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. The \(trump.rank.label)\(trumpSuit.symbol) ranks **right above** the other "
                                    + "\(DrillText.rankPlural(trump.rank)), so \(cards.shortText) are consecutive trump pairs: a tractor.")

        case .jokers:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 20)
            return TractorDraft(trump: trump, cards: DrillDeck.pair(.smallJoker) + DrillDeck.pair(.bigJoker),
                                explanation: "Yes. The small and big jokers are **consecutive** trumps, so their two pairs "
                                    + "make the highest tractor in the game.")

        case .suitRankAndJoker:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit else { return nil }
            let cards = DrillDeck.pair(trump.rank, trumpSuit) + DrillDeck.pair(.smallJoker)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. The small joker sits **right above** the \(trump.rank.label)\(trumpSuit.symbol), "
                                    + "so \(trump.rank.label)\(trumpSuit.symbol) \(trump.rank.label)\(trumpSuit.symbol) plus "
                                    + "two small jokers is a trump tractor.")

        case .noTrumpRankAndJoker:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 100)
            let suit = dice.pick(Suit.allCases) ?? .spades
            let cards = DrillDeck.pair(trump.rank, suit) + DrillDeck.pair(.smallJoker)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. With no trump suit, every \(DrillText.rankWord(trump.rank)) sits **right below** "
                                    + "the small joker, so \(cards[0].description) \(cards[0].description) plus two small "
                                    + "jokers is a tractor.")

        case .gap:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 15)
            let ranks = DrillDeck.ranks(trump)
            guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let index = dice.below(ranks.count - 2)
            let low = Card(ranks[index], suit), middle = Card(ranks[index + 1], suit), high = Card(ranks[index + 2], suit)
            let cards = DrillDeck.pair(low.face) + DrillDeck.pair(high.face)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "No. \(low.description) and \(high.description) are not neighbours: the "
                                    + "\(middle.description) sits between them. A tractor needs pairs of **consecutive** rank.")

        case .rankLookalike:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 15)
            let neighbours = [Rank(rawValue: trump.rank.rawValue - 1), Rank(rawValue: trump.rank.rawValue + 1)]
            guard let near = dice.pick(neighbours.compactMap { $0 }),
                  let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let nearPair = DrillDeck.pair(near, suit), rankPair = DrillDeck.pair(trump.rank, suit)
            let nearFirst = near < trump.rank
            let cards = nearFirst ? nearPair + rankPair : rankPair + nearPair
            let firstPair = nearFirst ? nearPair : rankPair
            let secondPair = nearFirst ? rankPair : nearPair
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "No. The \(rankPair[0].description) is a trump this round, not a "
                                    + "\(suit.singularName), so \(firstPair.shortText) and \(secondPair.shortText) are in "
                                    + "different suits: two separate pairs.")

        case .equalRankPairs:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit else { return nil }
            let suits = dice.shuffled(DrillDeck.plainSuits(trump))
            let first = DrillDeck.pair(trump.rank, suits[0]), second = DrillDeck.pair(trump.rank, suits[1])
            let label = "\(trump.rank.label)\(trumpSuit.symbol)"
            return TractorDraft(trump: trump, cards: first + second,
                                explanation: "No. \(first[0].description) and \(second[0].description) are **equal** trumps, so "
                                    + "their pairs are not consecutive: it's just two pairs. \(first.shortText) \(label) \(label) "
                                    + "would be a tractor.")

        case .offRankAndJoker:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit, let other = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let rankPair = DrillDeck.pair(trump.rank, other)
            return TractorDraft(trump: trump, cards: rankPair + DrillDeck.pair(.smallJoker),
                                explanation: "No. The \(trump.rank.label)\(trumpSuit.symbol) sits between the other "
                                    + "\(DrillText.rankPlural(trump.rank)) and the small joker, so \(rankPair.shortText) and two "
                                    + "small jokers are not consecutive.")

        case .noTrumpEqual:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 100)
            let suits = dice.shuffled(Suit.allCases)
            let first = DrillDeck.pair(trump.rank, suits[0]), second = DrillDeck.pair(trump.rank, suits[1])
            return TractorDraft(trump: trump, cards: first + second,
                                explanation: "No. With no trump suit all the \(DrillText.rankPlural(trump.rank)) are **equal**, "
                                    + "so \(first.shortText) and \(second.shortText) are not consecutive: just two pairs.")

        case .run3:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 15)
            let ranks = DrillDeck.ranks(trump)
            guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let skipping = (0...(ranks.count - 3)).filter { start in
                ranks[start + 2].rawValue - ranks[start].rawValue == 3
            }
            if dice.chance(50), let start = dice.pick(skipping) {
                let run = [ranks[start], ranks[start + 1], ranks[start + 2]]
                let cards = run.flatMap { DrillDeck.pair($0, suit) }
                let names = run.map { "\($0.label)\(suit.symbol)" }
                return TractorDraft(trump: trump, cards: cards,
                                    explanation: "Yes. The \(DrillText.rankPlural(trump.rank)) are trumps, so \(names[0]), "
                                        + "\(names[1]) and \(names[2]) are consecutive in \(suit.name.lowercased()): three pairs "
                                        + "in a row make a longer tractor.")
            }
            guard let start = dice.pick(printedRuns(ranks, length: 3)) else { return nil }
            let cards = (0..<3).flatMap { DrillDeck.pair(ranks[start + $0], suit) }
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. Three pairs in a row in one suit make a longer tractor. Only a tractor "
                                    + "just as long can beat it.")

        case .trumpRun3:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit, let top = DrillDeck.ranks(trump).last,
                  let other = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let cards = DrillDeck.pair(top, trumpSuit) + DrillDeck.pair(trump.rank, other) + DrillDeck.pair(trump.rank, trumpSuit)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. In trumps, the \(top.label)\(trumpSuit.symbol), the other "
                                    + "\(DrillText.rankPlural(trump.rank)) and the \(trump.rank.label)\(trumpSuit.symbol) are "
                                    + "consecutive: three pairs in a row make a tractor.")

        case .jokerRun3:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 30)
            let suit = trump.suit ?? (dice.pick(Suit.allCases) ?? .spades)
            let cards = DrillDeck.pair(trump.rank, suit) + DrillDeck.pair(.smallJoker) + DrillDeck.pair(.bigJoker)
            let first = cards[0].description
            let reason = trump.suit == nil
                ? "With no trump suit, every \(DrillText.rankWord(trump.rank)) sits right below the small joker"
                : "The \(first) sits right below the small joker"
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "Yes. \(reason), so \(first), small joker and big joker are three trumps in a "
                                    + "row: a tractor of three pairs.")

        case .gap3:
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: 15)
            let ranks = DrillDeck.ranks(trump)
            guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
            let start = dice.below(ranks.count - 3)
            let gapFirst = dice.chance(50)
            let picked: [Int] = gapFirst ? [start, start + 2, start + 3] : [start, start + 1, start + 3]
            let missing = gapFirst ? start + 1 : start + 2
            let cards = picked.flatMap { DrillDeck.pair(ranks[$0], suit) }
            let runPairs = gapFirst ? Array(cards[2...5]) : Array(cards[0...3])
            let loose = gapFirst ? cards[0] : cards[4]
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "No. \(runPairs.shortText) is a tractor, but the \(loose.description) pair isn't "
                                    + "next to it: the \(ranks[missing].label)\(suit.symbol) sits between. That's a tractor "
                                    + "plus a pair.")

        case .equal3:
            let trump = suited(&dice)
            guard let trumpSuit = trump.suit else { return nil }
            let suits = dice.shuffled(DrillDeck.plainSuits(trump))
            let first = Card(trump.rank, suits[0]), second = Card(trump.rank, suits[1])
            let cards = DrillDeck.pair(first.face) + DrillDeck.pair(second.face) + DrillDeck.pair(trump.rank, trumpSuit)
            return TractorDraft(trump: trump, cards: cards,
                                explanation: "No. \(first.description) and \(second.description) are equal, so only one of their "
                                    + "pairs can sit below the \(trump.rank.label)\(trumpSuit.symbol) pair. This is a tractor "
                                    + "plus a pair, not one tractor.")
        }
    }
}

// MARK: - Who wins the trick

/// Full tricks played from dealt hands with legal follows, biased towards the instructive ones
/// (ruffs, over-ruffs, ties, pairs answered with singles, discards).
private enum TrickDrill {
    /// How a follower's hand is dealt, to make an interesting trick likely.
    private enum Plan {
        case open, ruff, unmatchedTrumps, unmatchedSuit, discard, higher
    }

    /// What happened in a trick: used to pick instructive tricks and to explain the winner.
    struct Facts {
        var winner: Int
        var ruff = false
        /// A lower trump play of the lead's shape before the winner (the winner over-ruffed it).
        var ruffedBefore: Int?
        /// A lower trump play of the lead's shape after the winner.
        var ruffedAfter: Int?
        var tie: Int?
        /// The right number of led-suit or trump cards, but not the lead's shape.
        var unmatched: Int?
        /// The unmatched play looked strong: trumps on a plain lead, or a higher card than the winner's.
        var unmatchedLooksStrong = false
        var mixed: Int?
        var discard: Int?

        var score: Int {
            var total = 0
            if ruff { total += 3 }
            if ruffedBefore != nil { total += 3 }
            if ruffedAfter != nil { total += 2 }
            if tie != nil { total += 3 }
            if unmatched != nil { total += 3 }
            if mixed != nil || discard != nil { total += 1 }
            if winner > 0 && !ruff { total += 2 }
            return total
        }
    }

    static func make(level: Int, dice: inout DrillDice) -> DrillDraft {
        var best: (trump: Trump, plays: [Play], facts: Facts)?
        for _ in 0..<3 {
            guard let trick = simulate(level: level, dice: &dice) else { continue }
            let facts = analyze(trick.plays, trump: trick.trump)
            let better = best.map { facts.score > $0.facts.score } ?? true
            if better { best = (trick.trump, trick.plays, facts) }
            // Tractor tricks are instructive (and slow to deal), so a lower bar ends the search sooner.
            let leadSize = trick.plays.first?.cards.count ?? 1
            let goal = level == 1 || leadSize >= 4 ? 2 : 3
            if facts.score >= goal { break }
        }
        guard let chosen = best else { return fallback() }
        return draft(trump: chosen.trump, plays: chosen.plays, facts: chosen.facts)
    }

    private static func draft(trump: Trump, plays: [Play], facts: Facts) -> DrillDraft {
        guard let lead = plays.first, plays.indices.contains(facts.winner) else { return fallback() }
        let leadText: String
        switch lead.cards.count {
        case 1: leadText = "the " + DrillText.list(lead.cards)
        case 2: leadText = DrillText.list(lead.cards)
        default: leadText = "the tractor " + DrillText.list(lead.cards)
        }
        let verb = lead.player == Seats.human ? "lead" : "leads"
        let prompt = "\(DrillText.trumpLine(trump)) \(Seats.name(lead.player)) \(verb) \(leadText). Who wins the trick?"
        let winnerSeat = plays[facts.winner].player
        let wrong = Seats.all.filter { $0 != winnerSeat }.map { Choice(Seats.name($0)) }
        return DrillDraft(prompt: prompt, trump: trump, visual: .trick(plays), answer: Choice(Seats.name(winnerSeat)),
                          wrong: wrong, explanation: explain(plays, facts: facts, trump: trump))
    }

    /// Lesson 8's over-ruff, used only if a random trick ever fails to build.
    private static func fallback() -> DrillDraft {
        let trump = Trump(rank: .two, suit: .hearts)
        let plays = [Play(player: 1, cards: DrillDeck.pair(.king, .diamonds)),
                     Play(player: 2, cards: DrillDeck.pair(.three, .hearts)),
                     Play(player: 3, cards: DrillDeck.pair(.two, .clubs)),
                     Play(player: 0, cards: [Card(.queen, .diamonds), Card(.jack, .diamonds)])]
        let facts = analyze(plays, trump: trump)
        let winnerSeat = plays.indices.contains(facts.winner) ? plays[facts.winner].player : 3
        return DrillDraft(prompt: "Trump suit ♥, rank 2. East leads K♦ K♦. Who wins the trick?", trump: trump,
                          visual: .trick(plays), answer: Choice(Seats.name(winnerSeat)),
                          wrong: Seats.all.filter { $0 != winnerSeat }.map { Choice(Seats.name($0)) },
                          explanation: explain(plays, facts: facts, trump: trump))
    }

    // MARK: Dealing and playing

    private static func simulate(level: Int, dice: inout DrillDice) -> (trump: Trump, plays: [Play])? {
        let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: level == 3 ? 20 : 0)
        let shapeWeights: [Int]
        switch level {
        case 1: shapeWeights = [75, 25, 0, 0]
        case 2: shapeWeights = [25, 55, 20, 0]
        default: shapeWeights = [15, 35, 38, 12]
        }
        let pairs = dice.weighted(shapeWeights)
        let handSize = level == 1 ? 8 : 10
        var pool = DrillPool()
        // Difficulty 1 keeps to the basics: plain-suit leads, and no rank cards of other suits in play.
        let basic = level == 1
        let basicFace: (Face) -> Bool = { face in !basic || face.rank != trump.rank || face.suit == trump.suit }
        let plainSuit: Suit? = basic || dice.chance(80) ? dice.pick(DrillDeck.plainSuits(trump)) : nil
        let ledGroup: SuitGroup = plainSuit.map { SuitGroup.plain($0) } ?? .trump
        guard let lead = DrillDeck.combo(in: ledGroup, pairs: pairs, above: nil, trump: trump, pool: &pool, dice: &dice)
        else { return nil }
        let leadTop = lead.map { trump.strength($0) }.max() ?? 0
        let leader = dice.below(4)
        var hands: [[Card]] = [[], [], [], []]
        hands[leader] = DrillDeck.fill(lead, to: handSize, pool: &pool, dice: &dice) { basicFace($0.face) }

        let followers = [1, 2, 3].map { (leader + $0) % 4 }
        var plans: [Plan] = [.open, .open, .open, .open]
        let picked = dice.shuffled(followers)
        let target = ledGroup.isTrump ? dice.weighted([0, 0, 40, 60]) : dice.weighted([35, 20, 20, 25])
        switch target {
        case 0:
            plans[picked[0]] = .ruff
        case 1:
            plans[picked[0]] = .ruff
            plans[picked[1]] = .ruff
        case 2:
            if lead.count == 1 {
                plans[picked[0]] = .discard
            } else if !ledGroup.isTrump && dice.chance(50) {
                plans[picked[0]] = .unmatchedTrumps
            } else {
                plans[picked[0]] = .unmatchedSuit
            }
        default:
            plans[picked[0]] = .higher
        }

        for seat in followers {
            var base: [Card] = []
            var allow: (Card) -> Bool = { basicFace($0.face) }
            switch plans[seat] {
            case .open:
                break
            case .ruff:
                base = DrillDeck.combo(in: .trump, pairs: pairs, above: nil, trump: trump, pool: &pool, dice: &dice,
                                       allowing: basicFace) ?? []
                allow = { basicFace($0.face) && trump.group($0) != ledGroup }
            case .unmatchedTrumps:
                base = DrillDeck.distinctFaces(in: .trump, count: lead.count, trump: trump, pool: &pool, dice: &dice,
                                               allowing: basicFace)
                allow = { !trump.isTrump($0) && trump.group($0) != ledGroup }
            case .unmatchedSuit:
                base = DrillDeck.distinctFaces(in: ledGroup, count: lead.count, trump: trump, pool: &pool, dice: &dice)
                allow = { basicFace($0.face) && trump.group($0) != ledGroup }
            case .discard:
                allow = { !trump.isTrump($0) && trump.group($0) != ledGroup }
            case .higher:
                base = DrillDeck.combo(in: ledGroup, pairs: pairs, above: leadTop, trump: trump, pool: &pool, dice: &dice) ?? []
            }
            hands[seat] = DrillDeck.fill(base, to: handSize, pool: &pool, dice: &dice, allow: allow)
        }

        var plays = [Play(player: leader, cards: lead)]
        for seat in followers {
            let candidates = followCandidates(hand: hands[seat], lead: lead, trump: trump, dice: &dice)
            guard let choice = choose(from: candidates, hand: hands[seat], seat: seat, plays: plays, trump: trump,
                                      dice: &dice) else { return nil }
            plays.append(Play(player: seat, cards: choice))
        }
        return (trump, plays)
    }

    /// A seat tries to win when an opponent is winning, and usually lets a winning partner be.
    /// Candidates are checked with `Rules.validateFollow` as they are considered: only legal plays are chosen.
    private static func choose(from candidates: [[Card]], hand: [Card], seat: Int, plays: [Play], trump: Trump,
                               dice: inout DrillDice) -> [Card]? {
        guard let lead = plays.first?.cards, let first = lead.first else { return nil }
        let current = Rules.winningIndex(plays, trump: trump)
        guard plays.indices.contains(current) else { return nil }
        let partnerWinning = Seats.team(of: plays[current].player) == Seats.team(of: seat)
        // What the seat looks for first: a winning play, a non-winning one, or anything legal (nil).
        let wantWin: Bool?
        if partnerWinning {
            wantWin = dice.chance(85) ? false : nil
        } else {
            wantWin = dice.chance(75) ? true : nil
        }
        // The lead's format is worked out once; each candidate is then compared with the play winning now,
        // as `Rules.winningIndex` does for a new play (this only steers the seat's choice: the question's
        // answer always comes from `Rules.winningIndex` itself).
        let format = Rules.LeadFormat(lead, trump: trump)
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let bestCards = plays[current].cards
        let bestIsTrump = Combos.group(of: bestCards, trump: trump) == .trump
        let bestKey = Rules.structureKey(bestCards, format: format, trump: trump) ?? Int.max
        func wouldWin(_ play: [Card]) -> Bool {
            guard let group = Combos.group(of: play, trump: trump), group == ledGroup || group.isTrump,
                  let key = Rules.structureKey(play, format: format, trump: trump) else { return false }
            if group.isTrump && !bestIsTrump { return true }
            return group.isTrump == bestIsTrump && key > bestKey
        }
        var others: [[Card]] = []
        for play in dice.shuffled(candidates) {
            if let wanted = wantWin {
                if wouldWin(play) != wanted {
                    others.append(play)
                    continue
                }
            }
            if Rules.validateFollow(play, hand: hand, lead: lead, trump: trump) == nil { return play }
        }
        for play in others where Rules.validateFollow(play, hand: hand, lead: lead, trump: trump) == nil {
            return play
        }
        return nil
    }

    /// A varied set of follows from `hand` built from the follow rule (tractors and pairs first, then
    /// filler; ruffs and discards when short). Not yet validated: `choose` checks each one it considers.
    private static func followCandidates(hand: [Card], lead: [Card], trump: Trump, dice: inout DrillDice) -> [[Card]] {
        guard let first = lead.first else { return [] }
        let count = lead.count
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let sorted = cheapSorted(hand, trump: trump)
        let held = sorted.filter { trump.group($0) == ledGroup }
        let others = sorted.filter { trump.group($0) != ledGroup }
        var raw: [[Card]] = []
        if held.count >= count {
            if count == 1 {
                raw = held.map { [$0] }
            } else {
                let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
                for core in cores(held: held, requirement: requirement, trump: trump, dice: &dice) {
                    var rest = held
                    rest.remove(cards: core)
                    let need = count - core.count
                    guard need >= 0, rest.count >= need else { continue }
                    raw.append(core + Array(rest.prefix(need)))
                    raw.append(core + Array(dice.shuffled(rest).prefix(need)))
                    if count < 4 { raw.append(core + Array(rest.suffix(need))) }
                }
            }
        } else {
            let need = count - held.count
            let trumps = others.filter { trump.isTrump($0) }
            let plain = others.filter { !trump.isTrump($0) }
            if held.isEmpty && !ledGroup.isTrump {
                raw += matching(lead: lead, in: trumps, trump: trump)
                if trumps.count >= count { raw.append(Array(trumps.prefix(count))) }
            }
            if plain.count >= need { raw.append(held + Array(plain.prefix(need))) }
            raw.append(held + Array(others.prefix(need)))
            raw.append(held + Array(dice.shuffled(others).prefix(need)))
        }
        var seen: [[Int]] = []
        var candidates: [[Card]] = []
        for play in raw where play.count == count && Set(play.map(\.id)).count == count {
            let key = play.map(\.id).sorted()
            if seen.contains(key) { continue }
            seen.append(key)
            candidates.append(play)
        }
        return candidates
    }

    /// Cards grouped by suit group (plain suits, then trumps), low to high, ties by id. Same idea as
    /// `Trump.sorted` but with each card's key computed once, which keeps simulated tricks fast.
    private static func cheapSorted(_ cards: [Card], trump: Trump) -> [Card] {
        let keyed: [(card: Card, key: Int)] = cards.map { card in
            let groupKey = trump.group(card).plainSuit?.rawValue ?? 4
            return (card, groupKey * 1000 + trump.strength(card) * 10)
        }
        let ordered = keyed.sorted { a, b in a.key != b.key ? a.key < b.key : a.card.id < b.card.id }
        return ordered.map(\.card)
    }

    /// Trump combinations with the lead's shape (ruffs).
    private static func matching(lead: [Card], in cards: [Card], trump: Trump) -> [[Card]] {
        guard let shape = Combos.shape(of: lead, trump: trump) else { return [] }
        switch shape {
        case .single:
            var faces: [Face] = []
            var singles: [[Card]] = []
            for card in cards where !faces.contains(card.face) {
                faces.append(card.face)
                singles.append([card])
            }
            return singles
        case .pair:
            return Combos.pairs(in: cards, trump: trump)
        case let .tractor(length):
            return Array(Combos.tractors(in: cards, length: length, trump: trump).prefix(8))
        }
    }

    /// The structured part a follow must contain (tractors, then pairs), in a few variations.
    private static func cores(held: [Card], requirement: FollowRequirement, trump: Trump,
                              dice: inout DrillDice) -> [[Card]] {
        let pairs = Combos.pairs(in: held, trump: trump)
        if requirement.tractorLengths.isEmpty {
            let needed = requirement.totalPairs
            guard needed > 0 else { return [[]] }
            guard pairs.count >= needed else { return [] }
            var result: [[Card]] = [Array(pairs.prefix(needed).joined()), Array(pairs.suffix(needed).joined()),
                                    Array(dice.shuffled(pairs).prefix(needed).joined())]
            if needed == 1 { result += pairs }
            return result
        }
        guard requirement.tractorLengths.count == 1, let length = requirement.tractorLengths.first else { return [] }
        var result: [[Card]] = []
        for tractor in Combos.tractors(in: held, length: length, trump: trump).prefix(4) {
            var core = tractor
            var rest = held
            rest.remove(cards: tractor)
            let extra = requirement.totalPairs - length
            if extra > 0 {
                for pair in Combos.pairs(in: rest, trump: trump).prefix(extra) { core += pair }
            }
            result.append(core)
        }
        return result
    }

    // MARK: Explaining

    static func analyze(_ plays: [Play], trump: Trump) -> Facts {
        guard let lead = plays.first?.cards, let first = lead.first else { return Facts(winner: 0) }
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let winner = Rules.winningIndex(plays, trump: trump)
        var facts = Facts(winner: winner)
        guard plays.indices.contains(winner) else { return facts }
        let winningCards = plays[winner].cards
        let winnerIsTrump = Combos.group(of: winningCards, trump: trump) == .trump
        facts.ruff = !ledGroup.isTrump && winnerIsTrump
        let format = Rules.LeadFormat(lead, trump: trump)
        let winningKey = Rules.structureKey(winningCards, format: format, trump: trump)
        for index in plays.indices.dropFirst() where index != winner {
            let cards = plays[index].cards
            guard let group = Combos.group(of: cards, trump: trump) else {
                if facts.mixed == nil { facts.mixed = index }
                continue
            }
            if group != ledGroup && !group.isTrump {
                if facts.discard == nil { facts.discard = index }
                continue
            }
            guard let key = Rules.structureKey(cards, format: format, trump: trump) else {
                if lead.count > 1 {
                    let top = cards.map { trump.strength($0) }.max() ?? 0
                    let winningTop = winningCards.map { trump.strength($0) }.max() ?? 0
                    let strong = (group.isTrump && !winnerIsTrump) || (group.isTrump == winnerIsTrump && top > winningTop)
                    if facts.unmatched == nil || (strong && !facts.unmatchedLooksStrong) {
                        facts.unmatched = index
                        facts.unmatchedLooksStrong = strong
                    }
                }
                continue
            }
            let tied = index > winner && key == winningKey && group.isTrump == winnerIsTrump
            if tied { facts.tie = index }
            if !ledGroup.isTrump && group.isTrump {
                if index < winner {
                    facts.ruffedBefore = index
                } else if !tied {
                    facts.ruffedAfter = index
                }
            }
        }
        return facts
    }

    private static func explain(_ plays: [Play], facts: Facts, trump: Trump) -> String {
        guard let lead = plays.first?.cards, let first = lead.first, plays.indices.contains(facts.winner) else {
            return "The highest play of the lead's shape, all in the led suit or all trump, wins the trick."
        }
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let shape = Combos.decompose(lead, trump: trump).first?.shape ?? .single
        let word = DrillText.shapeWord(shape)
        let winning = plays[facts.winner]
        let isYou = winning.player == Seats.human
        let name = Seats.name(winning.player)
        let suitSingular = ledGroup.plainSuit?.singularName ?? "trump"
        var sentences: [String] = ["\(name) \(isYou ? "win" : "wins") with \(DrillText.list(winning.cards))."]

        if facts.ruff {
            if let before = facts.ruffedBefore {
                let midName = isYou ? "you" : name
                sentences.append("\(Seats.name(plays[before].player)) ruffed first, but \(midName) over-ruffed with a "
                    + "higher trump \(word): among trumps, the higher one wins.")
            } else {
                let beats = lead.count == 1 ? "a trump beats any plain card" : "a trump \(word) beats any plain \(word)"
                sentences.append("\(name) \(isYou ? "were" : "was") out of \(ledGroup.name) and ruffed: \(beats).")
                if let after = facts.ruffedAfter {
                    let what = lead.count == 1 ? "trump" : "trump \(word)"
                    sentences.append("\(DrillText.possessive(plays[after].player)) \(what) was lower.")
                }
            }
            // A rank card printed in the led suit looks like that suit, but it is a trump.
            if let ledSuit = ledGroup.plainSuit,
               let lookalike = winning.cards.first(where: { $0.rank == trump.rank && $0.suit == ledSuit }) {
                sentences.append("The \(lookalike.description) is a trump this round, not a \(ledSuit.singularName).")
            }
        } else if facts.winner == 0 {
            if ledGroup.isTrump {
                sentences.append(lead.count == 1 ? "Nobody played a higher trump." : "Nobody played a higher trump \(word).")
            } else if lead.count == 1 {
                sentences.append("Nobody played a higher \(suitSingular) or a trump.")
            } else {
                sentences.append("Nobody matched it with a higher \(suitSingular) \(word) or a trump \(word).")
            }
        } else if lead.count == 1 {
            let extra = ledGroup.isTrump ? "" : ", and nobody ruffed"
            sentences.append("It is the highest \(suitSingular) played\(extra).")
        } else {
            let same = ledGroup.isTrump ? "all trump" : "same suit"
            sentences.append("Same shape, \(same) and higher: the highest \(suitSingular) \(word) wins.")
        }

        // One note on the most tempting play that lost, if it fits in the 50-word budget.
        var note: String?
        if let index = facts.tie {
            note = "\(DrillText.possessive(plays[index].player)) \(DrillText.list(plays[index].cards)) only tied, "
                + "and a tie goes to the earlier play."
        } else if let index = facts.unmatched {
            note = "\(DrillText.possessive(plays[index].player)) \(DrillText.list(plays[index].cards)) are not a "
                + "\(word), so they can't win\(facts.unmatchedLooksStrong ? ", however high" : "")."
        } else if let index = facts.mixed {
            note = "\(Seats.name(plays[index].player)) mixed suits, and a mixed play never wins."
        } else if let index = facts.discard {
            note = "\(Seats.name(plays[index].player)) discarded, and a discard never wins."
        }
        let main = sentences.joined(separator: " ")
        guard let extra = note else { return main }
        let words = (main + " " + extra).split(whereSeparator: { $0.isWhitespace }).count
        return words <= 50 ? main + " " + extra : main
    }
}

// MARK: - Legal plays

private enum FollowDrill {
    private struct Setup {
        var trump: Trump
        var lead: [Card]
        var hand: [Card]
        var correct: [Card]
        var wrong: [[Card]]
        var explanation: String
    }

    private enum Template {
        case single, trumpSingle, pairHeld, noPair, short, trumpPair, tractorHeld, twoPairs, onePair
    }

    static func make(level: Int, dice: inout DrillDice) -> DrillDraft {
        let templates: [Template] = [.single, .trumpSingle, .pairHeld, .noPair, .short, .trumpPair,
                                     .tractorHeld, .twoPairs, .onePair]
        let weights: [Int]
        switch level {
        case 1: weights = [45, 0, 55, 0, 0, 0, 0, 0, 0]
        case 2: weights = [15, 15, 20, 20, 15, 15, 0, 0, 0]
        default: weights = [0, 8, 0, 10, 10, 12, 25, 18, 17]
        }
        for _ in 0..<12 {
            let template = templates[dice.weighted(weights)]
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: level == 3 ? 25 : 0)
            var pool = DrillPool()
            guard var setup = build(template, level: level, trump: trump, pool: &pool, dice: &dice),
                  let leadCard = setup.lead.first else { continue }
            // Fill up to 8 to 12 cards with cards outside the led suit: they never change what is legal.
            // At difficulty 1 that leaves out the led suit's rank card too (a trump that looks like the suit).
            let ledGroup = Combos.group(of: setup.lead, trump: trump) ?? trump.group(leadCard)
            let ledSuit = ledGroup.plainSuit
            let size = dice.int(8...12)
            setup.hand = DrillDeck.fill(setup.hand, to: size, pool: &pool, dice: &dice) { card in
                trump.group(card) != ledGroup && (level >= 2 || ledSuit == nil || card.suit != ledSuit)
            }
            guard isSound(setup) else { continue }
            return draft(setup, leader: dice.pick([1, 2, 3]) ?? 3)
        }
        return fallback()
    }

    /// Exactly the intended choice is legal, every choice comes from the hand, and the hand has 8 to 12 cards.
    private static func isSound(_ setup: Setup) -> Bool {
        guard (8...12).contains(setup.hand.count), !setup.wrong.isEmpty else { return false }
        let all = [setup.correct] + setup.wrong
        for (index, play) in all.enumerated() {
            guard play.count == setup.lead.count, setup.hand.containsAll(play) else { return false }
            let legal = Rules.validateFollow(play, hand: setup.hand, lead: setup.lead, trump: setup.trump) == nil
            if legal != (index == 0) { return false }
        }
        return true
    }

    private static func draft(_ setup: Setup, leader: Int) -> DrillDraft {
        let lead = setup.lead
        let leadText = lead.count == 1 ? "the " + DrillText.list(lead) : DrillText.list(lead)
        let prompt = "\(DrillText.trumpLine(setup.trump)) \(Seats.name(leader)) leads \(leadText). Which play is legal for you?"
        return DrillDraft(prompt: prompt, trump: setup.trump,
                          visual: .handAndLead(hand: setup.trump.sorted(setup.hand), lead: lead, leader: leader),
                          answer: DrillText.cardChoice(setup.correct, trump: setup.trump),
                          wrong: setup.wrong.map { DrillText.cardChoice($0, trump: setup.trump) },
                          explanation: setup.explanation)
    }

    /// Lesson 6's example, used only if random builds ever fail.
    private static func fallback() -> DrillDraft {
        let trump = Trump(rank: .two, suit: .hearts)
        let hand = DrillDeck.pair(.jack, .clubs) + [Card(.four, .clubs), Card(.ace, .spades), Card(.six, .hearts),
                                                    Card(.seven, .diamonds), Card(.three, .spades), Card(.queen, .diamonds)]
        let setup = Setup(trump: trump, lead: DrillDeck.pair(.nine, .clubs), hand: hand,
                          correct: DrillDeck.pair(.jack, .clubs),
                          wrong: [[Card(.jack, .clubs), Card(.four, .clubs)], [Card(.four, .clubs), Card(.ace, .spades)]],
                          explanation: "A pair was led and you hold a **club pair**, J♣ J♣, so you must play it. "
                            + "Splitting it, or playing another suit, isn't allowed.")
        return draft(setup, leader: 1)
    }

    // MARK: Templates

    /// One card of `suit` whose face is otherwise unused (so it never makes a pair by accident).
    private static func single(_ suit: Suit, ranks: [Rank], pool: inout DrillPool, dice: inout DrillDice) -> Card? {
        let options = ranks.map { Face.regular(suit, $0) }.filter { pool.freeCopies($0) == 2 }
        guard let face = dice.pick(options) else { return nil }
        return pool.take(face)
    }

    private static func singles(_ suit: Suit, count: Int, ranks: [Rank], pool: inout DrillPool,
                                dice: inout DrillDice) -> [Card] {
        var cards: [Card] = []
        for _ in 0..<count {
            if let card = single(suit, ranks: ranks, pool: &pool, dice: &dice) { cards.append(card) }
        }
        return cards
    }

    private static func pairOf(_ suit: Suit, ranks: [Rank], pool: inout DrillPool, dice: inout DrillDice) -> [Card]? {
        let options = ranks.map { Face.regular(suit, $0) }.filter { pool.freeCopies($0) == 2 }
        guard let face = dice.pick(options) else { return nil }
        return pool.takePair(face)
    }

    /// A low trump that isn't a point card (a joker or a rank card when there is no trump suit).
    private static func lowTrump(_ trump: Trump, notSuit: Suit, pool: inout DrillPool, dice: inout DrillDice) -> Card? {
        if let trumpSuit = trump.suit {
            let low = DrillDeck.ranks(trump).prefix(6).filter { $0.points == 0 }
            return single(trumpSuit, ranks: Array(low), pool: &pool, dice: &dice)
        }
        if dice.chance(50), let suit = dice.pick(Suit.allCases.filter { $0 != notSuit }) {
            return pool.take(.regular(suit, trump.rank))
        }
        return pool.take(dice.chance(50) ? .smallJoker : .bigJoker)
    }

    private static func build(_ template: Template, level: Int, trump: Trump, pool: inout DrillPool,
                              dice: inout DrillDice) -> Setup? {
        let ranks = DrillDeck.ranks(trump)
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
        let others = DrillDeck.otherPlainSuits(trump, except: suit)
        let plural = suit.name.lowercased()
        let singular = suit.singularName
        let rankWord = DrillText.rankWord(trump.rank)

        switch template {
        case .single:
            guard let lead = single(suit, ranks: ranks, pool: &pool, dice: &dice) else { return nil }
            let held = singles(suit, count: dice.int(1...3), ranks: ranks, pool: &pool, dice: &dice)
            guard let correct = dice.pick(held) else { return nil }
            var hand = held
            var wrong: [[Card]] = []
            if let other = dice.pick(others),
               let high = single(other, ranks: Array(ranks.suffix(4)), pool: &pool, dice: &dice) {
                wrong.append([high])
                hand.append(high)
            }
            if let low = lowTrump(trump, notSuit: suit, pool: &pool, dice: &dice) {
                wrong.append([low])
                hand.append(low)
            }
            var note = ""
            if level >= 2, let misread = pool.take(.regular(suit, trump.rank)) {
                wrong.append([misread])
                hand.append(misread)
                note = " The \(misread.description) is a trump this round, not a \(singular)."
            }
            return Setup(trump: trump, lead: [lead], hand: hand, correct: [correct], wrong: wrong,
                         explanation: "\(DrillText.capitalized(plural)) were led and you hold \(plural), so you must "
                            + "**follow suit** with one. Only when you have none may you ruff or discard." + note)

        case .trumpSingle:
            let trumpFaces = DrillDeck.faces(in: .trump, trump: trump)
            guard let leadFace = dice.pick(trumpFaces), let lead = pool.take(leadFace) else { return nil }
            let misread = dice.chance(60)
            var mine: Card?
            if misread {
                let suits = Suit.allCases.filter { $0 != trump.suit && pool.freeCopies(.regular($0, trump.rank)) == 2 }
                if let rankSuit = dice.pick(suits) { mine = pool.take(.regular(rankSuit, trump.rank)) }
            } else if let trumpSuit = trump.suit {
                mine = single(trumpSuit, ranks: ranks, pool: &pool, dice: &dice)
            } else {
                mine = pool.take(dice.chance(50) ? .smallJoker : .bigJoker)
            }
            guard let answer = mine else { return nil }
            // Plain cards to choose from, starting with the rank card's printed suit.
            var suits = DrillDeck.plainSuits(trump)
            if let printed = answer.suit, misread, let index = suits.firstIndex(of: printed) {
                suits.remove(at: index)
                suits.insert(printed, at: 0)
            } else {
                suits = dice.shuffled(suits)
            }
            var wrong: [[Card]] = []
            for plainSuit in suits.prefix(3) {
                if let card = single(plainSuit, ranks: Array(ranks.suffix(5)), pool: &pool, dice: &dice) {
                    wrong.append([card])
                }
            }
            let explanation = misread
                ? "A trump was led, so you must play a trump if you have one. Your **\(answer.description)** is a "
                    + "trump: every \(rankWord) is, whatever its suit."
                : "A trump was led, so you must play a trump if you have one, and your only trump is the "
                    + "**\(DrillText.name(answer))**. Plain cards can't follow a trump lead."
            return Setup(trump: trump, lead: [lead], hand: [answer] + wrong.flatMap { $0 }, correct: [answer], wrong: wrong,
                         explanation: explanation)

        case .pairHeld:
            guard let lead = pairOf(suit, ranks: ranks, pool: &pool, dice: &dice),
                  let mine = pairOf(suit, ranks: ranks, pool: &pool, dice: &dice) else { return nil }
            let held = singles(suit, count: dice.int(1...3), ranks: ranks, pool: &pool, dice: &dice)
            guard let first = held.first else { return nil }
            var hand = mine + held
            var wrong: [[Card]] = []
            wrong.append(held.count >= 2 ? [held[0], held[1]] : [mine[0], first])
            let otherSuit = dice.pick(others) ?? suit
            let otherPair: [Card]?
            if level >= 2 && dice.chance(30), let trumpSuit = trump.suit {
                otherPair = pairOf(trumpSuit, ranks: ranks, pool: &pool, dice: &dice)
            } else {
                otherPair = pairOf(otherSuit, ranks: ranks, pool: &pool, dice: &dice)
            }
            if let pair = otherPair {
                wrong.append(pair)
                hand += pair
            }
            if let off = single(otherSuit, ranks: ranks, pool: &pool, dice: &dice) {
                wrong.append([first, off])
                hand.append(off)
            }
            if level == 1 { wrong = Array(dice.shuffled(wrong).prefix(2)) }
            return Setup(trump: trump, lead: lead, hand: hand, correct: mine, wrong: wrong,
                         explanation: "A pair was led and you hold a **\(singular) pair**, \(mine.shortText), so you must "
                            + "play it. Splitting it, or playing another suit, isn't allowed.")

        case .noPair:
            guard let lead = pairOf(suit, ranks: ranks, pool: &pool, dice: &dice) else { return nil }
            let held = singles(suit, count: dice.int(2...4), ranks: ranks, pool: &pool, dice: &dice)
            guard held.count >= 2 else { return nil }
            let chosen = Array(dice.shuffled(held).prefix(2))
            var hand = held
            var wrong: [[Card]] = []
            let otherSuit = dice.pick(others) ?? suit
            if let off = single(otherSuit, ranks: ranks, pool: &pool, dice: &dice) {
                wrong.append([chosen[0], off])
                hand.append(off)
            }
            if let pair = pairOf(dice.pick(others) ?? otherSuit, ranks: ranks, pool: &pool, dice: &dice) {
                wrong.append(pair)
                hand += pair
            }
            var note = ""
            if let misread = pool.take(.regular(suit, trump.rank)) {
                wrong.append([chosen[1], misread])
                hand.append(misread)
                note = " The \(misread.description) is a trump, not a \(singular)."
            }
            return Setup(trump: trump, lead: lead, hand: hand, correct: chosen, wrong: wrong,
                         explanation: "You hold \(plural) but no \(singular) pair, so play **any two \(plural)**. You can't "
                            + "add another suit while you still have \(plural)." + note)

        case .short:
            guard let lead = pairOf(suit, ranks: ranks, pool: &pool, dice: &dice),
                  let only = single(suit, ranks: ranks, pool: &pool, dice: &dice),
                  let otherSuit = dice.pick(others) else { return nil }
            let lowRanks = Array(ranks.prefix(6).filter { $0.points == 0 })
            guard let filler = single(otherSuit, ranks: lowRanks, pool: &pool, dice: &dice),
                  let spare = single(dice.pick(others) ?? otherSuit, ranks: ranks, pool: &pool, dice: &dice) else {
                return nil
            }
            var hand = [only, filler, spare]
            var wrong: [[Card]] = [[filler, spare]]
            if let pair = pairOf(dice.pick(others) ?? otherSuit, ranks: ranks, pool: &pool, dice: &dice) {
                wrong.append(pair)
                hand += pair
            }
            var note = ""
            if let misread = pool.take(.regular(suit, trump.rank)) {
                wrong.append([misread, spare])
                hand.append(misread)
                note = " The \(misread.description) is a trump, not a \(singular)."
            }
            return Setup(trump: trump, lead: lead, hand: hand, correct: [only, filler], wrong: wrong,
                         explanation: "You hold only one \(singular), the \(only.description), so play it plus **any** other "
                            + "card. Leaving it out isn't allowed, even for a pair." + note)

        case .trumpPair:
            // Trumps are led and your trump pair is a pair of rank cards that look like a plain pair.
            let lead: [Card]?
            if let trumpSuit = trump.suit, dice.chance(70) {
                lead = pairOf(trumpSuit, ranks: ranks, pool: &pool, dice: &dice)
            } else {
                lead = pool.takePair(dice.chance(50) ? .smallJoker : .bigJoker)
            }
            guard let led = lead else { return nil }
            let rankSuits = Suit.allCases.filter { $0 != trump.suit }
            guard let rankSuit = dice.pick(rankSuits), let mine = pool.takePair(.regular(rankSuit, trump.rank)) else {
                return nil
            }
            let trumpSingle: Card?
            if let trumpSuit = trump.suit {
                trumpSingle = single(trumpSuit, ranks: ranks, pool: &pool, dice: &dice)
            } else {
                let jokers: [Face] = [Face.smallJoker, Face.bigJoker].filter { pool.freeCopies($0) == 2 }
                trumpSingle = dice.pick(jokers).flatMap { pool.take($0) }
            }
            guard let loose = trumpSingle,
                  let plainPair = pairOf(rankSuit, ranks: ranks, pool: &pool, dice: &dice),
                  let plainCard = single(dice.pick(DrillDeck.otherPlainSuits(trump, except: rankSuit)) ?? rankSuit,
                                         ranks: ranks, pool: &pool, dice: &dice) else { return nil }
            let wrong: [[Card]] = [[mine[0], loose], plainPair, [loose, plainCard]]
            return Setup(trump: trump, lead: led, hand: mine + [loose] + plainPair + [plainCard], correct: mine, wrong: wrong,
                         explanation: "Trumps were led, and your \(mine.shortText) is a **trump pair**: every \(rankWord) is "
                            + "a trump this round. You hold a trump pair, so you must play it.")

        case .tractorHeld:
            return tractorHeld(trump: trump, suit: suit, pool: &pool, dice: &dice)

        case .twoPairs:
            guard let lead = DrillDeck.combo(in: .plain(suit), pairs: 2, above: nil, trump: trump, pool: &pool, dice: &dice),
                  let first = pairOf(suit, ranks: ranks, pool: &pool, dice: &dice) else { return nil }
            let firstStrength = trump.strength(first[0])
            let apart = ranks.filter { abs(trump.strength(Face.regular(suit, $0)) - firstStrength) >= 2 }
            guard let second = pairOf(suit, ranks: apart, pool: &pool, dice: &dice) else { return nil }
            let held = singles(suit, count: dice.int(1...2), ranks: ranks, pool: &pool, dice: &dice)
            guard let otherSuit = dice.pick(others) else { return nil }
            let offs = singles(otherSuit, count: 2, ranks: ranks, pool: &pool, dice: &dice)
            guard let loose = held.first, offs.count == 2 else { return nil }
            let fourth = held.count >= 2 ? held[1] : offs[0]
            let pairs = trump.sorted(first + second)
            let wrong: [[Card]] = [first + [loose, fourth], second + offs, [first[0], second[0], loose, offs[1]]]
            let lowFirst = trump.strength(first[0]) < trump.strength(second[0])
            let lowerPair = lowFirst ? first : second
            let higherPair = lowFirst ? second : first
            return Setup(trump: trump, lead: lead, hand: first + second + held + offs, correct: pairs, wrong: wrong,
                         explanation: "You have no \(singular) tractor, so play **as many \(singular) pairs as you hold**, up "
                            + "to two: \(lowerPair.shortText) and \(higherPair.shortText).")

        case .onePair:
            guard let lead = DrillDeck.combo(in: .plain(suit), pairs: 2, above: nil, trump: trump, pool: &pool, dice: &dice),
                  let mine = pairOf(suit, ranks: ranks, pool: &pool, dice: &dice) else { return nil }
            let held = trump.sorted(singles(suit, count: dice.int(2...4), ranks: ranks, pool: &pool, dice: &dice))
            guard held.count >= 2, let otherSuit = dice.pick(others) else { return nil }
            let offs = singles(otherSuit, count: 2, ranks: ranks, pool: &pool, dice: &dice)
            guard offs.count == 2 else { return nil }
            var wrong: [[Card]] = []
            if held.count >= 4 {
                wrong.append(Array(held.prefix(4)))
            } else if held.count == 3 {
                wrong.append([mine[0]] + held)
            } else {
                wrong.append([mine[0], held[0], held[1], offs[0]])
            }
            wrong.append(mine + offs)
            wrong.append([held[0], held[1]] + offs)
            return Setup(trump: trump, lead: lead, hand: mine + held + offs, correct: mine + [held[0], held[1]],
                         wrong: wrong,
                         explanation: "You have no \(singular) tractor but one \(singular) pair, so play that pair plus two "
                            + "more \(plural). Splitting the pair isn't allowed.")
        }
    }

    /// A tractor is led and you hold one, sometimes across the skipped trump rank.
    private static func tractorHeld(trump: Trump, suit: Suit, pool: inout DrillPool, dice: inout DrillDice) -> Setup? {
        let ranks = DrillDeck.ranks(trump)
        let plural = suit.name.lowercased()
        let singular = suit.singularName
        guard let lead = DrillDeck.combo(in: .plain(suit), pairs: 2, above: nil, trump: trump, pool: &pool, dice: &dice)
        else { return nil }
        var mine: [Card]?
        var across = false
        if dice.chance(40), let below = Rank(rawValue: trump.rank.rawValue - 1),
           let above = Rank(rawValue: trump.rank.rawValue + 1),
           pool.freeCopies(.regular(suit, below)) == 2, pool.freeCopies(.regular(suit, above)) == 2 {
            mine = (pool.takePair(.regular(suit, below)) ?? []) + (pool.takePair(.regular(suit, above)) ?? [])
            across = true
        } else {
            mine = DrillDeck.combo(in: .plain(suit), pairs: 2, above: nil, trump: trump, pool: &pool, dice: &dice)
        }
        guard let tractor = mine, tractor.count == 4 else { return nil }
        let lowPair = Array(tractor.prefix(2))
        let highPair = Array(tractor.suffix(2))
        let low = trump.strength(tractor[0])
        let high = trump.strength(tractor[3])

        // Each distractor and the cards it needs in the hand.
        var options: [(play: [Card], extra: [Card])] = []
        var note = ""
        if across, let rankPair = pool.takePair(.regular(suit, trump.rank)) {
            options.append((highPair + rankPair, rankPair))
            note = " Your \(rankPair.shortText) are trumps, not \(plural)."
        }
        let apart = ranks.filter { rank in
            let strength = trump.strength(Face.regular(suit, rank))
            return strength < low - 1 || strength > high + 1
        }
        if let extra = pairOf(suit, ranks: apart, pool: &pool, dice: &dice) {
            options.append((lowPair + extra, extra))
        }
        let held = singles(suit, count: 2, ranks: ranks, pool: &pool, dice: &dice)
        if held.count == 2 { options.append((lowPair + held, held)) }
        if let otherSuit = dice.pick(DrillDeck.otherPlainSuits(trump, except: suit)) {
            let offs = singles(otherSuit, count: 2, ranks: ranks, pool: &pool, dice: &dice)
            if offs.count == 2 { options.append((highPair + offs, offs)) }
        }
        let chosen = Array(options.prefix(3))
        guard !chosen.isEmpty else { return nil }
        var hand = tractor
        for option in chosen { hand += option.extra }
        let explanation: String
        if across {
            explanation = "The \(DrillText.rankPlural(trump.rank)) are trumps this round, so \(tractor.shortText) is a "
                + "\(singular) tractor, and you must play it." + note
        } else {
            explanation = "A tractor was led and you hold one in \(plural), \(tractor.shortText), so you must play it. "
                + "Pairs that aren't consecutive don't count."
        }
        return Setup(trump: trump, lead: lead, hand: hand, correct: tractor, wrong: chosen.map(\.play),
                     explanation: explanation)
    }
}

// MARK: - Scoring

private enum ScoringDrills {
    /// The outcomes of the level table, in order, as (declarers hold, levels).
    private static let ladder: [(hold: Bool, levels: Int)] = [
        (true, 3), (true, 2), (true, 1), (false, 0), (false, 1), (false, 2), (false, 3), (false, 4), (false, 5),
    ]

    private static func outcomeText(hold: Bool, levels: Int) -> String {
        if hold { return "The declarers keep the deal and climb \(DrillText.levels(levels))" }
        if levels == 0 { return "The defenders take over but don't climb" }
        return "The defenders take over and climb \(DrillText.levels(levels))"
    }

    static func levelOutcome(level: Int, dice: inout DrillDice) -> DrillDraft {
        let boundaries: [Int]
        let maxPoints: Int
        switch level {
        case 1:
            boundaries = [0, 35, 40, 75, 80, 115, 120, 155]
            maxPoints = 155
        case 2:
            boundaries = [0, 5, 35, 40, 75, 80, 115, 120, 155, 160, 195]
            maxPoints = 195
        default:
            boundaries = [0, 35, 40, 75, 80, 115, 120, 155, 160, 195, 200, 235, 240, 280]
            maxPoints = 300
        }
        let points = dice.chance(60) ? (dice.pick(boundaries) ?? 80) : 5 * dice.int(0...(maxPoints / 5))
        let outcome = Scoring.outcome(defenderPoints: points)
        let index = ladder.firstIndex { $0.hold == outcome.declarersHold && $0.levels == outcome.levels } ?? 0
        // The nearest rows of the table make the most tempting distractors.
        let others = dice.shuffled(ladder.indices.filter { $0 != index }).sorted { abs($0 - index) < abs($1 - index) }
        let wrong = others.prefix(3).map { Choice(outcomeText(hold: ladder[$0].hold, levels: ladder[$0].levels)) }

        let prompts = ["The defenders end the round with \(points) points. What happens?",
                       "You are declaring, and the defenders score \(points) points. What happens?",
                       "Your team is defending and captures \(points) points. What happens?"]
        let explanation: String
        switch points {
        case 0:
            explanation = "Holding the defenders to **0** is the best result: the declarers climb **3 levels**. "
                + "5 to 35 gives +2, and 40 to 75 gives +1."
        case 5...35:
            explanation = "**5 to 35** points: the declarers keep the deal and climb **2 levels**. "
                + "Only a clean sweep, 0 points, earns +3."
        case 40...75:
            explanation = "**40 to 75**: the declarers keep the deal but climb only **1 level**. "
                + "At 80 the defenders would take over."
        case 80...115:
            explanation = "**80 to 115**: the defenders take over the deal but **don't climb**. "
                + "They need 120 to climb a level as well."
        default:
            let levels = (points - 80) / 40
            let low = 80 + 40 * levels
            explanation = "**\(low) to \(low + 35)**: the defenders take over **and climb \(DrillText.levels(levels))**. "
                + "Every 40 points above 80 is worth one more level."
        }
        return DrillDraft(prompt: dice.pick(prompts) ?? prompts[0], trump: nil, visual: .none,
                          answer: Choice(outcomeText(hold: outcome.declarersHold, levels: outcome.levels)),
                          wrong: Array(wrong), explanation: explanation)
    }

    static func kittyBonus(level: Int, dice: inout DrillDice) -> DrillDraft {
        let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: level == 3 ? 20 : 0)
        // 0 single, 1 pair, 2 two-pair tractor, 3 three-pair tractor, 4 a throw.
        let weights: [Int]
        switch level {
        case 1: weights = [50, 50, 0, 0, 0]
        case 2: weights = [25, 40, 35, 0, 0]
        default: weights = [10, 25, 25, 10, 30]
        }
        let kind = dice.weighted(weights)
        var pool = DrillPool()
        let plainSuit: Suit? = dice.chance(80) ? dice.pick(DrillDeck.plainSuits(trump)) : nil
        let group: SuitGroup = plainSuit.map { SuitGroup.plain($0) } ?? .trump
        var lead: [Card] = []
        if kind == 4 {
            let base = DrillDeck.combo(in: group, pairs: dice.chance(60) ? 1 : 2, above: nil, trump: trump,
                                       pool: &pool, dice: &dice) ?? []
            let singles = DrillDeck.distinctFaces(in: group, count: dice.int(1...2), trump: trump, pool: &pool, dice: &dice)
            lead = base + singles
        } else {
            lead = DrillDeck.combo(in: group, pairs: kind, above: nil, trump: trump, pool: &pool, dice: &dice) ?? []
        }
        if lead.isEmpty { lead = [Card(.ace, .spades)] }
        lead = trump.sorted(lead)

        let kitty: Int
        switch level {
        case 1: kitty = dice.pick([10, 15, 20, 25, 30]) ?? 20
        case 2: kitty = 5 * dice.int(1...9)
        default: kitty = 5 * dice.int(1...12)
        }
        let defendersWin = dice.chance(level == 1 ? 80 : 70)
        let multiplier = Scoring.kittyMultiplier(lastLead: lead, trump: trump)
        let answer = defendersWin ? kitty * multiplier : 0

        // Mistakes: the wrong multiplier, the raw kitty, or forgetting who must win the last trick.
        var candidates: [Int] = []
        if !defendersWin { candidates.append(kitty * multiplier) }
        switch multiplier {
        case 2: candidates += [kitty, kitty * 4, kitty * 8]
        case 4: candidates += [kitty * 2, kitty * 8, kitty]
        case 8: candidates += [kitty * 4, kitty * 2, kitty]
        default: candidates += [kitty * 8, kitty * 4, kitty * 2]
        }
        candidates += [kitty, kitty * 2, kitty * 4, 0]
        var values: [Int] = []
        for value in candidates where value != answer && !values.contains(value) && values.count < 3 {
            values.append(value)
        }

        let components = Combos.decompose(lead, trump: trump)
        let largest = components.first
        let shown: String
        if level == 3 {
            shown = lead.count == 1 ? "this card" : "these cards"
        } else {
            switch largest?.shape ?? .single {
            case .single: shown = "this card"
            case .pair: shown = "this pair"
            case .tractor: shown = "this tractor"
            }
        }
        let who = defendersWin ? "defenders" : "declarers"
        let question = defendersWin ? "What is their kitty bonus?" : "What is the defenders' kitty bonus?"
        let prompt = "Kitty: \(kitty) points. The \(who) win the last trick, led with \(shown). \(question)"

        let explanation: String
        if defendersWin {
            let size = largest?.shape.cardCount ?? 1
            let cards = size == 1 ? "1 card" : "\(size) cards"
            let part: String
            if components.count > 1, let biggest = largest {
                part = "The lead's biggest part, \(DrillText.list(biggest.cards)), has \(cards)"
            } else {
                part = "A \(shapeName(largest?.shape ?? .single)) has \(cards)"
            }
            explanation = "The defenders won the last trick, so they score the kitty: 抠底 (kōudǐ). \(part), so it "
                + "counts 2 × \(size) = **×\(multiplier)**: \(kitty) × \(multiplier) = **\(answer)**."
        } else {
            explanation = "Only the **defenders** can score the kitty, and only by winning the **last trick**. "
                + "The declarers won it, so the kitty adds **0**, however it was led."
        }
        return DrillDraft(prompt: prompt, trump: trump, visual: .cards(lead), answer: Choice(String(answer)),
                          wrong: values.map { Choice(String($0)) }, explanation: explanation)
    }

    private static func shapeName(_ shape: ComboShape) -> String {
        switch shape {
        case .single: return "single"
        case .pair: return "pair"
        case let .tractor(length): return length == 2 ? "two-pair tractor" : "\(length)-pair tractor"
        }
    }
}

// MARK: - Smart plays

/// Strategy judgements with one clear principle each. Every choice is a legal play; the right one
/// follows the principle named in the explanation.
private enum StrategyDrill {
    private struct Setup {
        var trump: Trump
        /// The trick so far (East, Partner, West: you play last), or empty when you lead.
        var plays: [Play]
        var hand: [Card]
        var correct: Card
        var wrong: [Card]
        var prompt: String
        var explanation: String
    }

    private enum Template {
        case feed, winCheaply, ruffLow, duck, leadAce
    }

    private static let east = 1
    private static let partner = 2
    private static let west = 3

    static func make(level: Int, dice: inout DrillDice) -> DrillDraft {
        let templates: [Template] = [.feed, .winCheaply, .ruffLow, .duck, .leadAce]
        let weights = level == 1 ? [35, 0, 0, 35, 30] : [20, 20, 20, 20, 20]
        for _ in 0..<12 {
            let template = templates[dice.weighted(weights)]
            let trump = DrillDeck.randomTrump(&dice, noTrumpPercent: level == 3 ? 25 : 0)
            var pool = DrillPool()
            let built: Setup?
            switch template {
            case .feed: built = feed(level: level, trump: trump, pool: &pool, dice: &dice)
            case .winCheaply: built = winCheaply(level: level, trump: trump, pool: &pool, dice: &dice)
            case .ruffLow: built = ruffLow(level: level, trump: trump, pool: &pool, dice: &dice)
            case .duck: built = duck(level: level, trump: trump, pool: &pool, dice: &dice)
            case .leadAce: built = leadAce(level: level, trump: trump, pool: &pool, dice: &dice)
            }
            if let setup = built, isSound(setup) { return draft(setup) }
        }
        return fallback()
    }

    private static func isSound(_ setup: Setup) -> Bool {
        let all = [setup.correct] + setup.wrong
        guard !setup.wrong.isEmpty, setup.hand.containsAll(all), Set(all.map(\.id)).count == all.count else { return false }
        guard let lead = setup.plays.first?.cards else {
            return all.allSatisfy { Rules.validateLead([$0], hand: setup.hand, trump: setup.trump) == nil }
        }
        return all.allSatisfy { Rules.validateFollow([$0], hand: setup.hand, lead: lead, trump: setup.trump) == nil }
    }

    private static func draft(_ setup: Setup) -> DrillDraft {
        let hand = setup.trump.sorted(setup.hand)
        let visual: QuestionVisual = setup.plays.isEmpty ? .cards(hand) : .situation(plays: setup.plays, hand: hand)
        return DrillDraft(prompt: setup.prompt, trump: setup.trump, visual: visual,
                          answer: DrillText.cardChoice([setup.correct], trump: nil),
                          wrong: setup.wrong.map { DrillText.cardChoice([$0], trump: nil) },
                          explanation: setup.explanation)
    }

    /// Lesson 12's example, used only if random builds ever fail.
    private static func fallback() -> DrillDraft {
        let trump = Trump(rank: .two, suit: .hearts)
        let setup = Setup(
            trump: trump,
            plays: [Play(player: east, cards: [Card(.six, .spades)]), Play(player: partner, cards: [Card(.ace, .spades)]),
                    Play(player: west, cards: [Card(.nine, .spades)])],
            hand: [Card(.king, .spades), Card(.three, .spades), Card(.eight, .diamonds), Card(.jack, .clubs), Card(.four, .hearts)],
            correct: Card(.king, .spades), wrong: [Card(.three, .spades)],
            prompt: "Trump suit ♥, rank 2. Partner is winning and you play last. What should you play?",
            explanation: "**Feed points**: Partner's A♠ is winning and nobody plays after you. Add your K♠ for 10 more "
                + "points, and save low cards for tricks the opponents win.")
        return draft(setup)
    }

    private static func card(_ rank: Rank?, _ suit: Suit?, pool: inout DrillPool) -> Card? {
        guard let rank, let suit else { return nil }
        return pool.take(.regular(suit, rank))
    }

    /// Plain cards of other suits that are not points and not trumps, to round out a hand.
    private static func neutralFiller(_ hand: [Card], ledSuit: Suit?, above minimum: Int, trump: Trump,
                                      pool: inout DrillPool, dice: inout DrillDice) -> [Card] {
        let size = hand.count + dice.int(3...5)
        return DrillDeck.fill(hand, to: size, pool: &pool, dice: &dice) { candidate in
            guard !trump.isTrump(candidate), candidate.points == 0, let suit = candidate.suit, suit != ledSuit else {
                return false
            }
            return trump.strength(candidate) > minimum
        }
    }

    /// A low trump worth no points (a rank card or joker when there is no trump suit). A rank card is
    /// never printed in `notSuit`, the led suit, where it would look like a card you could follow with.
    private static func lowTrump(_ trump: Trump, notSuit: Suit?, pool: inout DrillPool, dice: inout DrillDice) -> Card? {
        if let trumpSuit = trump.suit {
            let low = DrillDeck.ranks(trump).filter { $0.points == 0 && $0.rawValue <= 9 }
            return card(dice.pick(low), trumpSuit, pool: &pool)
        }
        if trump.rank.points == 0 {
            return card(trump.rank, dice.pick(Suit.allCases.filter { $0 != notSuit }), pool: &pool)
        }
        return pool.take(.smallJoker)
    }

    /// A higher trump than `low`, worth no points, and not a rank card printed in `notSuit` (the led suit).
    private static func highTrump(_ trump: Trump, than low: Card, notSuit: Suit, pool: inout DrillPool,
                                  dice: inout DrillDice) -> Card? {
        var faces: [Face] = [.smallJoker, .bigJoker]
        if trump.rank.points == 0 {
            faces += Suit.allCases.filter { $0 != notSuit }.map { Face.regular($0, trump.rank) }
        }
        if let trumpSuit = trump.suit, let top = DrillDeck.ranks(trump).last, top.points == 0 {
            faces.append(.regular(trumpSuit, top))
        }
        let lowStrength = trump.strength(low)
        let options = faces.filter { trump.isTrump($0) && trump.strength($0) > lowStrength && pool.freeCopies($0) > 0 }
        return dice.pick(options).flatMap { pool.take($0) }
    }

    // MARK: Templates

    /// Partner's top card is winning and you play last: feed points.
    private static func feed(level: Int, trump: Trump, pool: inout DrillPool, dice: inout DrillDice) -> Setup? {
        let ranks = DrillDeck.ranks(trump)
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)), let top = ranks.last else { return nil }
        let below = Array(ranks.dropLast())
        let feedRanks = below.filter { $0.points > 0 }
        let lowRanks = below.filter { $0.points == 0 && $0.rawValue <= 9 }
        guard let partnerCard = card(top, suit, pool: &pool),
              let eastCard = card(dice.pick(below), suit, pool: &pool),
              let westCard = card(dice.pick(below), suit, pool: &pool) else { return nil }
        let plays = [Play(player: east, cards: [eastCard]), Play(player: partner, cards: [partnerCard]),
                     Play(player: west, cards: [westCard])]
        let line = DrillText.trumpLine(trump)
        let prompt = level == 1 ? "\(line) Partner is winning and you play last. What should you play?"
            : "\(line) You play last. What should you play?"

        if level >= 2 && dice.chance(40) {
            // You have no cards of the led suit: discard a point card rather than ruff.
            let others = DrillDeck.otherPlainSuits(trump, except: suit)
            let tens = [Rank.king, .ten].filter { $0 != trump.rank }
            guard let feedCard = card(dice.pick(tens), dice.pick(others), pool: &pool),
                  let lowCard = card(dice.pick(lowRanks), dice.pick(others), pool: &pool),
                  let ruff = lowTrump(trump, notSuit: suit, pool: &pool, dice: &dice) else { return nil }
            let hand = neutralFiller([feedCard, lowCard, ruff], ledSuit: suit, above: -1, trump: trump,
                                     pool: &pool, dice: &dice)
            return Setup(trump: trump, plays: plays, hand: hand, correct: feedCard, wrong: [lowCard, ruff], prompt: prompt,
                         explanation: "**Feed points**: Partner's \(partnerCard.description) wins whatever you play, so "
                            + "discard your \(feedCard.description) for \(feedCard.points) more points. Ruffing would waste a "
                            + "trump on a trick your team already has.")
        }
        guard let feedCard = card(dice.pick(feedRanks), suit, pool: &pool),
              let lowCard = card(dice.pick(lowRanks), suit, pool: &pool) else { return nil }
        let hand = DrillDeck.fill([feedCard, lowCard], to: dice.int(6...8), pool: &pool, dice: &dice) { candidate in
            candidate.suit != suit
        }
        return Setup(trump: trump, plays: plays, hand: hand, correct: feedCard, wrong: [lowCard], prompt: prompt,
                     explanation: "**Feed points**: Partner's \(partnerCard.description) is winning and nobody plays after "
                        + "you. Add your \(feedCard.description) for \(feedCard.points) more points, and save low cards for "
                        + "tricks the opponents win.")
    }

    /// An opponent is winning a trick with points and you play last: win with your lowest winner.
    private static func winCheaply(level: Int, trump: Trump, pool: inout DrillPool, dice: inout DrillDice) -> Setup? {
        let ranks = DrillDeck.ranks(trump)
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
        let winnerIndex = dice.int(2...8)
        let highs = ranks.indices.filter { $0 > winnerIndex + 1 && ranks[$0].points == 0 }
        guard let highIndex = dice.pick(highs) else { return nil }
        let cheapIndex = dice.int((winnerIndex + 1)...(highIndex - 1))
        let lows = ranks.indices.filter { $0 < winnerIndex && ranks[$0].points == 0 }
        guard let lowIndex = dice.pick(lows) else { return nil }
        // Points on the table: a point card below the winner if there is one.
        let pointBelow = ranks.indices.filter { $0 < winnerIndex && ranks[$0].points > 0 }
        let tableIndex = dice.pick(pointBelow) ?? dice.int(0...(winnerIndex - 1))
        let partnerIndex = dice.pick(lows) ?? 0
        let westWins = dice.chance(50)
        guard let winning = card(ranks[winnerIndex], suit, pool: &pool),
              let other = card(ranks[tableIndex], suit, pool: &pool),
              let partnerCard = card(ranks[partnerIndex], suit, pool: &pool),
              let cheap = card(ranks[cheapIndex], suit, pool: &pool),
              let high = card(ranks[highIndex], suit, pool: &pool),
              let low = card(ranks[lowIndex], suit, pool: &pool) else { return nil }
        let eastCard = westWins ? other : winning
        let westCard = westWins ? winning : other
        let plays = [Play(player: east, cards: [eastCard]), Play(player: partner, cards: [partnerCard]),
                     Play(player: west, cards: [westCard])]
        let points = eastCard.points + partnerCard.points + westCard.points
        guard points > 0 else { return nil }
        let hand = DrillDeck.fill([cheap, high, low], to: dice.int(6...8), pool: &pool, dice: &dice) { candidate in
            candidate.suit != suit
        }
        let line = DrillText.trumpLine(trump)
        let winnerName = westWins ? "West" : "East"
        let prompt = level == 2 ? "\(line) \(winnerName) is winning and you play last. What should you play?"
            : "\(line) You play last. What should you play?"
        return Setup(trump: trump, plays: plays, hand: hand, correct: cheap, wrong: [high, low], prompt: prompt,
                     explanation: "**Win cheaply**: you play last, so your \(cheap.description) is enough to beat the "
                        + "\(winning.description) and take the \(points) points. Keep the \(high.description) for later; the "
                        + "\(low.description) would let the opponents win.")
    }

    /// You are out of the led suit, points are on the table and you play last: ruff with a low trump.
    private static func ruffLow(level: Int, trump: Trump, pool: inout DrillPool, dice: inout DrillDice) -> Setup? {
        let ranks = DrillDeck.ranks(trump)
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)) else { return nil }
        let lowRanks = ranks.filter { $0.points == 0 && $0.rawValue <= 8 }
        let pointRanks = ranks.filter { $0.points > 0 }
        guard let partnerCard = card(dice.pick(lowRanks), suit, pool: &pool),
              let pointCard = card(dice.pick(pointRanks), suit, pool: &pool),
              let thirdCard = card(dice.pick(Array(ranks.suffix(6))), suit, pool: &pool) else { return nil }
        let eastFirst = dice.chance(50)
        let eastCard = eastFirst ? pointCard : thirdCard
        let westCard = eastFirst ? thirdCard : pointCard
        let plays = [Play(player: east, cards: [eastCard]), Play(player: partner, cards: [partnerCard]),
                     Play(player: west, cards: [westCard])]
        // An opponent must be winning.
        let current = Rules.winningIndex(plays, trump: trump)
        guard plays.indices.contains(current), plays[current].player != partner else { return nil }
        let points = eastCard.points + partnerCard.points + westCard.points
        let discardRanks = Array(ranks.prefix(7)).filter { $0.points == 0 }
        guard points >= 10, let low = lowTrump(trump, notSuit: suit, pool: &pool, dice: &dice),
              let high = highTrump(trump, than: low, notSuit: suit, pool: &pool, dice: &dice),
              let discard = card(dice.pick(discardRanks), dice.pick(DrillDeck.otherPlainSuits(trump, except: suit)),
                                 pool: &pool) else { return nil }
        let hand = neutralFiller([low, high, discard], ledSuit: suit, above: -1, trump: trump, pool: &pool, dice: &dice)
        let line = DrillText.trumpLine(trump)
        let plural = suit.name.lowercased()
        let prompt = level == 2 ? "\(line) You have no \(plural) and you play last. What should you play?"
            : "\(line) You play last. What should you play?"
        return Setup(trump: trump, plays: plays, hand: hand, correct: low, wrong: [high, discard], prompt: prompt,
                     explanation: "**Ruff low**: you have no \(plural) and \(points) points are on the table. Nobody plays "
                        + "after you, so your \(DrillText.name(low)) wins as surely as the \(DrillText.name(high)). A discard "
                        + "would give the points away.")
    }

    /// An opponent wins whatever you play: give your lowest card, not points.
    private static func duck(level: Int, trump: Trump, pool: inout DrillPool, dice: inout DrillDice) -> Setup? {
        let ranks = DrillDeck.ranks(trump)
        guard let suit = dice.pick(DrillDeck.plainSuits(trump)), let top = ranks.last else { return nil }
        let below = Array(ranks.dropLast())
        let lowRanks = below.filter { $0.points == 0 && $0.rawValue <= 7 }
        let line = DrillText.trumpLine(trump)

        if level >= 2 && dice.chance(40) {
            // West ruffs high; you are out of the suit too and can't over-ruff.
            guard let eastCard = card(dice.pick(below), suit, pool: &pool),
                  let partnerCard = card(dice.pick(lowRanks), suit, pool: &pool),
                  let mine = lowTrump(trump, notSuit: suit, pool: &pool, dice: &dice),
                  let ruff = highTrump(trump, than: mine, notSuit: suit, pool: &pool, dice: &dice) else { return nil }
            let others = DrillDeck.otherPlainSuits(trump, except: suit)
            let tens = [Rank.king, .ten].filter { $0 != trump.rank }
            guard let pointCard = card(dice.pick(tens), dice.pick(others), pool: &pool),
                  let discard = card(dice.pick(lowRanks), dice.pick(others), pool: &pool) else { return nil }
            let plays = [Play(player: east, cards: [eastCard]), Play(player: partner, cards: [partnerCard]),
                         Play(player: west, cards: [ruff])]
            let hand = neutralFiller([mine, pointCard, discard], ledSuit: suit, above: trump.strength(discard),
                                     trump: trump, pool: &pool, dice: &dice)
            let prompt = level == 2 ? "\(line) West has ruffed and you play last. What should you play?"
                : "\(line) You play last. What should you play?"
            return Setup(trump: trump, plays: plays, hand: hand, correct: discard, wrong: [pointCard, mine], prompt: prompt,
                         explanation: "**Duck low**: West's \(DrillText.name(ruff)) wins whatever you play, so discard your "
                            + "lowest plain card, the \(discard.description). The \(pointCard.description) would give away "
                            + "\(pointCard.points) points, and your \(DrillText.name(mine)) can't beat it.")
        }

        let eastLeadsTop = dice.chance(50)
        let pointRanks = below.filter { $0.points > 0 }
        guard let topCard = card(top, suit, pool: &pool),
              let other = card(dice.pick(below), suit, pool: &pool),
              let partnerCard = card(dice.pick(lowRanks), suit, pool: &pool),
              let pointCard = card(dice.pick(pointRanks), suit, pool: &pool),
              let low = card(dice.pick(lowRanks), suit, pool: &pool) else { return nil }
        let eastCard = eastLeadsTop ? topCard : other
        let westCard = eastLeadsTop ? other : topCard
        let plays = [Play(player: east, cards: [eastCard]), Play(player: partner, cards: [partnerCard]),
                     Play(player: west, cards: [westCard])]
        var wrong = [pointCard]
        if level >= 2 {
            let lowRaw = low.rank?.rawValue ?? 0
            let middle = below.filter { $0.points == 0 && $0.rawValue > lowRaw }
            if let mid = card(dice.pick(middle), suit, pool: &pool) { wrong.append(mid) }
        }
        let hand = DrillDeck.fill([low] + wrong, to: dice.int(6...8), pool: &pool, dice: &dice) { candidate in
            candidate.suit != suit
        }
        let winner = eastLeadsTop ? east : west
        let prompt = level == 1 ? "\(line) \(Seats.name(winner)) is winning and you play last. What should you play?"
            : "\(line) You play last. What should you play?"
        return Setup(trump: trump, plays: plays, hand: hand, correct: low, wrong: wrong, prompt: prompt,
                     explanation: "**Duck low**: \(DrillText.possessive(winner)) \(topCard.description) wins whatever you "
                        + "play, so give the least you can: your \(low.description). Your \(pointCard.description) would "
                        + "hand the opponents \(pointCard.points) more points.")
    }

    /// You are on lead: cash a top card, don't lead a lone King into the ace.
    private static func leadAce(level: Int, trump: Trump, pool: inout DrillPool, dice: inout DrillDice) -> Setup? {
        var round = trump
        if round.rank >= .ten { round.rank = dice.pick([Rank.two, .three, .four, .six, .seven, .eight, .nine]) ?? .two }
        let suits = dice.shuffled(DrillDeck.plainSuits(round))
        guard suits.count >= 3 else { return nil }
        let aceSuit = suits[0]
        let kingSuit = suits[1]
        let thirdSuit = suits[2]
        let lowRanks = DrillDeck.ranks(round).filter { $0.points == 0 && $0.rawValue <= 9 }
        guard let ace = card(.ace, aceSuit, pool: &pool), let king = card(.king, kingSuit, pool: &pool) else { return nil }
        var hand = [ace, king]
        var wrong = [king]
        let counts: [(Suit, Int)] = [(aceSuit, dice.int(1...2)), (kingSuit, dice.int(1...2)), (thirdSuit, dice.int(1...2))]
        for (suit, count) in counts {
            for _ in 0..<count {
                if let low = card(dice.pick(lowRanks), suit, pool: &pool) { hand.append(low) }
            }
        }
        if let trumpCard = lowTrump(round, notSuit: nil, pool: &pool, dice: &dice) { hand.append(trumpCard) }
        var extra = ""
        if level >= 2, let ten = card(.ten, thirdSuit, pool: &pool) {
            hand.append(ten)
            wrong.append(ten)
            extra = " Leading the \(ten.description) risks the same."
        }
        return Setup(trump: round, plays: [], hand: hand, correct: ace, wrong: wrong,
                     prompt: "\(DrillText.trumpLine(round)) You are on lead. Which card should you lead?",
                     explanation: "**Lead sure winners**: no \(aceSuit.singularName) can beat your \(ace.description), so it "
                        + "should win the trick. A lone \(king.description) invites an opponent's A\(kingSuit.symbol) to "
                        + "capture it, plus its 10 points." + extra)
    }
}
