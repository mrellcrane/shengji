import SwiftUI
import ShengjiCore

/// Levels for Us and Them (declaring team flagged), defenders' points, trump, dealer and the table menu.
@MainActor
struct GameTopBar: View {
    let controller: GameController
    @Binding var coachLevel: CoachLevel
    var onShowRules: () -> Void
    var onShowLastTrick: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                levels
                Spacer(minLength: 4)
                defenderPoints
                menu
            }
            HStack(spacing: 8) {
                trumpView
                Spacer(minLength: 4)
                dealerView
            }
        }
        .padding(.top, 4)
    }

    // MARK: Levels

    private var levels: some View {
        HStack(spacing: 4) {
            GameTeamLevelChip(title: "Us", team: 0, level: controller.level(of: 0),
                              isDeclaring: controller.round.declarerTeam == 0)
            Text("·")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.6))
                .accessibilityHidden(true)
            GameTeamLevelChip(title: "Them", team: 1, level: controller.level(of: 1),
                              isDeclaring: controller.round.declarerTeam == 1)
        }
    }

    private var defenderPoints: some View {
        let points = controller.defenderPoints
        return HStack(spacing: 4) {
            Text("Defenders")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.8))
            Text("\(points) / \(Scoring.takeoverThreshold)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(points >= Scoring.takeoverThreshold ? Theme.gold : Color.white)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Defenders have \(points) points. They need \(Scoring.takeoverThreshold).")
    }

    // MARK: Trump and dealer

    @ViewBuilder private var trumpView: some View {
        if controller.isTrumpSet {
            TrumpBadge(trump: controller.round.trump, compact: true)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "star")
                    .foregroundStyle(Theme.gold)
                Text("Trump not set yet")
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Rank \(controller.round.trumpRank.label)")
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    private var dealerView: some View {
        let text: String
        if let dealer = controller.round.dealer {
            text = "Dealer: \(Seats.name(dealer))"
        } else {
            text = "Dealer: first to declare"
        }
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    // MARK: Menu

    private var quitTitle: String { controller.isDemo ? "Leave table" : "Save & quit" }

    private var menu: some View {
        Menu {
            Button(action: onShowRules) {
                Label("Rules quick sheet", systemImage: "book")
            }
            Button(action: onShowLastTrick) {
                Label("Last trick", systemImage: "clock.arrow.circlepath")
            }
            .disabled(controller.round.tricks.isEmpty)
            Picker(selection: $coachLevel) {
                ForEach(CoachLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            } label: {
                Label("Coach level", systemImage: "graduationcap")
            }
            .pickerStyle(.menu)
            Divider()
            Button(action: onQuit) {
                Label(quitTitle, systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Table menu")
    }
}

/// "Us 3" in the team colour, flagged when that team is declaring.
@MainActor
struct GameTeamLevelChip: View {
    let title: String
    let team: Int
    let level: Rank
    let isDeclaring: Bool

    var body: some View {
        HStack(spacing: 3) {
            if isDeclaring {
                Image(systemName: "flag.fill")
                    .font(.caption2)
            }
            Text("\(title) \(level.label)")
                .font(.subheadline.weight(.bold))
        }
        .foregroundStyle(Theme.teamColor(team))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.black.opacity(0.3)))
        .overlay(Capsule().strokeBorder(isDeclaring ? Theme.teamColor(team) : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team == 0 ? "Your team" : "Their team"), level \(level.label)\(isDeclaring ? ", declaring" : "")")
    }
}
