import Foundation

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
///
/// The table description is built from `SeatView` (the per-seat model that never holds hidden cards),
/// so privacy is structural: `describe(round:...)` first turns the round into the human's seat view.
/// The text is one fact per line ("Label: value"), with cards written as on screen ("10♥", "SJ", "BJ").
public enum CoachContext {
    /// Table descriptions stay under this many characters (the proxy accepts at most 6,000).
    public static let maxTableCharacters = 3_500
    /// Lesson and practice-question descriptions stay under this many characters.
    public static let maxLessonCharacters = 2_500

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
                                lastIllegal: IllegalAttempt?) -> String {
        let view = round.seatView(for: Seats.human, game: game)
        let declarations = round.phase == .dealing ? round.availableDeclarations(for: Seats.human) : nil
        let table = TableDescription(view: view, levelsKnown: game != nil, available: declarations,
                                     dealingComplete: round.isDealingComplete)
        return table.text(hint: hint, selection: selection, lastIllegal: lastIllegal)
    }

    /// The same description built from a seat view (online play, or any view where the viewer is seat 0).
    /// Levels come from the view. Declarations you could make come from `view.bidding` (online bidding).
    public static func describe(view: SeatView, hint: HintLadder?, selection: [Card],
                                lastIllegal: IllegalAttempt?) -> String {
        let total = view.handCounts.reduce(0, +)
        let size = view.table
        let table = TableDescription(view: view, levelsKnown: true, available: view.bidding?.available,
                                     dealingComplete: total >= size.players * size.handSize || view.phase != .dealing)
        return table.text(hint: hint, selection: selection, lastIllegal: lastIllegal)
    }

    /// Context for a question asked inside a lesson: lesson title and number, the page's title and text,
    /// cards shown on it (with trump context), and for predict pages the question, choices and whether the
    /// learner has answered (and what). Under ~2,500 characters.
    public static func describe(lesson: Lesson, pageIndex: Int, chosenAnswer: Int?) -> String {
        var lines: [String] = []
        var heading = "Where: lesson \(lesson.number) of \(Curriculum.lessons.count), \"\(CoachText.plain(lesson.title))\""
        if !lesson.subtitle.isEmpty { heading += " (\(CoachText.plain(lesson.subtitle)))" }
        lines.append(heading + ".")
        if let term = lesson.chineseTerm, !term.isEmpty {
            lines.append("Key term: \(CoachText.plain(term)).")
        }
        let titles: [String] = lesson.pages.enumerated().map { pair in
            "\(pair.offset + 1) \(CoachText.clip(CoachText.pageTitle(pair.element), 40))"
        }
        if !titles.isEmpty {
            lines.append(CoachText.clip("Lesson pages: " + titles.joined(separator: "; ") + ".", 500))
        }
        guard lesson.pages.indices.contains(pageIndex) else {
            lines.append("Page: not open (the learner is looking at the lesson as a whole).")
            return CoachText.fit(lines, limit: maxLessonCharacters)
        }
        let page = lesson.pages[pageIndex]
        let position = "Page \(pageIndex + 1) of \(lesson.pages.count)"
        switch page {
        case let .text(title, body):
            lines.append("\(position): \"\(CoachText.plain(title))\" (explanation).")
            lines.append("Text: " + CoachText.clip(CoachText.plain(body), 900))
        case let .cards(title, body, cards, trump):
            lines.append("\(position): \"\(CoachText.plain(title))\" (cards example).")
            lines.append("Text: " + CoachText.clip(CoachText.plain(body), 900))
            if let trump {
                lines.append(contentsOf: CoachText.trumpLines(trump))
            }
            if !cards.isEmpty { lines.append("Cards shown: \(cards.shortText).") }
        case let .trick(title, body, plays, trump, winner):
            lines.append("\(position): \"\(CoachText.plain(title))\" (worked trick example).")
            lines.append("Text: " + CoachText.clip(CoachText.plain(body), 900))
            lines.append(contentsOf: CoachText.trumpLines(trump))
            lines.append("Trick shown: " + CoachText.playsSentence(plays, trump: trump) + " Winner: \(Seats.name(winner)).")
        case let .predict(question):
            lines.append("\(position): a \"your turn\" question (the learner answers before seeing the explanation).")
            lines.append(contentsOf: CoachText.questionLines(question, chosenAnswer: chosenAnswer))
        case let .recap(points):
            lines.append("\(position): recap.")
            let joined = points.map { CoachText.plain($0) }.joined(separator: " ")
            lines.append("Key points: " + CoachText.clip(joined, 900))
        }
        return CoachText.fit(lines, limit: maxLessonCharacters)
    }

    /// Context for a practice/review question: the prompt, trump, visual (as text), choices, the learner's
    /// answer if given, and the correct answer + explanation only once answered.
    public static func describe(question: Question, chosenAnswer: Int?) -> String {
        var lines: [String] = ["Where: a practice question (\(CoachText.topic(of: question.itemID)))."]
        lines.append(contentsOf: CoachText.questionLines(question, chosenAnswer: chosenAnswer))
        return CoachText.fit(lines, limit: maxLessonCharacters)
    }
}

// MARK: - Table description

/// Builds the table text from a seat view (viewer = seat 0).
struct TableDescription {
    let view: SeatView
    let levelsKnown: Bool
    /// Declarations the viewer could make now (nil when unknown).
    let available: [Declaration]?
    let dealingComplete: Bool

    var trump: Trump { view.trump }

    /// Players and decks at this table.
    var table: TableSize { view.table }
    var players: Int { table.players }

    /// How the table names a seat: "East", "Partner" with 4 players, compass points with more.
    func name(_ seat: Int) -> String { CoachText.name(seat, players: players) }

    /// "East and West" at a table of four, "the other team" at a bigger one.
    var otherTeam: String { players > 4 ? "the other team" : "East and West" }

