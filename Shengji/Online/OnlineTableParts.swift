import SwiftUI
import ShengjiCore

// MARK: - Top bar

/// Levels (declaring team flagged), defenders' points, the coach and the menu; then close, trump,
/// dealer and the connection state.
@MainActor
struct OnlineTopBar: View {
    let model: OnlineGameModel
    @Binding var coachLevel: CoachLevel
    let onClose: () -> Void
    let onCoach: () -> Void
    let onEndGame: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                levels
                Spacer(minLength: 4)
                defenderPoints
                coachButton
                OnlineTableMenu(model: model, coachLevel: $coachLevel, onClose: onClose, onEndGame: onEndGame)
            }
            HStack(spacing: 8) {
                closeButton
                trumpView
                Spacer(minLength: 4)
                OnlineConnectionBadge(status: model.liveStatus)
                Text(model.roundAndDealerText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.top, 4)
    }

    private var levels: some View {
        HStack(spacing: 4) {
            GameTeamLevelChip(title: "Us", team: 0, level: model.level(of: 0) ?? .two,
                              isDeclaring: model.view?.declarerTeam == 0)
            Text("·")
                .font(.headline)
                .foregroundStyle(Color.white.opacity(0.6))
                .accessibilityHidden(true)
            GameTeamLevelChip(title: "Them", team: 1, level: model.level(of: 1) ?? .two,
                              isDeclaring: model.view?.declarerTeam == 1)
        }
    }

    private var defenderPoints: some View {
        let points = model.defenderPoints
        let score = Text("\(points) / \(Scoring.takeoverThreshold)")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(points >= Scoring.takeoverThreshold ? Theme.gold : Color.white)
        // On narrow screens the word "Defenders" goes first, so the level chips always fit.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                Text("Defenders")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.8))
                score
            }
            score
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Defenders have \(points) points. They need \(Scoring.takeoverThreshold).")
    }

    private var coachButton: some View {
        Button(action: onCoach) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.cardInk)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.gold))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canAskCoach)
        .opacity(model.canAskCoach ? 1 : 0.45)
        .accessibilityLabel("Ask the coach")
        .accessibilityHint("Opens a chat with the coach about this table.")
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "chevron.down")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.black.opacity(0.3)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close the table")
        .accessibilityHint("Your game stays where it is. Come back any time.")
    }

    @ViewBuilder private var trumpView: some View {
        if model.isTrumpSet, let trump = model.view?.trump {
            TrumpBadge(trump: trump, compact: true)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "star")
                    .foregroundStyle(Theme.gold)
                Text("Trump not set yet")
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Rank \(model.view?.trump.rank.label ?? "?")")
                    .fontWeight(.semibold)
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }
}

/// What happened, last round, rules, coach level, nudge, end game, close.
@MainActor
struct OnlineTableMenu: View {
    let model: OnlineGameModel
    @Binding var coachLevel: CoachLevel
    let onClose: () -> Void
    let onEndGame: () -> Void

