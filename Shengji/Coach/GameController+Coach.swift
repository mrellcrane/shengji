import Foundation
import ShengjiCore

/// What the table hands to the coach: the state you can see (never other hands), the hint on screen,
/// your selection and your last rejected play, plus chips for this moment.
extension GameController {
    /// The coach is available except while you are guessing who won the trick (its context would
    /// give the answer away).
    var canAskCoach: Bool { stage != .predicting && stallMessage == nil }

    var coachContext: String {
        CoachContext.describe(round: round, game: game, hint: activeHint, selection: selectedCards,
                              lastIllegal: lastIllegal)
    }

    var coachSuggestions: [SuggestedQuestion] {
        SuggestedQuestions.forTable(round: round, game: game, hint: activeHint, selection: selectedCards,
                                    lastIllegal: lastIllegal)
    }

    /// Points the conversation at the table as it is now.
    func prepareCoach(_ conversation: CoachConversation) {
        conversation.prepare(scope: .table, context: coachContext, suggestions: coachSuggestions)
    }

    /// The question offered under the hint banner ("Why?"), for the hint on screen.
    var explainHintQuestion: SuggestedQuestion? {
        activeHint.map { SuggestedQuestions.explainHint($0) }
    }
}