    func text(hint: HintLadder?, selection: [Card], lastIllegal: IllegalAttempt?,
              limit: Int = CoachContext.maxTableCharacters) -> String {
        // Lines in order of importance; optional ones are dropped from the end of the list (lowest
        // priority first) if the text grows too long. Priority 0 lines are always kept.
        var lines: [(text: String, priority: Int)] = []
        func add(_ text: String?, _ priority: Int) {
            guard let text, !text.isEmpty else { return }
            lines.append((text, priority))
        }

        add(phaseLine(), 0)
        add(gameLine(), 2)
        for line in trumpLines() { add(line, 1) }
        add(teamsLine(), 0)
        add(CoachText.namesLine(view), 0)
        add(pointsLine(), 0)
        add(handLine(), 0)
        add(combinationsLine(), 3)
        add(dealingLines(), 0)
        add(kittyLine(), 2)
        add(currentTrickLine(), 0)
        add(lastTrickLine(), 2)
        add(tricksWonLine(), 4)
        add(playedLine(compact: false), 5)
        add(stillOutLine(), 6)
        add(voidsLine(), 3)
        add(resultLines(), 0)
        add(previousRoundLine(), 6)
        add(hintLine(hint), 0)
        add(selectionLine(selection), 0)
        add(illegalLine(lastIllegal), 0)

        var texts = lines.map(\.text)
        if CoachText.length(texts) > limit, let index = texts.firstIndex(where: { $0.hasPrefix("Played so far") }),
           let compact = playedLine(compact: true) {
            texts[index] = compact
        }
        var priorities = lines.map(\.priority)
        var level = 6
        while CoachText.length(texts) > limit && level > 0 {
            var keptTexts: [String] = []
            var keptPriorities: [Int] = []
            for (index, text) in texts.enumerated() where priorities[index] < level {
                keptTexts.append(text)
                keptPriorities.append(priorities[index])
            }
            texts = keptTexts
            priorities = keptPriorities
            level -= 1
        }
        return CoachText.fit(texts, limit: limit)
    }

    // MARK: Lines

    func phaseLine() -> String {
        switch view.phase {
        case .dealing:
            let held = view.hand.count
            if dealingComplete {
                return "Phase: dealing is finished (you have \(held) cards). Last chance to declare trump before the kitty goes to the dealer."
            }
            return "Phase: dealing. Cards are still arriving (you have \(held) of \(table.handSize)). Anyone may declare trump now."
        case .bidding:
            if let turn = view.bidding?.turn {
                if turn == Seats.human { return "Phase: declaring. Your turn to declare trump or pass." }
                return "Phase: declaring. Waiting for \(name(turn)) to declare trump or pass."
            }
            return "Phase: declaring trump."
        case .burying:
            guard let dealer = view.dealer else { return "Phase: burying the kitty." }
            if dealer == Seats.human {
                return "Phase: burying. You are the dealer: you picked up the \(table.kittySize) kitty cards and now choose \(table.kittySize) cards to bury face down."
            }
            return "Phase: burying. \(name(dealer)) (the dealer) is burying \(table.kittySize) cards face down. Play starts after that."
        case .playing:
            let number = view.tricks.count + 1
            if view.currentTrick.isEmpty {
                if view.turn == Seats.human {
                    return "Phase: playing, trick \(number). Your turn to lead."
                }
                return "Phase: playing, trick \(number). Waiting for \(name(view.leader)) to lead."
            }
            if view.turn == Seats.human {
                return "Phase: playing, trick \(number). Your turn to follow."
            }
            if let turn = view.turn {
                return "Phase: playing, trick \(number). Waiting for \(name(turn)) to play."
            }
            return "Phase: playing, trick \(number)."
        case .finished:
            return "Phase: the round is over."
        }
    }

    func gameLine() -> String? {
        if view.findsFriends { return friendsGameLine() }
        guard levelsKnown, view.teamLevels.count == 2 else { return nil }
        let ours = view.teamLevels[0].label
        let theirs = view.teamLevels[1].label
        var line = "Levels: your team \(ours), \(otherTeam) \(theirs) (the game is won by holding the deal at \(view.targetRank.label))."
        line = "Round \(view.roundNumber) of this game. " + line
        if let winner = view.gameWinnerTeam {
            let theyWon = players > 4 ? " The other team has won the game." : " East and West have won the game."
            line += winner == 0 ? " Your team has won the game!" : theyWon
        }
        return line
    }

    func trumpLines() -> [String] {
        switch view.phase {
        case .dealing, .bidding:
            var lines: [String] = []
            if let declaration = view.declaration {
                let suit = declaration.suit.map { "\($0.symbol) would be the trump suit" } ?? "there would be no trump suit"
                lines.append("Trump rank: \(trump.rank.label). Current declaration: \(declaration.description(players: players)), so \(suit). A stronger declaration can still replace it.")
                lines.append(contentsOf: CoachText.orderLines(trump))
            } else {
                lines.append("Trump rank: \(trump.rank.label). Trump suit: not declared yet. If nobody declares, the kitty is flipped to choose it.")
            }
            return lines
        case .burying, .playing, .finished:
            var lines = CoachText.trumpLines(trump, decks: table.decks)
            if let flipped = view.trumpFromKitty {
                lines.append("Nobody declared, so the kitty was flipped: the \(flipped.description) set the trump.")
            } else if let declaration = view.declaration {
                lines.append("Trump was set by this declaration: \(declaration.description(players: players)).")
            }
            return lines
        }
    }

    /// Finding Friends: everyone's own level.
    func friendsGameLine() -> String? {
        guard levelsKnown, view.teamLevels.count == players else { return nil }
        let levels = Seats.all(players: players).map { seat in
            "\(seat == Seats.human ? "you" : name(seat)) \(view.teamLevels[seat].label)"
        }
        var line = "Round \(view.roundNumber) of this game. Levels (everyone climbs on their own): "
            + levels.joined(separator: ", ")
            + " (the game is won by the dealer's side holding the deal while the dealer is at \(view.targetRank.label))."
        if let winner = view.gameWinnerTeam {
            line += winner == 0 ? " You were on the side that won the game!" : " The game is over: the other side won it."
        }
        return line
    }

