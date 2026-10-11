import SwiftUI
import ShengjiCore

/// The seats of a 6- or 8-player table round the trick. The seat opposite you is at the top, the
/// others go down both sides in play order (your right first, up and over to your left), and your play
/// is at the bottom. A side seat shows a small label at the table's edge with its play beside it,
/// towards the middle. Shared by the offline and online tables (4 players keep their own layout).
@MainActor
struct GameBigTableLayout<Slot: View, Center: View>: View {
    /// Indexed by seat, you first.
    let seats: [GameSeatInfo]
    let size: CGSize
    /// A seat's play: cards `cardWidth` wide, overlapped to fit `maxWidth`.
    let slot: (_ seat: Int, _ cardWidth: CGFloat, _ maxWidth: CGFloat) -> Slot
    /// Dealing progress, the kitty, or the trick number and points on the table.
    let center: () -> Center

    /// Room for a side seat's label (the play gets the rest of its half of the row).
    private let chipWidth: CGFloat = 66
    private let centerWidth: CGFloat = 58

    private var players: Int { seats.count }
    /// Seats down each side: 2 with 6 players, 3 with 8.
    private var perSide: Int { max(1, (players - 2) / 2) }
    /// The seat opposite you.
    private var top: Int { players / 2 }
    /// With an even number of side rows (6 players) the centre gets a row of its own between them;
    /// with an odd number (8 players) it sits in the middle row.
    private var centerHasOwnRow: Bool { perSide % 2 == 0 }

    /// Side rows from the top: the seat on your left and the seat on your right.
    private var rows: [(left: Int, right: Int)] {
        (0..<perSide).map { row in (left: top + 1 + row, right: top - 1 - row) }
    }

    var body: some View {
        content()
    }

    private func content() -> some View {
        // Rows: the top seat's label and play, the side rows (plus the centre's own row with 6 players),
        // and your play. Every play slot is 1.4 x card width + 12 tall, so cards shrink until all fit.
        let slotRows = CGFloat(perSide + 2)
        let gaps = CGFloat(perSide + 2 + (centerHasOwnRow ? 1 : 0)) * 4
        let fixed = 30 + gaps + (centerHasOwnRow ? 34 : 0)
        let slotHeight = (size.height - fixed) / slotRows
        let cardWidth = min(40, max(16, (slotHeight - 12) / 1.4))
        let middleRow = perSide / 2
        let sideSlotWidth = max(56, (size.width - 2 * chipWidth - 16 - (centerHasOwnRow ? 0 : centerWidth)) / 2)
        return VStack(spacing: 4) {
            GameSeatChip(info: seats[top])
            slot(top, cardWidth, size.width * 0.6)
            Spacer(minLength: 0)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if centerHasOwnRow && index == middleRow {
                    center()
                        .frame(height: 34)
                }
                HStack(spacing: 4) {
                    sideSeat(row.left, onLeft: true, cardWidth: cardWidth, slotWidth: sideSlotWidth)
                    Spacer(minLength: 0)
                    if !centerHasOwnRow && index == middleRow {
                        center()
                            .frame(width: centerWidth)
                        Spacer(minLength: 0)
                    }
                    sideSeat(row.right, onLeft: false, cardWidth: cardWidth, slotWidth: sideSlotWidth)
                }
            }
            Spacer(minLength: 0)
            ZStack(alignment: .bottomLeading) {
                // Narrower than the full width so the centred play never runs under your label.
                slot(Seats.human, cardWidth, max(120, size.width - 2 * chipWidth - 16))
                    .frame(maxWidth: .infinity)
                GameSeatChip(info: seats[Seats.human])
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// A side seat: its label at the table's edge, its play towards the middle.
    private func sideSeat(_ seat: Int, onLeft: Bool, cardWidth: CGFloat, slotWidth: CGFloat) -> some View {
        HStack(spacing: 4) {
            if onLeft {
                GameSeatChip(info: seats[seat])
                    .frame(width: chipWidth, alignment: .leading)
                slot(seat, cardWidth, slotWidth)
                    .frame(width: slotWidth, alignment: .leading)
            } else {
                slot(seat, cardWidth, slotWidth)
                    .frame(width: slotWidth, alignment: .trailing)
                GameSeatChip(info: seats[seat])
                    .frame(width: chipWidth, alignment: .trailing)
            }
        }
    }
}

/// A seat's label at a table of 6 or 8: team dot and short name, then cards held and a "D" dealer button.
/// Gold edge when it is their turn.
@MainActor
struct GameSeatChip: View {
    let info: GameSeatInfo

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle()
                    .fill(Theme.teamColor(info.team))
                    .frame(width: 7, height: 7)
                Text(info.shortName ?? info.name)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if info.isThinking {
                    Image(systemName: "ellipsis")
                        .font(.caption2.weight(.bold))
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                }
                if info.isTrickWinner {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.gold)
                }
            }
            HStack(spacing: 3) {
                if info.seat != Seats.human {
                    Text("\(info.cardCount)")
                        .monospacedDigit()
                }
                if info.role == .dealer {
                    // A dealer button, as at a card table: there's no room for the word.
                    Text("D")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Theme.cardInk)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Theme.gold))
                }
            }
            .font(.caption2)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(info.isTurn ? 0.42 : 0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(info.isTurn ? Theme.gold : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.accessibilityText)
    }
}
