import Foundation

// API CONTRACT (stub). Filled in by the coach-core work.

/// A tap-to-ask chip. `label` is what the learner sees; `prompt` is what is sent to the coach
/// (it can be more specific than the label, e.g. naming the selected cards).
public struct SuggestedQuestion: Hashable, Sendable, Identifiable {
    /// Stable key, e.g. "table.whatToPlay", "followUp.why".
    public var id: String
    /// Short chip text (at most ~32 characters), e.g. "What should I play?"
    public var label: String
    /// Full message sent to the coach.
    public var prompt: String

    public init(id: String, label: String, prompt: String) {
        self.id = id
        self.label = label
        self.prompt = prompt
    }
}

public enum SuggestedQuestions {
    /// 3 to 5 chips for the current table moment, most useful first. Examples by situation:
    ///  - your turn to follow: "What should I play?", "Who's winning this trick?", "What must I follow with?"
    ///  - your turn to lead: "What should I lead?", "Is my ace safe to lead?" (only if you hold a plain ace)
    ///  - after an illegal attempt: "Why can't I play that?" first
    ///  - with a hint showing: "Why is that the hint?" first
    ///  - dealing: "Should I declare?", "What does declaring do?"
    ///  - burying (you): "What should I bury?", "Why bury cards at all?"
    ///  - waiting / bots playing: "Who's winning this trick?", "What's trump right now?"
    ///  - after a trick (trick pause): "Why did <winner> win that?"
    ///  - round over: "Why did we win/lose that round?", "How was the kitty scored?" (if it was)
    ///  Always plus "Explain the rules for this" style fallbacks if fewer than 3 apply. Never asks the coach to
    ///  reveal hidden cards.
    public static func forTable(round: Round, game: GameState?, hint: HintLadder?, selection: [Card],
                                lastIllegal: IllegalAttempt?) -> [SuggestedQuestion] { fatalError("TODO") }

    /// 3 or 4 chips for a lesson page: "Explain this another way", "Give me another example",
    /// "Quiz me on this", and for predict pages after answering: "Why is that the answer?".
    public static func forLesson(_ lesson: Lesson, pageIndex: Int, answered: Bool) -> [SuggestedQuestion] { fatalError("TODO") }

    /// Chips for a practice/review question after answering: "Why?", "Give me a similar example", "What's the rule?".
    public static func forQuestion(_ question: Question, answeredCorrectly: Bool?) -> [SuggestedQuestion] { fatalError("TODO") }

    /// Follow-ups shown under each coach answer: "Why?", "Show an example", "Just tell me" (the last only
    /// when the previous question asked what to play / lead / bury). 2 or 3 chips.
    public static func followUps(after question: SuggestedQuestion?) -> [SuggestedQuestion] { fatalError("TODO") }

    /// The chip offered under a hint: asks why that hint applies, naming the step and its text.
    public static func explainHint(_ ladder: HintLadder) -> SuggestedQuestion { fatalError("TODO") }
}
