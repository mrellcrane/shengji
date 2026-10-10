import SwiftUI
import ShengjiCore

/// End of a round: who declared, the defenders' points against the 80 line, the kitty and its
/// multiplier, the level change in words, the next dealer and one takeaway tip.
@MainActor
struct RoundResultView: View {
    let summary: RoundSummary
    let roundNumber: Int
    let isDemo: Bool
    let onNextRound: () -> Void
    let onNewGame: () -> Void
    let onViewTable: () -> Void
    let onLeave: () -> Void

    private var result: RoundResult { summary.result }
    private var defenderTeam: Int { 1 - result.declarerTeam }
    private var isGameOver: Bool { summary.gameWinner != nil }

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
        let humanTeam = Seats.team(of: Seats.human)
        if let winner = summary.gameWinner {
            return winner == humanTeam ? "You win the game!" : "East and West win the game"
        }
        let humanDeclared = result.declarerTeam == humanTeam
        if result.outcome.declarersHold {
            return humanDeclared ? "Your team held the deal" : "East and West held the deal"
        }
        return humanDeclared ? "East and West take over" : "Your team takes over!"
    }

    // MARK: Sections

    private var declarersSection: some View {
        RoundResultSection(title: "Declarers") {
            Text(declarersLine)
            TrumpBadge(trump: result.trump)
        }
    }

    /// "You and Partner were the declarers. You dealt." (In later rounds nobody has to declare,
    /// so this names the dealer's team rather than saying who declared.)
    private var declarersLine: String {
        let team = GameCoachText.teamName(result.declarerTeam, capitalized: true)
        return "\(team) were the declarers. \(Seats.name(result.dealer)) dealt."
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
            GamePointsBar(points: result.defenderPoints, color: Theme.teamColor(defenderTeam))
            Text(lineText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var lineText: String {
        result.defenderPoints >= Scoring.takeoverThreshold
            ? "That's at least 80, so the defenders take over the deal."
            : "Under 80, so the declarers keep the deal."
    }

    private var kittySection: some View {
        RoundResultSection(title: "The kitty") {
            CardRow(cards: result.trump.sorted(result.kitty), cardWidth: 34, spacing: -14,
                    trump: result.trump, markTrumps: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kitty: \(result.kitty.map { $0.face.longName }.joined(separator: ", "))")
            Text("Kitty points: \(result.kittyPoints)")
                .font(.subheadline)
            Text(GameCoachText.kittyLine(result))
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
            levelRow(team: 0, title: "Us")
            levelRow(team: 1, title: "Them")
            if !isGameOver {
                Text("Next dealer: \(Seats.name(summary.nextDealer))")
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

    private var tipSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(Theme.gold)
            Text(GameCoachText.takeaway(summary))
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

/// Defenders' points as a bar with the 80 line marked.
@MainActor
struct GamePointsBar: View {
    let points: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat(min(max(points, 0), Scoring.totalPoints)) / CGFloat(Scoring.totalPoints)
            let line = CGFloat(Scoring.takeoverThreshold) / CGFloat(Scoring.totalPoints)
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
                Text("80")
                    .font(.caption2.weight(.bold))
                    .offset(x: width * line + 4, y: -16)
            }
        }
        .frame(height: 16)
        .padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(points) of \(Scoring.totalPoints) points. The line is at \(Scoring.takeoverThreshold).")
    }
}
