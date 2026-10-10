import SwiftUI
import ShengjiCore

/// What a practice session should run, for presenting `PracticeView` full screen.
struct PracticeLaunch: Identifiable {
    let id = UUID()
    let kind: PracticeSession.Kind
    /// Fixes the questions (demo scenes); random when nil.
    var seed: UInt64? = nil
    /// Demo only: answers the first question wrongly so its feedback shows.
    var answerFirstQuestionWrongly = false
}

/// The Review tab: streak and due count, the daily review (or extra practice when you're caught up),
/// and how well you know each unlocked skill.
@MainActor
struct ReviewView: View {
    @Environment(LearningStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var launch: PracticeLaunch?

    /// - Parameter initialPractice: a session to open straight away, the same way a tap opens it
    ///   (used by the `quiz` demo scene, so closing it returns to the Review tab).
    init(initialPractice: PracticeLaunch? = nil) {
        _launch = State(initialValue: initialPractice)
    }

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                ReviewContent(now: context.date) { kind in
                    launch = PracticeLaunch(kind: kind)
                }
            }
            .navigationTitle("Review")
        }
        .fullScreenCover(item: $launch) { launch in
            PracticeView(kind: launch.kind, seed: launch.seed,
                         answerFirstQuestionWrongly: launch.answerFirstQuestionWrongly)
                .environment(store)
                .environment(router)
        }
    }
}

@MainActor
private struct ReviewContent: View {
    @Environment(LearningStore.self) private var store
    @Environment(AppRouter.self) private var router
    let now: Date
    let onStart: (PracticeSession.Kind) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.progress.completedLessons.isEmpty {
                    emptyState
                } else {
                    statsRow
                    sessionCard
                    ReviewItemList(itemIDs: store.progress.unlockedItemIDs) { skill in
                        onStart(.freePractice(skills: [skill]))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            LearnStatTile(value: "\(store.streak(now: now))", label: "day streak",
                          systemImage: "flame.fill", tint: .orange)
            LearnStatTile(value: "\(store.dueCount(now: now))", label: "due now",
                          systemImage: "arrow.triangle.2.circlepath", tint: Theme.usColor)
            LearnStatTile(value: "\(store.progress.completedLessons.count)", label: "lessons passed",
                          systemImage: "graduationcap.fill", tint: Theme.correct)
        }
    }

    @ViewBuilder private var sessionCard: some View {
        let due = store.dueCount(now: now)
        if due > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Time to review")
                    .font(.title3.weight(.bold))
                Text("Quick questions on what you've learned. Recalling it just as it starts to fade is what makes it last.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LearnPrimaryButton(title: "Start review (\(due))", systemImage: "play.fill") {
                    onStart(.review)
                }
            }
            .learnCard()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("All caught up", systemImage: "checkmark.circle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.correct)
                Text(nextDueText)
                    .font(.subheadline)
                LearnSecondaryButton(title: "Extra practice", systemImage: "dumbbell.fill") {
                    onStart(.freePractice(skills: []))
                }
                Text("Extra practice doesn't change your review schedule.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .learnCard()
        }
    }

    private var nextDueText: String {
        guard let next = store.progress.nextDueDate(after: now) else {
            return "Nothing is scheduled. Pass another lesson to add new skills."
        }
        return "Your next review is due \(TimePhrase.until(next, from: now))."
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.correct)
                .padding(.top, 48)
            Text("Nothing to review yet")
                .font(.title2.weight(.bold))
            Text("Pass your first lesson and its ideas will show up here, spaced out so they stick.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            LearnPrimaryButton(title: "Go to the lessons", systemImage: "arrow.right") {
                router.show(.learn)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Unlocked skills (tap to practise just that one) and facts, each with a mastery bar.
@MainActor
private struct ReviewItemList: View {
    @Environment(LearningStore.self) private var store
    let itemIDs: [String]
    let onPractice: (SkillID) -> Void

    private var skills: [SkillID] { itemIDs.compactMap(SkillID.init(itemID:)) }
    private var factIDs: [String] { itemIDs.filter { SkillID(itemID: $0) == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !skills.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your skills")
                        .font(.title3.weight(.bold))
                    Text("Tap one to practise just that.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    ForEach(skills, id: \.self) { skill in
                        Button {
                            onPractice(skill)
                        } label: {
                            ReviewItemRow(title: skill.title, mastery: store.mastery(of: skill.itemID), isTappable: true)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            if !factIDs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Facts")
                        .font(.title3.weight(.bold))
                        .padding(.bottom, 4)
                    ForEach(factIDs, id: \.self) { itemID in
                        ReviewItemRow(title: ItemNames.title(for: itemID), mastery: store.mastery(of: itemID), isTappable: false)
                        Divider()
                    }
                }
            }
        }
    }
}

@MainActor
private struct ReviewItemRow: View {
    let title: String
    let mastery: Double
    let isTappable: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                MasteryBar(value: mastery)
            }
            Text(percentText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "75%" (a plain string, so the percent sign is never read as a format specifier).
    private var percentText: String {
        "\(Int((min(max(mastery, 0), 1) * 100).rounded()))%"
    }
}
