import SwiftUI
import ShengjiCore

/// The middle of the table: Partner at the top, West on the left, East on the right, your play at the
/// bottom, each seat's current play near the centre (6 or 8 players: `GameBigTableLayout`). Tap during
/// the pause after a trick to go on.
@MainActor
struct GameTableArea: View {
    let controller: GameController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Read the observable state here in `body` (not inside the GeometryReader closure) so SwiftUI
        // tracks it reliably; the closure only uses this plain snapshot.
        let snapshot = GameTableSnapshot(controller: controller)
        GeometryReader { proxy in
            tableContent(size: proxy.size, snapshot: snapshot)
        }
        .contentShape(Rectangle())
        .onTapGesture { controller.skipTrickPause() }
        .accessibilityAction(named: "Continue") { controller.skipTrickPause() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: snapshot.display)
    }

    @ViewBuilder
    private func tableContent(size: CGSize, snapshot: GameTableSnapshot) -> some View {
        if snapshot.seats.count != 4 {
            GameBigTableLayout(seats: snapshot.seats, size: size,
                               slot: { seat, cardWidth, maxWidth in
                                   slot(seat, snapshot: snapshot, cardWidth: cardWidth, maxWidth: maxWidth)
                               },
                               center: { GameTableCenter(controller: controller) })
        } else {
            classicContent(size: size, snapshot: snapshot)
        }
    }

    private func classicContent(size: CGSize, snapshot: GameTableSnapshot) -> some View {
        // Fixed parts: two seat labels (about 44 pt each) and the stack spacing (about 24 pt), plus margin.
        // The three play slots are 1.4 x card width + 12 each, so cards shrink until everything fits
        // (an iPhone SE with a long coach message and the declare buttons still fits).
        let cardWidth = min(44, max(18, (size.height - 150) / 4.2))
        let sideWidth = max(80, min(150, size.width * 0.36))
        return VStack(spacing: 4) {
            GameSeatLabel(info: snapshot.seats[2])
            slot(2, snapshot: snapshot, cardWidth: cardWidth, maxWidth: size.width * 0.6)
            Spacer(minLength: 0)
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    GameSeatLabel(info: snapshot.seats[3])
                    slot(3, snapshot: snapshot, cardWidth: cardWidth, maxWidth: sideWidth)
                }
                Spacer(minLength: 0)
                GameTableCenter(controller: controller)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    GameSeatLabel(info: snapshot.seats[1])
                    slot(1, snapshot: snapshot, cardWidth: cardWidth, maxWidth: sideWidth)
                }
            }
            Spacer(minLength: 0)
            ZStack(alignment: .bottomLeading) {
                // Narrower than the full width so the centred play never runs under your seat label.
                slot(0, snapshot: snapshot, cardWidth: cardWidth, maxWidth: max(120, size.width - 200))
                    .frame(maxWidth: .infinity)
                GameSeatLabel(info: snapshot.seats[0], compact: true)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func slot(_ seat: Int, snapshot: GameTableSnapshot, cardWidth: CGFloat, maxWidth: CGFloat) -> some View {
        GamePlaySlot(cards: snapshot.display.cards(for: seat).map { snapshot.trump.sorted($0) },
                     trump: snapshot.trump,
                     markTrumps: snapshot.markTrumps,
                     isWinner: snapshot.display.winner == seat,
                     isLeading: snapshot.leadingSeat == seat,
                     cardWidth: cardWidth,
                     maxWidth: maxWidth)
    }
}

/// Everything the table area draws, read from the controller once per update.
struct GameTableSnapshot: Equatable {
    /// Indexed by seat (0...3 at a table of four).
    let seats: [GameSeatInfo]
    let display: TableTrickDisplay
    let trump: Trump
    let markTrumps: Bool
    let leadingSeat: Int?

    @MainActor
    init(controller: GameController) {
        seats = controller.seats.map { controller.seatInfo($0) }
        display = controller.trickDisplay
        trump = controller.round.trump
        markTrumps = controller.markTrumps
        leadingSeat = controller.leadingSeat
    }
}

