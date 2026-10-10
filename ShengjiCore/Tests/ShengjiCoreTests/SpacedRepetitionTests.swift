import XCTest
@testable import ShengjiCore

final class SpacedRepetitionTests: XCTestCase {
    private let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let scheduler = Scheduler()

    /// A graduated item with the given interval and ease.
    private func graduated(interval: Double, ease: Double = 2.5, reps: Int = 3, lapses: Int = 0) -> ItemSchedule {
        ItemSchedule(itemID: "skill.isTrump", due: t0, intervalDays: interval, ease: ease, reps: reps,
                     lapses: lapses, learningStep: nil, lastReviewed: t0.addingTimeInterval(-interval * day))
    }

    private func assertDue(_ s: ItemSchedule, _ seconds: TimeInterval, from now: Date,
                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(s.due.timeIntervalSince(now), seconds, accuracy: 0.001, file: file, line: line)
    }

    // MARK: New items

    func testNewScheduleIsDueNowAtFirstLearningStep() {
        let s = scheduler.newSchedule(itemID: "fact.teams", now: t0)
        XCTAssertEqual(s.itemID, "fact.teams")
        XCTAssertEqual(s.due, t0)
        XCTAssertEqual(s.learningStep, 0)
        XCTAssertEqual(s.intervalDays, 0)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(s.reps, 0)
        XCTAssertEqual(s.lapses, 0)
        XCTAssertNil(s.lastReviewed)
        XCTAssertFalse(s.isRelearning)
    }

    func testNewScheduleUsesConfiguredStartingEase() {
        let s = Scheduler(startingEase: 2.1).newSchedule(itemID: "x", now: t0)
        XCTAssertEqual(s.ease, 2.1)
    }

    // MARK: Learning steps

    func testGoodWalksThroughLearningStepsAndGraduatesToOneDay() {
        var s = scheduler.newSchedule(itemID: "skill.isTrump", now: t0)
        s = scheduler.review(s, grade: .good, now: t0)
        XCTAssertEqual(s.learningStep, 1)
        assertDue(s, 600, from: t0)
        XCTAssertEqual(s.reps, 1)
        XCTAssertEqual(s.intervalDays, 0)

        let t1 = t0.addingTimeInterval(600)
        s = scheduler.review(s, grade: .good, now: t1)
        XCTAssertNil(s.learningStep)
        XCTAssertEqual(s.intervalDays, 1)
        assertDue(s, day, from: t1)
        XCTAssertEqual(s.reps, 2)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(s.lastReviewed, t1)
    }

    func testAgainInLearningGoesBackToFirstStep() {
        var s = scheduler.newSchedule(itemID: "a", now: t0)
        s = scheduler.review(s, grade: .good, now: t0)
        s = scheduler.review(s, grade: .again, now: t0)
        XCTAssertEqual(s.learningStep, 0)
        assertDue(s, 60, from: t0)
        XCTAssertEqual(s.reps, 0)
        XCTAssertEqual(s.lapses, 0, "Failing during learning is not a lapse")
        XCTAssertEqual(s.ease, 2.5, "Ease does not change in learning")
    }

    func testHardInLearningRepeatsCurrentStep() {
        var s = scheduler.newSchedule(itemID: "a", now: t0)
        s = scheduler.review(s, grade: .hard, now: t0)
        XCTAssertEqual(s.learningStep, 0)
        assertDue(s, 60, from: t0)

        s = scheduler.review(s, grade: .good, now: t0)
        s = scheduler.review(s, grade: .hard, now: t0)
        XCTAssertEqual(s.learningStep, 1)
        assertDue(s, 600, from: t0)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(s.reps, 3, "Hard is still a successful answer")
    }

    func testEasyInLearningGraduatesStraightToEasyInterval() {
        let s = scheduler.review(scheduler.newSchedule(itemID: "a", now: t0), grade: .easy, now: t0)
        XCTAssertNil(s.learningStep)
        XCTAssertEqual(s.intervalDays, 4)
        assertDue(s, 4 * day, from: t0)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(s.reps, 1)
    }

