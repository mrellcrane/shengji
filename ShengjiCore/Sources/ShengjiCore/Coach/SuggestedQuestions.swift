import Foundation

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
    /// Chip labels are at most this many characters.
    public static let maxLabelLength = 32
    /// Prompts are at most this many characters (the proxy accepts 1,500).
    public static let maxPromptLength = 300

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
                                lastIllegal: IllegalAttempt?) -> [SuggestedQuestion] {
        let view = round.seatView(for: Seats.human, game: game)
        let options = round.phase == .dealing ? round.availableDeclarations(for: Seats.human) : []
        let builder = TableChips(view: view, declarations: options, canDeclare: !options.isEmpty)
        return builder.chips(hint: hint, selection: selection, lastIllegal: lastIllegal)
    }

    /// The same chips from a seat view (viewer = seat 0; declarations you could make come from `view.bidding`).
    public static func forTable(view: SeatView, hint: HintLadder?, selection: [Card],
                                lastIllegal: IllegalAttempt?) -> [SuggestedQuestion] {
        let options = view.bidding?.available ?? []
        let builder = TableChips(view: view, declarations: options, canDeclare: !options.isEmpty)
        return builder.chips(hint: hint, selection: selection, lastIllegal: lastIllegal)
    }

    /// 3 or 4 chips for a lesson page: "Explain this another way", "Give me another example",
    /// "Quiz me on this", and for predict pages after answering: "Why is that the answer?".
    /// Before a predict page is answered, "Give me a hint" replaces the quiz chip (no spoilers).
    public static func forLesson(_ lesson: Lesson, pageIndex: Int, answered: Bool) -> [SuggestedQuestion] {
        let page: LessonPage? = lesson.pages.indices.contains(pageIndex) ? lesson.pages[pageIndex] : nil
        let lessonName = "lesson \(lesson.number), \"\(CoachText.plain(lesson.title))\""
        var topic = "this part of \(lessonName)"
        var question: Question?
        switch page {
        case let .text(title, _)?, let .cards(title, _, _, _)?, let .trick(title, _, _, _, _)?:
            topic = "\"\(CoachText.clip(CoachText.plain(title), 60))\" from \(lessonName)"
        case let .predict(q)?:
            question = q
        case .recap?, nil:
            break
        }

        let explain = make("lesson.explainAgain", "Explain this another way",
                           "Explain \(topic) another way, with a different example.")
        let example = make("lesson.example", "Give me another example",
                           "Give me another example of \(topic), using real cards.")
        let quiz = make("lesson.quiz", "Quiz me on this",
                        "Ask me one quick question about \(lessonName) to check I've got it. Wait for my answer before explaining.")
        guard let question else { return [explain, example, quiz] }

        let asked = quote(CoachText.plain(question.prompt), room: 140)
        if answered {
            let why = make("lesson.whyAnswer", "Why is that the answer?",
                           "In \(lessonName), the question was \(asked) Why is the right answer correct? Explain the rule behind it.")
            return [why, explain, example, quiz]
        }
        let hint = make("lesson.hint", "Give me a hint",
                        "I'm answering \(asked) Give me a hint without telling me the answer.")
        let rule = make("lesson.explainAgain", "Explain this another way",
                        "Explain the idea behind this question from \(lessonName) another way, without giving away the answer.")
        return [hint, rule, example]
    }

    /// Chips for a practice/review question after answering: "Why?", "Give me a similar example", "What's the rule?".
    /// Before answering (`answeredCorrectly == nil`): a hint that doesn't give the answer away, the rule, and the terms.
    public static func forQuestion(_ question: Question, answeredCorrectly: Bool?) -> [SuggestedQuestion] {
        let asked = quote(CoachText.plain(question.prompt), room: 160)
        guard let correct = answeredCorrectly else {
            return [
                make("question.hint", "Give me a hint",
                     "I'm answering \(asked) Give me a hint, but don't tell me the answer."),
                make("question.rule", "What's the rule?",
                     "What's the general rule I need for this question? \(asked) Don't tell me the answer."),
                make("question.terms", "What do these words mean?",
                     "Explain any game terms in this question in plain words: \(asked)"),
            ]
        }
        let why = correct
            ? "I got this right: \(asked) Why is that the answer? Explain the rule in a sentence or two."
            : "I got this wrong: \(asked) Why is the right answer correct, and where did I go wrong?"
        return [
            make("question.why", "Why?", why),
            make("question.similar", "Give me a similar example",
                 "Give me a similar question with different cards, and let me answer it before you explain."),
            make("question.rule", "What's the rule?", "What's the general rule behind this question? \(asked)"),
        ]
    }

    /// Follow-ups shown under each coach answer: "Why?", "Show an example", "Just tell me" (the last only
    /// when the previous question asked what to play / lead / bury). 2 or 3 chips. "Just tell me" comes first
    /// when offered, since the coach answers those questions by asking the learner to think first.
    public static func followUps(after question: SuggestedQuestion?) -> [SuggestedQuestion] {
        let why = make("followUp.why", "Why?", "Why? Explain the reasoning in a sentence or two.")
        let example = make("followUp.example", "Show an example", "Show me an example with real cards.")
        let justTell: SuggestedQuestion?
        switch question?.id {
        case "table.whatToPlay"?, "table.isSelectionGood"?:
            justTell = make("followUp.justTell", "Just tell me", "Just tell me what you would play here and why, in one or two sentences.")
        case "table.whatToLead"?:
            justTell = make("followUp.justTell", "Just tell me", "Just tell me what you would lead here and why, in one or two sentences.")
        case "table.whatToBury"?, "table.isBurySelectionGood"?:
            justTell = make("followUp.justTell", "Just tell me", "Just tell me which 8 cards you would bury and why, in a few sentences.")
        case "table.shouldDeclare"?:
            justTell = make("followUp.justTell", "Just tell me", "Just tell me: would you declare now, and with what?")
        default:
            justTell = nil
        }
        if let justTell { return [justTell, why, example] }
        return [why, example]
    }

    /// The chip offered under a hint: asks why that hint applies, naming the step and its text.
    public static func explainHint(_ ladder: HintLadder) -> SuggestedQuestion {
        guard let step = ladder.step else {
            return make("hint.why", "What should I notice?",
                        "What should I notice at the table right now? Give me a nudge, not the answer.")
        }
        let total = HintStep.allCases.count
        let text = CoachText.plain(ladder.text)
        switch step {
        case .nudge:
            let quoted = quote(text, room: 170)
            return make("hint.why", "Why is that the hint?",
                        "My hint (step 1 of \(total), what to notice) says: \(quoted) Why does that matter here? Don't tell me the answer yet.")
        case .principle:
            let quoted = quote(text, room: 170)
            return make("hint.why", "Why is that the hint?",
                        "My hint (step 2 of \(total), the principle) says: \(quoted) Why does that principle apply here?")
        case .show:
            // The same chip sits under play, lead and bury hints, so the wording doesn't say what the cards are for.
            let cards = ladder.highlightedCards.shortText
            let quoted = quote(text, room: 150)
            let named = cards.isEmpty ? "says" : "points to \(CoachText.clip(cards, 60))"
            return make("hint.why", "Why is that the hint?",
                        "My hint (step 3 of \(total)) \(named): \(quoted) Why is that the best choice here?")
        }
    }

    // MARK: Helpers

    /// A chip, with the label and prompt kept within their limits.
    static func make(_ id: String, _ label: String, _ prompt: String) -> SuggestedQuestion {
        SuggestedQuestion(id: id, label: CoachText.clip(label, maxLabelLength),
                          prompt: CoachText.clip(prompt, maxPromptLength))
    }

    /// The text in quotes, cut to `room` characters and ending with a full stop (or other end mark).
    static func quote(_ text: String, room: Int) -> String {
        var body = CoachText.clip(text.trimmingCharacters(in: .whitespaces), room)
        if let last = body.last, !".!?".contains(last) { body += "." }
        return "\"" + body + "\""
    }
}

