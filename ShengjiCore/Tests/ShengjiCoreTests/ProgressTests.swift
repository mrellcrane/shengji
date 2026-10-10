import XCTest
@testable import ShengjiCore

/// Shared fixtures for the learning-core tests. Nothing here touches `Curriculum` or `Drills`.
enum LearningCoreFixtures {
    static let day: TimeInterval = 86_400
    /// 2026-10-10 12:00 UTC.
    static let t0 = Date(timeIntervalSince1970: 1_791_633_600)

    static func calendar(_ seconds: Int = 0) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: seconds) ?? c.timeZone
        return c
    }

    static let utc = calendar(0)
    static let tokyo = calendar(9 * 3_600)
    static let losAngeles = calendar(-7 * 3_600)

    static func lesson(_ number: Int, skills: [SkillID] = [], facts: [String] = []) -> Lesson {
        Lesson(id: "lesson.\(number)", number: number, title: "Lesson \(number)", subtitle: "", chineseTerm: nil,
               estimatedMinutes: 3, pages: [], skills: skills, factIDs: facts)
    }

    static let lesson1 = lesson(1, facts: ["fact.teams", "fact.goal", "fact.threshold"])
    static let lesson2 = lesson(2, skills: [.pointValue, .countPoints])
    static let lesson3 = lesson(3, skills: [.isTrump])
    static let lesson4 = lesson(4, skills: [.trumpOrder])
    static let lesson6 = lesson(6, skills: [.isPair, .legalFollow], facts: ["fact.pairRule"])
    static let lesson9 = lesson(9, skills: [.cardBeats, .isTractor, .trickWinner, .kittyBonus],
                                facts: ["fact.declare", "fact.kitty", "fact.bury"])
    static let lessons: [String: Lesson] = Dictionary(
        uniqueKeysWithValues: [lesson1, lesson2, lesson3, lesson4, lesson6, lesson9].map { ($0.id, $0) })

    /// A fake question for any item id except ones starting with "missing.".
    static let fakeQuestions: PracticeSession.QuestionProvider = { itemID, difficulty, seed in
        if itemID.hasPrefix("missing.") { return nil }
        return Question(id: "\(itemID)#\(seed)", itemID: itemID, prompt: "Question about \(itemID)", trump: nil,
                        visual: .none, choices: [Choice("Yes"), Choice("No")], correctChoice: 0,
                        explanation: "Because that is the rule.", difficulty: difficulty)
    }
    static let fakeLessons: PracticeSession.LessonProvider = { lessons[$0] }

    /// Progress after completing the given lessons at `t0`.
    static func progress(completing done: [Lesson], at now: Date = t0) -> LearnerProgress {
        var p = LearnerProgress()
        for l in done { p.completeLesson(l, now: now, scheduler: Scheduler(), calendar: utc) }
        return p
    }

    static func graduated(_ id: String, interval: Double, due: Date, reps: Int = 3) -> ItemSchedule {
        ItemSchedule(itemID: id, due: due, intervalDays: interval, ease: 2.5, reps: reps, lapses: 0,
                     learningStep: nil, lastReviewed: nil)
    }
}

final class ProgressTests: XCTestCase {
    private typealias F = LearningCoreFixtures
    private let t0 = LearningCoreFixtures.t0
    private let day = LearningCoreFixtures.day

    // MARK: Basics

    func testNewProgressIsEmptyAndGuided() {
        let p = LearnerProgress()
        XCTAssertTrue(p.completedLessons.isEmpty)
        XCTAssertTrue(p.schedules.isEmpty)
        XCTAssertTrue(p.stats.isEmpty)
        XCTAssertTrue(p.studyDays.isEmpty)
        XCTAssertEqual(p.coachLevel, .guided)
        XCTAssertEqual(p.gamesPlayed, 0)
        XCTAssertEqual(p.gamesWon, 0)
        XCTAssertEqual(p.roundsPlayed, 0)
        XCTAssertTrue(p.unlockedItemIDs.isEmpty)
        XCTAssertTrue(p.dueItemIDs(now: t0).isEmpty)
        XCTAssertNil(p.nextDueDate(after: t0))
        XCTAssertEqual(p.streak(now: t0, calendar: F.utc), 0)
    }

    func testCoachLevelTextIsShortAndFriendly() {
        XCTAssertEqual(CoachLevel.guided.title, "Guided")
        XCTAssertEqual(CoachLevel.coached.title, "Coached")
        XCTAssertEqual(CoachLevel.solo.title, "Solo")
        XCTAssertEqual(CoachLevel.guided.blurb, "Legal cards lit up, trumps marked, every trick explained.")
        for level in CoachLevel.allCases {
            XCTAssertFalse(level.blurb.isEmpty)
            XCTAssertLessThan(level.blurb.count, 70)
            XCTAssertFalse(level.blurb.contains("\u{2014}"))
            XCTAssertFalse(level.title.contains("\u{2014}"))
        }
        XCTAssertEqual(Set(CoachLevel.allCases.map(\.blurb)).count, 3)
    }

    // MARK: Unlocking and lessons

