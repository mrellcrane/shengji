import SwiftUI
import ShengjiCore

/// A mini table showing a trick: each play sits at its seat (You bottom, East right, Partner top,
/// West left) with the seat's name and its place in the play order. Works for 1 to 4 plays,
/// each of one or several cards. The winner can be highlighted, and an empty seat can be marked
/// as next to play (for "what should you play?" questions).
@MainActor
struct TrickDiagram: View {
    let plays: [Play]
    var trump: Trump? = nil
    /// Seat to highlight as the winner (nil = none).
    var winner: Int? = nil
    /// Gold edge on trumps (needs `trump`).
    var markTrumps: Bool = false
    /// Seat whose turn it is; shown as an empty spot with a question mark.
    var nextToPlay: Int? = nil
    var cardWidth: CGFloat = 34

    var body: some View {
        VStack(spacing: 8) {
            seat(2)
            HStack(alignment: .center, spacing: 6) {
                seat(3)
                Spacer(minLength: 0)
                seat(1)
            }
            seat(0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Theme.felt, Theme.feltDeep], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func seat(_ player: Int) -> TrickSeatView {
        let index = plays.firstIndex { $0.player == player }
        return TrickSeatView(
            name: Seats.name(player),
            cards: index.map { plays[$0].cards } ?? [],
            order: index.map { $0 + 1 },
            isLeader: index == 0,
            isWinner: winner == player,
            isNext: nextToPlay == player && index == nil,
            trump: trump,
            markTrumps: markTrumps,
            cardWidth: cardWidth
        )
    }

    private var accessibilitySummary: String {
        var parts: [String] = plays.enumerated().map { (offset, play) -> String in
            let verb = offset == 0 ? "led" : "played"
            let cards = play.cards.map(\.face.longName).joined(separator: ", ")
            return "\(Seats.name(play.player)) \(verb) \(cards)"
        }
        if let winner { parts.append("\(Seats.name(winner)) wins") }
        if let nextToPlay, !plays.contains(where: { $0.player == nextToPlay }) {
            parts.append("\(Seats.name(nextToPlay)) to play")
        }
        return parts.joined(separator: ". ")
    }
}

/// One seat of the mini table: label plus the cards played (or an empty spot).
@MainActor
private struct TrickSeatView: View {
    let name: String
    let cards: [Card]
    /// 1-based place in the play order (nil if this seat hasn't played).
    let order: Int?
    let isLeader: Bool
    let isWinner: Bool
    let isNext: Bool
    let trump: Trump?
    let markTrumps: Bool
    let cardWidth: CGFloat

    var body: some View {
        VStack(spacing: 4) {
            label
            cardsArea
        }
        .padding(5)
        .background {
            if isWinner {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.gold.opacity(0.25))
            }
        }
        .overlay {
            if isWinner {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.gold, lineWidth: 2)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let order {
                Text("\(order)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .frame(width: 15, height: 15)
                    .background(Color.white.opacity(0.25), in: Circle())
            }
            Text(name)
                .font(.caption.weight(.semibold))
            if isLeader {
                Text("led")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            if isWinner {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.gold)
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    @ViewBuilder private var cardsArea: some View {
        if cards.isEmpty {
            RoundedRectangle(cornerRadius: cardWidth * 0.11, style: .continuous)
                .strokeBorder(Color.white.opacity(isNext ? 0.8 : 0.3),
                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: cardWidth, height: cardWidth * 1.4)
                .overlay {
                    if isNext {
                        Text("?")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
        } else {
            CardRow(cards: cards, cardWidth: cardWidth, spacing: -cardWidth * 0.5,
                    trump: trump, markTrumps: markTrumps)
        }
    }
}
