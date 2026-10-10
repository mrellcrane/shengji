import SwiftUI
import ShengjiCore

/// Hint (Hint, Another hint, Show me), Clear, a short status and the main action (Play, Bury, Continue...).
@MainActor
struct GameActionBar: View {
    let controller: GameController

    var body: some View {
        HStack(spacing: 8) {
            if controller.hintsAvailable {
                Button {
                    controller.showHint()
                } label: {
                    Label(controller.hintButtonTitle, systemImage: "lightbulb")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(Color.white)
                .disabled(!controller.canHint)
                .accessibilityHint("Each tap gives a little more help.")
            }
            Button {
                controller.clearSelection()
            } label: {
                Label("Clear", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(Color.white)
            .disabled(controller.selection.isEmpty)
            .accessibilityLabel("Clear selection")

            Text(controller.statusText)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)

            primaryButton
        }
        .font(.subheadline.weight(.semibold))
        .frame(minHeight: 40)
    }

    @ViewBuilder private var primaryButton: some View {
        switch controller.primaryAction {
        case .none:
            EmptyView()
        case .resumeDeal:
            GamePrimaryButton(title: "Deal on", systemImage: "play.fill", enabled: true) {
                controller.resumeAutoplay()
            }
        case .continueDeal:
            GamePrimaryButton(title: "Continue", systemImage: "arrow.right", enabled: true) {
                controller.continueAfterDeal()
            }
        case let .bury(count, enabled):
            GamePrimaryButton(title: "Bury \(count)/\(Round.kittySize)", systemImage: "tray.and.arrow.down",
                              enabled: enabled) {
                controller.burySelected()
            }
        case let .play(enabled):
            GamePrimaryButton(title: "Play", systemImage: "arrow.up", enabled: enabled) {
                controller.playSelected()
            }
        case .nextTrick:
            GamePrimaryButton(title: "Next", systemImage: "forward.fill", enabled: true) {
                controller.skipTrickPause()
            }
        case .showResult:
            GamePrimaryButton(title: "Results", systemImage: "list.bullet.rectangle", enabled: true) {
                controller.isShowingResult = true
            }
        }
    }
}

/// The gold main button.
@MainActor
struct GamePrimaryButton: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.cardInk)
                .padding(.horizontal, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.gold)
        .disabled(!enabled)
    }
}

/// One button per declaration you could make right now.
@MainActor
struct GameDeclareRow: View {
    let declarations: [Declaration]
    let current: Declaration?
    let onDeclare: (Declaration) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(declarations, id: \.self) { declaration in
                    declareButton(declaration)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func declareButton(_ declaration: Declaration) -> some View {
        let text = GameCoachText.declareButton(declaration, current: current)
        return Button {
            onDeclare(declaration)
        } label: {
            VStack(spacing: 0) {
                Text(text.title)
                    .font(.subheadline.weight(.bold))
                Text(text.detail)
                    .font(.caption2)
            }
            .foregroundStyle(Theme.cardInk)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.gold)
        .accessibilityLabel(GameCoachText.declarationAccessibility(declaration))
    }
}

/// The coach's message: icon, text (with **bold**) and the concept tag. Under a hint, a "Why?" chip
/// asks the coach why that hint applies.
@MainActor
struct GameCoachBannerView: View {
    let message: GameCoachMessage?
    var onWhy: (() -> Void)? = nil

    var body: some View {
        Group {
            if let message {
                content(message)
                    .id(message.id)
                    .transition(AnyTransition.opacity)
            } else {
                Color.clear
                    .frame(height: 52)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(message == nil ? 0.12 : 0.34))
        )
    }

    private func content(_ message: GameCoachMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: message.kind))
                .font(.body.weight(.semibold))
                .foregroundStyle(color(for: message.kind))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                RichText(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                if message.concept != nil || onWhy != nil {
                    HStack(spacing: 8) {
                        if let concept = message.concept {
                            Text(concept)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.cardInk)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(color(for: message.kind)))
                                .accessibilityLabel("Idea: \(concept)")
                        }
                        if let onWhy {
                            whyChip(onWhy)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: onWhy == nil ? .combine : .contain)
    }

    private func whyChip(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Why?", systemImage: "bubble.left.and.text.bubble.right.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.18)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Why? Ask the coach about this hint")
    }

    private func icon(for kind: GameCoachMessage.Kind) -> String {
        switch kind {
        case .info: return "info.circle.fill"
        case .hint: return "lightbulb.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    private func color(for kind: GameCoachMessage.Kind) -> Color {
        switch kind {
        case .info: return Color.white.opacity(0.85)
        case .hint: return Theme.gold
        case .warning: return Color(red: 1.0, green: 0.62, blue: 0.45)
        case .success: return Color(red: 0.55, green: 0.9, blue: 0.6)
        }
    }
}

/// "Who wins this trick?" with one button per seat.
@MainActor
struct GamePredictionPanel: View {
    let onAnswer: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Who wins this trick?", systemImage: "questionmark.circle.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
            HStack(spacing: 6) {
                ForEach(Seats.all, id: \.self) { seat in
                    Button {
                        onAnswer(seat)
                    } label: {
                        // Four buttons share a 375 pt row, so let "Partner" shrink rather than truncate.
                        Text(Seats.name(seat))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel(answerLabel(seat))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.teamColor(Seats.team(of: seat)))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.gold, lineWidth: 1.5)
        )
    }

    private func answerLabel(_ seat: Int) -> String {
        seat == Seats.human ? "You win it" : "\(Seats.name(seat)) wins it"
    }
}
