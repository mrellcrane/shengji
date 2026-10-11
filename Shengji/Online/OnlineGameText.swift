import Foundation
import ShengjiCore

/// Learner-facing sentences for the online table and lists: short, warm, second person, with your
/// friends' names (seat 0 is always "You"). Pure functions so they can be checked without the UI.
enum OnlineGameText {
    // MARK: Names

    /// "You" for seat 0, otherwise the player's name (or the seat's direction if the name is missing).
    static func name(_ seat: Int, players: [SeatView.Player]) -> String {
        if seat == Seats.human { return "You" }
        guard players.indices.contains(seat) else { return fallbackName(seat, count: players.count) }
        let trimmed = players[seat].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackName(seat, count: players.count) : trimmed
    }

    /// A seat label for a crowded table of 6 or 8: the first word of the name, at most 9 characters
    /// ("Panda" for "Panda Bot").
    static func shortName(_ seat: Int, players: [SeatView.Player]) -> String {
        let full = name(seat, players: players)
        let first = full.split(separator: " ").first.map(String.init) ?? full
        return first.count > 9 ? String(first.prefix(8)) + "…" : first
    }

    /// Lower-case "you" inside a sentence.
    static func inlineName(_ seat: Int, players: [SeatView.Player]) -> String {
        seat == Seats.human ? "you" : name(seat, players: players)
    }

    /// "You play" / "Mei plays".
    static func subject(_ seat: Int, players: [SeatView.Player], _ youForm: String, _ otherForm: String) -> String {
        "\(name(seat, players: players)) \(seat == Seats.human ? youForm : otherForm)"
    }

    /// A seat's direction when its name is missing: "Right", "Partner", "Left" at a table of four,
    /// compass points at a bigger one.
    static func fallbackName(_ seat: Int, count: Int = 4) -> String {
        if count > 4 { return Seats.name(seat, players: count) }
        switch seat {
        case 1: return "Right"
        case 2: return "Partner"
        case 3: return "Left"
        default: return "You"
        }
    }

    /// The seats of a team (viewer-relative), in seat order: seats 0 and 2 at a table of four.
    static func teamSeats(_ team: Int, count: Int) -> [Int] {
        Seats.all(players: TableSize(players: count).players).filter { Seats.team(of: $0) == team }
    }