    var body: some View {
        Menu {
            Button { model.setSheet(.whatHappened) } label: {
                Label("What happened", systemImage: "clock.arrow.circlepath")
            }
            .disabled(model.view == nil)
            if let summary = model.lastRoundSummary {
                Button { model.setSheet(.roundSummary(summary)) } label: {
                    Label("Last round's result", systemImage: "list.bullet.rectangle")
                }
            }
            Button { model.setSheet(.rules) } label: {
                Label("Rules quick sheet", systemImage: "book")
            }
            Picker(selection: $coachLevel) {
                ForEach(CoachLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            } label: {
                Label("Coach level", systemImage: "graduationcap")
            }
            .pickerStyle(.menu)
            if model.canNudge, let seat = model.actingSeat {
                Button { Task { await model.nudge() } } label: {
                    Label("Remind \(model.name(seat))", systemImage: "bell")
                }
            }
            Divider()
            if !model.isGameOver && !model.isGone {
                Button(role: .destructive, action: onEndGame) {
                    Label("End game for everyone", systemImage: "xmark.octagon")
                }
            }
            Button(action: onClose) {
                Label("Close table", systemImage: "chevron.down")
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

/// Shown only while live updates are down (the table is then checked every 15 seconds).
@MainActor
struct OnlineConnectionBadge: View {
    let status: OnlineLiveUpdates.Status

    var body: some View {
        if case let .reconnecting(attempt) = status, attempt >= 2 {
            Label("Reconnecting", systemImage: "wifi.slash")
                .labelStyle(.iconOnly)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.gold)
                .accessibilityLabel("Reconnecting. The table still updates every 15 seconds.")
        }
    }
}

// MARK: - Table area

/// Everything the table area draws, read from the model once per update.
struct OnlineTableSnapshot: Equatable {
    /// Indexed by seat 0...3.
    let seats: [GameSeatInfo]
    let display: TableTrickDisplay
    let trump: Trump
    let markTrumps: Bool
    let leadingSeat: Int?
    let phase: SeatView.Phase?
    let roundNumber: Int
    let trickNumber: Int
    let isFlash: Bool

    @MainActor
    init(model: OnlineGameModel) {
        seats = Seats.all.map { model.seatInfo($0) }
        display = model.trickDisplay
        trump = model.view?.trump ?? Trump(rank: .two, suit: nil)
        markTrumps = model.markTrumps
        leadingSeat = model.leadingSeat
        phase = model.view?.phase
        roundNumber = model.view?.roundNumber ?? model.summary?.roundNumber ?? 1
        isFlash = model.flash != nil
        if let flash = model.flash {
            trickNumber = flash.number
        } else {
            let finished = model.view?.tricks.count ?? 0
            trickNumber = model.view?.phase == .playing ? finished + 1 : max(1, finished)
        }
    }
}

/// Partner at the top, your left and right at the sides, your play at the bottom; each seat's play near
/// the centre. Tap to skip the last trick shown after a new one starts.
@MainActor
struct OnlineTableArea: View {
    let model: OnlineGameModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = OnlineTableSnapshot(model: model)
        GeometryReader { proxy in
            tableContent(size: proxy.size, snapshot: snapshot)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.skipFlash() }
        .accessibilityAction(named: "Show the trick in progress") { model.skipFlash() }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: snapshot.display)
    }

    private func tableContent(size: CGSize, snapshot: OnlineTableSnapshot) -> some View {
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
                OnlineTableCenter(snapshot: snapshot)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    GameSeatLabel(info: snapshot.seats[1])
                    slot(1, snapshot: snapshot, cardWidth: cardWidth, maxWidth: sideWidth)
                }
            }
            Spacer(minLength: 0)
            ZStack(alignment: .bottomLeading) {
                slot(0, snapshot: snapshot, cardWidth: cardWidth, maxWidth: max(120, size.width - 200))
                    .frame(maxWidth: .infinity)
                GameSeatLabel(info: snapshot.seats[0], compact: true)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func slot(_ seat: Int, snapshot: OnlineTableSnapshot, cardWidth: CGFloat, maxWidth: CGFloat) -> some View {
        GamePlaySlot(cards: snapshot.display.cards(for: seat).map { snapshot.trump.sorted($0) },
                     trump: snapshot.trump,
                     markTrumps: snapshot.markTrumps,
                     isWinner: snapshot.display.winner == seat,
                     isLeading: snapshot.leadingSeat == seat,
                     cardWidth: cardWidth,
                     maxWidth: maxWidth)
    }
}

/// Between your left and right: the round while bidding, the kitty while burying, the trick number and
/// points in play ("Last trick" while a finished one is shown).
@MainActor
struct OnlineTableCenter: View {
    let snapshot: OnlineTableSnapshot

    var body: some View {
        VStack(spacing: 4) {
            content
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.white.opacity(0.85))
        .frame(minWidth: 60)
    }

    @ViewBuilder private var content: some View {
        switch snapshot.phase {
        case .bidding?, .dealing?:
            CardView(card: Card(.two, .spades), width: 26, faceDown: true)
            Text("Round \(snapshot.roundNumber)")
            Text("Declaring")
        case .burying?:
            CardView(card: Card(.two, .spades), width: 26, faceDown: true)
            Text("Kitty")
        case .playing?:
            Text(snapshot.isFlash ? "Last trick" : "Trick")
            Text(String(snapshot.trickNumber))
                .font(.headline)
                .monospacedDigit()
            if snapshot.display.points > 0 {
                Text("+\(snapshot.display.points)")
                    .foregroundStyle(Theme.gold)
            }
            if snapshot.isFlash {
                Text("Tap for now")
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        case .finished?:
            Image(systemName: "flag.checkered")
                .font(.headline)
            Text("Done")
        case nil:
            EmptyView()
        }
    }
}

// MARK: - Coach banner and bidding

/// The coach banner (hints offer "Why?"), and your declare buttons while bidding.
@MainActor
struct OnlineCoachArea: View {
    let model: OnlineGameModel
    let onWhy: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            GameCoachBannerView(message: model.banner,
                                onWhy: model.isShowingHint && model.canAskCoach ? onWhy : nil)
            if !model.availableBids.isEmpty {
                GameDeclareRow(declarations: model.availableBids, current: model.view?.declaration) { declaration in
                    model.bid(declaration)
                }
                .disabled(model.isSending)
                .transition(AnyTransition.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.banner)
    }
}

// MARK: - Action bar

/// Hint (when a hint exists), Clear, the status ("Waiting for Mei") and the main button.
@MainActor
struct OnlineActionBar: View {
    let model: OnlineGameModel

    var body: some View {
        HStack(spacing: 8) {
            if model.hintsAvailable {
                Button {
                    model.showHint()
                } label: {
                    Label(model.hintButtonTitle, systemImage: "lightbulb")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(Color.white)
                .accessibilityHint("Each tap gives a little more help.")
            }
            if model.canSelectCards {
                Button {
                    model.clearSelection()
                } label: {
                    Label("Clear", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .tint(Color.white)
                .disabled(model.selection.isEmpty)
                .accessibilityLabel("Clear selection")
            }
            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
            primaryButton
        }
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 40)
    }

    @ViewBuilder private var primaryButton: some View {
        switch model.primaryAction {
        case .none:
            if model.isSending {
                ProgressView()
                    .tint(Color.white)
            }
        case let .pass(enabled):
            GamePrimaryButton(title: "Pass", systemImage: "hand.raised", enabled: enabled) {
                model.pass()
            }
        case let .bury(count, enabled):
            GamePrimaryButton(title: "Bury \(count)/\(Round.kittySize)", systemImage: "tray.and.arrow.down",
                              enabled: enabled) {
                model.bury()
            }
        case let .play(enabled):
            GamePrimaryButton(title: "Play", systemImage: "arrow.up", enabled: enabled) {
                model.play()
            }
        case .retry:
            GamePrimaryButton(title: "Retry", systemImage: "arrow.clockwise", enabled: !model.isSending) {
                model.retry()
            }
        }
    }
}

// MARK: - Your hand

/// Your hand in up to two overlapping rows (no horizontal scrolling), plain suits on the left and trumps
/// on the right. Tap to select; long-press for the whole pair or tractor.
@MainActor
struct OnlineHandView: View {
    let model: OnlineGameModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var width: CGFloat = 0

    var body: some View {
        let hand = model.hand
        let layout = GameHandLayout(count: hand.count, width: Double(width))
        let context = OnlineHandContext(model: model)
        ZStack(alignment: .topLeading) {
            ForEach(Array(hand.enumerated()), id: \.element.id) { index, card in
                OnlineHandCard(card: card, index: index, layout: layout, context: context,
                               onTap: { model.toggle(card) },
                               onLongPress: { model.selectCombo(containing: card) })
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CGFloat(GameHandLayout.reservedHeight(count: hand.count, width: Double(width),
                                                             fullHand: Round.handSize)),
               alignment: .top)
        .background(widthReader)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: model.selection)
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

/// Per-render facts every card needs (computed once per hand).
struct OnlineHandContext {
    let selection: Set<Int>
    let dimmed: Set<Int>
    let newCards: Set<Int>
    let highlighted: Set<Int>
    let markTrumps: Bool
    let trump: Trump
    let canSelect: Bool

    @MainActor
    init(model: OnlineGameModel) {
        selection = model.selection
        dimmed = model.dimmedCardIDs
        newCards = model.newCardIDs
        highlighted = Set(model.activeHint?.highlightedCards.map(\.id) ?? [])
        markTrumps = model.markTrumps
        trump = model.view?.trump ?? Trump(rank: .two, suit: nil)
        canSelect = model.canSelectCards
    }
}

/// One card of your hand, placed by `GameHandLayout`.
@MainActor
struct OnlineHandCard: View {
    let card: Card
    let index: Int
    let layout: GameHandLayout
    let context: OnlineHandContext
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
            .accessibilityHint(context.canSelect ? "Double-tap to select." : "")
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

    private func accessibilityValue(selected: Bool) -> String {
        var parts: [String] = []
        if context.markTrumps && context.trump.isTrump(card) { parts.append("trump") }
        if context.newCards.contains(card.id) { parts.append("new from the kitty") }
        if context.dimmed.contains(card.id) { parts.append("can't be played now") }
        if context.highlighted.contains(card.id) { parts.append("suggested") }
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }
}
