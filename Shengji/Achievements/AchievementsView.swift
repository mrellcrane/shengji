import SwiftUI
import ShengjiCore

/// Every badge: an overall progress bar, Moves / Journey, and a grid of badges with progress to the
/// next tier. Tap a badge for what it teaches, an example, the goal and the tiers.
@MainActor
struct AchievementsView: View {
    @Environment(AchievementStore.self) private var store
    @State private var category: AchievementCategory
    @State private var selected: AchievementDefinition?

    init(category: AchievementCategory = .moves) {
        _category = State(initialValue: category)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AchievementsOverallCard(fraction: store.progress.overallFraction,
                                        moves: store.tierCounts(in: .moves),
                                        journey: store.tierCounts(in: .journey))
                Picker("Badges", selection: $category) {
                    ForEach(AchievementCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                Text(blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                AchievementGrid(definitions: store.definitions(in: category), progress: store.progress) { definition in
                    selected = definition
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Achievements")
        .sheet(item: $selected) { definition in
            AchievementDetailView(definition: definition)
                .environment(store)
        }
    }

    private var blurb: String {
        switch category {
        case .moves:
            return "Named moves you pull off at the table. Each badge is a mini lesson: tap one to see how it works."
        case .journey:
            return "Your learning and your games: lessons, streaks, skills you've mastered, levels and wins."
        }
    }
}

/// The overall bar across every badge tier.
@MainActor
private struct AchievementsOverallCard: View {
    let fraction: Double
    let moves: (earned: Int, possible: Int)
    let journey: (earned: Int, possible: Int)

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Overall")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("\(Int((clamped * 100).rounded()))%")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            ProgressView(value: clamped)
                .tint(Theme.gold)
            HStack(spacing: 16) {
                Label("Moves \(moves.earned) of \(moves.possible)", systemImage: "suit.spade.fill")
                Label("Journey \(journey.earned) of \(journey.possible)", systemImage: "map.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .learnCard()
        .accessibilityElement(children: .combine)
    }
}

/// Badges in an adaptive grid.
@MainActor
private struct AchievementGrid: View {
    let definitions: [AchievementDefinition]
    let progress: AchievementProgress
    let onSelect: (AchievementDefinition) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(definitions) { definition in
                Button {
                    onSelect(definition)
                } label: {
                    AchievementCell(definition: definition, progress: progress)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One badge: symbol, title, a bar to the next tier and "3 / 5". Locked badges say how to earn them.
@MainActor
private struct AchievementCell: View {
    let definition: AchievementDefinition
    let progress: AchievementProgress

    var body: some View {
        let tier = progress.tier(for: definition)
        let count = progress.count(for: definition)
        let next = progress.nextThreshold(for: definition)
        let nextTier = AchievementToast.nextTier(after: tier, thresholds: definition.thresholds)?.tier ?? .gold
        VStack(spacing: 8) {
            AchievementBadge(symbol: definition.symbol, tier: tier)
            Text(definition.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.primary)
            ProgressView(value: progress.fractionOfNextThreshold(for: definition))
                .tint(AchievementStyle.color(for: nextTier))
            Text(AchievementStyle.progressText(count: count, next: next))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if tier == .none {
                Text(definition.goal)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .top)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AchievementStyle.color(for: tier).opacity(tier == .none ? 0.15 : 0.5), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(tier: tier, count: count, next: next))
        .accessibilityHint("Shows how it works")
        .accessibilityAddTraits(.isButton)
    }

    private func accessibilityText(tier: AchievementTier, count: Int, next: Int?) -> String {
        var text = "\(definition.title), \(tier == .none ? "not earned yet" : tier.title)"
        if let next {
            text += ", \(count) of \(next) for the next tier"
        }
        if tier == .none { text += ". \(definition.goal)" }
        return text
    }
}

/// A badge up close: what it teaches, an example with real cards, the goal, and the tiers with dates.
@MainActor
struct AchievementDetailView: View {
    let definition: AchievementDefinition

    @Environment(AchievementStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AchievementDetailHeader(definition: definition, progress: store.progress)
                    AchievementLessonCard(definition: definition)
                    goalCard
                    AchievementTiersCard(definition: definition, progress: store.progress) { tier in
                        store.earnedDate(definition, tier: tier)
                    }
                }
                .padding(20)
            }
            .navigationTitle(definition.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var goalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(store.progress.tier(for: definition) == .none ? "How to earn it" : "Goal", systemImage: "target")
                .font(.headline)
            Text(definition.goal)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .learnCard()
    }
}

/// Big badge, title (with the Chinese term for moves), tier and progress to the next tier.
@MainActor
private struct AchievementDetailHeader: View {
    let definition: AchievementDefinition
    let progress: AchievementProgress

    private var chineseTerm: String? {
        if case let .move(kind) = definition.source { return kind.chineseTerm }
        return nil
    }

    var body: some View {
        let tier = progress.tier(for: definition)
        HStack(alignment: .center, spacing: 16) {
            AchievementBadge(symbol: definition.symbol, tier: tier, size: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(definition.title)
                    .font(.title2.weight(.bold))
                if let chineseTerm {
                    Text(chineseTerm)
                        .font(.subheadline)
                        .foregroundStyle(Theme.cardRed)
                }
                Text(tier == .none ? "Not earned yet" : "\(tier.title) badge")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tier == .none ? Color.secondary : AchievementStyle.color(for: tier))
                ProgressView(value: progress.fractionOfNextThreshold(for: definition))
                    .tint(Theme.gold)
                Text(AchievementStyle.progressText(count: progress.count(for: definition),
                                                   next: progress.nextThreshold(for: definition)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the badge teaches, with its example cards.
@MainActor
private struct AchievementLessonCard: View {
    let definition: AchievementDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("What it teaches", systemImage: "lightbulb.fill")
                .font(.headline)
            RichText(definition.lesson)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if let trump = definition.exampleTrump {
                TrumpBadge(trump: trump)
            }
            if !definition.exampleCards.isEmpty {
                LearnCardRows(cards: definition.exampleCards, trump: definition.exampleTrump,
                              markTrumps: definition.exampleTrump != nil, cardWidth: 48, perRow: 6,
                              spacing: definition.exampleCards.count <= 4 ? 8 : -14, alignment: .center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 8)
                    .background(
                        LinearGradient(colors: [Theme.felt, Theme.feltDeep], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Example: " + definition.exampleCards.map { $0.face.longName }.joined(separator: ", "))
            }
        }
        .learnCard()
    }
}

/// Bronze, silver and gold: what each needs and when you earned it.
@MainActor
private struct AchievementTiersCard: View {
    let definition: AchievementDefinition
    let progress: AchievementProgress
    let earnedDate: (AchievementTier) -> Date?

    private struct TierStep: Hashable {
        let tier: AchievementTier
        let threshold: Int
    }

    private var tiers: [TierStep] {
        AchievementTier.allCases.filter { $0 != .none }.compactMap { tier in
            let index = tier.rawValue - 1
            guard definition.thresholds.indices.contains(index) else { return nil }
            return TierStep(tier: tier, threshold: definition.thresholds[index])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tiers", systemImage: "medal.fill")
                .font(.headline)
            ForEach(tiers, id: \.self) { step in
                tierRow(step.tier, threshold: step.threshold)
            }
        }
        .learnCard()
    }

    private func tierRow(_ tier: AchievementTier, threshold: Int) -> some View {
        let reached = progress.tier(for: definition) >= tier
        let date = earnedDate(tier)
        return HStack(spacing: 12) {
            AchievementBadge(symbol: definition.symbol, tier: reached ? tier : .none, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tier.title) · \(threshold)")
                    .font(.subheadline.weight(.semibold))
                if reached, let date {
                    (Text("Earned ") + Text(date, style: .date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(reached ? "Earned" : "Not yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if reached {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.correct)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