// MARK: - Table chips

/// Chooses the table chips from what the viewer (seat 0) can see.
struct TableChips {
    let view: SeatView
    let declarations: [Declaration]
    let canDeclare: Bool

    var trump: Trump { view.trump }

    func chips(hint: HintLadder?, selection: [Card], lastIllegal: IllegalAttempt?) -> [SuggestedQuestion] {
        var list: [SuggestedQuestion] = []
        if let attempt = lastIllegal { list.append(whyIllegal(attempt)) }
        if let hint, hint.step != nil { list.append(SuggestedQuestions.explainHint(hint)) }
        let selected = CoachText.owned(selection, from: view.hand)

        switch view.phase {
        case .dealing, .bidding:
            list += dealingChips()
        case .burying:
            list += buryingChips(selected: selected)
        case .playing:
            list += playingChips(selected: selected)
        case .finished:
            list += finishedChips()
        }
        list += fallbacks()

        var seen = Set<String>()
        var out: [SuggestedQuestion] = []
        for chip in list where seen.insert(chip.id).inserted {
            out.append(chip)
            if out.count == 5 { break }
        }
        return out
    }

    // MARK: Situations

    /// The app reports rejected buries and declarations as illegal attempts too, so the chip names what you tried.
    func whyIllegal(_ attempt: IllegalAttempt) -> SuggestedQuestion {
        let cards = CoachText.owned(attempt.cards, from: view.hand + view.playedCards)
        let kind = CoachText.Attempt(attempt.error, phase: view.phase)
        let label: String
        let instead: String
        switch kind {
        case .bury:
            label = "Why can't I bury those?"
            instead = "what should I bury instead?"
        case .declare:
            label = "Why can't I declare that?"
            instead = "what could I declare instead?"
        case .play:
            label = "Why can't I play that?"
            instead = "what can I play instead?"
        }
        let prompt: String
        if cards.isEmpty {
            prompt = "My last move wasn't allowed. Why not, and what can I do instead?"
        } else {
            let text = CoachText.clip(trump.sorted(cards).shortText, 120)
            prompt = "I tried to \(kind.verb) \(text) but it wasn't allowed. Why not, and \(instead)"
        }
        return SuggestedQuestions.make("table.whyIllegal", label, prompt)
    }

