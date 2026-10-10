import Foundation
import Observation
import ShengjiCore

/// The learner's persisted progress (lessons, spaced-repetition schedules, stats, coach level).
/// One instance lives for the whole app and is shared through the SwiftUI environment:
/// `@Environment(LearningStore.self) private var learning`.
@MainActor
@Observable
final class LearningStore {
    private(set) var progress: LearnerProgress

    /// Demo/screenshot scenes use an ephemeral store so they never touch saved progress.
    let isEphemeral: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key = "learnerProgress.v1"

    init(defaults: UserDefaults = .standard, ephemeral: Bool = false) {
        self.defaults = defaults
        self.isEphemeral = ephemeral
        if !ephemeral,
           let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(LearnerProgress.self, from: data) {
            progress = saved
        } else {
            progress = LearnerProgress()
        }
    }

    // MARK: Reading

    var coachLevel: CoachLevel {
        get { progress.coachLevel }
        set {
            progress.coachLevel = newValue
            save()
        }
    }

    func dueItemIDs(now: Date = .now) -> [String] { progress.dueItemIDs(now: now) }

    func dueCount(now: Date = .now) -> Int { progress.dueItemIDs(now: now).count }

    func isUnlocked(_ lesson: Lesson) -> Bool { progress.isUnlocked(lesson) }

    func isCompleted(_ lesson: Lesson) -> Bool { progress.completedLessons.contains(lesson.id) }

    func mastery(of itemID: String) -> Double { progress.mastery(of: itemID) }

    /// Average mastery of the items a lesson introduces (0 if it has none or isn't completed).
    func mastery(of lesson: Lesson) -> Double {
        let ids = lesson.itemIDs
        guard !ids.isEmpty, isCompleted(lesson) else { return 0 }
        return ids.map { progress.mastery(of: $0) }.reduce(0, +) / Double(ids.count)
    }

    func streak(now: Date = .now) -> Int { progress.streak(now: now) }

    // MARK: Writing

    func completeLesson(_ lesson: Lesson) {
        progress.completeLesson(lesson, now: .now)
        save()
    }

    /// Records one answered question. Pass `updateSchedule: session.updatesSchedule`.
    func record(itemID: String, correct: Bool, seconds: Double, updateSchedule: Bool) {
        progress.record(itemID: itemID, correct: correct, seconds: seconds, now: .now, updateSchedule: updateSchedule)
        save()
    }

    /// A mistake at the table (e.g. an illegal follow) brings the related skill back for review now.
    func noteGameMistake(_ skill: SkillID) {
        progress.noteGameMistake(skill, now: .now)
        save()
    }

    func recordRoundPlayed() {
        progress.roundsPlayed += 1
        save()
    }

    func recordGameFinished(won: Bool) {
        progress.gamesPlayed += 1
        if won { progress.gamesWon += 1 }
        save()
    }

    /// Used by demo scenes to show a realistic mid-course state (never saved when ephemeral).
    func replaceProgress(_ newProgress: LearnerProgress) {
        progress = newProgress
        save()
    }

    func resetAll() {
        progress = LearnerProgress()
        save()
    }

    private func save() {
        guard !isEphemeral, let data = try? JSONEncoder().encode(progress) else { return }
        defaults.set(data, forKey: key)
    }
}
