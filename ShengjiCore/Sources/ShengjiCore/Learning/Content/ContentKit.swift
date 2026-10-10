import Foundation

// Small builders that keep the lesson content readable. Internal to the Curriculum namespace,
// so they never clash with helpers elsewhere in the module.
//
// Card conventions used throughout the content:
//  - A single card uses copy 0: c(.ace, .spades).
//  - A pair is copy 0 + copy 1 of one face: pair(.ace, .spades).
//  - The same (face, copy) never appears twice within one visual or one trick.
extension Curriculum {
    /// One card. `copy` is 0 for the first deck, 1 for the second.
    static func c(_ rank: Rank, _ suit: Suit, _ copy: Int = 0) -> Card {
        Card(rank, suit, copy: copy)
    }

    /// Both copies of one face: a pair.
    static func pair(_ rank: Rank, _ suit: Suit) -> [Card] {
        [Card(rank, suit, copy: 0), Card(rank, suit, copy: 1)]
    }

    static let smallJoker0 = Card.smallJoker(copy: 0)
    static let smallJoker1 = Card.smallJoker(copy: 1)
    static let bigJoker0 = Card.bigJoker(copy: 0)
    static let bigJoker1 = Card.bigJoker(copy: 1)

    /// One seat's play in a trick (0 You, 1 East, 2 Partner, 3 West).
    static func play(_ seat: Int, _ cards: [Card]) -> Play {
        Play(player: seat, cards: cards)
    }

    /// A choice drawn as cards, captioned with their short text (e.g. "J♣ J♣").
    static func cardChoice(_ cards: [Card]) -> Choice {
        Choice(cards.shortText, cards: cards)
    }

    /// A choice that names a seat ("You", "East", "Partner", "West") for "who wins?" questions.
    static func seatChoice(_ seat: Int) -> Choice {
        Choice(Seats.name(seat))
    }

    /// A "your turn" page. Ids follow "lesson.<n>.predict.<k>"; the item is the lesson itself.
    static func predict(_ lesson: Int, _ number: Int, prompt: String, trump: Trump? = nil,
                        visual: QuestionVisual = .none, choices: [Choice], correct: Int,
                        explanation: String) -> LessonPage {
        .predict(Question(id: "lesson.\(lesson).predict.\(number)", itemID: "lesson.\(lesson)",
                          prompt: prompt, trump: trump, visual: visual, choices: choices,
                          correctChoice: correct, explanation: explanation, difficulty: 1))
    }

    /// Ids of the facts that belong to lesson `number`, in order.
    static func factIDs(forLesson number: Int) -> [String] {
        allFacts.filter { $0.lessonID == "lesson.\(number)" }.map(\.id)
    }
}