    func dealingChips() -> [SuggestedQuestion] {
        var chips: [SuggestedQuestion] = []
        let declarePrompt: String
        if canDeclare && !declarations.isEmpty {
            let options = declarations.prefix(3).map { CoachText.declarationOption($0) }.joined(separator: ", or ")
            declarePrompt = "I could declare \(options). Should I, with the cards I have so far?"
        } else {
            declarePrompt = "Should I declare trump with the cards I have so far? What would I need to declare?"
        }
        chips.append(SuggestedQuestions.make("table.shouldDeclare", "Should I declare?", declarePrompt))
        chips.append(SuggestedQuestions.make("table.whatDeclaringDoes", "What does declaring do?",
                                             "What does declaring trump do, and what happens if my declaration wins?"))
        chips.append(SuggestedQuestions.make("table.goodTrumpSuit", "Which suit would be good trump?",
                                             "Looking at my cards so far, which suit would make the best trump for me, and why?"))
        chips.append(SuggestedQuestions.make("table.noDeclaration", "What if nobody declares?",
                                             "What happens if nobody declares trump during the deal?"))
        return chips
    }

    func buryingChips(selected: [Card]) -> [SuggestedQuestion] {
        guard view.dealer == Seats.human else {
            let dealer = view.dealer.map { CoachText.seatName($0, in: view) } ?? "The dealer"
            return [
                SuggestedQuestions.make("table.whileBurying", "What is the dealer doing?",
                                        "\(dealer) is burying cards now. What are they doing, and why does the kitty matter to my team?"),
                whatsTrump(),
                ourGoal(),
            ]
        }
        var chips: [SuggestedQuestion] = []
        if !selected.isEmpty {
            let cards = trump.sorted(selected).shortText
            chips.append(SuggestedQuestions.make("table.isBurySelectionGood", "Are these good to bury?",
                                                 "I'm thinking of burying \(CoachText.clip(cards, 100)). Is that a good choice? Why or why not?"))
        }
        chips.append(SuggestedQuestions.make("table.whatToBury", "What should I bury?",
                                             "I'm the dealer and must bury 8 cards. Which 8 should I bury from this hand, and why?"))
        chips.append(SuggestedQuestions.make("table.whyBury", "Why bury cards at all?",
                                             "Why does the dealer bury 8 cards, and what happens to them at the end of the round?"))
        chips.append(SuggestedQuestions.make("table.buryPoints", "Can I bury point cards?",
                                             "Is it a good idea to bury point cards like 5s, 10s and Ks? What's the risk?"))
        return chips
    }