    func teamsLine() -> String {
        if view.findsFriends { return friendsTeamsLine() }
        if players > 4 { return bigTeamsLine() }
        guard let dealer = view.dealer else {
            return "Seats: you (South), East, Partner (North, your partner), West. Dealer: not decided yet. In the first round, whoever wins the declaration deals."
        }
        let declarersAreUs = Seats.team(of: dealer) == Seats.team(of: Seats.human)
        let dealerName = dealer == Seats.human ? "you" : Seats.name(dealer)
        if declarersAreUs {
            return "Seats: you (South) and Partner (North) against East and West. Dealer: \(dealerName). Your team are the declarers; East and West are the defenders."
        }
        return "Seats: you (South) and Partner (North) against East and West. Dealer: \(dealerName). East and West are the declarers; your team are the defenders."
    }

    /// Seats and teams at a table of 6 or 8: seats in play order, every other seat a partner.
    func bigTeamsLine() -> String {
        let order = Seats.all(players: players).map { $0 == Seats.human ? "you (South)" : name($0) }
        let partners = Seats.teammates(of: Seats.human, players: players).map(name)
        let opponents = Seats.opponents(of: Seats.human, players: players).map(name)
        var line = "Seats in order of play: \(order.joined(separator: ", ")). Teams sit in every other seat: "
            + "your team is you, \(CoachText.list(partners)); the other team is \(CoachText.list(opponents)). "
            + "This table has \(players) players and \(table.decks) decks (\(table.cardCount) cards, \(table.totalPoints) points): "
            + "every card exists \(table.decks) times, so triples\(table.decks >= 4 ? " and four of a kind" : "") "
            + "are combinations too, \(Scoring.takeoverThreshold(decks: table.decks)) points take over the deal, "
            + "and each level is worth \(Scoring.stepSize(decks: table.decks)) points."
        guard let dealer = view.dealer else {
            return line + " Dealer: not decided yet. In the first round, whoever wins the declaration deals."
        }
        let dealerName = dealer == Seats.human ? "you" : name(dealer)
        let declarersAreUs = Seats.team(of: dealer) == Seats.team(of: Seats.human)
        line += " Dealer: \(dealerName). "
        line += declarersAreUs ? "Your team are the declarers; the other team are the defenders."
            : "The other team are the declarers; your team are the defenders."
        return line
    }

    /// Finding Friends: no fixed teams; the friends called and found so far.
    func friendsTeamsLine() -> String {
        let order = Seats.all(players: players).map { $0 == Seats.human ? "you (South)" : name($0) }
        let friends = table.friendCount
        var line = "Seats in order of play: \(order.joined(separator: ", ")). This table has \(players) players and "
            + "\(table.decks) decks (\(table.cardCount) cards, \(table.totalPoints) points), so it plays Finding Friends "
            + "(找朋友 zhǎo péngyou): nobody has fixed partners. After burying, the dealer calls \(friends) "
            + (friends == 1 ? "friend" : "friends") + " by naming cards (such as the first A♠); whoever plays a called "
            + "card joins the dealer's side, and nobody knows who the friends are until then. Everyone else defends. "
            + "Every card exists \(table.decks) times, so triples and bigger sets are combinations too, "
            + "\(Scoring.takeoverThreshold(decks: table.decks)) points take over the deal, and each level is worth "
            + "\(Scoring.stepSize(decks: table.decks)) points. A dealer's side that holds the deal with fewer players than "
            + "it could have had goes up 1 extra level."
        guard let dealer = view.dealer else {
            return line + " Dealer: not decided yet. In the first round, whoever wins the declaration deals."
        }
        line += " Dealer: \(dealer == Seats.human ? "you" : name(dealer))."
        guard let calls = view.friendCalls, !calls.isEmpty else {
            return line + (view.phase == .burying ? " The dealer calls their friends when they bury." : "")
        }
        let called = calls.map { call -> String in
            guard let friend = call.friend else { return "\(call) (not played yet)" }
            if friend == dealer { return "\(call) (played by the dealer, so no friend)" }
            return "\(call) (played by \(friend == Seats.human ? "you" : name(friend)))"
        }
        line += " Friends called: \(CoachText.list(called))."
        let side = view.declarers.map { $0 == Seats.human ? "you" : name($0) }
        line += " The dealer's side so far: \(CoachText.list(side))."
        let held = calls.filter { call in call.friend == nil && view.hand.contains { $0.face == call.face } }
        if !held.isEmpty, !view.isDeclarer(Seats.human) {
            line += " You hold \(CoachText.list(held.map { "a copy of \($0.face)" })): play the called copy and you join the dealer's side."
        } else if view.isDeclarer(Seats.human) {
            line += " You are on the dealer's side."
        } else {
            line += " You are a defender unless you play a called card."
        }
        return line
    }

    func pointsLine() -> String? {
        guard view.phase == .playing else { return nil }
        let defenders = view.defenderTrickPoints
        let played = view.playedCards.points
        let threshold = Scoring.takeoverThreshold(decks: table.decks)
        let need = max(0, threshold - defenders)
        let who: String
        if view.findsFriends {
            who = view.isDefender(Seats.human) ? "the defenders (your side unless you play a called card)" : "the defenders"
        } else {
            who = view.isDefender(Seats.human) ? "your team (the defenders)" : "the defenders (\(otherTeam))"
        }
        var line = "Points: \(who) have \(defenders) so far; \(threshold) takes over the deal"
        line += need > 0 ? " (\(need) more needed)." : " (already reached)."
        line += " Points in the cards played so far: \(played) of \(table.totalPoints)."
        return line
    }

