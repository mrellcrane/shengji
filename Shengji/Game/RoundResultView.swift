import SwiftUI
import ShengjiCore

/// End of a round: who declared, the defenders' points against the 80 line (40 per deck), the kitty and
/// its multiplier, the level change in words, the next dealer and one takeaway tip.
@MainActor
struct RoundResultView: View {
    let summary: RoundSummary
    let roundNumber: Int
    /// Seats at the table (4, 6 or 8).
    var players: Int = 4
    let isDemo: Bool
    let onNextRound: () -> Void
    let onNewGame: () -> Void
    let onViewTable: () -> Void
    let onLeave: () -> Void

    private var result: RoundResult { summary.result }
    private var decks: Int { TableSize(players: players).decks }
    private var threshold: Int { Scoring.takeoverThreshold(decks: decks) }
    /// "East and West" with 4 players, "The other team" with more.
    private var theirTeam: String { GameCoachText.teamName(1, capitalized: true, players: players) }
    private var defenderTeam: Int { 1 - result.declarerTeam }
    private var isGameOver: Bool { summary.gameWinner != nil }
    /// Finding Friends: no fixed teams, everyone has their own level.
    private var findsFriends: Bool { result.declarers != nil }
    private func name(_ seat: Int) -> String { Seats.name(seat, players: players) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    declarersSection
                    pointsSection
                    kittySection
                    outcomeSection
                    levelsSection
                    tipSection
                }
                .padding(16)
            }
            Divider()
            buttons
        }
        .frame(maxWidth: 560)
        .frame(maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 40)
        .padding(.horizontal, 8)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            Text(headline)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Round \(roundNumber)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var headline: String {
        if findsFriends { return friendsHeadline }
        let humanTeam = Seats.team(of: Seats.human)
        if let winner = summary.gameWinner {
            return winner == humanTeam ? "You win the game!" : "\(theirTeam) \(players > 4 ? "wins" : "win") the game"
        }
        let humanDeclared = result.declarerTeam == humanTeam
        if result.outcome.declarersHold {
            return humanDeclared ? "Your team held the deal" : "\(theirTeam) held the deal"
        }
        return humanDeclared ? "\(theirTeam) \(players > 4 ? "takes" : "take") over" : "Your team takes over!"
    }

    /// Finding Friends: team 0 is your side this round.
    private var friendsHeadline: String {
        let youDeclared = result.isDeclarer(Seats.human)
        if let winner = summary.gameWinner {
            return winner == 0 ? "You win the game!" : "\(name(result.dealer))'s side wins the game"
        }
        if result.outcome.declarersHold {
            return youDeclared ? "Your side held the deal" : "The dealer's side held the deal"
        }
        return youDeclared ? "The defenders took over" : "Your side takes over!"
    }

    // MARK: Sections

    @ViewBuilder private var declarersSection: some View {
        if findsFriends {
            RoundResultSection(title: "The dealer's side") {
                Text(friendsSideLine)
                ForEach(Array((result.friendCalls ?? []).enumerated()), id: \.offset) { _, call in
                    HStack {
                        Text(FriendCallText.short(call))
                        Spacer()
                        Text(answer(call))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                TrumpBadge(trump: result.trump)
            }
        } else {
            RoundResultSection(title: "Declarers") {
                Text(declarersLine)
                TrumpBadge(trump: result.trump)
            }
        }
    }

    /// "East dealt. East, Northeast and you played together." / "You dealt and played alone."
    private var friendsSideLine: String {
        let seats = result.declarers ?? [result.dealer]
        guard seats.count > 1 else {
            return "\(name(result.dealer)) dealt and played alone: no friend joined."
        }
        // "you" inside the sentence; the dealer comes first, so the list starts capitalised.
        let names = seats.enumerated().map { index, seat in
            seat == Seats.human && index > 0 ? "you" : name(seat)
        }
        let list = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        return "\(name(result.dealer)) dealt. \(list) played together."
    }

    /// Who answered a call: a seat, the dealer themself, or nobody.
    private func answer(_ call: FriendCall) -> String {
        guard let friend = call.friend else { return "Never played" }
        if friend == result.dealer { return "\(name(friend)) (the dealer)" }
        return name(friend)
    }

    /// "You and Partner were the declarers. You dealt." (In later rounds nobody has to declare,
    /// so this names the dealer's team rather than saying who declared.)
    private var declarersLine: String {
        let team = GameCoachText.teamName(result.declarerTeam, capitalized: true, players: players)
        return "\(team) were the declarers. \(Seats.name(result.dealer, players: players)) dealt."
    }

    private var pointsSection: some View {
        RoundResultSection(title: "Defenders' points") {
            HStack {
                Text("Won in tricks")
                Spacer()
                Text("\(result.trickPoints)").monospacedDigit()
            }
            HStack {
                Text("Kitty bonus")
                Spacer()
                Text("\(result.defenderPoints - result.trickPoints)").monospacedDigit()
            }
            HStack {
                Text("Total").fontWeight(.bold)
                Spacer()
                Text("\(result.defenderPoints)").fontWeight(.bold).monospacedDigit()
            }
            GamePointsBar(points: result.defenderPoints, color: Theme.teamColor(defenderTeam), decks: decks)
            Text(lineText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var lineText: String {
        result.defenderPoints >= threshold
            ? "That's at least \(threshold), so the defenders take over the deal."
            : "Under \(threshold), so the declarers keep the deal."
    }

    private var kittySection: some View {
        RoundResultSection(title: "The kitty") {
            CardRow(cards: result.trump.sorted(result.kitty), cardWidth: 34, spacing: -14,
                    trump: result.trump, markTrumps: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kitty: \(result.kitty.map { $0.face.longName }.joined(separator: ", "))")
            Text("Kitty points: \(result.kittyPoints)")
                .font(.subheadline)
            Text(GameCoachText.kittyLine(result, decks: decks))
                .font(.subheadline.weight(.semibold))
        }
    }

    private var outcomeSection: some View {
        RoundResultSection(title: "What happened") {
            Text(result.outcome.summary)
                .fontWeight(.semibold)
            Text(summary.explanation)
                .foregroundStyle(.secondary)
        }
    }

    private var levelsSection: some View {
        RoundResultSection(title: "Levels") {
            if findsFriends {
                ForEach(0..<min(players, summary.levelsAfter.count), id: \.self) { seat in
                    seatLevelRow(seat)
                }
            } else {
                levelRow(team: 0, title: "Us")
                levelRow(team: 1, title: "Them")
            }
            if !isGameOver {
                Text("Next dealer: \(Seats.name(summary.nextDealer, players: players))")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func levelRow(team: Int, title: String) -> some View {
        let before = summary.levelsBefore.indices.contains(team) ? summary.levelsBefore[team].label : "?"
        let after = summary.levelsAfter.indices.contains(team) ? summary.levelsAfter[team].label : "?"
        let gained = summary.advancingTeam == team && summary.levelsGained > 0
        return HStack(spacing: 8) {
            Circle()
                .fill(Theme.teamColor(team))
                .frame(width: 10, height: 10)
            Text(title)
                .fontWeight(.semibold)
            Spacer()
            Text("\(before) → \(after)")
                .monospacedDigit()
            if gained {
                Text("+\(summary.levelsGained)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.correct)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Finding Friends: one player's level, before and after.
    private func seatLevelRow(_ seat: Int) -> some View {
        let before = summary.levelsBefore.indices.contains(seat) ? summary.levelsBefore[seat] : nil
        let after = summary.levelsAfter.indices.contains(seat) ? summary.levelsAfter[seat] : nil
        let gained = (after?.rawValue ?? 0) - (before?.rawValue ?? 0)
        let declared = result.isDeclarer(seat)
        let team = declared == result.isDeclarer(Seats.human) ? 0 : 1
        return HStack(spacing: 8) {
            Circle()
                .fill(Theme.teamColor(team))
                .frame(width: 10, height: 10)
            Text(name(seat))
                .fontWeight(seat == Seats.human ? .bold : .semibold)
            if seat == result.dealer {
                Text("Dealer")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if declared {
                Text("Friend")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(before?.label ?? "?") → \(after?.label ?? "?")")
                .monospacedDigit()
            if gained > 0 {
                Text("+\(gained)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.correct)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tipSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Theme.gold)
            Text(GameCoachText.takeaway(summary, decks: decks))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Buttons

    private var leaveTitle: String { isDemo ? "Leave" : "Back to menu" }

    private var buttons: some View {
        HStack(spacing: 10) {
            if isGameOver {
                Button(leaveTitle, action: onLeave)
                    .buttonStyle(.bordered)
                Button(action: onNewGame) {
                    Text("New game").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.felt)
            } else {
                Button("View table", action: onViewTable)
                    .buttonStyle(.bordered)
                Button(action: onNextRound) {
                    Text("Next round").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.felt)
            }
        }
        .controlSize(.large)
        .padding(16)
    }
}

/// A titled block in the result view.
@MainActor
struct RoundResultSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Defenders' points as a bar with the 80 line marked (40 points per deck in play).
@MainActor
struct GamePointsBar: View {
    let points: Int
    let color: Color
    var decks: Int = 2

    private var total: Int { Scoring.totalPoints(decks: decks) }
    private var threshold: Int { Scoring.takeoverThreshold(decks: decks) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat(min(max(points, 0), total)) / CGFloat(total)
            let line = CGFloat(threshold) / CGFloat(total)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: max(width * fraction, points > 0 ? 6 : 0))
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2, height: 22)
                    .offset(x: width * line - 1)
                Text("\(threshold)")
                    .font(.caption2.weight(.bold))
                    .offset(x: width * line + 4, y: -16)
            }
        }
        .frame(height: 16)
        .padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(points) of \(total) points. The line is at \(threshold).")
    }
}