    /// "Mei and Lin", "Mei, Lin and Sam".
    static func list(_ names: [String]) -> String {
        guard let last = names.last else { return "" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// "You and Mei" (your team) or "Jun and Ana"; with 6 or 8 players everyone in the team, "You, Mei
    /// and Lin".
    static func teamName(_ team: Int, players: [SeatView.Player]) -> String {
        list(teamSeats(team, count: players.count).map { name($0, players: players) })
    }

    /// "Mei, Jun and Ana" for a games-list row (everyone but you: your partners first; with Finding
    /// Friends, in seat order).
    static func othersLine(_ players: [SeatView.Player]) -> String {
        let count = TableSize(players: players.count).players
        let seats = count % 2 == 1 ? Array(1..<count)
            : Seats.teammates(of: Seats.human, players: count) + Seats.opponents(of: Seats.human, players: count)
        let names = seats.filter { players.indices.contains($0) }.map { name($0, players: players) }
        return names.isEmpty ? "Just you" : list(names)
    }

    // MARK: Turns

    /// Whose action the table waits for (bidding turn, burying dealer or player to play).
    static func actingSeat(_ view: SeatView) -> Int? {
        switch view.phase {
        case .bidding: return view.bidding?.turn
        case .burying: return view.turn ?? view.dealer
        case .playing: return view.turn
        case .dealing, .finished: return nil
        }
    }

    /// "Waiting for Mei to play", or nil when it is your turn or nobody needs to act.
    static func waitingText(_ view: SeatView) -> String? {
        guard let seat = actingSeat(view), seat != Seats.human else { return nil }
        let who = name(seat, players: view.players)
        switch view.phase {
        case .bidding: return "Waiting for \(who) to declare or pass"
        case .burying: return "Waiting for \(who) to bury the kitty"
        case .playing: return "Waiting for \(who) to play"
        case .dealing, .finished: return nil
        }
    }

    /// The short status beside the main button.
    static func statusText(_ view: SeatView, gameOver: Bool) -> String {
        if gameOver { return "Game over" }
        if let waiting = waitingText(view) { return waiting }
        switch view.phase {
        case .bidding:
            return actingSeat(view) == Seats.human ? "Declare or pass" : ""
        case .burying:
            guard actingSeat(view) == Seats.human else { return "" }
            return view.findsFriends ? "Pick \(view.table.kittySize) to bury, then call friends"
                : "Pick \(view.table.kittySize) to bury"
        case .playing:
            guard view.turn == Seats.human else { return "" }
            let lead = view.currentLead
            return lead.isEmpty ? "Your lead" : "Play \(lead.count) card\(lead.count == 1 ? "" : "s")"
        case .dealing:
            return "Dealing"
        case .finished:
            return "Round over"
        }
    }

    // MARK: Bidding

    /// "one 2♥", "a pair of 2♥", "small jokers", and with three or more decks "three 2♥".
    static func declarationDetail(_ d: Declaration) -> String {
        switch d.strength {
        case 1: return d.cards.first.map { "one \($0.description)" } ?? "one trump-rank card"
        case 2: return d.cards.first.map { "a pair of \($0.description)" } ?? "a pair of trump-rank cards"
        case 3: return "a pair of small jokers"
        case 4: return "a pair of big jokers"
        default: return d.detail
        }
    }

    /// "Mei declared ♥ with one 2♥." / "You declared no trump with a pair of big jokers."
    static func declarationLine(_ d: Declaration, players: [SeatView.Player]) -> String {
        let what = d.suit.map { $0.symbol } ?? "no trump"
        return "\(name(d.player, players: players)) declared \(what) with \(declarationDetail(d))."
    }

    /// "Mei passed." or the declaration line.
    static func bidLine(_ bid: SeatView.Bid, players: [SeatView.Player]) -> String {
        if let declaration = bid.declaration { return declarationLine(declaration, players: players) }
        return "\(name(bid.player, players: players)) passed."
    }

    // MARK: Tricks

    /// "Mei won the trick with A♠." plus the points.
    static func trickLine(_ trick: TrickRecord, view: SeatView) -> String {
        let players = view.players
        let winner = trick.winner
        let cards = trick.plays.first { $0.player == winner }?.cards ?? []
        var text = "\(subject(winner, players: players, "won", "won")) the trick"
        if !cards.isEmpty { text += " with \(GameCoachText.describePlay(cards, trump: view.trump))" }
        text += "."
        if trick.points > 0 {
            text += view.isDefender(winner) ? " +\(trick.points) for the defenders." : " The \(trick.points) points stay with the declarers."
        }
        return text
    }

    /// "Mei led K♠ K♠." for the trick on the table.
    static func leadLine(_ view: SeatView) -> String? {
        guard let lead = view.currentTrick.first, !lead.cards.isEmpty else { return nil }
        let who = subject(lead.player, players: view.players, "led", "led")
        return "\(who) \(GameCoachText.describePlay(lead.cards, trump: view.trump))."
    }

    /// "Your throw failed: Mei could beat part of it, so only a pair of 9♠ was played."
    static func throwFailedLine(forced: [Card], blocker: Int?, view: SeatView) -> String {
        let played = GameCoachText.describePlay(forced, trump: view.trump)
        guard let blocker else {
            return "Your throw failed: someone could beat part of it, so only \(played) was played."
        }
        return "Your throw failed: \(inlineName(blocker, players: view.players)) could beat part of it, so only \(played) was played."
    }

    // MARK: Banner after an update

    /// What the coach banner says after the table changes from `old` to `new` (nil keeps it quiet).
    static func banner(old: SeatView?, new view: SeatView) -> String? {
        let players = view.players
        var parts: [String] = []
        let sameRound = old?.roundNumber == view.roundNumber
        if let old, !sameRound, view.roundNumber > old.roundNumber {
            parts.append("Round \(view.roundNumber) has started.")
        }
        switch view.phase {
        case .bidding:
            if let last = view.bidding?.history.last, last.player != Seats.human {
                parts.append(bidLine(last, players: players))
            }
            if actingSeat(view) == Seats.human {
                let hasOptions = !(view.bidding?.available.isEmpty ?? true)
                parts.append(hasOptions ? "Your turn: declare a trump suit, or pass." : "Your turn. You have nothing to declare, so pass.")
                // Lesson 9 teaches declaring as the cards arrive; online bidding works differently.
                let firstBid = !(view.bidding?.history.contains { $0.player == Seats.human } ?? false)
                if hasOptions, firstBid {
                    parts.append("Online, bids go round in turns after the deal and you can't reinforce later, so a pair is the stronger bid.")
                }
            }
        case .burying:
            if actingSeat(view) == Seats.human {
                let friends = view.table.friendCount == 1 ? "a friend" : "\(view.table.friendCount) friends"
                parts.append("You're the dealer, so the kitty is yours. Choose \(view.table.kittySize) cards to bury"
                             + (view.findsFriends ? ", then call \(friends)." : "."))
            } else if let dealer = view.dealer {
                parts.append("\(name(dealer, players: players)) is the dealer and is burying the kitty.")
            }
        case .playing:
            if let found = friendsFoundLine(old: sameRound ? old : nil, new: view) {
                parts.append(found)
            }
            if let old, sameRound, view.tricks.count > old.tricks.count, let trick = view.tricks.last {
                parts.append(trickLine(trick, view: view))
            } else if old?.phase != .playing, view.tricks.isEmpty, view.currentTrick.isEmpty {
                if let dealer = view.dealer, let calls = view.friendCalls,
                   let line = GameCoachText.friendCallLine(dealer: dealer, calls: calls, name: { name($0, players: players) }) {
                    parts.append(line)
                }
                parts.append("\(subject(view.leader, players: players, "lead", "leads")) the first trick.")
            }
            if view.turn == Seats.human {
                if let lead = leadLine(view) {
                    parts.append("Your turn. \(lead)")
                } else {
                    parts.append("Your lead.")
                }
            }
        case .finished:
            if let winner = view.gameWinnerTeam, view.findsFriends {
                parts.append(winner == 0 ? "Game over: your side wins!" : "Game over: the dealer's side wins.")
            } else if let winner = view.gameWinnerTeam {
                parts.append(winner == 0 ? "Game over: \(teamName(0, players: players)) win!" : "Game over: \(teamName(1, players: players)) win.")
            } else {
                parts.append("The round is over.")
            }
        case .dealing:
            break
        }
        let text = parts.joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    // MARK: Finding Friends

    /// Friends found between two views of the same round ("Mei played the first A♠ and joins Lin's side.").
    static func friendsFoundLine(old: SeatView?, new view: SeatView) -> String? {
        guard let old, let after = view.friendCalls, after.count == old.friendCalls?.count ?? after.count else { return nil }
        let before = old.friendCalls ?? after.map(\.unfound)
        return GameCoachText.friendsFoundLine(before: before, after: after, dealer: view.dealer,
                                              name: { name($0, players: view.players) })
    }

    /// "Mei, Lin and you": seats of one side, in the order given.
    static func names(_ seats: [Int], players: [SeatView.Player]) -> String {
        list(seats.map { name($0, players: players) })
    }

    /// Finding Friends: who was on the dealer's side, and what the points did to everyone's levels
    /// (with your friends' names).
    static func friendsRoundExplanation(_ summary: RoundSummary, players: [SeatView.Player], target: Rank) -> String {
        let result = summary.result
        let declarers = result.declarers ?? [result.dealer]
        let points = result.defenderPoints
        let kittyBonus = result.kittyPoints * result.kittyMultiplier
        let scored = kittyBonus > 0
            ? "The defenders scored \(points) points (including \(kittyBonus) from the kitty)"
            : "The defenders scored \(points) points"
        let threshold = Scoring.takeoverThreshold(decks: TableSize(players: players.count).decks)
        var sentences: [String] = []
        sentences.append(declarers.count == 1
            ? "\(names(declarers, players: players)) played alone: no friend joined."
            : "\(names(declarers, players: players)) played together as the dealer's side.")
        if result.outcome.declarersHold {
            sentences.append("\(scored), short of \(threshold), so the dealer's side keeps the deal.")
        } else {
            sentences.append("\(scored), reaching \(threshold), so they take over the deal.")
        }
        if let winner = summary.gameWinner {
            let ending = winner == 0 ? "so you win the game!" : "so they win the game."
            sentences.append("\(name(result.dealer, players: players)) held the deal at level \(target.label), \(ending)")
            return sentences.joined(separator: " ")
        }
        if result.outcome.levels == 0 {
            sentences.append("Nobody goes up a level this time.")
        } else {
            let who = result.outcome.declarersHold ? "The dealer's side" : "The defenders"
            let verb = result.outcome.declarersHold ? "goes" : "go"
            let phrase = result.outcome.levels == 1 ? "1 level" : "\(result.outcome.levels) levels"
            sentences.append("\(who) \(verb) up \(phrase).")
        }
        if summary.levelsBefore.indices.contains(0), summary.levelsAfter.indices.contains(0),
           summary.levelsAfter[0] != summary.levelsBefore[0] {
            sentences.append("You are now at level \(summary.levelsAfter[0].label).")
        }
        return sentences.joined(separator: " ")
    }

    // MARK: Round summary

    /// "You and Mei held the deal" / "Jun and Ana take over".
    static func roundHeadline(_ summary: RoundSummary, players: [SeatView.Player]) -> String {
        if let declarers = summary.result.declarers {
            if let winner = summary.gameWinner {
                return winner == 0 ? "Your side wins the game!" : "\(names(declarers, players: players)) win the game"
            }
            if summary.result.outcome.declarersHold {
                return "\(names(declarers, players: players)) held the deal"
            }
            return summary.result.isDeclarer(Seats.human) ? "The defenders take over the deal" : "Your side takes over the deal"
        }
        if let winner = summary.gameWinner {
            return winner == 0 ? "\(teamName(0, players: players)) win the game!" : "\(teamName(1, players: players)) win the game"
        }
        let declarers = summary.result.declarerTeam
        if summary.result.outcome.declarersHold {
            return "\(teamName(declarers, players: players)) held the deal"
        }
        return "\(teamName(1 - declarers, players: players)) take over the deal"
    }

    /// How the round's points turned into levels, with your friends' names. The server's
    /// `summary.explanation` comes from the shared engine text, which calls the other team
    /// "East and West" and the seats by direction. (Who deals next is `nextDealerLine`.)
    static func roundExplanation(_ summary: RoundSummary, players: [SeatView.Player], target: Rank) -> String {
        if summary.result.declarers != nil {
            return friendsRoundExplanation(summary, players: players, target: target)
        }
        let result = summary.result
        let points = result.defenderPoints
        let kittyBonus = result.kittyPoints * result.kittyMultiplier
        let scored = kittyBonus > 0
            ? "The defenders scored \(points) points (including \(kittyBonus) from the kitty)"
            : "The defenders scored \(points) points"
        let threshold = Scoring.takeoverThreshold(decks: TableSize(players: players.count).decks)
        var sentences: [String] = []
        if result.outcome.declarersHold {
            sentences.append("\(scored), short of \(threshold), so the declarers keep the deal.")
        } else {
            sentences.append("\(scored), reaching \(threshold), so they take over the deal.")
        }
        if let winner = summary.gameWinner {
            let ending = winner == 0 ? "so you win the game!" : "so they win the game."
            sentences.append("\(teamName(winner, players: players)) held the deal at level \(target.label), \(ending)")
            return sentences.joined(separator: " ")
        }
        let team = result.outcome.declarersHold ? result.declarerTeam : 1 - result.declarerTeam
        let newLevel = summary.levelsAfter.indices.contains(team) ? summary.levelsAfter[team].label : target.label
        let gained = summary.levelsGained
        if result.outcome.levels == 0 {
            sentences.append("Nobody goes up a level this time.")
        } else if gained == 0 {
            sentences.append("\(teamName(team, players: players)) stay at level \(newLevel), the top level.")
        } else {
            let phrase = gained == 1 ? "1 level" : "\(gained) levels"
            let capNote = gained < result.outcome.levels ? " (levels stop at \(target.label))" : ""
            sentences.append("\(teamName(team, players: players)) go up \(phrase), to \(newLevel)\(capNote).")
        }
        return sentences.joined(separator: " ")
    }

    /// "Mei deals next."
    static func nextDealerLine(_ summary: RoundSummary, players: [SeatView.Player]) -> String {
        "\(subject(summary.nextDealer, players: players, "deal", "deals")) next."
    }

    /// "Mei: your turn" style subtitle for a games-list row.
    static func rowStatus(_ game: OnlineGameSummary) -> String {
        if game.isFinished {
            guard let winner = game.winnerTeam else { return "Finished" }
            if game.findsFriends { return winner == 0 ? "You won" : "Finished" }
            return winner == 0 ? "You won" : "\(teamName(1, players: game.players)) won"
        }
        if game.isYourTurn {
            switch game.phase {
            case .bidding?: return "Your turn to declare or pass"
            case .burying?: return "Your turn to bury the kitty"
            default: return "Your turn to play"
            }
        }
        if let turn = game.turn, turn != Seats.human {
            return "Waiting for \(name(turn, players: game.players))"
        }
        return "Waiting"
    }

    /// "Round 3 · Us 4, Them 3 · to A" (with "· 6 players" at a bigger table).
    static func rowDetail(_ game: OnlineGameSummary) -> String {
        if game.findsFriends {
            return "Round \(game.roundNumber) · You \(game.level(of: 0)?.label ?? "?") · to \(game.targetRank.label)"
                + tableNote(game)
        }
        let us = game.level(of: 0)?.label ?? "?"
        let them = game.level(of: 1)?.label ?? "?"
        return "Round \(game.roundNumber) · Us \(us), Them \(them) · to \(game.targetRank.label)" + tableNote(game)
    }

    /// " · 6 players" for a table of 6 or 8 (" · 9 players · friends" for Finding Friends), nothing for
    /// the classic four.
    static func tableNote(_ game: OnlineGameSummary) -> String {
        if game.findsFriends { return " · \(game.players.count) players · friends" }
        return game.players.count > 4 ? " · \(game.players.count) players" : ""
    }

    // MARK: Club games you are not in

    /// Whether you hold a seat. A club's page also lists games you are not in, seen from seat 0, where
    /// nobody is you. Unknown while your profile loads (`userID` nil): treated as yours.
    static func isSeated(_ game: OnlineGameSummary, userID: String?) -> Bool {
        guard let userID else { return true }
        return game.player(Seats.human)?.userID == userID
    }

    /// A player's name in a game you are not in (nobody there is "You").
    static func playerName(_ seat: Int, players: [SeatView.Player]) -> String {
        guard players.indices.contains(seat) else { return "Someone" }
        let trimmed = players[seat].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Someone" : trimmed
    }

    /// "Ben and Cai vs Tiger Bot and Dragon Bot" for a game you are not in.
    static func everyoneLine(_ players: [SeatView.Player]) -> String {
        if players.count % 2 == 1 {
            return list(players.indices.map { playerName($0, players: players) })
        }
        return "\(othersTeam(0, players: players)) vs \(othersTeam(1, players: players))"
    }

    /// "Ben and Cai": a team in a game you are not in.
    static func othersTeam(_ team: Int, players: [SeatView.Player]) -> String {
        list(teamSeats(team, count: players.count).map { playerName($0, players: players) })
    }

    /// "Waiting for Ben" or "Ben and Cai won" for a game you are not in.
    static func othersGameStatus(_ game: OnlineGameSummary) -> String {
        let name = { (seat: Int) in playerName(seat, players: game.players) }
        if game.isFinished {
            guard let winner = game.winnerTeam, !game.findsFriends else { return "Finished" }
            return "\(othersTeam(winner, players: game.players)) won"
        }
        if let turn = game.turn { return "Waiting for \(name(turn))" }
        return "Waiting"
    }

    /// "Round 3 · to A" for a game you are not in (neither team is "Us").
    static func othersGameDetail(_ game: OnlineGameSummary) -> String {
        "Round \(game.roundNumber) · to \(game.targetRank.label)" + tableNote(game)
    }

    /// "just now", "5 min ago", "3 h ago", "yesterday", "4 days ago".
    static func relativeTime(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        if hours < 24 { return "\(hours) h ago" }
        if days == 1 { return "yesterday" }
        if days < 14 { return "\(days) days ago" }
        return "\(days / 7) weeks ago"
    }
}