    func testCustomLearningStepsAndGraduatingInterval() {
        let sch = Scheduler(learningSteps: [30, 300, 3_600], graduatingIntervalDays: 2, easyIntervalDays: 5)
        var s = sch.newSchedule(itemID: "a", now: t0)
        s = sch.review(s, grade: .good, now: t0)
        assertDue(s, 300, from: t0)
        s = sch.review(s, grade: .good, now: t0)
        assertDue(s, 3_600, from: t0)
        XCTAssertEqual(s.learningStep, 2)
        s = sch.review(s, grade: .again, now: t0)
        assertDue(s, 30, from: t0)
        s = sch.review(s, grade: .good, now: t0)
        s = sch.review(s, grade: .good, now: t0)
        s = sch.review(s, grade: .good, now: t0)
        XCTAssertNil(s.learningStep)
        XCTAssertEqual(s.intervalDays, 2)
        XCTAssertEqual(sch.review(sch.newSchedule(itemID: "b", now: t0), grade: .easy, now: t0).intervalDays, 5)
    }

    func testEmptyLearningStepsGraduateOnFirstGoodWithoutCrashing() {
        let sch = Scheduler(learningSteps: [], relearningSteps: [])
        var s = sch.newSchedule(itemID: "a", now: t0)
        s = sch.review(s, grade: .hard, now: t0)
        XCTAssertEqual(s.learningStep, 0)
        XCTAssertEqual(s.due, t0)
        s = sch.review(s, grade: .again, now: t0)
        XCTAssertEqual(s.due, t0)
        s = sch.review(s, grade: .good, now: t0)
        XCTAssertNil(s.learningStep)
        XCTAssertEqual(s.intervalDays, 1)
    }

    func testOutOfRangeLearningStepIsClampedNotACrash() {
        var s = scheduler.newSchedule(itemID: "a", now: t0)
        s.learningStep = 7
        let hard = scheduler.review(s, grade: .hard, now: t0)
        XCTAssertEqual(hard.learningStep, 1)
        assertDue(hard, 600, from: t0)
        let good = scheduler.review(s, grade: .good, now: t0)
        XCTAssertNil(good.learningStep)
        XCTAssertEqual(good.intervalDays, 1)
        s.learningStep = -3
        XCTAssertEqual(scheduler.review(s, grade: .good, now: t0).learningStep, 1)
    }

    // MARK: Graduated reviews

    func testGraduatedGoodMultipliesByEase() {
        let s = scheduler.review(graduated(interval: 1), grade: .good, now: t0)
        XCTAssertEqual(s.intervalDays, 2.5, accuracy: 1e-9)
        assertDue(s, 2.5 * day, from: t0)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(s.reps, 4)
        XCTAssertNil(s.learningStep)
    }

    func testGraduatedGoodAddsAtLeastOneDay() {
        let s = scheduler.review(graduated(interval: 1, ease: 1.3), grade: .good, now: t0)
        XCTAssertEqual(s.intervalDays, 2, accuracy: 1e-9, "1 × 1.3 = 1.3 is below 1 + 1")
        let zero = scheduler.review(graduated(interval: 0), grade: .good, now: t0)
        XCTAssertEqual(zero.intervalDays, 1, accuracy: 1e-9)
    }

    func testGraduatedEasyUsesBonusAndRaisesEase() {
        let s = scheduler.review(graduated(interval: 10), grade: .easy, now: t0)
        XCTAssertEqual(s.intervalDays, 10 * 2.5 * 1.3, accuracy: 1e-9)
        XCTAssertEqual(s.ease, 2.65, accuracy: 1e-9)
        assertDue(s, 32.5 * day, from: t0)
    }

    func testGraduatedHardGrowsSlowlyAndLowersEase() {
        let s = scheduler.review(graduated(interval: 10), grade: .hard, now: t0)
        XCTAssertEqual(s.intervalDays, 12, accuracy: 1e-9)
        XCTAssertEqual(s.ease, 2.35, accuracy: 1e-9)
        XCTAssertEqual(s.reps, 4)
        XCTAssertEqual(s.lapses, 0)
    }

