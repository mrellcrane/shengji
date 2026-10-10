import SwiftUI
import ShengjiCore

/// Tier colours: none grey, then bronze, silver and gold.
enum AchievementStyle {
    static let bronze = Color(red: 0.80, green: 0.50, blue: 0.24)
    static let silver = Color(red: 0.60, green: 0.64, blue: 0.70)

    static func color(for tier: AchievementTier) -> Color {
        switch tier {
        case .none: return Color.gray
        case .bronze: return bronze
        case .silver: return silver
        case .gold: return Theme.gold
        }
    }

    /// "3 / 5", or "Gold · 27" once the top tier is reached.
    static func progressText(count: Int, next: Int?) -> String {
        if let next { return "\(count) / \(next)" }
        return "Gold · \(count)"
    }
}

/// The badge: an SF Symbol in a circle tinted by tier (grey with a small lock until earned).
@MainActor
struct AchievementBadge: View {
    let symbol: String
    let tier: AchievementTier
    var size: CGFloat = 56

    private var color: Color { AchievementStyle.color(for: tier) }
    private var isLocked: Bool { tier == .none }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(isLocked ? 0.12 : 0.2))
            Circle()
                .strokeBorder(color.opacity(isLocked ? 0.45 : 1), lineWidth: isLocked ? 1.5 : max(2, size * 0.055))
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(isLocked ? Color.secondary : color)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if isLocked && size >= 40 {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.2, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(size * 0.06)
                    .background(Circle().fill(Color.gray))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A progress card linking to the achievements: an overall bar and the badges earned most recently.
/// Used on the Play tab ("Your moves") and the Review tab ("Journey").
@MainActor
struct AchievementSummaryCard: View {
    let title: String
    let systemImage: String
    let fraction: Double
    let earned: Int
    let possible: Int
    let recent: [EarnedBadge]
    /// Shown while nothing is earned yet.
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text("\(earned) of \(possible)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(Theme.gold)
            if recent.isEmpty {
                Text(emptyText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                recentRow
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var recentRow: some View {
        HStack(spacing: 8) {
            ForEach(recent) { badge in
                AchievementBadge(symbol: badge.definition.symbol, tier: badge.tier, size: 30)
            }
            Text(recentText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var recentText: String {
        guard let first = recent.first else { return "" }
        return "Latest: \(first.definition.title) · \(first.tier.title)"
    }

    private var accessibilityText: String {
        let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
        var text = "\(title). \(earned) of \(possible) badge tiers earned, \(percent) percent."
        if !recentText.isEmpty { text += " \(recentText)." }
        return text
    }
}
