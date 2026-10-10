import SwiftUI
import ShengjiCore

/// "Why this works": the learning science behind the app, one or two plain sentences each.
@MainActor
struct WhyThisWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("This app is built on how memory works. Here's what that means for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(LearningPrinciple.all) { principle in
                        PrincipleRow(principle: principle)
                    }
                }
            }
            .navigationTitle("Why this works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

@MainActor
private struct PrincipleRow: View {
    let principle: LearningPrinciple

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: principle.symbol)
                .font(.title3)
                .foregroundStyle(Theme.correct)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(principle.title)
                    .font(.headline)
                Text(principle.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