    func testGraduatedAgainIsALapseIntoRelearning() {
        let s = scheduler.review(graduated(interval: 10, reps: 6), grade: .again, now: t0)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.reps, 0)
        XCTAssertEqual(s.ease, 2.3, accuracy: 1e-9)
        XCTAssertEqual(s.learningStep, 0)
        XCTAssertTrue(s.isRelearning)
        XCTAssertEqual(s.intervalDays, 5, accuracy: 1e-9, "Half the interval is kept for re-graduation")
        assertDue(s, 600, from: t0)
    }

    func testLapseKeepsAtLeastOneDay() {
        let s = scheduler.review(graduated(interval: 1), grade: .again, now: t0)
        XCTAssertEqual(s.intervalDays, 1)
    }

    func testRelearningGoodGraduatesBackToKeptInterval() {
        var s = scheduler.review(graduated(interval: 10), grade: .again, now: t0)
        let t1 = t0.addingTimeInterval(600)
        s = scheduler.review(s, grade: .good, now: t1)
        XCTAssertNil(s.learningStep)
        XCTAssertFalse(s.isRelearning)
        XCTAssertEqual(s.intervalDays, 5, accuracy: 1e-9)
        assertDue(s, 5 * day, from: t1)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.ease, 2.3, accuracy: 1e-9)
    }

    func testRelearningEasyUsesLargerOfEasyIntervalAndKeptTimesBonus() {
        let lapsedBig = scheduler.review(graduated(interval: 20), grade: .again, now: t0)
        XCTAssertEqual(scheduler.review(lapsedBig, grade: .easy, now: t0).intervalDays, 13, accuracy: 1e-9)
        let lapsedSmall = scheduler.review(graduated(interval: 2), grade: .again, now: t0)
        XCTAssertEqual(scheduler.review(lapsedSmall, grade: .easy, now: t0).intervalDays, 4, accuracy: 1e-9)
    }

    func testRelearningAgainAndHardStayInRelearningSteps() {
        var s = scheduler.review(graduated(interval: 10), grade: .again, now: t0)
        s = scheduler.review(s, grade: .again, now: t0)
        XCTAssertTrue(s.isRelearning)
        XCTAssertEqual(s.learningStep, 0)
        // Relearning uses the relearning steps, not the 1-minute learning step.
        assertDue(s, 600, from: t0)
        XCTAssertEqual(s.lapses, 1, "Failing again while relearning is not another lapse")
        XCTAssertEqual(s.intervalDays, 5, accuracy: 1e-9)
        s = scheduler.review(s, grade: .hard, now: t0)
        XCTAssertTrue(s.isRelearning)
        assertDue(s, 600, from: t0)
    }

    func testMultiStepRelearning() {
        let sch = Scheduler(relearningSteps: [300, 3_600])
        var s = sch.review(graduated(interval: 8), grade: .again, now: t0)
        assertDue(s, 300, from: t0)
        s = sch.review(s, grade: .good, now: t0)
        XCTAssertEqual(s.learningStep, 1)
        XCTAssertTrue(s.isRelearning)
        assertDue(s, 3_600, from: t0)
        s = sch.review(s, grade: .good, now: t0)
        XCTAssertNil(s.learningStep)
        XCTAssertEqual(s.intervalDays, 4, accuracy: 1e-9)
    }

    func testNoRelearningStepsGoesStraightToReducedInterval() {
        let sch = Scheduler(relearningSteps: [])
        let s = sch.review(graduated(interval: 10), grade: .again, now: t0)
        XCTAssertNil(s.learningStep)
        XCTAssertFalse(s.isRelearning)
        XCTAssertEqual(s.intervalDays, 5, accuracy: 1e-9)
        assertDue(s, 5 * day, from: t0)
        XCTAssertEqual(s.lapses, 1)
    }

    // MARK: Limits

    func testEaseNeverDropsBelowMinimum() {
        var s = graduated(interval: 30, ease: 1.4)
        s = scheduler.review(s, grade: .hard, now: t0)
        XCTAssertEqual(s.ease, 1.3, accuracy: 1e-9)
        for _ in 0..<5 {
            s = scheduler.review(s, grade: .again, now: t0)
            s = scheduler.review(s, grade: .good, now: t0)
        }
        XCTAssertEqual(s.ease, 1.3, accuracy: 1e-9)
        XCTAssertEqual(s.lapses, 5)
    }

    func testIntervalsAreCappedAtMaximum() {
        let good = scheduler.review(graduated(interval: 100), grade: .good, now: t0)
        XCTAssertEqual(good.intervalDays, 180)
        assertDue(good, 180 * day, from: t0)
        let easy = scheduler.review(graduated(interval: 180), grade: .easy, now: t0)
        XCTAssertEqual(easy.intervalDays, 180)
        let hard = scheduler.review(graduated(interval: 170), grade: .hard, now: t0)
        XCTAssertEqual(hard.intervalDays, 180)
        let small = Scheduler(maximumIntervalDays: 3)
        XCTAssertEqual(small.review(small.newSchedule(itemID: "a", now: t0), grade: .easy, now: t0).intervalDays, 3)
    }

    func testRepeatedGoodGrowsMonotonicallyUntilCap() {
        var s = scheduler.newSchedule(itemID: "a", now: t0)
        var now = t0
        var intervals: [Double] = []
        for _ in 0..<15 {
            s = scheduler.review(s, grade: .good, now: now)
            if s.learningStep == nil { intervals.append(s.intervalDays) }
            now = s.due
        }
        XCTAssertEqual(intervals.first, 1)
        XCTAssertEqual(intervals.last, 180)
        for (a, b) in zip(intervals, intervals.dropFirst()) {
            XCTAssertTrue(b > a || b == 180, "\(a) -> \(b)")
        }
        // Expanding retrieval: 1, 2.5, 6.25, ...
        XCTAssertEqual(intervals[1], 2.5, accuracy: 1e-9)
        XCTAssertEqual(intervals[2], 6.25, accuracy: 1e-9)
    }

    func testBetterGradesNeverGiveShorterIntervals() {
        for interval in [0.0, 1, 2.5, 7, 30, 179] {
            for ease in [1.3, 2.0, 2.5, 3.1] {
                let s = graduated(interval: interval, ease: ease)
                let next = Grade.allCases.map { scheduler.review(s, grade: $0, now: t0) }
                let dues = next.map(\.due)
                XCTAssertEqual(dues, dues.sorted(), "interval \(interval), ease \(ease)")
                for n in next.dropFirst() { XCTAssertGreaterThanOrEqual(n.intervalDays, min(interval, 180)) }
            }
        }
        let fresh = scheduler.newSchedule(itemID: "a", now: t0)
        let dues = Grade.allCases.map { scheduler.review(fresh, grade: $0, now: t0).due }
        XCTAssertEqual(dues, dues.sorted())
    }

    func testReviewIsDeterministicAndSetsLastReviewed() {
        let s = graduated(interval: 6, ease: 2.2)
        for grade in Grade.allCases {
            let a = scheduler.review(s, grade: grade, now: t0)
            let b = scheduler.review(s, grade: grade, now: t0)
            XCTAssertEqual(a, b)
            XCTAssertEqual(a.lastReviewed, t0)
            XCTAssertEqual(a.itemID, s.itemID)
        }
    }

    // MARK: Automatic grading

    func testGradeFromCorrectnessAndTime() {
        XCTAssertEqual(Scheduler.grade(correct: false, seconds: 1, expectedSeconds: 10), .again)
        XCTAssertEqual(Scheduler.grade(correct: false, seconds: 100, expectedSeconds: 10), .again)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 4.9, expectedSeconds: 10), .easy)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 0, expectedSeconds: 10), .easy)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 5, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 10, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 15, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 20, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 20.1, expectedSeconds: 10), .hard)
    }

    func testGradeWithUnusableTimesFallsBackToGood() {
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: -1, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: .nan, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: .infinity, expectedSeconds: 10), .good)
        XCTAssertEqual(Scheduler.grade(correct: true, seconds: 3, expectedSeconds: 0), .good)
        XCTAssertEqual(Scheduler.grade(correct: false, seconds: .nan, expectedSeconds: 0), .again)
    }

    // MARK: Codable

    func testItemScheduleRoundTrips() throws {
        var s = scheduler.review(graduated(interval: 10), grade: .again, now: t0)
        s.lastReviewed = t0
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(ItemSchedule.self, from: data), s)
    }

    func testItemScheduleDecodesOlderJSONWithoutRelearningFlag() throws {
        let json = """
        {"itemID":"skill.isPair","due":800000000,"intervalDays":3,"ease":2.2,"reps":4,"lapses":1,"learningStep":null}
        """
        let s = try JSONDecoder().decode(ItemSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(s.itemID, "skill.isPair")
        XCTAssertEqual(s.due, t0)
        XCTAssertEqual(s.intervalDays, 3)
        XCTAssertEqual(s.ease, 2.2)
        XCTAssertEqual(s.reps, 4)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertNil(s.learningStep)
        XCTAssertNil(s.lastReviewed)
        XCTAssertFalse(s.isRelearning)
    }

    func testItemScheduleDecodesMinimalJSONWithDefaults() throws {
        let json = #"{"itemID":"fact.goal","due":800000000}"#
        let s = try JSONDecoder().decode(ItemSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(s.intervalDays, 0)
        XCTAssertEqual(s.ease, 2.5)
        XCTAssertEqual(s.reps, 0)
        XCTAssertNil(s.learningStep)
    }

    func testItemScheduleWithoutIDFailsToDecode() {
        let json = #"{"due":800000000}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ItemSchedule.self, from: Data(json.utf8)))
    }
}
