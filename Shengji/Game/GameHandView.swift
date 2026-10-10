import SwiftUI
import ShengjiCore

/// Your hand in up to two overlapping rows sized to the width (no horizontal scrolling),
/// plain suits on the left and trumps on the right. Tap a card to select it (it rises);
/// long-press to select the whole pair or tractor it belongs to.
@MainActor
struct GameHandView: View {
    let controller: GameController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    var body: some View {
        let hand = controller.hand
        let layout = GameHandLayout(count: hand.count, width: Double(width))
        let context = GameHandCardContext(controller: controller)
        ZStack(alignment: .topLeading) {
            ForEach(Array(hand.enumerated()), id: \.element.id) { index, card in
                GameHandCard(card: card, index: index, layout: layout, context: context,
                             onTap: { controller.toggle(card) },
                             onLongPress: { controller.selectCombo(containing: card) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The ZStack is only one card tall (cards are placed with offsets), so pin it to the top:
        // centred, the second row would hang about 25 pt below the hand area.
        .frame(height: CGFloat(GameHandLayout.reservedHeight(count: hand.count, width: Double(width),
                                                             fullHand: Round.handSize)),
               alignment: .top)
        .background(widthReader)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: controller.selection)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hand.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your hand, \(hand.count) cards")
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in
                    width = newWidth
                }
        }
    }
}

/// Per-render facts every card needs (computed once per hand, not once per card).
struct GameHandCardContext {
    let selection: Set<Int>
    let dimmed: Set<Int>
    let newCards: Set<Int>
    let markTrumps: Bool
    let trump: Trump
    let canSelect: Bool

    @MainActor
    init(controller: GameController) {
        selection = controller.selection
        dimmed = controller.dimmedCardIDs
        newCards = controller.newKittyCardIDs
        markTrumps = controller.markTrumps
        trump = controller.round.trump
        canSelect = controller.canSelectCards
    }
}

/// One card of your hand, placed by `GameHandLayout`.
@MainActor
struct GameHandCard: View {
    let card: Card
    let index: Int
    let layout: GameHandLayout
    let context: GameHandCardContext
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        let origin = layout.origin(of: index)
        let selected = context.selection.contains(card.id)
        let lift = selected ? GameHandLayout.raise : 0
        return CardView(card: card,
                        width: CGFloat(layout.cardWidth),
                        markTrump: context.markTrumps && context.trump.isTrump(card),
                        isSelected: selected,
                        isDimmed: context.dimmed.contains(card.id))
            .overlay(alignment: .topLeading) { newBadge }
            .offset(x: CGFloat(origin.x), y: CGFloat(origin.y - lift))
            .zIndex(Double(index))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.35) { onLongPress() }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(accessibilityValue(selected: selected))
            .accessibilityHint(hintText)
            .accessibilityAction(named: "Select pair or tractor", onLongPress)
    }

    @ViewBuilder private var newBadge: some View {
        if context.newCards.contains(card.id) {
            Text("new")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.cardInk)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.gold))
                .offset(x: 1, y: -9)
                .accessibilityHidden(true)
        }
    }

    private var hintText: String { context.canSelect ? "Double-tap to select." : "" }

    private func accessibilityValue(selected: Bool) -> String {
        var parts: [String] = []
        if context.markTrumps && context.trump.isTrump(card) { parts.append("trump") }
        if context.newCards.contains(card.id) { parts.append("new from the kitty") }
        if context.dimmed.contains(card.id) { parts.append("can't be played now") }
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}