    func handLine() -> String? {
        let hand = view.hand
        if hand.isEmpty {
            return view.phase == .dealing || view.phase == .bidding ? "Your hand: no cards yet." : nil
        }
        var parts: [String] = []
        for suit in trump.plainSuitOrder {
            let cards = trump.sorted(hand.filter { trump.group($0) == .plain(suit) })
            if cards.isEmpty {
                parts.append("\(suit.name): none")
            } else {
                parts.append("\(suit.name) (\(cards.count)): \(cards.shortText)")
            }
        }
        let trumps = trump.sorted(hand.filter { trump.isTrump($0) })
        if trumps.isEmpty {
            parts.append("Trumps: none")
        } else {
            parts.append("Trumps (\(trumps.count)): \(trumps.shortText)")
        }
        return "Your hand (\(hand.count) cards, low to high): " + parts.joined(separator: " | ")
    }

    func combinationsLine() -> String? {
        guard view.phase == .playing || view.phase == .burying else { return nil }
        var tractors: [String] = []
        var pairs: [String] = []
        for group in CoachText.groupOrder(trump) {
            let cards = view.hand.filter { trump.group($0) == group }
            guard cards.count >= 2 else { continue }
            for component in Combos.decompose(cards, trump: trump) {
                let text = trump.sorted(component.cards).shortText
                switch component.shape {
                case .tractor, .setTractor: tractors.append(text)
                case .pair, .set: pairs.append(text)
                case .single: break
                }
            }
        }
        if tractors.isEmpty && pairs.isEmpty { return nil }
        var line = "Your combinations:"
        if !tractors.isEmpty { line += " tractors \(tractors.joined(separator: ", "));" }
        line += pairs.isEmpty ? " no other pairs." : " pairs \(pairs.joined(separator: ", "))."
        return line
    }

