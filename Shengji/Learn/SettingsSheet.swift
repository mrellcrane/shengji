import SwiftUI
import ShengjiCore

/// Coach level, progress (with reset) and about.
@MainActor
struct SettingsSheet: View {
    @Environment(LearningStore.self) private var store
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                coachSection
                progressSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all progress?", isPresented: $confirmsReset, titleVisibility: .visible) {
                Button("Reset progress", role: .destructive) {
                    achievements.resetAll()
                    store.resetAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears your lessons, review schedule, streak, stats and badges. It can't be undone.")
            }
        }
    }

    private var coachSection: some View {
        Section {
            ForEach(CoachLevel.allCases, id: \.self) { level in
                Button {
                    store.coachLevel = level
                } label: {
                    CoachLevelRow(level: level, isSelected: store.coachLevel == level)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Coach at the table")
        } footer: {
            Text("Start with Guided. As the help starts to feel unnecessary, switch to Coached, then Solo.")
        }
    }

    private var progressSection: some View {
        Section("Your progress") {
            LabeledContent("Lessons passed",
                           value: "\(store.progress.completedLessons.count) of \(Curriculum.lessons.count)")
            LabeledContent("Streak", value: TimePhrase.streak(store.streak()))
            LabeledContent("Games won", value: "\(store.progress.gamesWon) of \(store.progress.gamesPlayed)")
            Button("Reset progress", role: .destructive) {
                confirmsReset = true
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shengji · Tractor")
                    .font(.headline)
                Text("升级 (shēngjí) · 拖拉机 (tuōlājī)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Learn the game in short lessons, keep it fresh with spaced reviews, then practise against friendly bots. Your progress stays on this device.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            if store.isEphemeral {
                Text("Demo mode: nothing you change here is saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Version", value: appVersion)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

@MainActor
private struct CoachLevelRow: View {
    let level: CoachLevel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .font(.body.weight(.semibold))
                Text(level.blurb)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.bold))
                    .foregroundStyle(Theme.correct)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