/// Name, card count and role of a seat. Gold edge when it is their turn.
@MainActor
struct GameSeatLabel: View {
    let info: GameSeatInfo
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Theme.teamColor(info.team))
                    .frame(width: 8, height: 8)
                Text(info.name)
                    .font(.subheadline.weight(.semibold))
                if info.isThinking {
                    Image(systemName: "ellipsis")
                        .font(.caption.weight(.bold))
                        .symbolEffect(.pulse, isActive: !reduceMotion)
                }
                if info.isTrickWinner {
                    Image(systemName: "crown.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }
            }
            HStack(spacing: 4) {
                if !compact || info.seat != Seats.human {
                    Text("\(info.cardCount) cards")
                }
                if let role = info.role {
                    GameRoleBadge(role: role, team: info.team)
                }
            }
            .font(.caption2)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(info.isTurn ? 0.42 : 0.24))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(info.isTurn ? Theme.gold : Color.clear, lineWidth: 2)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(info.accessibilityText)
    }
}

/// "Dealer" / "Declarer" / "Defender" / "Friend".
@MainActor
struct GameRoleBadge: View {
    let role: GameSeatRole
    let team: Int

    var body: some View {
        Text(role.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(fill))
            .foregroundStyle(role == .dealer ? Theme.cardInk : Color.white)
    }

    private var fill: Color {
        switch role {
        case .dealer: return Theme.gold
        case .declarer, .friend: return Theme.teamColor(team).opacity(0.75)
        case .defender: return Color.white.opacity(0.22)
        }
    }
}

/// One seat's cards in the current trick (or an empty space of the same size).
@MainActor
struct GamePlaySlot: View {
    let cards: [Card]?
    let trump: Trump
    let markTrumps: Bool
    let isWinner: Bool
    let isLeading: Bool
    let cardWidth: CGFloat
    let maxWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let cards, !cards.isEmpty {
                CardRow(cards: cards, cardWidth: cardWidth, spacing: spacing(for: cards.count),
                        trump: trump, markTrumps: markTrumps)
                    .padding(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 2.5)
                    )
                    .overlay(alignment: .bottom) { tag }
                    .transition(reduceMotion ? AnyTransition.opacity
                                             : AnyTransition.scale(scale: 0.7).combined(with: AnyTransition.opacity))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText(cards))
            }
        }
        .frame(height: cardWidth * 1.4 + 12)
    }

    private var borderColor: Color {
        if isWinner { return Theme.gold }
        if isLeading { return Color.white.opacity(0.7) }
        return Color.clear
    }

    @ViewBuilder private var tag: some View {
        // Fixed size: under a single small card (a table of 8) the tag is wider than the card.
        if isWinner {
            Text("Wins")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Theme.cardInk)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.gold))
                .offset(y: 8)
        } else if isLeading {
            Text("Winning")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.cardInk)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.85)))
                .offset(y: 8)
        }
    }

    /// Overlap so the whole play fits in `maxWidth`.
    private func spacing(for count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let natural = -cardWidth * 0.45
        let fit = (maxWidth - 6 - cardWidth) / CGFloat(count - 1) - cardWidth
        return min(natural, fit)
    }

    private func accessibilityText(_ cards: [Card]) -> String {
        var text = cards.map { $0.face.longName }.joined(separator: ", ")
        if isWinner { text += ", wins the trick" } else if isLeading { text += ", winning so far" }
        return text
    }
}

/// Between West and East: dealing progress, the kitty, or the trick number and points on the table.
@MainActor
struct GameTableCenter: View {
    let controller: GameController

    var body: some View {
        VStack(spacing: 4) {
            content
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.85))
        .frame(minWidth: 56)
    }

    @ViewBuilder private var content: some View {
        switch controller.stage {
        case .dealing, .declareWindow, .botsRespond:
            CardView(card: Card(.two, .spades), width: 26, faceDown: true)
            Text("\(controller.dealtCount)/\(controller.cardsToDeal)")
                .monospacedDigit()
        case .burying:
            CardView(card: Card(.two, .spades), width: 26, faceDown: true)
            Text("Kitty")
        case .playing, .trickPause, .predicting:
            Text("Trick")
            Text(trickNumberText)
                .font(.headline)
                .monospacedDigit()
            if pointsOnTable > 0 {
                Text("+\(pointsOnTable)")
                    .foregroundStyle(Theme.gold)
            }
        case .roundOver:
            Image(systemName: "flag.checkered")
                .font(.headline)
            Text("Done")
        }
    }

    /// The trick in progress (or the one just finished during the pause), 1-based.
    private var trickNumberText: String {
        let finished = controller.round.tricks.count
        let number = controller.stage == .playing ? finished + 1 : finished
        return String(max(1, number))
    }

    private var pointsOnTable: Int { controller.trickDisplay.points }
}
