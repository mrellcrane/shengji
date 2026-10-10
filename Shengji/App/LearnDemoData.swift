import Foundation
import ShengjiCore

/// Sample data for demo / screenshot scenes. It only ever goes into the ephemeral store,
/// so a scene never touches saved progress.
enum LearnDemoData {
    /// Seed for the practice question shown by the `quiz` scene.
    static let quizSeed: UInt64 = 7

    /// A learner partway through the course, built through the public `LearnerProgress` API with past dates:
    /// lessons 1 to 5 passed over the last four days, a few items due for review now,
    /// some answer and game stats, and a 4-day streak.
    static func sampleProgress(now: Date = .now, calendar: Calendar = .current) -> LearnerProgress {
        var progress = LearnerProgress()
        let lessons = Array(Curriculum.lessons.prefix(5))

        // Study sessions started two hours ago, and at the same time on each of the previous days.
        let sessionStart = now.addingTimeInterval(-2 * 3600)
        func daysAgo(_ days: Int, plusMinutes minutes: Double = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: sessionStart)
                ?? sessionStart.addingTimeInterval(-Double(days) * 86_400)
            return day.addingTimeInterval(minutes * 60)
        }

        // Pass a lesson, then review its items through the learning steps:
        // right after the lesson, and again about ten minutes later.
        func study(_ lesson: Lesson, at start: Date, missing missed: Set<String> = []) {
            progress.completeLesson(lesson, now: start)
            for (offset, itemID) in lesson.itemIDs.enumerated() {
                let stagger: TimeInterval = Double(offset) * 15
                let firstStep: Date = start.addingTimeInterval(90 + stagger)
                let secondStep: Date = start.addingTimeInterval(720 + stagger)
                if missed.contains(itemID) {
                    progress.record(itemID: itemID, correct: false, seconds: 11, now: firstStep)
                    progress.record(itemID: itemID, correct: true, seconds: 8, now: firstStep.addingTimeInterval(150))
                } else {
                    progress.record(itemID: itemID, correct: true, seconds: 6, now: firstStep)
                }
                progress.record(itemID: itemID, correct: true, seconds: 5, now: secondStep)
            }
        }

        // A daily review of every item the given lessons introduced.
        func review(_ reviewed: [Lesson], at time: Date) {
            for (offset, itemID) in reviewed.flatMap(\.itemIDs).enumerated() {
                progress.record(itemID: itemID, correct: offset % 5 != 3, seconds: 6,
                                now: time.addingTimeInterval(Double(offset) * 20))
            }
        }

        if lessons.count >= 2 {
            study(lessons[0], at: daysAgo(3))
            study(lessons[1], at: daysAgo(3, plusMinutes: 20))
            review(Array(lessons[0...1]), at: daysAgo(2, plusMinutes: 45))
        } else if let only = lessons.first {
            study(only, at: daysAgo(3))
        }
        if lessons.count >= 3 {
            study(lessons[2], at: daysAgo(2, plusMinutes: 55))
            review([lessons[2]], at: daysAgo(1, plusMinutes: 75))
        }
        if lessons.count >= 5 {
            study(lessons[3], at: daysAgo(1, plusMinutes: 80))
            let firstNewItem = lessons[4].itemIDs.first.map { Set([$0]) } ?? []
            study(lessons[4], at: daysAgo(1, plusMinutes: 95), missing: firstNewItem)
        } else if lessons.count == 4 {
            study(lessons[3], at: daysAgo(1, plusMinutes: 80))
        }

        // Today: a little extra practice (it counts for the streak but leaves schedules alone).
        for (offset, itemID) in lessons.prefix(3).flatMap(\.itemIDs).prefix(4).enumerated() {
            progress.record(itemID: itemID, correct: offset != 1, seconds: 7,
                            now: sessionStart.addingTimeInterval(Double(offset) * 30), updateSchedule: false)
        }

        progress.roundsPlayed = 11
        progress.gamesPlayed = 2
        progress.gamesWon = 1

        // Keep the scene's promises even if scheduling details differ: a few items due now...
        if progress.dueItemIDs(now: now).count < 2 {
            let recentItems = lessons.suffix(2).flatMap(\.itemIDs)
            for (offset, itemID) in recentItems.prefix(4).enumerated() where progress.schedules[itemID] != nil {
                let minutesOverdue = Double(10 + offset * 7)
                progress.schedules[itemID]?.due = now.addingTimeInterval(-minutesOverdue * 60)
            }
        }
        // ...and a 4-day streak.
        if progress.streak(now: now, calendar: calendar) < 4 {
            let days = (0..<4).map { dayKey(daysAgo($0), calendar: calendar) }
            progress.studyDays = Array(Set(progress.studyDays).union(days)).sorted()
        }
        return progress
    }

    /// The `lesson` scene: lesson 4 opened at its first page that draws cards.
    static func lessonPage() -> LearnDemoLessonPage? {
        let lessons = Curriculum.lessons
        guard let lesson = lessons.first(where: { $0.number == 4 }) ?? lessons.first else { return nil }
        let page = lesson.pages.firstIndex { page in
            if case .cards = page { return true }
            return false
        } ?? 0
        return LearnDemoLessonPage(lesson: lesson, page: page, answer: nil)
    }

    /// The `predict` scene: a "your turn" page with the right answer chosen (lesson 4 if it has one).
    static func predictPage() -> LearnDemoLessonPage? {
        let lessons = Curriculum.lessons
        let ordered = lessons.filter { $0.number == 4 } + lessons.filter { $0.number != 4 }
        for lesson in ordered {
            for (index, page) in lesson.pages.enumerated() {
                if case let .predict(question) = page {
                    return LearnDemoLessonPage(lesson: lesson, page: index, answer: question.correctChoice)
                }
            }
        }
        return nil
    }

    /// Study-day key in the format `LearnerProgress.studyDays` uses (yyyy-MM-dd, local time).
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// A lesson page to open a demo scene on.
struct LearnDemoLessonPage {
    let lesson: Lesson
    let page: Int
    /// Answer to show as already chosen on a predict page.
    let answer: Int?
}