    func dealingLines() -> String? {
        guard view.phase == .dealing || view.phase == .bidding else { return nil }
        var parts: [String] = []
        if view.declarationHistory.count > 1 {
            let history = view.declarationHistory.map(\.description).joined(separator: "; ")
            parts.append("Declarations so far: \(history).")
        }
        if let options = available {
            if options.isEmpty {
                parts.append(whyNoDeclaration())
            } else {
                let texts = options.map { CoachText.declarationOption($0) }
                parts.append("You could declare: \(texts.joined(separator: "; ")).")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Why the viewer has no declaration to make right now.
    func whyNoDeclaration() -> String {
        var myTurnToBid = false
        if view.phase == .bidding, let turn = view.bidding?.turn {
            if turn != Seats.human {
                return "It is \(name(turn))'s turn to declare or pass; you can declare when your turn comes."
            }
            myTurnToBid = true
        }
        let reason: String
        if let current = view.declaration {
            if current.player != Seats.human {
                reason = "You can't declare right now (no rank cards or jokers that beat the current declaration)."
            } else if current.strength == 1 || (table.decks > 2 && current.cardCount < table.decks) {
                reason = current.strength == 1 && table.decks <= 2
                    ? "Your declaration is the current one. You can only strengthen it with a pair of the same card."
                    : "Your declaration is the current one. You can only strengthen it with more of the same card."
            } else {
                reason = "Your declaration is the current one, and it can't be strengthened any further."
            }
        } else {
            let rank = CoachText.rankSingular(trump.rank)
            reason = "You can't declare yet: you need a \(rank) (any suit) or a pair of matching jokers."
        }
        return myTurnToBid ? reason + " So pass this turn." : reason
    }

    func kittyLine() -> String? {
        switch view.phase {
        case .dealing, .bidding:
            return nil
        case .burying:
            if let kitty = view.kitty, view.dealer == Seats.human {
                return "Kitty cards you picked up (now in your hand): \(trump.sorted(kitty).shortText)."
            }
            return nil
        case .playing:
            guard let dealer = view.dealer else { return nil }
            if dealer == Seats.human {
                guard let kitty = view.kitty else { return "Kitty: you buried \(table.kittySize) cards face down." }
                return "Kitty you buried (\(kitty.points) points): \(trump.sorted(kitty).shortText). If the defenders win the last trick, its points count for them, multiplied."
            }
            return "Kitty: \(table.kittySize) cards buried face down by \(name(dealer)). They stay hidden until the round ends."
        case .finished:
            return nil
        }
    }

    func currentTrickLine() -> String? {
        guard view.phase == .playing, !view.currentTrick.isEmpty else { return nil }
        let plays = view.currentTrick
        var line = "Current trick (\(plays.flatMap(\.cards).points) points so far): "
        line += CoachText.playsSentence(plays, trump: trump, players: players)
        line += " " + CoachText.winningSentence(plays, trump: trump, players: players)
        var waiting: [String] = []
        // A trick has a play per seat; an online view could hold more by mistake, which must not crash.
        if plays.count < players {
            for offset in plays.count..<players { waiting.append(name((view.leader + offset) % players)) }
        }
        if !waiting.isEmpty { line += " Still to play: \(waiting.joined(separator: ", "))." }
        return line
    }

    func lastTrickLine() -> String? {
        guard let last = view.tricks.last else { return nil }
        let number = view.tricks.count
        let justFinished = view.phase == .playing && view.currentTrick.isEmpty
        let label = justFinished ? "Trick just finished (#\(number))" : "Last finished trick (#\(number))"
        let winner = last.winner == Seats.human ? "You won it" : "\(name(last.winner)) won it"
        return "\(label): " + CoachText.playsSentence(last.plays, trump: trump, players: players)
            + " \(winner) (\(last.points) points)."
    }

    func tricksWonLine() -> String? {
        guard !view.tricks.isEmpty else { return nil }
        var parts: [String] = []
        for seat in Seats.all(players: players) {
            let won = view.tricks.filter { $0.winner == seat }
            guard !won.isEmpty else { continue }
            let points = won.reduce(0) { $0 + $1.points }
            let tricks = won.count == 1 ? "1 trick" : "\(won.count) tricks"
            parts.append("\(name(seat)) \(tricks) (\(points) points)")
        }
        guard !parts.isEmpty else { return nil }
        let header = view.phase == .finished ? "Tricks won" : "Tricks won so far"
        return "\(header): " + parts.joined(separator: ", ") + "."
    }

    func playedLine(compact: Bool) -> String? {
        guard view.phase == .playing else { return nil }
        let played = view.playedCards
        guard !played.isEmpty else { return nil }
        var parts: [String] = []
        for group in CoachText.groupOrder(trump) {
            let inGroup: [Card] = played.filter { trump.group($0) == group }
            let cards: [Card] = Array(trump.sorted(inGroup).reversed())
            guard !cards.isEmpty else { continue }
            let name = CoachText.groupTitle(group)
            if compact {
                parts.append("\(name) \(cards.count) (\(cards.points) points)")
            } else {
                parts.append("\(name) (\(cards.count)): \(cards.shortText)")
            }
        }
        let header = compact ? "Played so far by suit (counts)" : "Played so far (\(played.count) cards, high to low)"
        return "\(header): " + parts.joined(separator: " | ")
    }

    func stillOutLine() -> String? {
        guard view.phase == .playing else { return nil }
        var known: [Card] = view.hand + view.playedCards
        let kittyKnown = view.kitty != nil
        if let kitty = view.kitty { known += kitty }
        var counts: [SuitGroup: Int] = [:]
        var seen = Set(known.map(\.id))
        for card in Deck.cards(decks: table.decks) where seen.insert(card.id).inserted {
            counts[trump.group(card), default: 0] += 1
        }
        var parts: [String] = []
        for group in CoachText.groupOrder(trump) {
            parts.append("\(CoachText.groupTitle(group)) \(counts[group] ?? 0)")
        }
        let others = players > 4 ? "\(players - 1)" : "three"
        let note = kittyKnown ? "in the other \(others) hands" : "in the other hands or the kitty"
        return "Cards still out (\(note)): " + parts.joined(separator: ", ") + "."
    }

    func voidsLine() -> String? {
        guard view.phase == .playing else { return nil }
        let voids = CoachText.knownVoids(tricks: view.tricks, current: view.currentTrick, trump: trump)
        var parts: [String] = []
        for seat in 1..<players {
            guard let groups = voids[seat], !groups.isEmpty else { continue }
            let names = CoachText.groupOrder(trump).filter { groups.contains($0) }.map(\.name)
            parts.append("\(name(seat)) has no \(CoachText.list(names))")
        }
        guard !parts.isEmpty else { return nil }
        return "Known to be out of a suit: " + parts.joined(separator: "; ") + "."
    }

    func resultLines() -> String? {
        guard view.phase == .finished, let result = view.result else { return nil }
        var parts: [String] = []
        let bonus = result.kittyPoints * result.kittyMultiplier
        var scored = "Result: the defenders scored \(result.defenderPoints)"
        scored += bonus > 0 ? " (\(result.trickPoints) from tricks + \(bonus) kitty bonus)." : "."
        parts.append(scored)
        let kittyText = trump.sorted(result.kitty).shortText
        let buriedBy = result.dealer == Seats.human ? "you" : name(result.dealer)
        var kitty = "Kitty (buried by \(buriedBy), \(result.kittyPoints) points): \(kittyText)."
        if result.kittyMultiplier > 0 {
            kitty += " The defenders won the last trick, so the kitty's points counted ×\(result.kittyMultiplier)."
        } else {
            kitty += " The declarers won the last trick, so the kitty did not count."
        }
        parts.append(kitty)
        parts.append("Outcome: " + CoachText.plain(result.outcome.summary))
        let ourTeamDeclared = result.declarerTeam == Seats.team(of: Seats.human)
        let weWon = ourTeamDeclared == result.outcome.declarersHold
        if let declarers = result.declarers {
            let side = declarers.map { $0 == Seats.human ? "you" : name($0) }
            parts.append("The dealer's side was \(CoachText.list(side)).")
            parts.append(weWon ? "Your side won this round." : "Your side lost this round.")
        } else {
            parts.append(weWon ? "Your team won this round." : "Your team lost this round.")
        }
        if let summary = view.lastRoundSummary, summary.result == result {
            parts.append("What happens next: " + CoachText.plain(summary.explanation))
        }
        return parts.joined(separator: " ")
    }

    func previousRoundLine() -> String? {
        guard view.phase == .dealing || view.phase == .bidding, let summary = view.lastRoundSummary else { return nil }
        return "Previous round: " + CoachText.clip(CoachText.plain(summary.explanation), 400)
    }

    func hintLine(_ hint: HintLadder?) -> String? {
        guard let hint, let step = hint.step else { return nil }
        let text = CoachText.clip(CoachText.plain(hint.text), 400)
        let buryHint: Bool = step == HintStep.show && view.phase == SeatView.Phase.burying
        let name: String = buryHint ? "the cards to bury" : CoachText.stepName(step)
        var line = "Hint shown to you (step \(step.rawValue) of \(HintStep.allCases.count), \(name)): \(text)"
        if let concept = hint.concept { line += " Concept: \(CoachText.clip(CoachText.plain(concept), 60))." }
        let cards = CoachText.owned(hint.highlightedCards, from: view.hand)
        if !cards.isEmpty { line += " Suggested cards: \(trump.sorted(cards).shortText)." }
        return line
    }

    func selectionLine(_ selection: [Card]) -> String? {
        let cards = CoachText.owned(selection, from: view.hand)
        guard !cards.isEmpty else { return nil }
        let pending = view.phase == .burying ? "not buried yet" : "not played yet"
        return "Cards you have selected (\(pending)): \(trump.sorted(cards).shortText)."
    }

    func illegalLine(_ attempt: IllegalAttempt?) -> String? {
        guard let attempt else { return nil }
        let visible = view.hand + view.playedCards + (view.kitty ?? [])
        let cards = CoachText.owned(attempt.cards, from: visible)
        let reason = CoachText.clip(CoachText.plain(attempt.error.explanation), 500)
        if cards.isEmpty {
            return "Your last attempt was not allowed. Reason: \(reason)"
        }
        let verb = CoachText.Attempt(attempt.error, phase: view.phase).verb
        return "You just tried to \(verb) \(trump.sorted(cards).shortText) and it was not allowed. Reason: \(reason)"
    }
}

// MARK: - Shared text helpers (coach context, suggested questions, move toasts)

enum CoachText {
    /// Plain text for the coach: no markdown bold markers, no line breaks, no em dashes.
    static func plain(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "**", with: "")
        out = out.replacingOccurrences(of: " \u{2014} ", with: ", ")
        out = out.replacingOccurrences(of: "\u{2014}", with: ", ")
        out = out.replacingOccurrences(of: "\r", with: " ")
        out = out.replacingOccurrences(of: "\n", with: " ")
        return out
    }

    /// How a table of `players` names a seat: "East", "Partner" with 4, compass points with 6 or 8.
    static func name(_ seat: Int, players: Int = 4) -> String {
        players > 4 ? Seats.name(seat, players: players) : Seats.name(seat)
    }

    /// What the table calls `seat` (someone other than you): the player's name in the view. Offline views
    /// carry the compass names ("East", "Partner", "West"); online ones carry people's names, as the table shows.
    static func seatName(_ seat: Int, in view: SeatView) -> String {
        let players = view.playerCount
        let s = Seats.normalized(seat, players: players)
        guard view.players.indices.contains(s) else { return name(s, players: players) }
        let text = plain(view.players[s].name).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? name(s, players: players) : clip(text, 24)
    }

    /// "Names at this table: East is Bo, Partner (North) is Cy, West is Di." for an online table, which
    /// shows names rather than compass seats. Nil offline, where the table says East and West too.
    static func namesLine(_ view: SeatView) -> String? {
        let players = view.playerCount
        let seats = Array(1..<players)
        guard seats.contains(where: { seatName($0, in: view) != name($0, players: players) }) else { return nil }
        let labels = players > 4 ? Seats.all(players: players).map { Seats.name($0, players: players) }
            : ["", "East", "Partner (North)", "West"]
        let pairs = seats.map { "\(labels[$0]) is \(seatName($0, in: view))" }
        return "Names at this table: \(pairs.joined(separator: ", ")). The table shows these names, so call players by them, not by compass seats."
    }

    /// Cuts `text` to at most `limit` characters (adding "..." when cut).
    static func clip(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > 3 else { return String(text.prefix(max(0, limit))) }
        return String(text.prefix(limit - 3)) + "..."
    }

    /// Length the proxy measures (JavaScript string length, UTF-16 code units).
    static func length(_ lines: [String]) -> Int {
        var total = max(0, lines.count - 1)
        for line in lines { total += line.utf16.count }
        return total
    }

    /// Joins lines with newlines, keeping the result within `limit` UTF-16 code units.
    static func fit(_ lines: [String], limit: Int) -> String {
        var out = ""
        for line in lines {
            let candidate = out.isEmpty ? line : out + "\n" + line
            if candidate.utf16.count <= limit {
                out = candidate
                continue
            }
            // Cut the line that doesn't fit and stop.
            let room = limit - out.utf16.count - (out.isEmpty ? 0 : 1) - 3
            guard room > 0 else { break }
            var piece = line
            while piece.utf16.count > room, !piece.isEmpty {
                piece.removeLast()
            }
            out = out.isEmpty ? piece + "..." : out + "\n" + piece + "..."
            break
        }
        return out
    }

    /// "a, b and c"
    static func list(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Plain suits in display order, then trumps.
    static func groupOrder(_ trump: Trump) -> [SuitGroup] {
        trump.plainSuitOrder.map { SuitGroup.plain($0) } + [.trump]
    }

    /// "Spades", "Trumps"
    static func groupTitle(_ group: SuitGroup) -> String {
        switch group {
        case .trump: return "Trumps"
        case let .plain(suit): return suit.name
        }
    }

    /// "spade", "trump"
    static func groupSingular(_ group: SuitGroup) -> String {
        switch group {
        case .trump: return "trump"
        case let .plain(suit): return suit.singularName
        }
    }

    /// "your", "East's", "Partner's"
    static func possessive(_ seat: Int, players: Int = 4) -> String {
        seat == Seats.human ? "your" : name(seat, players: players) + "'s"
    }

    /// Cards of `cards` that are in `pool` (as a multiset, by identity).
    static func owned(_ cards: [Card], from pool: [Card]) -> [Card] {
        var left = pool
        var out: [Card] = []
        for card in cards {
            if let index = left.firstIndex(of: card) {
                left.remove(at: index)
                out.append(card)
            }
        }
        return out
    }

    /// What the learner was doing when a move was rejected: the app reports rejected buries and declarations
    /// as illegal attempts too, not only plays.
    enum Attempt {
        case play, bury, declare

        init(_ error: RoundError, phase: SeatView.Phase) {
            switch error {
            case .invalidBury:
                self = .bury
            case .invalidDeclaration:
                self = .declare
            case .illegalLead, .illegalFollow:
                self = .play
            case .wrongPhase, .notYourTurn:
                switch phase {
                case .burying: self = .bury
                case .dealing, .bidding: self = .declare
                case .playing, .finished: self = .play
                }
            }
        }

        /// "You just tried to <verb> 3♠ 4♠"
        var verb: String {
            switch self {
            case .play: return "play"
            case .bury: return "bury"
            case .declare: return "declare with"
            }
        }
    }

    static func stepName(_ step: HintStep) -> String {
        switch step {
        case .nudge: return "what to notice"
        case .principle: return "the principle"
        case .show: return "the suggested play"
        }
    }

    // MARK: Trump

    /// "Trump: suit ♥, rank 2." plus the trump order and the plain-suit order.
    static func trumpLines(_ trump: Trump, decks: Int = 2) -> [String] {
        let first: String
        if let suit = trump.suit {
            let jokers = decks > 2 ? "all \(2 * decks) jokers" : "all four jokers"
            first = "Trump: suit \(suit.symbol) (\(suit.name.lowercased())), rank \(trump.rank.label). Trumps are \(jokers), every \(rankSingular(trump.rank)) and every \(suit.singularName)."
        } else {
            first = "Trump: no trump suit this round, rank \(trump.rank.label). Only the jokers and the \(rankPlural(trump.rank)) are trumps."
        }
        return [first] + orderLines(trump)
    }

    static func orderLines(_ trump: Trump) -> [String] {
        var ranks: [String] = []
        for rank in Rank.allCases.reversed() where rank != trump.rank { ranks.append(rank.label) }
        let plainRanks = ranks.joined(separator: " ")
        return [
            "Trump order (high to low): " + trumpOrder(trump) + ".",
            "Plain suits rank \(plainRanks) (the \(rankPlural(trump.rank)) are trumps).",
        ]
    }

    /// "2", "10", "jack", "ace"
    static func rankSingular(_ rank: Rank) -> String {
        rank.rawValue > 10 ? rank.name.lowercased() : rank.label
    }

    /// "2s", "10s", "jacks", "aces"
    static func rankPlural(_ rank: Rank) -> String {
        rankSingular(rank) + "s"
    }

    /// "BJ > SJ > 2♥ > 2♠ = 2♣ = 2♦ > A♥ > ..."
    static func trumpOrder(_ trump: Trump) -> String {
        let faces = trump.trumpFacesHighToLow
        var parts: [String] = []
        var index = 0
        while index < faces.count {
            let strength = trump.strength(faces[index])
            var same: [Face] = [faces[index]]
            var next = index + 1
            while next < faces.count && trump.strength(faces[next]) == strength {
                same.append(faces[next])
                next += 1
            }
            // Equal cards (the off-suit rank cards) in a fixed suit order.
            same.sort { ($0.suit?.rawValue ?? 9) < ($1.suit?.rawValue ?? 9) }
            parts.append(same.map(\.description).joined(separator: " = "))
            index = next
        }
        return parts.joined(separator: " > ")
    }

    static func declarationOption(_ declaration: Declaration) -> String {
        let suit = declaration.suit.map { "\($0.symbol) as trump" } ?? "no trump suit"
        let shown = declaration.cards.first?.description ?? ""
        switch declaration.strength {
        case 1: return "\(suit) by showing one \(shown)"
        case 2: return "\(suit) by showing a pair of \(shown)"
        case 3: return "no trump suit by showing a pair of small jokers"
        case 4: return "no trump suit by showing a pair of big jokers"
        default: return suit
        }
    }

    // MARK: Plays and tricks

    /// "pair of spades", "single trump", "tractor of hearts", "throw of 3 spades (pair + single)"
    static func shapeText(_ cards: [Card], trump: Trump) -> String {
        guard let first = cards.first else { return "nothing" }
        let group = Combos.group(of: cards, trump: trump) ?? trump.group(first)
        let components = Combos.decompose(cards, trump: trump)
        if components.count == 1, let component = components.first {
            switch component.shape {
            case .single: return "single \(groupSingular(group))"
            case .pair: return "pair of \(group.name)"
            case let .tractor(n): return n == 2 ? "tractor of \(group.name)" : "\(n)-pair tractor of \(group.name)"
            case .set, .setTractor: return "\(component.shape.name) of \(group.name)"
            }
        }
        let shapes = components.map(\.shape.name).joined(separator: " + ")
        return "throw of \(cards.count) \(group.name): \(shapes)"
    }

    /// "East led K♠ K♠ (pair of spades). Partner played A♠ 3♠ (not the same shape, can't win). ..."
    static func playsSentence(_ plays: [Play], trump: Trump, players: Int = 4) -> String {
        guard let lead = plays.first else { return "" }
        let leadCards = lead.cards
        let ledGroup = Combos.group(of: leadCards, trump: trump) ?? leadCards.first.map { trump.group($0) } ?? .trump
        var sentences: [String] = []
        let leader = lead.player == Seats.human ? "You" : name(lead.player, players: players)
        sentences.append("\(leader) led \(trump.sorted(leadCards).shortText) (\(shapeText(leadCards, trump: trump))).")
        for play in plays.dropFirst() {
            let who = play.player == Seats.human ? "You" : name(play.player, players: players)
            let note = followNote(play.cards, lead: leadCards, ledGroup: ledGroup, trump: trump)
            let suffix = note.isEmpty ? "" : " (\(note))"
            sentences.append("\(who) played \(trump.sorted(play.cards).shortText)\(suffix).")
        }
        return sentences.joined(separator: " ")
    }

    /// Why a follow can or can't compete for the trick.
    static func followNote(_ cards: [Card], lead: [Card], ledGroup: SuitGroup, trump: Trump) -> String {
        guard let group = Combos.group(of: cards, trump: trump) else { return "mixed suits, can't win" }
        if group != ledGroup && !group.isTrump { return "discard, can't win" }
        let matches = Rules.matchesStructure(cards, lead: lead, trump: trump)
        if !matches { return "not the same shape as the lead, can't win" }
        if group.isTrump && !ledGroup.isTrump { return "trumped in" }
        return ""
    }

    /// "Winning now: Partner with A♠ (the highest spade so far)."
    static func winningSentence(_ plays: [Play], trump: Trump, players: Int = 4) -> String {
        guard let lead = plays.first?.cards, let firstCard = lead.first else { return "" }
        let index = Rules.winningIndex(plays, trump: trump)
        guard plays.indices.contains(index) else { return "" }
        let winner = plays[index]
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(firstCard)
        let who = winner.player == Seats.human ? "you" : name(winner.player, players: players)
        let cards = trump.sorted(winner.cards).shortText
        let reason: String
        if plays.count == 1 {
            reason = "nobody has played to it yet"
        } else if index == 0 {
            reason = "nobody has beaten the lead"
        } else if !ledGroup.isTrump, Combos.group(of: winner.cards, trump: trump) == .trump {
            reason = "a trump beats any \(groupSingular(ledGroup)), and it is the highest trump play"
        } else {
            reason = "the highest matching \(groupSingular(ledGroup)) play so far"
        }
        return "Winning now: \(who) with \(cards) (\(reason))."
    }

    /// Groups each seat is known to be out of, from the plays so far: a follower who played anything
    /// outside the led group had no more cards of it.
    static func knownVoids(tricks: [TrickRecord], current: [Play], trump: Trump) -> [Int: Set<SuitGroup>] {
        var voids: [Int: Set<SuitGroup>] = [:]
        var allPlays: [[Play]] = tricks.map(\.plays)
        if !current.isEmpty { allPlays.append(current) }
        for plays in allPlays {
            guard let lead = plays.first?.cards, let first = lead.first else { continue }
            let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
            for play in plays.dropFirst() where play.cards.contains(where: { trump.group($0) != ledGroup }) {
                voids[play.player, default: []].insert(ledGroup)
            }
        }
        return voids
    }

    // MARK: Lessons and questions

    static func pageTitle(_ page: LessonPage) -> String {
        switch page {
        case let .text(title, _): return plain(title)
        case let .cards(title, _, _, _): return plain(title)
        case let .trick(title, _, _, _, _): return plain(title)
        case .predict: return "Your turn (question)"
        case .recap: return "Recap"
        }
    }

    /// What a practice item is about, for the coach.
    static func topic(of itemID: String) -> String {
        if let skill = SkillID(itemID: itemID) {
            switch skill {
            case .pointValue: return "skill: how many points a card is worth"
            case .countPoints: return "skill: counting the points in a group of cards"
            case .isTrump: return "skill: spotting which cards are trumps"
            case .trumpOrder: return "skill: the order of the trumps"
            case .cardBeats: return "skill: which single card wins (follow, ruff or discard)"
            case .isPair: return "skill: what is and isn't a pair"
            case .isTractor: return "skill: what is and isn't a tractor"
            case .trickWinner: return "skill: who wins a whole trick"
            case .legalFollow: return "skill: which follow is legal"
            case .levelOutcome: return "skill: what a score means for the levels"
            case .kittyBonus: return "skill: the kitty bonus"
            case .bestPlay: return "skill: choosing a good play"
            }
        }
        if let fact = Curriculum.fact(id: itemID), let lesson = Curriculum.lesson(id: fact.lessonID) {
            return "a fact from lesson \(lesson.number), \(plain(lesson.title))"
        }
        if let lesson = Curriculum.lesson(id: itemID) {
            return "lesson \(lesson.number), \(plain(lesson.title))"
        }
        return "a rules question"
    }

    static func choiceText(_ choice: Choice) -> String {
        let label = plain(choice.label)
        if choice.cards.isEmpty { return label }
        let cards = choice.cards.shortText
        if label.isEmpty || label == cards { return cards }
        return "\(label) (cards: \(cards))"
    }

    /// The question, its trump, what is shown, the choices, and the answer state. The correct answer and
    /// explanation only appear once the learner has answered.
    static func questionLines(_ question: Question, chosenAnswer: Int?) -> [String] {
        var lines: [String] = ["Question: " + clip(plain(question.prompt), 500)]
        if let trump = question.trump { lines.append(contentsOf: trumpLines(trump)) }
        if let shown = visualText(question.visual, trump: question.trump) { lines.append(shown) }
        var choices: [String] = []
        for (index, choice) in question.choices.enumerated() { choices.append("\(index + 1)) \(choiceText(choice))") }
        lines.append(clip("Choices: " + choices.joined(separator: "; ") + ".", 700))
        let answered = chosenAnswer.flatMap { question.choices.indices.contains($0) ? $0 : nil }
        guard let chosen = answered else {
            lines.append("The learner has not answered yet. Help them think it through, but don't give away the answer.")
            return lines
        }
        let correct = question.correctChoice
        let verdict = chosen == correct ? "correct" : "not correct"
        lines.append("The learner answered \(chosen + 1)) \(choiceText(question.choices[chosen])), which is \(verdict).")
        if chosen != correct, question.choices.indices.contains(correct) {
            lines.append("The right answer is \(correct + 1)) \(choiceText(question.choices[correct])).")
        }
        if !question.explanation.isEmpty {
            lines.append("Explanation shown: " + clip(plain(question.explanation), 700))
        }
        return lines
    }

    /// The question's picture as text. Who wins a trick shown in a question is never stated (it is often the answer).
    static func visualText(_ visual: QuestionVisual, trump: Trump?) -> String? {
        let context = trump ?? Trump(rank: .two, suit: nil)
        switch visual {
        case .none:
            return nil
        case let .cards(cards):
            return cards.isEmpty ? nil : "Cards shown: \(cards.shortText)."
        case let .trick(plays):
            return plays.isEmpty ? nil : "Trick shown: " + playsList(plays)
        case let .handAndLead(hand, lead, leader):
            let who = leader == Seats.human ? "You" : Seats.name(leader)
            return "Lead: \(who) led \(lead.shortText). The learner's hand: \(context.sorted(hand).shortText)."
        case let .situation(plays, hand):
            return "Trick so far: " + playsList(plays) + " The learner's hand: \(context.sorted(hand).shortText)."
        }
    }

    /// "East led A♣. Partner played 7♣. ..." with no comments on who can win.
    static func playsList(_ plays: [Play]) -> String {
        var sentences: [String] = []
        for (index, play) in plays.enumerated() {
            let who = play.player == Seats.human ? "You" : Seats.name(play.player)
            let verb = index == 0 ? "led" : "played"
            sentences.append("\(who) \(verb) \(play.cards.shortText).")
        }
        return sentences.joined(separator: " ")
    }
}
