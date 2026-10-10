import SwiftUI
import ShengjiCore

/// A compact capsule celebrating a move or a new badge tier: symbol, title and one line of detail.
@MainActor
struct AchievementToastView: View {
    let toast: AchievementToast

    private var tint: Color {
        switch toast.kind {
        case .move: return Theme.gold
        case let .tierUp(tier): return AchievementStyle.color(for: tier)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.cardInk)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(toast.detail)
                    .font(.caption)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.white)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .padding(.trailing, 16)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.black.opacity(0.82)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(tint, lineWidth: 1.5))
        .frame(maxWidth: 440)
        .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 2)
    }
}

/// Shows the store's toasts one at a time, each for about 2.5 seconds (tap to dismiss).
/// While `canShow` is false (the "who wins?" prompt) they wait, so they never give an answer away.
@MainActor
struct AchievementToastLayer: View {
    let store: AchievementStore
    let canShow: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let displaySeconds: Double = 2.5

    var body: some View {
        let toast = canShow ? store.currentToast : nil
        VStack(spacing: 0) {
            if let toast {
                AchievementToastView(toast: toast)
                    .id(toast.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.dismissToast(toast.id)
                    }
                    .task(id: toast.id) {
                        AccessibilityAnnouncer.announce(toast.accessibilityText)
                        try? await Task.sleep(nanoseconds: UInt64(AchievementToastLayer.displaySeconds * 1_000_000_000))
                        if !Task.isCancelled {
                            store.dismissToast(toast.id)
                        }
                    }
                    .transition(reduceMotion ? AnyTransition.opacity
                                             : AnyTransition.move(edge: .top).combined(with: AnyTransition.opacity))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(toast.accessibilityText)
                    .accessibilityHint("Double-tap to dismiss.")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: toast?.id)
    }
}