    func testLessonOneIsAlwaysUnlockedAndLaterLessonsAreGated() {
        var p = LearnerProgress()
        XCTAssertTrue(p.isUnlocked(F.lesson1))
        XCTAssertFalse(p.isUnlocked(F.lesson2))
        XCTAssertFalse(p.isUnlocked(F.lesson3))
        p.completeLesson(F.lesson1, now: t0, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertTrue(p.isUnlocked(F.lesson2))
        XCTAssertFalse(p.isUnlocked(F.lesson3))
        p.completeLesson(F.lesson2, now: t0, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertTrue(p.isUnlocked(F.lesson3))
        XCTAssertFalse(p.isUnlocked(F.lesson6), "Lesson 6 needs lesson 5, not just any earlier lesson")
    }

    func testCompletedLessonStaysUnlocked() {
        var p = LearnerProgress()
        p.completedLessons = ["lesson.6"]
        XCTAssertTrue(p.isUnlocked(F.lesson6))
    }

    func testCompleteLessonSchedulesItemsDueNowAtFirstStep() {
        var p = LearnerProgress()
        p.completeLesson(F.lesson6, now: t0, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.completedLessons, ["lesson.6"])
        XCTAssertEqual(Set(p.schedules.keys), ["skill.isPair", "skill.legalFollow", "fact.pairRule"])
        for (id, s) in p.schedules {
            XCTAssertEqual(s.itemID, id)
            XCTAssertEqual(s.due, t0)
            XCTAssertEqual(s.learningStep, 0)
            XCTAssertEqual(s.reps, 0)
        }
        XCTAssertEqual(p.unlockedItemIDs, ["skill.isPair", "skill.legalFollow", "fact.pairRule"])
        XCTAssertEqual(p.studyDays, ["2026-10-10"])
    }

    func testCompleteLessonUsesGivenScheduler() {
        var p = LearnerProgress()
        p.completeLesson(F.lesson3, now: t0, scheduler: Scheduler(startingEase: 2.0), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.ease, 2.0)
    }

    func testCompletingAgainNeverResetsExistingSchedules() {
        var p = F.progress(completing: [F.lesson3])
        p.record(itemID: "skill.isTrump", correct: true, seconds: 3, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        let before = p.schedules["skill.isTrump"]
        XCTAssertEqual(before?.learningStep, 1, "Moved on a step")
        p.completeLesson(F.lesson3, now: t0.addingTimeInterval(day), scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isTrump"], before)
        XCTAssertEqual(p.unlockedItemIDs, ["skill.isTrump"])
        XCTAssertEqual(p.studyDays, ["2026-10-10", "2026-10-11"])
    }

    func testUnlockedItemIDsFollowLessonOrder() {
        let p = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4])
        XCTAssertEqual(p.unlockedItemIDs, ["fact.teams", "fact.goal", "fact.threshold",
                                           "skill.pointValue", "skill.countPoints", "skill.isTrump",
                                           "skill.trumpOrder"])
    }

    func testItemSharedByTwoLessonsKeepsItsFirstPosition() {
        var p = F.progress(completing: [F.lesson3, F.lesson4])
        let review = F.lesson(5, skills: [.cardBeats, .isTrump])
        p.completeLesson(review, now: t0, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.unlockedItemIDs, ["skill.isTrump", "skill.trumpOrder", "skill.cardBeats"])
    }

    func testUnlockedItemIDsCoverSchedulesSetDirectly() {
        var p = F.progress(completing: [F.lesson3])
        p.schedules["fact.extra"] = Scheduler().newSchedule(itemID: "fact.extra", now: t0)
        p.schedules["skill.pointValue"] = Scheduler().newSchedule(itemID: "skill.pointValue", now: t0)
        XCTAssertEqual(p.unlockedItemIDs, ["skill.isTrump", "skill.pointValue", "fact.extra"])
        p.schedules["skill.isTrump"] = nil
        XCTAssertEqual(p.unlockedItemIDs, ["skill.pointValue", "fact.extra"])
    }

    // MARK: Due items

    func testDueItemsAreMostOverdueFirstWithStableTies() {
        var p = LearnerProgress()
        p.schedules = [
            "b": F.graduated("b", interval: 1, due: t0.addingTimeInterval(-60)),
            "a": F.graduated("a", interval: 1, due: t0.addingTimeInterval(-60)),
            "c": F.graduated("c", interval: 1, due: t0.addingTimeInterval(-3 * day)),
            "d": F.graduated("d", interval: 1, due: t0),
            "e": F.graduated("e", interval: 1, due: t0.addingTimeInterval(1)),
        ]
        XCTAssertEqual(p.dueItemIDs(now: t0), ["c", "a", "b", "d"])
        XCTAssertEqual(p.dueItemIDs(now: t0.addingTimeInterval(-4 * day)), [])
    }

    func testNextDueDateIsEarliestFutureDue() {
        var p = LearnerProgress()
        XCTAssertNil(p.nextDueDate(after: t0))
        p.schedules["past"] = F.graduated("past", interval: 1, due: t0.addingTimeInterval(-10))
        p.schedules["now"] = F.graduated("now", interval: 1, due: t0)
        XCTAssertNil(p.nextDueDate(after: t0), "Items due now are not in the future")
        p.schedules["later"] = F.graduated("later", interval: 1, due: t0.addingTimeInterval(2 * day))
        p.schedules["soon"] = F.graduated("soon", interval: 1, due: t0.addingTimeInterval(600))
        XCTAssertEqual(p.nextDueDate(after: t0), t0.addingTimeInterval(600))
    }

    // MARK: Recording answers

    func testRecordCountsAnswersAndKeepsTenRecent() {
        var p = LearnerProgress()
        let answers = [false, true, true, false, true, true, true, false, true, true, false, true]
        for (i, ok) in answers.enumerated() {
            p.record(itemID: "skill.isTrump", correct: ok, seconds: 5, now: t0.addingTimeInterval(Double(i)),
                     updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        }
        let s = p.stats["skill.isTrump"]
        XCTAssertEqual(s?.attempts, 12)
        XCTAssertEqual(s?.correct, 8)
        XCTAssertEqual(s?.recent, Array(answers.suffix(10)))
        XCTAssertEqual(s?.accuracy ?? 0, 8.0 / 12.0, accuracy: 1e-9)
        XCTAssertTrue(p.schedules.isEmpty, "Recording never schedules an item by itself")
        XCTAssertEqual(p.studyDays, ["2026-10-10"])
    }

    func testRecordGradesSkillsAgainstTwelveSecondsAndFactsAgainstEight() {
        var p = F.progress(completing: [F.lesson6])
        // 5 s at the first review a day after the lesson: under half of 12 (easy, graduates to 4 days)
        // but not under half of 8 (good, next step).
        let nextDay = t0.addingTimeInterval(day)
        p.record(itemID: "skill.isPair", correct: true, seconds: 5, now: nextDay, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        p.record(itemID: "fact.pairRule", correct: true, seconds: 5, now: nextDay, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertNil(p.schedules["skill.isPair"]?.learningStep)
        XCTAssertEqual(p.schedules["skill.isPair"]?.intervalDays, 4)
        XCTAssertEqual(p.schedules["fact.pairRule"]?.learningStep, 1)

        // 17 s on graduated items: slow for a fact (over 16, hard) but fine for a skill (good).
        var q = F.progress(completing: [F.lesson6])
        q.schedules["skill.legalFollow"] = F.graduated("skill.legalFollow", interval: 4, due: t0)
        q.schedules["fact.pairRule"] = F.graduated("fact.pairRule", interval: 4, due: t0)
        q.record(itemID: "skill.legalFollow", correct: true, seconds: 17, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        q.record(itemID: "fact.pairRule", correct: true, seconds: 17, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(q.schedules["skill.legalFollow"]?.intervalDays ?? 0, 10, accuracy: 1e-9, "Good: 4 × 2.5")
        XCTAssertEqual(q.schedules["fact.pairRule"]?.intervalDays ?? 0, 4.8, accuracy: 1e-9, "Hard: 4 × 1.2")
    }

    func testWrongAnswerMakesGraduatedItemLapse() {
        var p = F.progress(completing: [F.lesson3])
        p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 10, due: t0)
        p.record(itemID: "skill.isTrump", correct: false, seconds: 4, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        let s = p.schedules["skill.isTrump"]
        XCTAssertEqual(s?.lapses, 1)
        XCTAssertEqual(s?.isRelearning, true)
        XCTAssertEqual(s?.due, t0.addingTimeInterval(600))
    }

    func testRecordWithoutScheduleUpdateLeavesScheduleAlone() {
        var p = F.progress(completing: [F.lesson3])
        let before = p.schedules["skill.isTrump"]
        p.record(itemID: "skill.isTrump", correct: false, seconds: 4, now: t0, updateSchedule: false,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isTrump"], before)
        XCTAssertEqual(p.stats["skill.isTrump"]?.attempts, 1)
    }

    func testPublicRecordUsesDefaults() {
        var p = LearnerProgress()
        p.completeLesson(F.lesson3, now: t0)
        p.record(itemID: "skill.isTrump", correct: true, seconds: 8, now: t0)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.learningStep, 1)
        XCTAssertEqual(p.studyDays.count, 1)
    }

    func testStudyDaysAreUniqueAndSortedEvenIfTheClockGoesBack() {
        var p = LearnerProgress()
        for offset in [0.0, 0.1, 2, 1, 2, -5] {
            p.record(itemID: "fact.goal", correct: true, seconds: 3, now: t0.addingTimeInterval(offset * day),
                     updateSchedule: false, scheduler: Scheduler(), calendar: F.utc)
        }
        XCTAssertEqual(p.studyDays, ["2026-10-05", "2026-10-10", "2026-10-11", "2026-10-12"])
    }

    func testStudyDayUsesTheLocalCalendarDay() {
        let lateUTC = Date(timeIntervalSince1970: 1_791_675_000) // 2026-10-10 23:30 UTC
        XCTAssertEqual(LearnerProgress.dayKey(for: lateUTC, calendar: F.utc), "2026-10-10")
        XCTAssertEqual(LearnerProgress.dayKey(for: lateUTC, calendar: F.tokyo), "2026-10-11")
        XCTAssertEqual(LearnerProgress.dayKey(for: lateUTC, calendar: F.losAngeles), "2026-10-10")
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = F.utc.timeZone
        XCTAssertEqual(LearnerProgress.dayKey(for: lateUTC, calendar: buddhist), "2026-10-10",
                       "Keys are Gregorian whatever calendar the device uses")
        var p = LearnerProgress()
        p.record(itemID: "fact.goal", correct: true, seconds: 3, now: lateUTC, updateSchedule: false,
                 scheduler: Scheduler(), calendar: F.tokyo)
        XCTAssertEqual(p.studyDays, ["2026-10-11"])
    }

    // MARK: Game mistakes

    func testGameMistakeMakesScheduledSkillDueNow() {
        var p = F.progress(completing: [F.lesson6])
        let later = F.graduated("skill.legalFollow", interval: 12, due: t0.addingTimeInterval(9 * day))
        p.schedules["skill.legalFollow"] = later
        p.noteGameMistake(.legalFollow, now: t0)
        let s = p.schedules["skill.legalFollow"]
        XCTAssertEqual(s?.due, t0)
        XCTAssertEqual(s?.ease, later.ease)
        XCTAssertEqual(s?.intervalDays, later.intervalDays)
        XCTAssertEqual(s?.lapses, 0)
        XCTAssertTrue(p.dueItemIDs(now: t0).contains("skill.legalFollow"))
    }

    func testGameMistakeKeepsAnEarlierDueDate() {
        var p = LearnerProgress()
        let overdue = F.graduated("skill.isPair", interval: 2, due: t0.addingTimeInterval(-day))
        p.schedules["skill.isPair"] = overdue
        p.noteGameMistake(.isPair, now: t0)
        XCTAssertEqual(p.schedules["skill.isPair"], overdue)
    }

    func testGameMistakeOnUnscheduledSkillDoesNothing() {
        var p = F.progress(completing: [F.lesson3])
        let before = p
        p.noteGameMistake(.bestPlay, now: t0)
        XCTAssertEqual(p, before)
    }

    /// A graduated skill last reviewed 2 days before `t0` with a 10-day interval (originally due at t0 + 8 days).
    private func onTimeLegalFollow() -> ItemSchedule {
        let last = t0.addingTimeInterval(-2 * day)
        return ItemSchedule(itemID: "skill.legalFollow", due: last.addingTimeInterval(10 * day), intervalDays: 10,
                            ease: 2.5, reps: 4, lapses: 0, learningStep: nil, lastReviewed: last)
    }

    func testRightAnswerAfterAGameMistakeKeepsTheOriginalSchedule() {
        var p = F.progress(completing: [F.lesson6])
        let original = onTimeLegalFollow()
        p.schedules["skill.legalFollow"] = original
        p.noteGameMistake(.legalFollow, now: t0)
        XCTAssertTrue(p.dueItemIDs(now: t0).contains("skill.legalFollow"))
        p.record(itemID: "skill.legalFollow", correct: true, seconds: 3, now: t0.addingTimeInterval(60),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        let s = p.schedules["skill.legalFollow"]
        XCTAssertEqual(s?.intervalDays, 10, "Reviewing early must not grow the interval")
        XCTAssertEqual(s?.due, original.due, "Back on its original date")
        XCTAssertEqual(s?.ease, original.ease)
        XCTAssertFalse(p.dueItemIDs(now: t0.addingTimeInterval(120)).contains("skill.legalFollow"))
        XCTAssertEqual(p.stats["skill.legalFollow"]?.attempts, 1, "The answer still counts in the stats")
    }

    func testRepeatedGameMistakesNeverPushASkillFurtherAway() {
        var p = F.progress(completing: [F.lesson6])
        p.schedules["skill.legalFollow"] = onTimeLegalFollow()
        var now = t0
        for _ in 0..<6 {
            p.noteGameMistake(.legalFollow, now: now)
            now = now.addingTimeInterval(300)
            p.record(itemID: "skill.legalFollow", correct: true, seconds: 3, now: now, updateSchedule: true,
                     scheduler: Scheduler(), calendar: F.utc)
            now = now.addingTimeInterval(3_600)
        }
        XCTAssertEqual(p.schedules["skill.legalFollow"]?.intervalDays, 10)
        XCTAssertEqual(p.schedules["skill.legalFollow"]?.due, onTimeLegalFollow().due)
    }

    func testWrongAnswerAfterAGameMistakeIsALapse() {
        var p = F.progress(completing: [F.lesson6])
        p.schedules["skill.legalFollow"] = onTimeLegalFollow()
        p.noteGameMistake(.legalFollow, now: t0)
        p.record(itemID: "skill.legalFollow", correct: false, seconds: 3, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        let s = p.schedules["skill.legalFollow"]
        XCTAssertEqual(s?.lapses, 1)
        XCTAssertEqual(s?.intervalDays, 5)
        XCTAssertEqual(s?.due, t0.addingTimeInterval(600))
    }

    func testGameMistakeOnALearningItemJustBringsItsStepForward() {
        var p = F.progress(completing: [F.lesson6])
        p.record(itemID: "skill.isPair", correct: true, seconds: 8, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isPair"]?.due, t0.addingTimeInterval(600))
        let later = t0.addingTimeInterval(120)
        p.noteGameMistake(.isPair, now: later)
        XCTAssertEqual(p.schedules["skill.isPair"]?.due, later)
        p.record(itemID: "skill.isPair", correct: true, seconds: 8, now: later.addingTimeInterval(30),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertNil(p.schedules["skill.isPair"]?.learningStep, "Learning steps carry on as usual")
        XCTAssertEqual(p.schedules["skill.isPair"]?.intervalDays, 1)
    }

    func testOnTimeReviewOfAGraduatedItemStillGrows() {
        var p = F.progress(completing: [F.lesson6])
        let s = onTimeLegalFollow()
        p.schedules["skill.legalFollow"] = s
        p.record(itemID: "skill.legalFollow", correct: true, seconds: 8, now: s.due, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.legalFollow"]?.intervalDays, 25)
    }

    // MARK: Answers before an item is due (in-session retries)

    func testQuickRetryOfAMissedNewItemDoesNotGraduateIt() {
        var p = F.progress(completing: [F.lesson3])
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        let missed = p.schedules["skill.isTrump"]
        XCTAssertEqual(missed?.due, t0.addingTimeInterval(60))
        // The retry comes back a few questions later, before the 1-minute step is up, and is answered fast.
        p.record(itemID: "skill.isTrump", correct: true, seconds: 2, now: t0.addingTimeInterval(30),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isTrump"], missed, "A retry before the item is due moves nothing")
        XCTAssertEqual(p.stats["skill.isTrump"]?.recent, [false, true])
    }

    func testQuickRetryAfterALapseCannotLengthenTheInterval() {
        var p = F.progress(completing: [F.lesson3])
        p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 2, due: t0)
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        p.record(itemID: "skill.isTrump", correct: true, seconds: 1, now: t0.addingTimeInterval(40),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        let s = p.schedules["skill.isTrump"]
        XCTAssertEqual(s?.isRelearning, true)
        XCTAssertEqual(s?.due, t0.addingTimeInterval(600), "Still waits for the 10-minute relearning step")
        // Once the relearning step is up, a right answer re-graduates to the reduced interval.
        p.record(itemID: "skill.isTrump", correct: true, seconds: 9, now: t0.addingTimeInterval(600),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertNil(p.schedules["skill.isTrump"]?.learningStep)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.intervalDays ?? 0, 1, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(p.schedules["skill.isTrump"]?.intervalDays ?? 99, 2,
                                 "A lapse never ends with a longer interval than before")
    }

    func testWrongAnswerBeforeDueStillCounts() {
        var p = F.progress(completing: [F.lesson3])
        p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 6, due: t0)
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        let retry = t0.addingTimeInterval(45)
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: retry, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        let s = p.schedules["skill.isTrump"]
        XCTAssertEqual(s?.due, retry.addingTimeInterval(600), "Missing it again restarts the relearning step")
        XCTAssertEqual(s?.lapses, 1, "Still only one lapse")
        XCTAssertEqual(s?.intervalDays ?? 0, 3, accuracy: 1e-9)
    }

    func testRetryAfterTheStepIsUpMovesTheItemOn() {
        var p = F.progress(completing: [F.lesson3])
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        p.record(itemID: "skill.isTrump", correct: true, seconds: 9, now: t0.addingTimeInterval(61),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.learningStep, 1)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.due, t0.addingTimeInterval(661))
    }

    func testFastRightAnswerAfterAMissStillTakesTheNextStep() {
        var p = F.progress(completing: [F.lesson3])
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        // Answered in 2 seconds once the 1-minute step is up: still learning, so no jump straight to 4 days.
        p.record(itemID: "skill.isTrump", correct: true, seconds: 2, now: t0.addingTimeInterval(61),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.learningStep, 1)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.due, t0.addingTimeInterval(661))
    }

    // MARK: Learning steps: one step per right answer

    func testSlowButRightAnswersStillTakeEachLearningStep() {
        // 26 s on a skill (over 2 × 12 s) and 17 s on a fact (over 2 × 8 s): slow, but right every time.
        for (id, seconds) in [("skill.legalFollow", 26.0), ("fact.pairRule", 17.0)] {
            var p = F.progress(completing: [F.lesson6])
            p.record(itemID: id, correct: true, seconds: seconds, now: t0, updateSchedule: true,
                     scheduler: Scheduler(), calendar: F.utc)
            XCTAssertEqual(p.schedules[id]?.learningStep, 1, "\(id): a slow right answer still moves on a step")
            XCTAssertEqual(p.schedules[id]?.due, t0.addingTimeInterval(600), id)
            p.record(itemID: id, correct: true, seconds: seconds, now: t0.addingTimeInterval(600), updateSchedule: true,
                     scheduler: Scheduler(), calendar: F.utc)
            XCTAssertNil(p.schedules[id]?.learningStep, "\(id): graduates after the 10-minute step")
            XCTAssertEqual(p.schedules[id]?.intervalDays, 1, id)
        }
    }

    func testSlowButRightAnswerAfterALapseReGraduates() {
        var p = F.progress(completing: [F.lesson3])
        p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 6, due: t0)
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        p.record(itemID: "skill.isTrump", correct: true, seconds: 30, now: t0.addingTimeInterval(600),
                 updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertNil(p.schedules["skill.isTrump"]?.learningStep)
        XCTAssertEqual(p.schedules["skill.isTrump"]?.intervalDays ?? 0, 3, accuracy: 1e-9)
    }

    func testFastFirstReviewRightAfterTheLessonStillTakesTheSteps() {
        // The lesson quiz asked these a moment ago, so a quick answer now is short-term memory.
        var p = F.progress(completing: [F.lesson6])
        let soon = t0.addingTimeInterval(10)
        p.record(itemID: "skill.isPair", correct: true, seconds: 3, now: soon, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        p.record(itemID: "fact.pairRule", correct: true, seconds: 2, now: soon, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        for id in ["skill.isPair", "fact.pairRule"] {
            XCTAssertEqual(p.schedules[id]?.learningStep, 1, "\(id): comes back in 10 minutes, not in 4 days")
            XCTAssertEqual(p.schedules[id]?.due, soon.addingTimeInterval(600), id)
        }
        // Fast again once the 10-minute step is up: still only the next step (tomorrow).
        let later = soon.addingTimeInterval(600)
        p.record(itemID: "skill.isPair", correct: true, seconds: 3, now: later, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertNil(p.schedules["skill.isPair"]?.learningStep)
        XCTAssertEqual(p.schedules["skill.isPair"]?.intervalDays, 1)
    }

    func testFastFirstReviewADayAfterTheLessonCanGraduateStraightAway() {
        var p = F.progress(completing: [F.lesson6])
        p.record(itemID: "skill.isPair", correct: true, seconds: 3, now: t0.addingTimeInterval(day), updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertNil(p.schedules["skill.isPair"]?.learningStep)
        XCTAssertEqual(p.schedules["skill.isPair"]?.intervalDays, 4)
    }

    // MARK: Mastery and difficulty

    func testMasteryIsZeroForUnknownItems() {
        XCTAssertEqual(LearnerProgress().mastery(of: "skill.isTrump"), 0)
    }

    func testIntervalScoreInterpolates() {
        let cases: [(Double, Double)] = [(0, 0.1), (-2, 0.1), (0.5, 0.25), (1, 0.4), (4, 0.575), (7, 0.75),
                                         (14, 0.875), (21, 1), (60, 1), (.infinity, 1), (.nan, 0.1)]
        for (days, score) in cases {
            XCTAssertEqual(LearnerProgress.intervalScore(days: days), score, accuracy: 1e-9, "\(days) days")
        }
    }

    func testMasteryBlendsIntervalAndRecentAccuracy() {
        var p = LearnerProgress()
        p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 7, due: t0)
        p.stats["skill.isTrump"] = SkillStats(attempts: 4, correct: 3, recent: [true, true, false, true])
        XCTAssertEqual(p.mastery(of: "skill.isTrump"), 0.6 * 0.75 + 0.4 * 0.75, accuracy: 1e-9)

        p.schedules["fact.goal"] = Scheduler().newSchedule(itemID: "fact.goal", now: t0)
        XCTAssertEqual(p.mastery(of: "fact.goal"), 0.06, accuracy: 1e-9, "Just learned, never answered")

        p.stats["fact.teams"] = SkillStats(attempts: 2, correct: 2, recent: [true, true])
        XCTAssertEqual(p.mastery(of: "fact.teams"), 0.4, accuracy: 1e-9, "Answered but not scheduled")

        p.schedules["skill.max"] = F.graduated("skill.max", interval: 180, due: t0)
        p.stats["skill.max"] = SkillStats(attempts: 10, correct: 10, recent: Array(repeating: true, count: 10))
        XCTAssertEqual(p.mastery(of: "skill.max"), 1, accuracy: 1e-9)
    }

    func testMasteryDropsWhileRelearning() {
        var p = LearnerProgress()
        var s = F.graduated("skill.isPair", interval: 10, due: t0)
        p.schedules["skill.isPair"] = s
        let before = p.mastery(of: "skill.isPair")
        s = Scheduler().review(s, grade: .again, now: t0)
        p.schedules["skill.isPair"] = s
        XCTAssertEqual(p.mastery(of: "skill.isPair"), 0.06, accuracy: 1e-9)
        XCTAssertLessThan(p.mastery(of: "skill.isPair"), before)
    }

    func testMasteryUsesOnlyTheLastTenAnswers() {
        var p = LearnerProgress()
        for i in 0..<20 {
            p.record(itemID: "fact.goal", correct: i >= 10, seconds: 3, now: t0, updateSchedule: false,
                     scheduler: Scheduler(), calendar: F.utc)
        }
        XCTAssertEqual(p.mastery(of: "fact.goal"), 0.4, accuracy: 1e-9)
        XCTAssertEqual(p.stats["fact.goal"]?.accuracy ?? 0, 0.5, accuracy: 1e-9)
    }

    func testMasteryStaysInRange() {
        var p = LearnerProgress()
        p.schedules["x"] = F.graduated("x", interval: 1_000, due: t0)
        p.stats["x"] = SkillStats(attempts: 3, correct: 3, recent: [true, true, true])
        XCTAssertLessThanOrEqual(p.mastery(of: "x"), 1)
        p.stats["y"] = SkillStats(attempts: 0, correct: 0, recent: [])
        XCTAssertEqual(p.mastery(of: "y"), 0)
    }

    func testDifficultyRisesWithSuccessfulReps() {
        var p = LearnerProgress()
        XCTAssertEqual(p.difficulty(for: "skill.isTrump"), 1)
        let expected = [0: 1, 1: 1, 2: 2, 3: 2, 4: 2, 5: 3, 9: 3]
        for (reps, level) in expected {
            p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 3, due: t0, reps: reps)
            XCTAssertEqual(p.difficulty(for: "skill.isTrump"), level, "\(reps) reps")
        }
    }

    func testDifficultyFollowsTheSchedulerThroughLearning() {
        var p = F.progress(completing: [F.lesson3])
        var now = t0
        var levels: [Int] = []
        for _ in 0..<6 {
            levels.append(p.difficulty(for: "skill.isTrump"))
            p.record(itemID: "skill.isTrump", correct: true, seconds: 10, now: now, updateSchedule: true,
                     scheduler: Scheduler(), calendar: F.utc)
            now = p.schedules["skill.isTrump"]?.due ?? now
        }
        XCTAssertEqual(levels, [1, 1, 2, 2, 2, 3])
        p.record(itemID: "skill.isTrump", correct: false, seconds: 10, now: now, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(p.difficulty(for: "skill.isTrump"), 1, "A lapse resets the difficulty")
    }

    // MARK: Streak

    func testStreakCountsConsecutiveDaysEndingToday() {
        var p = LearnerProgress()
        p.studyDays = ["2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10"]
        XCTAssertEqual(p.streak(now: t0, calendar: F.utc), 4)
    }

    func testStreakStillCountsIfNotStudiedYetToday() {
        var p = LearnerProgress()
        p.studyDays = ["2026-10-08", "2026-10-09"]
        XCTAssertEqual(p.streak(now: t0, calendar: F.utc), 2)
        p.studyDays = ["2026-10-08"]
        XCTAssertEqual(p.streak(now: t0, calendar: F.utc), 0, "A missed day breaks the streak")
    }

    func testStreakStopsAtAGap() {
        var p = LearnerProgress()
        p.studyDays = ["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-05", "2026-10-09", "2026-10-10"]
        XCTAssertEqual(p.streak(now: t0, calendar: F.utc), 2)
        XCTAssertEqual(p.streak(now: t0.addingTimeInterval(-6 * day), calendar: F.utc), 3, "On 10-04")
    }

    func testStreakAcrossMonthAndYearBoundaries() {
        var p = LearnerProgress()
        p.studyDays = ["2025-11-30", "2025-12-01", "2025-12-30", "2025-12-31", "2026-01-01"]
        let newYear = Date(timeIntervalSince1970: 1_767_268_800) // 2026-01-01 12:00 UTC
        XCTAssertEqual(p.streak(now: newYear, calendar: F.utc), 3)
        let dec1 = newYear.addingTimeInterval(-31 * day)
        XCTAssertEqual(p.streak(now: dec1, calendar: F.utc), 2)
        p.studyDays = ["2024-02-28", "2024-02-29", "2024-03-01"]
        let march1 = newYear.addingTimeInterval(-671 * day) // 2024-03-01
        XCTAssertEqual(LearnerProgress.dayKey(for: march1, calendar: F.utc), "2024-03-01")
        XCTAssertEqual(p.streak(now: march1, calendar: F.utc), 3, "Leap day counts")
    }

    func testStreakUsesTheGivenTimeZone() {
        var p = LearnerProgress()
        p.studyDays = ["2026-10-10", "2026-10-11"]
        let lateUTC = Date(timeIntervalSince1970: 1_791_675_000) // 2026-10-10 23:30 UTC = 10-11 in Tokyo
        XCTAssertEqual(p.streak(now: lateUTC, calendar: F.tokyo), 2)
        XCTAssertEqual(p.streak(now: lateUTC, calendar: F.losAngeles), 1)
    }

    func testStreakBuiltFromRecordedAnswers() {
        var p = LearnerProgress()
        for d in [0.0, 1, 2, 4, 5] {
            p.record(itemID: "fact.goal", correct: true, seconds: 3, now: t0.addingTimeInterval(d * day),
                     updateSchedule: false, scheduler: Scheduler(), calendar: F.utc)
        }
        XCTAssertEqual(p.streak(now: t0.addingTimeInterval(5 * day), calendar: F.utc), 2)
        XCTAssertEqual(p.streak(now: t0.addingTimeInterval(6 * day), calendar: F.utc), 2)
        XCTAssertEqual(p.streak(now: t0.addingTimeInterval(7 * day), calendar: F.utc), 0)
        XCTAssertEqual(p.streak(now: t0.addingTimeInterval(2 * day), calendar: F.utc), 3)
    }

    func testStreakIgnoresMalformedDays() {
        var p = LearnerProgress()
        p.studyDays = ["garbage", "2026-13-01", "2026-10-10", "", "2026-10-09"]
        XCTAssertEqual(p.streak(now: t0, calendar: F.utc), 2)
    }

    func testDayKeysMustBeRealCalendarDays() {
        for bad in ["2026-02-30", "2026-02-29", "2026-04-31", "2026-00-10", "2026-10-00", "2026-1-05", "26-10-10",
                    "+026-10-10", "2026-10-1x", "2026-10-10 ", "0000-01-01"] {
            XCTAssertNil(LearnerProgress.dayNumber(fromKey: bad), bad)
        }
        XCTAssertNotNil(LearnerProgress.dayNumber(fromKey: "2024-02-29"), "Leap day")
        XCTAssertNotNil(LearnerProgress.dayNumber(fromKey: "2000-02-29"), "Leap year divisible by 400")
        XCTAssertNil(LearnerProgress.dayNumber(fromKey: "1900-02-29"), "1900 was not a leap year")
        XCTAssertEqual(LearnerProgress.dayNumber(fromKey: "1970-01-01"), 0)
        XCTAssertEqual(LearnerProgress.dayNumber(fromKey: "2026-10-10"),
                       LearnerProgress.dayNumber(for: t0, calendar: F.utc))
        // 2026-02-31 must not quietly become 2026-03-03 and join a streak.
        var p = LearnerProgress()
        p.studyDays = ["2026-02-31", "2026-03-02"]
        let march3 = Date(timeIntervalSince1970: 1_772_539_200) // 2026-03-03 12:00 UTC
        XCTAssertEqual(LearnerProgress.dayKey(for: march3, calendar: F.utc), "2026-03-03")
        XCTAssertEqual(p.streak(now: march3, calendar: F.utc), 1)
    }

    func testDayKeysRoundTripDayByDayAcrossLeapYears() {
        // 2019-12-25 12:00 UTC, then every day for about 9 years.
        let start = Date(timeIntervalSince1970: 1_577_275_200)
        var previous: Int?
        for i in 0..<3_300 {
            let date = start.addingTimeInterval(Double(i) * day)
            guard let key = LearnerProgress.dayKey(for: date, calendar: F.utc),
                  let number = LearnerProgress.dayNumber(for: date, calendar: F.utc) else {
                return XCTFail("No key for day \(i)")
            }
            XCTAssertEqual(LearnerProgress.dayNumber(fromKey: key), number, key)
            if let previous { XCTAssertEqual(number, previous + 1, key) }
            previous = number
        }
    }

    func testAbsurdYearInSavedDataIsDroppedNotACrash() throws {
        // A huge year used to overflow the day arithmetic and crash while loading.
        let json = #"{"studyDays": ["1000000000000000000-01-01", "2026-10-10"]}"#
        let p = try JSONDecoder().decode(LearnerProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.studyDays, ["2026-10-10"])
        var q = LearnerProgress()
        q.studyDays = ["4000000000000000000-12-31", "2026-10-10"]
        XCTAssertEqual(q.streak(now: t0, calendar: F.utc), 1)
    }

    // MARK: Codable

    func testProgressRoundTripsThroughJSON() throws {
        var p = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3])
        p.record(itemID: "skill.isTrump", correct: false, seconds: 9, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        p.schedules["skill.pointValue"] = F.graduated("skill.pointValue", interval: 6.25, due: t0.addingTimeInterval(day))
        p.coachLevel = .coached
        p.gamesPlayed = 4
        p.gamesWon = 3
        p.roundsPlayed = 31
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(LearnerProgress.self, from: data)
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.unlockedItemIDs, p.unlockedItemIDs)
    }

    func testRelearningStateSurvivesSaving() throws {
        var p = F.progress(completing: [F.lesson3])
        p.schedules["skill.isTrump"] = F.graduated("skill.isTrump", interval: 8, due: t0)
        p.record(itemID: "skill.isTrump", correct: false, seconds: 5, now: t0, updateSchedule: true,
                 scheduler: Scheduler(), calendar: F.utc)
        var loaded = try JSONDecoder().decode(LearnerProgress.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(loaded.schedules["skill.isTrump"]?.isRelearning, true)
        loaded.record(itemID: "skill.isTrump", correct: true, seconds: 9, now: t0.addingTimeInterval(600),
                      updateSchedule: true, scheduler: Scheduler(), calendar: F.utc)
        XCTAssertEqual(loaded.schedules["skill.isTrump"]?.intervalDays, 4, "Re-graduates to the kept half")
    }

    func testEncodedJSONIsStable() throws {
        let p = F.progress(completing: [F.lesson1, F.lesson2])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let a = try encoder.encode(p)
        let b = try encoder.encode(try JSONDecoder().decode(LearnerProgress.self, from: a))
        XCTAssertEqual(a, b)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: a) as? [String: Any])
        XCTAssertEqual(object["completedLessons"] as? [String], ["lesson.1", "lesson.2"])
        XCTAssertEqual((object["unlockOrder"] as? [String])?.count, 5)
    }

    func testEmptyJSONDecodesToFreshProgress() throws {
        let p = try JSONDecoder().decode(LearnerProgress.self, from: Data("{}".utf8))
        XCTAssertEqual(p, LearnerProgress())
    }

    func testOlderJSONWithMissingKeysStillDecodes() throws {
        // Saved before unlockOrder, isRelearning and the game counters existed.
        let json = """
        {
          "completedLessons": ["lesson.1", "lesson.2"],
          "schedules": {
            "fact.teams": {"itemID": "fact.teams", "due": 800000000, "intervalDays": 1, "ease": 2.5,
                           "reps": 2, "lapses": 0},
            "skill.countPoints": {"itemID": "skill.countPoints", "due": 800000100, "intervalDays": 0, "ease": 2.5,
                                  "reps": 0, "lapses": 0, "learningStep": 1},
            "skill.pointValue": {"itemID": "skill.pointValue", "due": 800000200, "intervalDays": 0, "ease": 2.5,
                                 "reps": 0, "lapses": 0, "learningStep": 0}
          },
          "stats": {"fact.teams": {"attempts": 3, "correct": 2, "recent": [true, false, true]}},
          "studyDays": ["2026-10-09"]
        }
        """
        let p = try JSONDecoder().decode(LearnerProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.completedLessons, ["lesson.1", "lesson.2"])
        XCTAssertEqual(p.schedules.count, 3)
        XCTAssertEqual(p.schedules["skill.countPoints"]?.learningStep, 1)
        XCTAssertEqual(p.schedules["skill.countPoints"]?.isRelearning, false)
        XCTAssertEqual(p.stats["fact.teams"]?.correct, 2)
        XCTAssertEqual(p.studyDays, ["2026-10-09"])
        XCTAssertEqual(p.coachLevel, .guided)
        XCTAssertEqual(p.gamesPlayed, 0)
        XCTAssertEqual(p.unlockedItemIDs, ["skill.pointValue", "skill.countPoints", "fact.teams"],
                       "Without a saved order: skills in skill order, then facts")
        XCTAssertEqual(p.dueItemIDs(now: Date(timeIntervalSinceReferenceDate: 800_000_100)),
                       ["fact.teams", "skill.countPoints"])
    }

    func testMalformedEntriesAreDroppedNotFatal() throws {
        let json = """
        {
          "completedLessons": ["lesson.1", 7],
          "schedules": {
            "fact.goal": {"itemID": "fact.goal", "due": 800000000},
            "fact.broken": {"itemID": "fact.broken"},
            "fact.renamed": {"itemID": "fact.oldName", "due": 800000000}
          },
          "stats": {"fact.goal": {"attempts": 2}, "fact.bad": "nope"},
          "studyDays": ["2026-10-09", "not a day", "2026-10-09"],
          "coachLevel": "expert",
          "gamesPlayed": "many",
          "gamesWon": -4,
          "roundsPlayed": 12
        }
        """
        let p = try JSONDecoder().decode(LearnerProgress.self, from: Data(json.utf8))
        XCTAssertEqual(p.completedLessons, ["lesson.1"])
        XCTAssertEqual(Set(p.schedules.keys), ["fact.goal", "fact.renamed"])
        XCTAssertEqual(p.schedules["fact.renamed"]?.itemID, "fact.renamed")
        XCTAssertEqual(p.stats["fact.goal"], SkillStats(attempts: 2, correct: 0, recent: []))
        XCTAssertNil(p.stats["fact.bad"])
        XCTAssertEqual(p.studyDays, ["2026-10-09"])
        XCTAssertEqual(p.coachLevel, .guided)
        XCTAssertEqual(p.gamesPlayed, 0)
        XCTAssertEqual(p.gamesWon, 0)
        XCTAssertEqual(p.roundsPlayed, 12)
    }

    func testSkillStatsDecodingIsLenientAndConsistent() throws {
        let json = #"{"attempts": 3, "correct": 9, "recent": [true,true,true,true,true,true,true,true,true,true,false,false]}"#
        let s = try JSONDecoder().decode(SkillStats.self, from: Data(json.utf8))
        XCTAssertEqual(s.attempts, 3)
        XCTAssertEqual(s.correct, 3)
        XCTAssertEqual(s.recent.count, 10)
        XCTAssertEqual(s.recent.last, false)
    }

    func testNonObjectJSONFailsToDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(LearnerProgress.self, from: Data("[1,2]".utf8)))
    }

    // MARK: A learner's first days

    func testDailyReviewSpacesItemsOut() {
        let sch = Scheduler()
        var p = F.progress(completing: [F.lesson3])
        var now = t0
        // Session 1 (right after the lesson): two quick correct answers in learning.
        p.record(itemID: "skill.isTrump", correct: true, seconds: 10, now: now, updateSchedule: true,
                 scheduler: sch, calendar: F.utc)
        XCTAssertEqual(p.nextDueDate(after: now), now.addingTimeInterval(600))
        now = now.addingTimeInterval(600)
        p.record(itemID: "skill.isTrump", correct: true, seconds: 10, now: now, updateSchedule: true,
                 scheduler: sch, calendar: F.utc)
        XCTAssertTrue(p.dueItemIDs(now: now.addingTimeInterval(day - 1)).isEmpty)
        XCTAssertEqual(p.dueItemIDs(now: now.addingTimeInterval(day)), ["skill.isTrump"])
        // The next days: intervals expand.
        var intervals: [Double] = []
        for _ in 0..<3 {
            now = p.schedules["skill.isTrump"]?.due ?? now
            p.record(itemID: "skill.isTrump", correct: true, seconds: 10, now: now, updateSchedule: true,
                     scheduler: sch, calendar: F.utc)
            intervals.append(p.schedules["skill.isTrump"]?.intervalDays ?? 0)
        }
        XCTAssertEqual(intervals, [2.5, 6.25, 15.625])
        XCTAssertGreaterThan(p.mastery(of: "skill.isTrump"), 0.9)
        XCTAssertEqual(p.studyDays.count, 4)
    }
}

/// Practice sessions with fake question and lesson providers (the real ones live in Curriculum).
final class PracticeSessionTests: XCTestCase {
    private typealias F = LearningCoreFixtures
    private let t0 = LearningCoreFixtures.t0
    private let day = LearningCoreFixtures.day

    override func setUp() {
        super.setUp()
        PracticeSession.questionProvider = F.fakeQuestions
        PracticeSession.lessonProvider = F.fakeLessons
    }

    override func tearDown() {
        PracticeSession.questionProvider = PracticeSession.curriculumQuestionProvider
        PracticeSession.lessonProvider = PracticeSession.curriculumLessonProvider
        super.tearDown()
    }

    /// Runs the session to the end, answering with `answer(itemID, isFirstTimeForItem)`. Returns the asked item ids.
    @discardableResult
    private func run(_ session: inout PracticeSession, progress: LearnerProgress = LearnerProgress(), seed: UInt64 = 1,
                     answer: (String, Bool) -> Bool = { _, _ in true }) -> [String] {
        var rng = SeededGenerator(seed: seed)
        var asked: [String] = []
        var guardCount = 0
        while let q = session.next(progress: progress, rng: &rng), guardCount < 500 {
            asked.append(q.itemID)
            session.answer(correct: answer(q.itemID, asked.filter { $0 == q.itemID }.count == 1))
            guardCount += 1
        }
        XCTAssertTrue(session.isFinished)
        return asked
    }

    private func families(_ ids: [String]) -> [String] { ids.map(PracticeSession.family(of:)) }

    private func adjacentRepeats(_ ids: [String]) -> Int {
        let f = families(ids)
        return zip(f, f.dropFirst()).filter { $0 == $1 }.count
    }

    private func dueProgress(_ items: [(String, Double)]) -> LearnerProgress {
        var p = LearnerProgress()
        for (id, hoursAgo) in items {
            p.schedules[id] = F.graduated(id, interval: 2, due: t0.addingTimeInterval(-hoursAgo * 3_600))
            p.unlockOrder.append(id)
        }
        return p
    }

    // MARK: Review

    func testEmptyReviewIsFinishedAtOnce() {
        var rng = SeededGenerator(seed: 1)
        var progress = F.progress(completing: [F.lesson3])
        progress.schedules["skill.isTrump"]?.due = t0.addingTimeInterval(day)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertTrue(s.queue.isEmpty)
        XCTAssertTrue(s.isFinished)
        XCTAssertNil(s.next(progress: progress, rng: &rng))
        XCTAssertEqual(s.score, 0)
        XCTAssertFalse(s.passed)
        XCTAssertEqual(s.answeredCount, 0)
        s.answer(correct: true)
        XCTAssertEqual(s.answeredCount, 0, "Answering with no question is ignored")
    }

    func testReviewTakesTheMostOverdueItemsUpToTheLimit() {
        var progress = dueProgress((0..<12).map { ("fact.f\($0)", Double($0)) })
        progress.schedules["fact.future"] = F.graduated("fact.future", interval: 2, due: t0.addingTimeInterval(60))
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .review, progress: progress, now: t0, maxItems: 5, rng: &rng)
        XCTAssertEqual(s.queue, ["fact.f11", "fact.f10", "fact.f9", "fact.f8", "fact.f7"])
        XCTAssertTrue(s.updatesSchedule)
        let all = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(all.queue.count, 12)
        XCTAssertFalse(all.queue.contains("fact.future"))
        let none = PracticeSession(kind: .review, progress: progress, now: t0, maxItems: 0, rng: &rng)
        XCTAssertTrue(none.queue.isEmpty)
    }

    func testReviewAsksAtMostTheDefaultNumberOfItems() {
        // The Review tab's "Start review (N)" shows at most this many, so it matches the session.
        let progress = dueProgress((0..<28).map { ("fact.f\($0)", Double($0)) })
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(PracticeSession.defaultMaxItems, 15)
        XCTAssertEqual(s.queue.count, PracticeSession.defaultMaxItems)
        XCTAssertEqual(progress.dueItemIDs(now: t0).count, 28)
    }

    func testReviewInterleavesKindsAndSkills() {
        let progress = dueProgress([("fact.a", 9), ("fact.b", 8), ("fact.c", 7), ("skill.isTrump", 6),
                                    ("skill.isPair", 5)])
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(s.queue, ["fact.a", "skill.isTrump", "fact.b", "skill.isPair", "fact.c"])
    }

    func testReviewWithOnlyOneFamilyKeepsOverdueOrder() {
        let progress = dueProgress([("fact.a", 3), ("fact.b", 2), ("fact.c", 1)])
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(s.queue, ["fact.a", "fact.b", "fact.c"])
    }

    // MARK: Interleaving

    func testInterleavingKeepsAnAlreadyMixedOrder() {
        let mixed = ["skill.isTrump", "fact.a", "skill.isPair", "fact.b", "skill.isTrump"]
        XCTAssertEqual(PracticeSession.interleaved(mixed), mixed)
        XCTAssertEqual(PracticeSession.interleaved([]), [])
        XCTAssertEqual(PracticeSession.interleaved(["fact.a"]), ["fact.a"])
    }

    func testFamiliesSeparateSkillsButGroupFacts() {
        XCTAssertEqual(PracticeSession.family(of: "skill.isTrump"), "skill.isTrump")
        XCTAssertNotEqual(PracticeSession.family(of: "skill.isTrump"), PracticeSession.family(of: "skill.isPair"))
        XCTAssertEqual(PracticeSession.family(of: "fact.a"), PracticeSession.family(of: "fact.b"))
        XCTAssertNotEqual(PracticeSession.family(of: "fact.a"), PracticeSession.family(of: "skill.isPair"))
    }

    func testInterleavingIsOptimalOnRandomInputs() {
        let pool = ["skill.isTrump", "skill.isPair", "skill.pointValue", "fact.a", "fact.b", "fact.c"]
        var rng = SeededGenerator(seed: 2_024)
        for _ in 0..<2_000 {
            let n = Int.random(in: 0...12, using: &rng)
            // Skew towards a few ids so that some inputs cannot avoid repeats.
            let width = Int.random(in: 1...pool.count, using: &rng)
            let items = (0..<n).map { _ in pool[Int.random(in: 0..<width, using: &rng)] }
            let result = PracticeSession.interleaved(items)
            XCTAssertEqual(result.sorted(), items.sorted(), "Must be a reordering of \(items)")
            var counts: [String: Int] = [:]
            for f in families(items) { counts[f, default: 0] += 1 }
            let most = counts.values.max() ?? 0
            let fewestPossible = max(0, 2 * most - n - 1)
            XCTAssertEqual(adjacentRepeats(result), fewestPossible, "\(items) -> \(result)")
            if adjacentRepeats(items) == 0 { XCTAssertEqual(result, items) }
        }
    }

    // MARK: Retries and scoring

    func testWrongAnswerComesBackAfterRetryGapQuestions() {
        let progress = dueProgress([("fact.a", 9), ("skill.isTrump", 8), ("fact.b", 7), ("skill.isPair", 6),
                                    ("fact.c", 5), ("skill.cardBeats", 4)])
        var rng = SeededGenerator(seed: 1)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(s.retryGap, 3)
        XCTAssertEqual(s.next(progress: progress, rng: &rng)?.itemID, "fact.a")
        s.answer(correct: false)
        XCTAssertNil(s.current)
        XCTAssertEqual(s.queue, ["skill.isTrump", "fact.b", "skill.isPair", "fact.a", "fact.c", "skill.cardBeats"])
        let rest = run(&s, progress: progress)
        XCTAssertEqual(rest, ["skill.isTrump", "fact.b", "skill.isPair", "fact.a", "fact.c", "skill.cardBeats"])
        XCTAssertEqual(s.answeredCount, 7)
        XCTAssertEqual(s.firstTryTotal, 6)
        XCTAssertEqual(s.firstTryCorrect, 5)
        XCTAssertEqual(s.score, 5.0 / 6.0, accuracy: 1e-9)
    }

    func testMissedItemKeepsComingBackUntilRight() {
        let progress = dueProgress([("fact.a", 2), ("skill.isTrump", 1)])
        var rng = SeededGenerator(seed: 1)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        var misses = 0
        let asked = run(&s, progress: progress) { id, _ in
            guard id == "fact.a", misses < 3 else { return true }
            misses += 1
            return false
        }
        XCTAssertEqual(asked, ["fact.a", "skill.isTrump", "fact.a", "fact.a", "fact.a"])
        XCTAssertEqual(s.firstTryTotal, 2)
        XCTAssertEqual(s.firstTryCorrect, 1)
        XCTAssertEqual(s.answeredCount, 5)
    }

    func testRetryGapIsAdjustable() {
        let progress = dueProgress([("fact.a", 4), ("skill.isTrump", 3), ("fact.b", 2), ("skill.isPair", 1)])
        var rng = SeededGenerator(seed: 1)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        s.retryGap = 1
        _ = s.next(progress: progress, rng: &rng)
        s.answer(correct: false)
        XCTAssertEqual(s.queue, ["skill.isTrump", "fact.a", "fact.b", "skill.isPair"])
        s.retryGap = -5
        _ = s.next(progress: progress, rng: &rng)
        s.answer(correct: false)
        XCTAssertEqual(s.queue, ["skill.isTrump", "fact.a", "fact.b", "skill.isPair"],
                       "A negative gap acts as 0")
    }

    func testRetryIsNotPlacedNextToAnotherCopyOfTheSameItem() {
        XCTAssertEqual(PracticeSession.retryPosition(for: "s", in: ["x", "y", "z", "w"], gap: 3), 3)
        XCTAssertEqual(PracticeSession.retryPosition(for: "s", in: ["x", "y", "s", "z"], gap: 3), 4)
        XCTAssertEqual(PracticeSession.retryPosition(for: "s", in: ["x", "y", "z", "s", "w"], gap: 3), 5)
        XCTAssertEqual(PracticeSession.retryPosition(for: "s", in: ["x"], gap: 3), 1)
        XCTAssertEqual(PracticeSession.retryPosition(for: "s", in: [], gap: 3), 0)
        XCTAssertEqual(PracticeSession.retryPosition(for: "s", in: ["x", "s"], gap: 3), 2,
                       "No better place: falls back to the end")
    }

    func testPassThresholdIsEightyPercentFirstTry() {
        let five = dueProgress([("fact.a", 5), ("skill.isTrump", 4), ("fact.b", 3), ("skill.isPair", 2),
                                ("fact.c", 1)])
        var rng = SeededGenerator(seed: 1)
        var s = PracticeSession(kind: .review, progress: five, now: t0, rng: &rng)
        run(&s, progress: five) { id, first in !(id == "fact.b" && first) }
        XCTAssertEqual(s.score, 0.8, accuracy: 1e-9)
        XCTAssertTrue(s.passed, "4 of 5 passes even though the retry was needed")

        let four = dueProgress([("fact.a", 4), ("skill.isTrump", 3), ("fact.b", 2), ("skill.isPair", 1)])
        var t = PracticeSession(kind: .review, progress: four, now: t0, rng: &rng)
        run(&t, progress: four) { id, first in !(id == "fact.b" && first) }
        XCTAssertEqual(t.score, 0.75, accuracy: 1e-9)
        XCTAssertFalse(t.passed)

        var perfect = PracticeSession(kind: .review, progress: four, now: t0, rng: &rng)
        run(&perfect, progress: four)
        XCTAssertEqual(perfect.score, 1)
        XCTAssertTrue(perfect.passed)
    }

    func testRetriesDoNotCountButASkillsSecondPlannedQuestionDoes() throws {
        let progress = F.progress(completing: [F.lesson1, F.lesson2])
        var rng = SeededGenerator(seed: 5)
        var s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.3"), progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(s.queue.filter { $0 == "skill.isTrump" }.count, 2)
        // Miss the first isTrump question, get its second (planned) question and the retry right.
        let asked = run(&s, progress: progress) { id, first in !(id == "skill.isTrump" && first) }
        XCTAssertEqual(asked.filter { $0 == "skill.isTrump" }.count, 3)
        XCTAssertEqual(s.firstTryTotal, 4, "Two planned isTrump questions plus two earlier items; not the retry")
        XCTAssertEqual(s.firstTryCorrect, 3)
        XCTAssertEqual(s.answeredCount, asked.count)
        XCTAssertFalse(s.passed)
    }

    func testMissingASkillsSecondQuestionCostsTheQuizScore() {
        // A skill is asked twice with two different questions. Getting the second one wrong is a real miss:
        // the summary must not say "everything right first time".
        let progress = F.progress(completing: [F.lesson1, F.lesson2])
        for seed in 1...10 as ClosedRange<UInt64> {
            var rng = SeededGenerator(seed: seed)
            var s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.3"), progress: progress, now: t0, rng: &rng)
            var isTrumpAsked = 0
            var qrng = SeededGenerator(seed: seed)
            while let q = s.next(progress: progress, rng: &qrng), s.answeredCount < 50 {
                var correct = true
                if q.itemID == "skill.isTrump" {
                    isTrumpAsked += 1
                    correct = isTrumpAsked != 2
                }
                s.answer(correct: correct)
            }
            XCTAssertEqual(isTrumpAsked, 3, "Two planned questions and one retry")
            XCTAssertEqual(s.firstTryTotal, 4)
            XCTAssertEqual(s.firstTryCorrect, 3)
            XCTAssertEqual(s.score, 0.75, accuracy: 1e-9)
            XCTAssertFalse(s.passed)
        }
    }

    func testFirstTryTotalMatchesTheQuestionsPlannedWhenAllRight() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4])
        var rng = SeededGenerator(seed: 21)
        var s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.6"), progress: progress, now: t0, rng: &rng)
        let planned = s.queue.count
        let asked = run(&s, progress: progress)
        XCTAssertEqual(asked.count, planned)
        XCTAssertEqual(s.firstTryTotal, planned)
        XCTAssertEqual(s.firstTryCorrect, planned)
        XCTAssertTrue(s.passed)
    }

    func testRandomSessionsKeepTheirBookkeepingStraight() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4, F.lesson6])
        let kinds: [PracticeSession.Kind] = [.review, .lessonQuiz(lessonID: "lesson.6"),
                                             .lessonQuiz(lessonID: "lesson.9"), .freePractice(skills: []),
                                             .freePractice(skills: [.isPair, .isTrump])]
        var dice = SeededGenerator(seed: 99)
        for round in 0..<300 {
            let kind = kinds[round % kinds.count]
            var rng = SeededGenerator(seed: UInt64(round))
            var s = PracticeSession(kind: kind, progress: progress, now: t0, maxItems: Int.random(in: 0...12, using: &dice),
                                    rng: &rng)
            s.retryGap = Int.random(in: -1...5, using: &dice)
            let planned = s.queue.count
            var wrong = 0
            var steps = 0
            while let q = s.next(progress: progress, rng: &rng), steps < 1_000 {
                XCTAssertEqual(s.current, q)
                let ok = Int.random(in: 0..<10, using: &dice) < 6
                if !ok { wrong += 1 }
                s.answer(correct: ok)
                steps += 1
            }
            XCTAssertTrue(s.isFinished, "\(kind)")
            XCTAssertEqual(s.firstTryTotal, planned, "Every planned question counts once")
            XCTAssertEqual(s.answeredCount, planned + wrong, "One retry per wrong answer")
            XCTAssertLessThanOrEqual(s.firstTryCorrect, s.firstTryTotal)
            XCTAssertTrue((0...1).contains(s.score))
        }
    }

    func testFreePracticeScoresEveryFreshQuestion() {
        let progress = F.progress(completing: [F.lesson3])
        var rng = SeededGenerator(seed: 2)
        var s = PracticeSession(kind: .freePractice(skills: [.isTrump]), progress: progress, now: t0, maxItems: 5,
                                rng: &rng)
        var n = 0
        run(&s, progress: progress) { _, _ in
            n += 1
            return n != 2 && n != 4
        }
        XCTAssertEqual(s.answeredCount, 7)
        XCTAssertEqual(s.firstTryTotal, 5)
        XCTAssertEqual(s.firstTryCorrect, 3)
    }

    // MARK: Lesson quiz

    func testLessonQuizAsksSkillsTwiceFactsOnceAndTwoEarlierItems() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4])
        var rng = SeededGenerator(seed: 11)
        let s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.6"), progress: progress, now: t0, rng: &rng)
        XCTAssertFalse(s.updatesSchedule)
        let counts = s.queue.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        XCTAssertEqual(counts["skill.isPair"], 2)
        XCTAssertEqual(counts["skill.legalFollow"], 2)
        XCTAssertEqual(counts["fact.pairRule"], 1)
        let earlier = s.queue.filter { !["skill.isPair", "skill.legalFollow", "fact.pairRule"].contains($0) }
        XCTAssertEqual(earlier.count, 2)
        XCTAssertEqual(Set(earlier).count, 2)
        XCTAssertTrue(Set(earlier).isSubset(of: Set(progress.unlockedItemIDs)))
        XCTAssertEqual(s.queue.count, 7)
        XCTAssertEqual(adjacentRepeats(s.queue), 0)
    }

    func testLessonQuizReviewsTheWeakestEarlierItems() {
        var progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4])
        for id in progress.unlockedItemIDs {
            progress.schedules[id] = F.graduated(id, interval: 21, due: t0.addingTimeInterval(day))
        }
        progress.schedules["skill.countPoints"] = F.graduated("skill.countPoints", interval: 1, due: t0)
        progress.schedules["fact.goal"] = F.graduated("fact.goal", interval: 2, due: t0)
        for seed in 1...20 as ClosedRange<UInt64> {
            var rng = SeededGenerator(seed: seed)
            let s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.6"), progress: progress, now: t0, rng: &rng)
            let earlier = Set(s.queue.filter { !F.lesson6.itemIDs.contains($0) })
            XCTAssertEqual(earlier, ["skill.countPoints", "fact.goal"])
        }
    }

    func testLessonQuizCapsTheLessonPartAtEight() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2])
        var rng = SeededGenerator(seed: 3)
        let s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.9"), progress: progress, now: t0, rng: &rng)
        let lessonItems = Set(F.lesson9.itemIDs)
        let core = s.queue.filter { lessonItems.contains($0) }
        XCTAssertEqual(core.count, 8)
        XCTAssertEqual(Set(core), lessonItems, "Every lesson item is asked at least once")
        XCTAssertEqual(s.queue.count, 10)
        XCTAssertEqual(adjacentRepeats(s.queue), 0)

        var small = SeededGenerator(seed: 3)
        let capped = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.9"), progress: progress, now: t0,
                                     maxItems: 5, rng: &small)
        XCTAssertEqual(capped.queue.count, 5)
        XCTAssertTrue(capped.queue.allSatisfy(lessonItems.contains), "Lesson items come before earlier review")
    }

    func testFirstLessonQuizHasNoEarlierItems() {
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.1"), progress: LearnerProgress(), now: t0,
                                rng: &rng)
        XCTAssertEqual(s.queue.sorted(), ["fact.goal", "fact.teams", "fact.threshold"])
    }

    func testRetakingAQuizOnlyReviewsItemsFromBeforeThatLesson() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4])
        for seed in 1...10 as ClosedRange<UInt64> {
            var rng = SeededGenerator(seed: seed)
            let s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.3"), progress: progress, now: t0, rng: &rng)
            let earlier = s.queue.filter { $0 != "skill.isTrump" }
            XCTAssertEqual(earlier.count, 2)
            XCTAssertFalse(earlier.contains("skill.trumpOrder"), "Lesson 4 comes after lesson 3")
        }
    }

    func testUnknownLessonGivesAnEmptyQuiz() {
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .lessonQuiz(lessonID: "lesson.99"), progress: F.progress(completing: [F.lesson1]),
                                now: t0, rng: &rng)
        XCTAssertTrue(s.isFinished)
        XCTAssertFalse(s.passed)
    }

    func testLessonQuizOrderVariesWithTheSeed() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3, F.lesson4])
        let orders = Set((1...10 as ClosedRange<UInt64>).map { seed -> [String] in
            var rng = SeededGenerator(seed: seed)
            return PracticeSession(kind: .lessonQuiz(lessonID: "lesson.6"), progress: progress, now: t0, rng: &rng).queue
        })
        XCTAssertGreaterThan(orders.count, 1)
        var a = SeededGenerator(seed: 4), b = SeededGenerator(seed: 4)
        XCTAssertEqual(PracticeSession(kind: .lessonQuiz(lessonID: "lesson.6"), progress: progress, now: t0, rng: &a).queue,
                       PracticeSession(kind: .lessonQuiz(lessonID: "lesson.6"), progress: progress, now: t0, rng: &b).queue)
    }

    // MARK: Free practice

    func testFreePracticeDrawsFromUnlockedItems() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3])
        var rng = SeededGenerator(seed: 8)
        let s = PracticeSession(kind: .freePractice(skills: []), progress: progress, now: t0, maxItems: 4, rng: &rng)
        XCTAssertFalse(s.updatesSchedule)
        XCTAssertEqual(s.queue.count, 4)
        XCTAssertEqual(Set(s.queue).count, 4, "No repeats while there are enough items")
        XCTAssertTrue(Set(s.queue).isSubset(of: Set(progress.unlockedItemIDs)))
    }

    func testFreePracticeFillsWithSkillsButNeverRepeatsFacts() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2])
        var rng = SeededGenerator(seed: 8)
        let s = PracticeSession(kind: .freePractice(skills: []), progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(s.queue.count, 15)
        let counts = s.queue.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        for fact in F.lesson1.factIDs { XCTAssertEqual(counts[fact], 1) }
        XCTAssertEqual((counts["skill.pointValue"] ?? 0) + (counts["skill.countPoints"] ?? 0), 12)
        XCTAssertLessThanOrEqual(abs((counts["skill.pointValue"] ?? 0) - (counts["skill.countPoints"] ?? 0)), 1,
                                 "Skills share the extra slots evenly")
        XCTAssertEqual(adjacentRepeats(s.queue), 0)
    }

    func testFreePracticeOnChosenSkills() {
        let progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3])
        var rng = SeededGenerator(seed: 9)
        let s = PracticeSession(kind: .freePractice(skills: [.isTrump, .isTrump]), progress: progress, now: t0,
                                maxItems: 6, rng: &rng)
        XCTAssertEqual(s.queue, Array(repeating: "skill.isTrump", count: 6))
        let two = PracticeSession(kind: .freePractice(skills: [.isTrump, .pointValue]), progress: progress, now: t0,
                                  maxItems: 6, rng: &rng)
        XCTAssertEqual(Set(two.queue), ["skill.isTrump", "skill.pointValue"])
        XCTAssertEqual(adjacentRepeats(two.queue), 0)
    }

    func testFreePracticeWithNothingUnlockedIsEmpty() {
        var rng = SeededGenerator(seed: 1)
        let s = PracticeSession(kind: .freePractice(skills: []), progress: LearnerProgress(), now: t0, rng: &rng)
        XCTAssertTrue(s.isFinished)
        let facts = F.progress(completing: [F.lesson1])
        let onlyFacts = PracticeSession(kind: .freePractice(skills: []), progress: facts, now: t0, rng: &rng)
        XCTAssertEqual(onlyFacts.queue.count, 3, "Three facts, each asked once")
    }

    // MARK: Questions

    func testNextUsesDifficultyFromProgressAndIsDeterministic() {
        var progress = dueProgress([("skill.isTrump", 2), ("fact.a", 1)])
        progress.schedules["skill.isTrump"]?.reps = 6
        func ids(seed: UInt64) -> [String] {
            var rng = SeededGenerator(seed: seed)
            var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
            var out: [String] = []
            while let q = s.next(progress: progress, rng: &rng) {
                out.append(q.id)
                if q.itemID == "skill.isTrump" { XCTAssertEqual(q.difficulty, 3) }
                if q.itemID == "fact.a" { XCTAssertEqual(q.difficulty, 2) }
                s.answer(correct: true)
            }
            return out
        }
        XCTAssertEqual(ids(seed: 42), ids(seed: 42))
        XCTAssertNotEqual(ids(seed: 42), ids(seed: 43))
    }

    func testNextReturnsTheUnansweredQuestionAgain() {
        let progress = dueProgress([("fact.a", 2), ("skill.isTrump", 1)])
        var rng = SeededGenerator(seed: 1)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        let first = s.next(progress: progress, rng: &rng)
        XCTAssertEqual(s.next(progress: progress, rng: &rng), first)
        XCTAssertEqual(s.current, first)
        XCTAssertEqual(s.queue, ["skill.isTrump"])
        XCTAssertFalse(s.isFinished)
        s.answer(correct: true)
        XCTAssertNil(s.current)
        XCTAssertEqual(s.next(progress: progress, rng: &rng)?.itemID, "skill.isTrump")
        s.answer(correct: true)
        XCTAssertTrue(s.isFinished)
    }

    func testItemsWithoutAQuestionAreSkipped() {
        let progress = dueProgress([("missing.one", 3), ("fact.a", 2), ("missing.two", 1)])
        var rng = SeededGenerator(seed: 1)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        let asked = run(&s, progress: progress)
        XCTAssertEqual(asked, ["fact.a"])
        XCTAssertEqual(s.firstTryTotal, 1)
        XCTAssertEqual(s.score, 1)
    }

    // MARK: End to end

    func testReviewSessionDrivesTheSchedule() throws {
        var progress = F.progress(completing: [F.lesson1, F.lesson2, F.lesson3])
        var rng = SeededGenerator(seed: 77)
        var s = PracticeSession(kind: .review, progress: progress, now: t0, rng: &rng)
        XCTAssertEqual(Set(s.queue), Set(progress.unlockedItemIDs))
        XCTAssertEqual(adjacentRepeats(s.queue), 0)
        var now = t0
        var missedGoalAt: Date?
        var retriedGoalAt: Date?
        while let q = s.next(progress: progress, rng: &rng), s.answeredCount < 50 {
            now = now.addingTimeInterval(10)
            // The learner misses fact.goal once, then gets it right when it comes back.
            let correct = q.itemID != "fact.goal" || missedGoalAt != nil
            if q.itemID == "fact.goal" {
                if missedGoalAt == nil { missedGoalAt = now } else { retriedGoalAt = now }
            }
            progress.record(itemID: q.itemID, correct: correct, seconds: 7, now: now,
                            updateSchedule: s.updatesSchedule, scheduler: Scheduler(), calendar: F.utc)
            s.answer(correct: correct)
        }
        XCTAssertTrue(s.isFinished)
        XCTAssertEqual(s.answeredCount, 7)
        XCTAssertEqual(s.firstTryTotal, 6)
        XCTAssertEqual(s.firstTryCorrect, 5)
        let missed = try XCTUnwrap(missedGoalAt)
        for id in progress.unlockedItemIDs where id != "fact.goal" {
            XCTAssertEqual(progress.schedules[id]?.learningStep, 1, id)
            XCTAssertGreaterThan(progress.schedules[id]?.due ?? .distantPast, now, id)
        }
        // The retry came back a few questions after the miss, before the 1-minute step was up: it doesn't
        // promote the item, so a quick answer to a question you just saw explained can't inflate its interval.
        XCTAssertLessThan(try XCTUnwrap(retriedGoalAt).timeIntervalSince(missed), 60)
        XCTAssertEqual(progress.schedules["fact.goal"]?.learningStep, 0)
        XCTAssertEqual(progress.schedules["fact.goal"]?.due, missed.addingTimeInterval(60))
        XCTAssertEqual(progress.stats["fact.goal"]?.recent, [false, true])
        XCTAssertEqual(progress.dueItemIDs(now: missed.addingTimeInterval(60)), ["fact.goal"])
    }
}
