import SwiftUI
import ShengjiCore

/// Cards that wrap onto several rows when there are many (lesson examples, hands, quiz visuals).
@MainActor
struct LearnCardRows: View {
    let cards: [Card]
    var trump: Trump? = nil
    /// Gold edge on trumps (needs `trump`).
    var markTrumps: Bool = false
    var cardWidth: CGFloat = 44
    var perRow: Int = 7
    var spacing: CGFloat = -14
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        let rows = Self.rows(of: cards, perRow: perRow)
        VStack(alignment: alignment, spacing: 8) {
            ForEach(rows.indices, id: \.self) { index in
                CardRow(cards: rows[index], cardWidth: cardWidth, spacing: spacing, trump: trump, markTrumps: markTrumps)
            }
        }
    }

    static func rows(of cards: [Card], perRow: Int) -> [[Card]] {
        let size = max(1, perRow)
        return stride(from: 0, to: cards.count, by: size).map { start in
            Array(cards[start..<min(start + size, cards.count)])
        }
    }
}

/// "Your hand": a learner's cards sorted the way the table shows them.
@MainActor
struct LearnHandView: View {
    let cards: [Card]
    let trump: Trump?
    var markTrumps: Bool = false
    var title: String = "Your hand"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LearnCardRows(cards: sortedCards, trump: trump, markTrumps: markTrumps,
                          cardWidth: 44, perRow: 8, spacing: -14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sortedCards: [Card] {
        guard let trump else { return cards }
        return trump.sorted(cards)
    }
}

/// Circular mastery indicator (0...1) with the percentage inside.
@MainActor
struct MasteryRing: View {
    let value: Double
    var size: CGFloat = 34
    var lineWidth: CGFloat = 4

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, clamped))
                .stroke(MasteryBar.color(for: clamped), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((clamped * 100).rounded()))")
                .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mastery \(Int((clamped * 100).rounded())) percent")
    }
}

/// Horizontal mastery bar (0...1).
@MainActor
struct MasteryBar: View {
    let value: Double

    private var clamped: Double { min(max(value, 0), 1) }

    static func color(for value: Double) -> Color {
        if value >= 0.75 { return Theme.correct }
        if value >= 0.4 { return Theme.gold }
        return Theme.themColor
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Self.color(for: clamped))
                    .frame(width: max(6, proxy.size.width * clamped))
            }
        }
        .frame(height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mastery \(Int((clamped * 100).rounded())) percent")
    }
}

/// Right / not quite, with the rule behind the answer.
@MainActor
struct AnswerFeedbackCard: View {
    let correct: Bool
    let title: String
    let explanation: String

    private var tint: Color { correct ? Theme.correct : Theme.wrong }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(tint)
            RichText(explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
    }
}

/// Close button, title and progress bar at the top of a lesson or practice session.
@MainActor
struct LearnFlowTopBar: View {
    let title: String
    var subtitle: String? = nil
    let progress: Double
    var detail: String? = nil
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                VStack(alignment: .leading, spacing: 0) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(Theme.correct)
                .animation(.easeInOut(duration: 0.3), value: progress)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// Buttons pinned to the bottom of a flow (use with `.safeAreaInset(edge: .bottom)`).
@MainActor
struct LearnBottomBar<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

/// The main call to action: full width, prominent.
@MainActor
struct LearnPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.felt)
    }
}

/// A secondary full-width button.
@MainActor
struct LearnSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

/// A small figure with a caption, e.g. "4 · day streak".
@MainActor
struct LearnStatTile: View {
    let value: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Flame and "4-day streak".
@MainActor
struct LearnStreakBadge: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(days > 0 ? Color.orange : Color.secondary)
            Text(days > 0 ? TimePhrase.streak(days) : "Start a streak today")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(days > 0 ? 0.15 : 0.06), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Checklist bullets.
@MainActor
struct LearnBulletList: View {
    let items: [String]
    var symbol: String = "circle.fill"
    var symbolColor: Color = .secondary
    var symbolSize: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol)
                        .font(.system(size: symbolSize))
                        .foregroundStyle(symbolColor)
                    RichText(item)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension View {
    /// Rounded, lightly tinted panel used for cards on the Learn, Review and Rules tabs.
    func learnCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
