import SwiftUI
import ShengjiCore

/// "What happened": the tricks since your last move (the last one or two), who won them and the points,
/// plus what is on the table now.
@MainActor
struct OnlineWhatHappenedSheet: View {
    let info: OnlineWhatHappened
    let players: [SeatView.Player]
    let trump: Trump?
    let lastRound: RoundSummary?
    let onShowLastRound: (RoundSummary) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let lead = info.currentLead {
                    Section("On the table now") {
                        Text(lead)
                    }
                }
                ForEach(info.tricks.reversed()) { entry in
                    Section {
                        ForEach(Array(entry.trick.plays.enumerated()), id: \.offset) { index, play in
                            OnlinePlayRow(play: play, name: OnlineGameText.name(play.player, players: players),
                                          isLead: index == 0, isWinner: play.player == entry.trick.winner,
                                          trump: trump ?? Trump(rank: .two, suit: nil))
                        }
                    } header: {
                        Text("Trick \(entry.number)")
                    } footer: {
                        Text(entry.line)
                    }
                }
                if let note = info.note {
                    Section {
                        Text(note)
                        if let lastRound {
                            Button("See how the round ended") { onShowLastRound(lastRound) }
                        }
                    }
                }
                if let trump {
                    Section {
                        TrumpBadge(trump: trump)
                    }
                }
            }
            .navigationTitle(info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One play in a trick: who, led or followed, the cards, a crown for the winner.
@MainActor
struct OnlinePlayRow: View {
    let play: Play
    let name: String
    let isLead: Bool
    let isWinner: Bool
    let trump: Trump

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(Theme.gold)
                    }
                }
                Text(isLead ? "Led" : "Followed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96, alignment: .leading)
            CardRow(cards: trump.sorted(play.cards), cardWidth: 34, spacing: -15, trump: trump, markTrumps: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let cards = play.cards.map { $0.face.longName }.joined(separator: ", ")
        return "\(name) \(isLead ? "led" : "played") \(cards)\(isWinner ? ", won the trick" : "")"
    }
}

/// How a round went, with your friends' names: declarers, the defenders' points against the 80 line,
/// the kitty, the level change and who deals next. Shown when a new round has started since you looked.
@MainActor
struct OnlineRoundSummarySheet: View {
    let summary: RoundSummary
    let players: [SeatView.Player]
    let roundNumber: Int
    /// The game's target level (for "levels stop at A").
    let target: Rank

    @Environment(\.dismiss) private var dismiss

    private var result: RoundResult { summary.result }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    declarersSection
                    pointsSection
                    kittySection
                    outcomeSection
                    levelsSection
                    tip
                }
                .padding(16)
            }
            .navigationTitle("Round \(roundNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Decks at this table (2 for 4 players, 3 for 6, 4 for 8).
    private var decks: Int { TableSize(players: players.count).decks }
    private var threshold: Int { Scoring.takeoverThreshold(decks: decks) }

    private var header: some View {
        Text(OnlineGameText.roundHeadline(summary, players: players))
            .font(.title2.weight(.bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var declarersSection: some View {
        if let declarers = result.declarers {
            RoundResultSection(title: "The dealer's side") {
                Text("\(OnlineGameText.subject(result.dealer, players: players, "dealt", "dealt")). "
                     + (declarers.count <= 1 ? "No friend joined."
                        : "\(OnlineGameText.names(declarers, players: players)) played together."))
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
                Text("\(OnlineGameText.teamName(result.declarerTeam, players: players)) were the declarers. \(OnlineGameText.subject(result.dealer, players: players, "dealt", "dealt")).")
                TrumpBadge(trump: result.trump)
            }
        }
    }

    /// Finding Friends: who answered a call (a player, the dealer themself, or nobody).
    private func answer(_ call: FriendCall) -> String {
        guard let friend = call.friend else { return "Never played" }
        let who = OnlineGameText.name(friend, players: players)
        return friend == result.dealer ? "\(who) (the dealer)" : who
    }

    private var pointsSection: some View {
        RoundResultSection(title: "Defenders' points") {
            row("Won in tricks", result.trickPoints)
            row("Kitty bonus", result.defenderPoints - result.trickPoints)
            HStack {
                Text("Total").fontWeight(.bold)
                Spacer()
                Text("\(result.defenderPoints)").fontWeight(.bold).monospacedDigit()
            }
            GamePointsBar(points: result.defenderPoints, color: Theme.teamColor(1 - result.declarerTeam), decks: decks)
            Text(result.defenderPoints >= threshold
                 ? "That's at least \(threshold), so the defenders take over the deal."
                 : "Under \(threshold), so the declarers keep the deal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").monospacedDigit()
        }
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
            Text(OnlineGameText.roundExplanation(summary, players: players, target: target))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var levelsSection: some View {
        RoundResultSection(title: "Levels") {
            if result.declarers != nil {
                ForEach(0..<min(players.count, summary.levelsAfter.count), id: \.self) { seat in
                    seatLevelRow(seat)
                }
            } else {
                levelRow(team: 0, title: "Us")
                levelRow(team: 1, title: "Them")
            }
            if summary.gameWinner == nil {
                Text(OnlineGameText.nextDealerLine(summary, players: players))
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
            Text("\(title) (\(OnlineGameText.teamName(team, players: players)))")
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
            Text(OnlineGameText.name(seat, players: players))
                .fontWeight(seat == Seats.human ? .bold : .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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

    private var tip: some View {
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
}
