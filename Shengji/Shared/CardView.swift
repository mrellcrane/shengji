import SwiftUI
import ShengjiCore

/// A single playing card drawn with SwiftUI shapes (no image assets).
/// The rank/suit index sits in the top-left corner so it stays readable when cards overlap.
struct CardView: View {
    let card: Card
    var width: CGFloat = 56
    /// Gold edge marking a trump (used in guided mode and lessons).
    var markTrump: Bool = false
    var isSelected: Bool = false
    /// Greyed out, e.g. not a legal play in guided mode.
    var isDimmed: Bool = false
    var faceDown: Bool = false

    var height: CGFloat { width * 1.4 }
    private var corner: CGFloat { width * 0.11 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(faceDown ? Theme.cardBack : Color.white)
            if faceDown {
                back
            } else {
                face
            }
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .frame(width: width, height: height)
        .overlay {
            if isDimmed {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            }
        }
        .shadow(color: .black.opacity(isSelected ? 0.35 : 0.18), radius: isSelected ? 4 : 1.5, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceDown ? "Face-down card" : card.face.longName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var borderColor: Color {
        if isSelected { return Theme.usColor }
        if markTrump && !faceDown { return Theme.gold }
        return Color.black.opacity(0.25)
    }

    private var borderWidth: CGFloat {
        if isSelected { return max(2, width * 0.05) }
        if markTrump && !faceDown { return max(2, width * 0.05) }
        return 0.75
    }

    @ViewBuilder private var face: some View {
        let ink = Theme.ink(for: card)
        switch card.face {
        case .smallJoker, .bigJoker:
            jokerFace(ink: ink, big: card.face == .bigJoker)
        case let .regular(suit, rank):
            ZStack(alignment: .topLeading) {
                Color.clear
                VStack(spacing: -width * 0.04) {
                    Text(rank.label)
                        .font(.system(size: width * (rank == .ten ? 0.27 : 0.31), weight: .bold, design: .rounded))
                        .tracking(rank == .ten ? -width * 0.02 : 0)
                    Text(suit.symbol)
                        .font(.system(size: width * 0.27))
                }
                .foregroundStyle(ink)
                .padding(.leading, width * 0.06)
                .padding(.top, width * 0.05)
                .frame(width: width * 0.36)

                Text(suit.symbol)
                    .font(.system(size: width * 0.62))
                    .foregroundStyle(ink.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, width * 0.08)
                    .padding(.bottom, width * 0.04)

                if markTrump {
                    Image(systemName: "star.fill")
                        .font(.system(size: width * 0.16))
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .padding(.top, width * 0.07)
                        .padding(.trailing, width * 0.07)
                }
            }
        }
    }

    private func jokerFace(ink: Color, big: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            VStack(spacing: -width * 0.05) {
                ForEach(Array("JOKER".enumerated()), id: \.offset) { _, ch in
                    Text(String(ch))
                        .font(.system(size: width * 0.17, weight: .heavy, design: .rounded))
                }
            }
            .foregroundStyle(ink)
            .padding(.leading, width * 0.08)
            .padding(.top, width * 0.06)

            Image(systemName: big ? "crown.fill" : "star.fill")
                .font(.system(size: width * 0.42))
                .foregroundStyle(big ? Theme.cardRed : Theme.cardInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, width * 0.1)
                .padding(.bottom, width * 0.1)
        }
    }

    private var back: some View {
        RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous)
            .strokeBorder(Color.white.opacity(0.55), lineWidth: max(1, width * 0.03))
            .background(
                RoundedRectangle(cornerRadius: corner * 0.7, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Theme.cardBack, Theme.cardBack.opacity(0.75)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                Text("升")
                    .font(.system(size: width * 0.42, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
            )
            .padding(width * 0.07)
    }
}

/// Cards in a row, overlapping when `spacing` is negative. Used for tricks, lessons and quiz visuals.
struct CardRow: View {
    let cards: [Card]
    var cardWidth: CGFloat = 46
    /// Horizontal gap between cards; negative overlaps them.
    var spacing: CGFloat = -18
    var trump: Trump? = nil
    /// Draw the gold trump edge on trumps (needs `trump`).
    var markTrumps: Bool = false

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(cards) { card in
                CardView(card: card, width: cardWidth,
                         markTrump: markTrumps && (trump?.isTrump(card) ?? false))
            }
        }
        .padding(.trailing, 0)
    }
}

/// "Trump: ♥ · Rank 5" chip.
struct TrumpBadge: View {
    let trump: Trump
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill").foregroundStyle(Theme.gold)
            if let suit = trump.suit {
                Text(compact ? "Trump" : "Trump suit")
                Text(suit.symbol)
                    .foregroundStyle(suit.isRed ? Theme.cardRed : Color.primary)
                    .fontWeight(.bold)
            } else {
                Text("No trump suit")
            }
            Text("·").foregroundStyle(.secondary)
            Text(compact ? "Rank \(trump.rank.label)" : "Trump rank \(trump.rank.label)")
                .fontWeight(.semibold)
        }
        .font(compact ? .caption : .subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Text that renders **bold** and *italic* inline markdown.
struct RichText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
    }
}

#Preview("Cards") {
    VStack(spacing: 20) {
        HStack {
            CardView(card: Card(.ace, .spades))
            CardView(card: Card(.ten, .hearts), markTrump: true)
            CardView(card: Card(.queen, .diamonds), isSelected: true)
            CardView(card: .bigJoker())
            CardView(card: .smallJoker())
            CardView(card: Card(.two, .clubs), faceDown: true)
        }
        CardRow(cards: [Card(.five, .hearts), Card(.five, .hearts, copy: 1), Card(.king, .clubs)],
                trump: Trump(rank: .two, suit: .hearts), markTrumps: true)
        TrumpBadge(trump: Trump(rank: .five, suit: .hearts))
        RichText("Points: **5s**, **10s** and **Kings**.")
    }
    .padding()
    .background(Theme.felt)
}