    func playingChips(selected: [Card]) -> [SuggestedQuestion] {
        var chips: [SuggestedQuestion] = []
        let myTurn = view.turn == Seats.human
        let trickPause = view.currentTrick.isEmpty && !view.tricks.isEmpty

        if myTurn, !selected.isEmpty { chips.append(selectionChip(selected)) }
        if myTurn && view.currentTrick.isEmpty {
            chips.append(SuggestedQuestions.make("table.whatToLead", "What should I lead?",
                                                 "It's my turn to lead. What should I lead from this hand, and why?"))
            if let ace = safeLeadCandidate() {
                chips.append(SuggestedQuestions.make("table.isTopCardSafe", "Is my \(ace.description) safe to lead?",
                                                     "Is it safe to lead my \(ace.description) now, or could it be beaten or trumped? Use what has been played so far."))
            }
            if trickPause { chips.append(whyTrickWon()) }
            if view.hand.contains(where: { trump.isTrump($0) }) {
                chips.append(SuggestedQuestions.make("table.leadTrumps", "Should I lead trumps?",
                                                     "Should I lead trumps now, or save them? Explain using my hand and the score."))
            }
            chips.append(pointsSoFar())
            return chips
        }
        if myTurn, let lead = view.currentTrick.first {
            let leader = lead.player == Seats.human ? "I" : CoachText.seatName(lead.player, in: view)
            let cards = CoachText.clip(trump.sorted(lead.cards).shortText, 80)
            let shape = CoachText.shapeText(lead.cards, trump: trump)
            chips.append(SuggestedQuestions.make("table.whatToPlay", "What should I play?",
                                                 "\(leader) led \(cards). What should I play from my hand, and why?"))
            chips.append(whoIsWinning())
            chips.append(SuggestedQuestions.make("table.mustFollow", "What must I follow with?",
                                                 "\(leader) led \(cards) (\(shape)). What does the follow rule say I must play from my hand?"))
            if let ruff = ruffChip(lead: lead.cards) { chips.append(ruff) }
            return chips
        }
        if trickPause { chips.append(whyTrickWon()) }
        if !view.currentTrick.isEmpty { chips.append(whoIsWinning()) }
        chips.append(whatsTrump())
        chips.append(pointsSoFar())
        if view.tricks.isEmpty && view.currentTrick.isEmpty { chips.append(ourGoal()) }
        return chips
    }

    func finishedChips() -> [SuggestedQuestion] {
        guard let result = view.result else { return [] }
        var chips: [SuggestedQuestion] = []
        let ourTeamDeclared = result.declarerTeam == Seats.team(of: Seats.human)
        let weWon = ourTeamDeclared == result.outcome.declarersHold
        let label = weWon ? "Why did we win that round?" : "Why did we lose that round?"
        let verb = weWon ? "win" : "lose"
        chips.append(SuggestedQuestions.make("table.whyRoundResult", label,
                                             "The defenders scored \(result.defenderPoints). Why did my team \(verb) this round, and what decided it?"))
        if result.kittyMultiplier > 0 && result.kittyPoints > 0 {
            chips.append(SuggestedQuestions.make("table.kittyScoring", "How was the kitty scored?",
                                                 "The kitty held \(result.kittyPoints) points and counted ×\(result.kittyMultiplier). How was that worked out?"))
        }
        if let winner = view.gameWinnerTeam {
            // The game is over: there is no next round to ask about.
            let ours = winner == Seats.team(of: Seats.human)
            let who = ours ? "My team" : "\(CoachText.seatName(1, in: view)) and \(CoachText.seatName(3, in: view))"
            chips.append(SuggestedQuestions.make("table.gameOver", ours ? "How did we win the game?" : "How did they win the game?",
                                                 "\(who) just won the whole game. How does a team win the game in Shengji, and what decided it this round?"))
        } else {
            chips.append(SuggestedQuestions.make("table.whatNext", "What happens next round?",
                                                 "What happens to the levels after this round, and who deals next?"))
        }
        chips.append(SuggestedQuestions.make("table.doBetter", "What could I do better?",
                                             "Looking at how this round went, what's one thing I could do better next time?"))
        return chips
    }

