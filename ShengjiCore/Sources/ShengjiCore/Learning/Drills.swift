import Foundation

// API CONTRACT (stub). Filled in by the learning work.

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
    public var title: String { fatalError("TODO") }
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
    public static func make<G: RandomNumberGenerator>(_ skill: SkillID, difficulty: Int, rng: inout G) -> Question { fatalError("TODO") }
}
