import SwiftUI
import ShengjiCore

/// Review the previous trick: every play in order, who won, the points, and why.
@MainActor
struct LastTrickView: View {
    let trick: TrickRecord?
    let trickNumber: Int
    let trump: Trump
    let explanation: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let trick {
                    trickList(trick)
                } else {
                    ContentUnavailableView("No tricks yet", systemImage: "rectangle.stack",
                                           description: Text("Finished tricks show up here."))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        trick == nil ? "Last trick" : "Trick \(trickNumber)"
    }

    private func pointsText(_ trick: TrickRecord) -> String {
        trick.points > 0 ? "\(trick.points) points in this trick." : "No points in this trick."
    }

    private func trickList(_ trick: TrickRecord) -> some View {
        List {
            Section {
                ForEach(Array(trick.plays.enumerated()), id: \.offset) { index, play in
                    LastTrickPlayRow(play: play, isLead: index == 0, isWinner: play.player == trick.winner, trump: trump,
                                     players: trick.plays.count)
                }
            } footer: {
                Text(pointsText(trick))
            }
            if let explanation {
                Section("Why") {
                    Text(explanation)
                }
            }
            Section {
                TrumpBadge(trump: trump)
            }
        }
    }
}

/// One play in the last-trick review.
@MainActor
struct LastTrickPlayRow: View {
    let play: Play
    let isLead: Bool
    let isWinner: Bool
    let trump: Trump
    /// Seats at the table (every seat plays to a trick).
    var players: Int = 4

    private var name: String { Seats.name(play.player, players: TableSize(players: players).players) }

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
                Text(roleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 92, alignment: .leading)
            CardRow(cards: trump.sorted(play.cards), cardWidth: 36, spacing: -16, trump: trump, markTrumps: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var roleText: String { isLead ? "Led" : "Followed" }

    private var accessibilityText: String {
        let cards = play.cards.map { $0.face.longName }.joined(separator: ", ")
        return "\(name) \(isLead ? "led" : "played") \(cards)\(isWinner ? ", won the trick" : "")"
    }
}