    func fallbacks() -> [SuggestedQuestion] {
        let part: String
        switch view.phase {
        case .dealing, .bidding: part = "dealing and declaring trump"
        case .burying: part = "burying the kitty"
        case .playing: part = view.currentTrick.isEmpty ? "leading a trick" : "following in a trick"
        case .finished: part = "scoring a round"
        }
        return [
            SuggestedQuestions.make("table.explainRules", "Explain the rules for this",
                                    "Explain the rules for this part of the round (\(part)) in a few sentences."),
            whatsTrump(),
            SuggestedQuestions.make("table.scoring", "How does scoring work?",
                                    "How does scoring work in Shengji, and what do the defenders need?"),
        ]
    }

    // MARK: Chips used in several situations

    func whatsTrump() -> SuggestedQuestion {
        SuggestedQuestions.make("table.whatsTrump", "What's trump right now?",
                                "What's trump right now? List the trumps from highest to lowest.")
    }

    func whoIsWinning() -> SuggestedQuestion {
        SuggestedQuestions.make("table.whoIsWinning", "Who's winning this trick?",
                                "Who is winning this trick right now, and why?")
    }

    func pointsSoFar() -> SuggestedQuestion {
        SuggestedQuestions.make("table.points", "How are the points going?",
                                "How many points have the defenders got so far, and what does that mean for this round?")
    }

    func ourGoal() -> SuggestedQuestion {
        let prompt: String
        if let dealer = view.dealer, Seats.team(of: dealer) == Seats.team(of: Seats.human) {
            prompt = "My team are the declarers this round. What do we need to do, and how should I play?"
        } else if view.dealer != nil {
            prompt = "My team are defending this round. How many points do we need, and how do we get them?"
        } else {
            prompt = "What is my team trying to do this round?"
        }
        return SuggestedQuestions.make("table.ourGoal", "What's our goal this round?", prompt)
    }

    func whyTrickWon() -> SuggestedQuestion {
        guard let last = view.tricks.last else { return whoIsWinning() }
        // Online the winner goes by name; a long one would be cut off, so the label says "they" instead.
        let named = "Why did \(CoachText.seatName(last.winner, in: view)) win that?"
        let label = last.winner == Seats.human ? "Why did I win that?"
            : named.count <= SuggestedQuestions.maxLabelLength ? named : "Why did they win that?"
        let winner = last.winner == Seats.human ? "I" : CoachText.seatName(last.winner, in: view)
        let leadPlay = last.plays.first
        var prompt = "Why did \(winner) win the last trick?"
        if let leadPlay {
            let leader = leadPlay.player == Seats.human ? "I" : CoachText.seatName(leadPlay.player, in: view)
            prompt = "Why did \(winner) win the last trick (\(leader) led \(CoachText.clip(trump.sorted(leadPlay.cards).shortText, 80)))?"
        }
        prompt += " Walk me through what beat what."
        return SuggestedQuestions.make("table.whyTrickWon", label, prompt)
    }

    func selectionChip(_ selected: [Card]) -> SuggestedQuestion {
        let cards = trump.sorted(selected).shortText
        let shortLabel = "Is \(cards) a good play?"
        let label = shortLabel.count <= SuggestedQuestions.maxLabelLength ? shortLabel : "Is my selection a good play?"
        return SuggestedQuestions.make("table.isSelectionGood", label,
                                       "I'm thinking of playing \(CoachText.clip(cards, 100)). Is that legal, and is it a good idea here?")
    }

    /// The viewer is out of the led suit and holds trumps: trump or discard?
    func ruffChip(lead: [Card]) -> SuggestedQuestion? {
        guard let first = lead.first else { return nil }
        let group = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        guard case let .plain(suit) = group else { return nil }
        let holdsSuit = view.hand.contains { trump.group($0) == group }
        let holdsTrump = view.hand.contains { trump.isTrump($0) }
        guard !holdsSuit && holdsTrump else { return nil }
        return SuggestedQuestions.make("table.ruffOrDiscard", "Should I trump or discard?",
                                       "I have no \(suit.name.lowercased()) left. Should I trump this trick or throw away a low card?")
    }

    /// The top plain card the viewer holds (an ace, or a king when aces are the trump rank), in display order.
    func safeLeadCandidate() -> Card? {
        for suit in trump.plainSuitOrder {
            let top = view.hand.filter { trump.group($0) == .plain(suit) && trump.strength($0) == Trump.topPlainStrength }
            if let card = top.min(by: { $0.id < $1.id }) { return card }
        }
        return nil
    }
}
