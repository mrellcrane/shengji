import SwiftUI
import ShengjiCore

/// Eight short reminders with example cards, opened from the table menu.
@MainActor
struct RulesQuickSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TrumpBadge(trump: GameRuleReminder.exampleTrump)
                } footer: {
                    Text("The examples use this trump: hearts are the trump suit and 2 is the trump rank.")
                }
                ForEach(GameRuleReminder.all) { rule in
                    RulesQuickRow(rule: rule)
                }
            }
            .navigationTitle("Quick rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One reminder: title, a sentence and mini cards.
@MainActor
struct RulesQuickRow: View {
    let rule: GameRuleReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(rule.title)
                .font(.headline)
            Text(rule.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !rule.cards.isEmpty {
                CardRow(cards: rule.cards, cardWidth: 32, spacing: -12,
                        trump: GameRuleReminder.exampleTrump, markTrumps: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(rule.cards.map { $0.face.longName }.joined(separator: ", "))
            }
            if let caption = rule.caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
