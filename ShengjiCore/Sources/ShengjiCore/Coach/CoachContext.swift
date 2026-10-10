import Foundation

// API CONTRACT (stub). Filled in by the coach-core work.

/// A move the learner just tried that the rules rejected (shown to the coach so it can explain).
public struct IllegalAttempt: Equatable, Sendable {
    public var cards: [Card]
    public var error: RoundError

    public init(cards: [Card], error: RoundError) {
        self.cards = cards
        self.error = error
    }
}

/// Builds the plain-text `<table_state>` the coach receives. It describes ONLY what the human
/// (seat 0) can see: never other players' hands, never the kitty unless the human buried it
/// (or the round is over and it was revealed).
public enum CoachContext {
    /// Everything relevant at the table, compact and structured, under ~3,500 characters. Includes:
    /// phase (and whose turn), trump (rank, suit, the full trump order in one line), team levels, dealer,
    /// declarers vs defenders (and which team you are on), defenders' points so far, tricks played,
    /// your hand grouped by suit (trumps last, using card short text like "10♥", "SJ", "BJ"),
    /// the current trick (who led what, who played what, who is winning right now and why),
    /// the previous trick and its winner, cards already played grouped by suit (for counting),
    /// players known to be out of a suit, available declarations (dealing), the kitty you buried (if you dealt),
    /// the round result (if finished), the current hint (step, text, suggested cards) if any, the cards you
    /// have selected, and the last illegal attempt with the rule it broke.
    public static func describe(round: Round, game: GameState?, hint: HintLadder?, selection: [Card],
                                lastIllegal: IllegalAttempt?) -> String { fatalError("TODO") }

    /// Context for a question asked inside a lesson: lesson title and number, the page's title and text,
    /// cards shown on it (with trump context), and for predict pages the question, choices and whether the
    /// learner has answered (and what). Under ~2,500 characters.
    public static func describe(lesson: Lesson, pageIndex: Int, chosenAnswer: Int?) -> String { fatalError("TODO") }

    /// Context for a practice/review question: the prompt, trump, visual (as text), choices, the learner's
    /// answer if given, and the correct answer + explanation only once answered.
    public static func describe(question: Question, chosenAnswer: Int?) -> String { fatalError("TODO") }
}
