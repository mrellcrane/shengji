import Foundation

/// How much help the table gives during play. Scaffolding is meant to fade as skill grows.
public enum CoachLevel: String, Codable, CaseIterable, Sendable {
    /// Legal cards highlighted, trumps marked, every trick explained, hints on tap.
    case guided
    /// Mistakes explained and hints on tap; no highlighting.
    case coached
    /// No help.
    case solo

    public var title: String {
        switch self {
        case .guided: return "Guided"
        case .coached: return "Coached"
        case .solo: return "Solo"
        }
    }

    public var blurb: String {
        switch self {
        case .guided: return "Legal cards lit up, trumps marked, every trick explained."
        case .coached: return "Hints on tap and your mistakes explained. No highlights."
        case .solo: return "No hints, no highlights. Show what you know."
        }
    }
}

public struct SkillStats: Codable, Hashable, Sendable {
    public var attempts: Int
    public var correct: Int
    /// Most recent results, newest last, at most 10.
    public var recent: [Bool]

    /// How many results `recent` keeps.
    static let recentLimit = 10

    public init(attempts: Int = 0, correct: Int = 0, recent: [Bool] = []) {
        self.attempts = attempts
        self.correct = correct
        self.recent = recent
    }

    public var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }

    private enum CodingKeys: String, CodingKey {
        case attempts, correct, recent
    }

    /// Lenient decoding: missing or malformed keys fall back to empty values.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let attempts = max(0, (try? c.decodeIfPresent(Int.self, forKey: .attempts)) ?? 0)
        self.attempts = attempts
        correct = min(attempts, max(0, (try? c.decodeIfPresent(Int.self, forKey: .correct)) ?? 0))
        recent = Array(((try? c.decodeIfPresent([Bool].self, forKey: .recent)) ?? []).suffix(Self.recentLimit))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(correct, forKey: .correct)
        try c.encode(recent, forKey: .recent)
    }

    mutating func add(correct isCorrect: Bool) {
        attempts += 1
        if isCorrect { correct += 1 }
        recent.append(isCorrect)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
    }

    /// Share of correct answers among the recent ones (all answers if no recent list was kept).
    var recentAccuracy: Double {
        guard !recent.isEmpty else { return accuracy }
        return Double(recent.filter { $0 }.count) / Double(recent.count)
    }
}

/// Everything persisted about the learner. Plain value type; the app stores it as JSON.
public struct LearnerProgress: Codable, Hashable, Sendable {
    public var completedLessons: Set<String>
    public var schedules: [String: ItemSchedule]
    public var stats: [String: SkillStats]
    /// Days (yyyy-MM-dd, local time) with at least one review or lesson, for the streak.
    public var studyDays: [String]
    public var coachLevel: CoachLevel
    public var gamesPlayed: Int
    public var gamesWon: Int
    public var roundsPlayed: Int
    /// Item ids in the order they were first scheduled (lesson order). Backs `unlockedItemIDs`.
    var unlockOrder: [String]

    /// Expected answer time for skill questions (cards to read), in seconds. Used for automatic grading.
    static let skillExpectedSeconds: Double = 12
    /// Expected answer time for fact questions, in seconds.
    static let factExpectedSeconds: Double = 8

    public init() {
        completedLessons = []
        schedules = [:]
        stats = [:]
        studyDays = []
        coachLevel = .guided
        gamesPlayed = 0
        gamesWon = 0
        roundsPlayed = 0
        unlockOrder = []
    }

    /// Lesson 1 is always open; lesson n opens once lesson n-1 is completed (mastery gating).
    public func isUnlocked(_ lesson: Lesson) -> Bool {
        lesson.number <= 1
            || completedLessons.contains(lesson.id)
            || completedLessons.contains("lesson.\(lesson.number - 1)")
    }

    /// Marks the lesson complete and schedules its items (due now, at learning step 0) if new.
    public mutating func completeLesson(_ lesson: Lesson, now: Date, scheduler: Scheduler = Scheduler()) {
        completeLesson(lesson, now: now, scheduler: scheduler, calendar: .current)
    }

    mutating func completeLesson(_ lesson: Lesson, now: Date, scheduler: Scheduler, calendar: Calendar) {
        completedLessons.insert(lesson.id)
        for id in lesson.itemIDs where schedules[id] == nil {
            schedules[id] = scheduler.newSchedule(itemID: id, now: now)
            if !unlockOrder.contains(id) { unlockOrder.append(id) }
        }
        recordStudyDay(now, calendar: calendar)
    }

    /// Item ids due at `now`, most overdue first (ties by id, so the order is stable).
    public func dueItemIDs(now: Date) -> [String] {
        schedules
            .filter { $0.value.due <= now }
            .sorted { a, b in a.value.due != b.value.due ? a.value.due < b.value.due : a.key < b.key }
            .map(\.key)
    }

    /// Earliest future due date among scheduled items.
    public func nextDueDate(after now: Date) -> Date? {
        schedules.values.lazy.map(\.due).filter { $0 > now }.min()
    }

    /// Records an answer: updates stats and study days, and (when `updateSchedule` is true and the
    /// item is scheduled) its spaced-repetition schedule, graded by `Scheduler.grade`.
    ///
    /// A wrong answer always counts. A right answer only moves the item on once its time has come, because
    /// reviewing before that would distort the intervals:
    /// - The in-session retry of a question you just missed (the item is not due yet) leaves the schedule alone,
    ///   so a quick answer to a question you saw explained a moment ago can't graduate it or lengthen its interval.
    /// - A graduated item brought forward by `noteGameMistake` goes back to its original due date instead of
    ///   growing its interval early.
    public mutating func record(itemID: String, correct: Bool, seconds: Double, now: Date,
                                updateSchedule: Bool = true, scheduler: Scheduler = Scheduler()) {
        record(itemID: itemID, correct: correct, seconds: seconds, now: now,
               updateSchedule: updateSchedule, scheduler: scheduler, calendar: .current)
    }

    mutating func record(itemID: String, correct: Bool, seconds: Double, now: Date,
                         updateSchedule: Bool, scheduler: Scheduler, calendar: Calendar) {
        stats[itemID, default: SkillStats()].add(correct: correct)
        recordStudyDay(now, calendar: calendar)
        guard updateSchedule, var schedule = schedules[itemID] else { return }
        let rawGrade = Scheduler.grade(correct: correct, seconds: seconds,
                                       expectedSeconds: Self.expectedSeconds(for: itemID))
        // Once an item has been answered in its (re)learning steps, a fast answer counts as good, never easy:
        // speed on something just seen or just missed is short-term memory, so it still takes each step.
        // (A fast first answer to a new item can still graduate it straight away.)
        let midSteps = schedule.learningStep != nil && schedule.lastReviewed != nil
        let grade = midSteps && rawGrade == .easy ? .good : rawGrade
        if grade != .again {
            // Not due yet: the retry of an item missed a moment ago.
            if schedule.due > now { return }
            // Brought forward early (a game mistake): a right answer restores the original date.
            if let original = Self.originalDue(of: schedule), now.addingTimeInterval(1) < original {
                schedule.due = original
                schedules[itemID] = schedule
                return
            }
        }
        schedules[itemID] = scheduler.review(schedule, grade: grade, now: now)
    }

    /// When a graduated item was due before anything moved it: last review + interval. Nil while (re)learning
    /// or if it has never been reviewed.
    static func originalDue(of schedule: ItemSchedule) -> Date? {
        guard schedule.learningStep == nil, let last = schedule.lastReviewed,
              schedule.intervalDays.isFinite, schedule.intervalDays > 0 else { return nil }
        return last.addingTimeInterval(schedule.intervalDays * Scheduler.secondsPerDay)
    }

    /// Item ids the learner has unlocked (scheduled), in lesson order.
    public var unlockedItemIDs: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in unlockOrder where schedules[id] != nil && seen.insert(id).inserted {
            result.append(id)
        }
        // Items scheduled some other way (or saved before unlock order was kept) go last, in a stable order.
        let extras = schedules.keys.filter { !seen.contains($0) }.sorted(by: Self.fallbackOrder)
        return result + extras
    }

    /// A mistake made during real play (e.g. an illegal follow): makes that skill due now
    /// so it gets retrieval practice soon. No-op if the skill isn't scheduled yet.
    /// Ease and interval are untouched; an item that is already overdue keeps its earlier due date.
    /// In review, a wrong answer then counts as a lapse, while a right one puts a graduated item back on
    /// its original date (see `record`), so mistakes at the table never push a skill further away.
    public mutating func noteGameMistake(_ skill: SkillID, now: Date) {
        guard var schedule = schedules[skill.itemID] else { return }
        schedule.due = min(schedule.due, now)
        schedules[skill.itemID] = schedule
    }

    /// 0...1 estimate of how well an item is known (interval length and recent accuracy).
    /// 60% comes from the graduated interval (learning: 0.1, 1 day: 0.4, 7 days: 0.75, 21+ days: 1),
    /// 40% from accuracy over the last 10 answers.
    public func mastery(of itemID: String) -> Double {
        let schedule = schedules[itemID]
        let stat = stats[itemID]
        if schedule == nil && stat == nil { return 0 }
        var intervalScore = 0.0
        if let schedule {
            let graduatedDays = schedule.learningStep == nil ? schedule.intervalDays : 0
            intervalScore = Self.intervalScore(days: graduatedDays)
        }
        let accuracy = stat?.recentAccuracy ?? 0
        return min(1, max(0, 0.6 * intervalScore + 0.4 * accuracy))
    }

    /// Question difficulty for an item, 1...3, rising with successful reps.
    public func difficulty(for itemID: String) -> Int {
        guard let reps = schedules[itemID]?.reps else { return 1 }
        if reps < 2 { return 1 }
        if reps < 5 { return 2 }
        return 3
    }

    /// Consecutive study days ending today (or yesterday, if not studied yet today).
    public func streak(now: Date, calendar: Calendar = .current) -> Int {
        guard let today = Self.dayNumber(for: now, calendar: calendar) else { return 0 }
        let days = Set(studyDays.compactMap(Self.dayNumber(fromKey:)))
        var day = days.contains(today) ? today : today - 1
        var count = 0
        while days.contains(day) {
            count += 1
            day -= 1
        }
        return count
    }

    // MARK: - Helpers

    static func expectedSeconds(for itemID: String) -> Double {
        itemID.hasPrefix("skill.") ? skillExpectedSeconds : factExpectedSeconds
    }

    /// Piecewise-linear score for a graduated interval: 0 days → 0.1, 1 → 0.4, 7 → 0.75, 21 or more → 1.
    static func intervalScore(days: Double) -> Double {
        let points: [(days: Double, score: Double)] = [(0, 0.1), (1, 0.4), (7, 0.75), (21, 1.0)]
        guard days.isFinite, days > 0 else { return days == .infinity ? 1 : 0.1 }
        for i in 1..<points.count where days <= points[i].days {
            let a = points[i - 1], b = points[i]
            return a.score + (b.score - a.score) * (days - a.days) / (b.days - a.days)
        }
        return 1
    }

    /// Stable order for scheduled items that have no recorded unlock position:
    /// skills in `SkillID` order, then everything else alphabetically.
    static func fallbackOrder(_ a: String, _ b: String) -> Bool {
        let ia = SkillID(itemID: a).flatMap { SkillID.allCases.firstIndex(of: $0) } ?? Int.max
        let ib = SkillID(itemID: b).flatMap { SkillID.allCases.firstIndex(of: $0) } ?? Int.max
        return ia != ib ? ia < ib : a < b
    }

    mutating func recordStudyDay(_ now: Date, calendar: Calendar) {
        guard let key = Self.dayKey(for: now, calendar: calendar), !studyDays.contains(key) else { return }
        studyDays.append(key)
        // Keys sort chronologically as strings; keep the list ordered even if the clock went backwards.
        if studyDays.count > 1, studyDays[studyDays.count - 2] > key { studyDays.sort() }
    }

    /// A Gregorian calendar in the time zone of `calendar`, so day keys are always yyyy-MM-dd
    /// whatever calendar system the device uses.
    private static func gregorian(in calendar: Calendar) -> Calendar {
        var g = Calendar(identifier: .gregorian)
        g.timeZone = calendar.timeZone
        return g
    }

    private static func ymd(for date: Date, calendar: Calendar) -> (year: Int, month: Int, day: Int)? {
        let parts = gregorian(in: calendar).dateComponents([.year, .month, .day], from: date)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return nil }
        return (y, m, d)
    }

    /// "yyyy-MM-dd" for the local day containing `date`.
    static func dayKey(for date: Date, calendar: Calendar) -> String? {
        guard let (y, m, d) = ymd(for: date, calendar: calendar) else { return nil }
        return pad(y, 4) + "-" + pad(m, 2) + "-" + pad(d, 2)
    }

    /// Days since 1970-01-01 of the local day containing `date`.
    static func dayNumber(for date: Date, calendar: Calendar) -> Int? {
        guard let (y, m, d) = ymd(for: date, calendar: calendar) else { return nil }
        return daysFromCivil(year: y, month: m, day: d)
    }

    /// Days since 1970-01-01 for a "yyyy-MM-dd" key; nil unless the key is exactly that shape and names a real
    /// Gregorian day (so "2026-02-31" can't pose as March 3, and a huge year can't overflow the arithmetic).
    static func dayNumber(fromKey key: String) -> Int? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.unicodeScalars.allSatisfy { $0 >= "0" && $0 <= "9" } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              y >= 1, (1...12).contains(m), d >= 1, d <= daysInMonth(year: y, month: m) else { return nil }
        return daysFromCivil(year: y, month: m, day: d)
    }

    private static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Proleptic Gregorian date to a day count (Howard Hinnant's days_from_civil).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case completedLessons, schedules, stats, studyDays, coachLevel, gamesPlayed, gamesWon, roundsPlayed
        case unlockOrder
    }

    /// Lenient decoding so progress saved by any earlier version still loads: missing keys get their
    /// defaults, and a malformed entry is dropped on its own instead of failing the whole file.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func lossyStrings(_ key: CodingKeys) -> [String] {
            (try? c.decodeIfPresent([Lossy<String>].self, forKey: key))?.compactMap(\.value) ?? []
        }
        func count(_ key: CodingKeys) -> Int {
            max(0, (try? c.decodeIfPresent(Int.self, forKey: key)) ?? 0)
        }

        completedLessons = Set(lossyStrings(.completedLessons))
        var schedules: [String: ItemSchedule] = [:]
        let rawSchedules = try? c.decodeIfPresent([String: Lossy<ItemSchedule>].self, forKey: .schedules)
        for (id, entry) in rawSchedules ?? [:] {
            guard var schedule = entry.value else { continue }
            schedule.itemID = id
            schedules[id] = schedule
        }
        self.schedules = schedules
        let rawStats = try? c.decodeIfPresent([String: Lossy<SkillStats>].self, forKey: .stats)
        stats = (rawStats ?? [:]).compactMapValues(\.value)
        studyDays = Array(Set(lossyStrings(.studyDays).filter { Self.dayNumber(fromKey: $0) != nil })).sorted()
        coachLevel = (try? c.decodeIfPresent(CoachLevel.self, forKey: .coachLevel)) ?? .guided
        gamesPlayed = count(.gamesPlayed)
        gamesWon = count(.gamesWon)
        roundsPlayed = count(.roundsPlayed)
        unlockOrder = []
        var seen = Set<String>()
        for id in lossyStrings(.unlockOrder) where seen.insert(id).inserted { unlockOrder.append(id) }
        if !c.contains(.unlockOrder) {
            // Saved before unlock order was kept: rebuild a stable order from the schedules.
            unlockOrder = schedules.keys.sorted(by: Self.fallbackOrder)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(completedLessons.sorted(), forKey: .completedLessons)
        try c.encode(schedules, forKey: .schedules)
        try c.encode(stats, forKey: .stats)
        try c.encode(studyDays, forKey: .studyDays)
        try c.encode(coachLevel, forKey: .coachLevel)
        try c.encode(gamesPlayed, forKey: .gamesPlayed)
        try c.encode(gamesWon, forKey: .gamesWon)
        try c.encode(roundsPlayed, forKey: .roundsPlayed)
        try c.encode(unlockOrder, forKey: .unlockOrder)
    }
}

/// A value guarded by a lock, so shared state stays safe to touch from any thread.
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Decodes a value if it can, or nil instead of failing the surrounding collection.
private struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// A queue of retrieval-practice questions with immediate feedback. Missed items are re-asked
/// later in the same session (after `retryGap` other questions) until answered correctly.
/// Used for both daily review (interleaved due items) and end-of-lesson quizzes.
public struct PracticeSession: Sendable {
    public enum Kind: Hashable, Sendable {
        /// Due items across all lessons, interleaved.
        case review
        /// End-of-lesson check: the lesson's items plus a couple of earlier items (cumulative review).
        case lessonQuiz(lessonID: String)
        /// Extra practice on demand: random unlocked items (or just `skills` if non-empty).
        /// Answers here should NOT move schedules (reviewing before due would distort intervals).
        case freePractice(skills: [SkillID])
    }

    /// Whether answers in this session should update spaced-repetition schedules (only `.review`).
    public var updatesSchedule: Bool { kind == .review }

    public let kind: Kind
    /// Item ids still to ask, front first.
    public private(set) var queue: [String]
    public private(set) var current: Question?
    /// Questions answered correctly on the first try / questions asked for the first time.
    /// Every planned question counts (a skill asked twice in a lesson quiz gets two different questions);
    /// the retries of a missed question do not.
    public private(set) var firstTryCorrect: Int
    public private(set) var firstTryTotal: Int
    public private(set) var answeredCount: Int
    public var retryGap: Int

    /// Item id of `current` (as queued).
    private var currentItemID: String?
    /// Whether `current` is the retry of a question missed earlier in this session.
    private var currentIsRetry: Bool
    /// Parallel to `queue`: true for entries that are retries of a missed question.
    private var queueRetries: [Bool]

    /// Questions in a lesson quiz drawn from the lesson itself.
    static let lessonQuizCoreLimit = 8
    /// Earlier items mixed into a lesson quiz (cumulative review).
    static let lessonQuizEarlierLimit = 2
    /// Lesson quizzes pass at this first-try accuracy.
    static let passThreshold = 0.8

    /// Review: up to `maxItems` due items, most overdue first, ordered so consecutive questions differ in kind
    /// (interleaving).
    /// Lesson quiz: each lesson skill twice and each fact once (at most 8 questions) plus up to 2 earlier items,
    /// shuffled and interleaved.
    /// Free practice: `maxItems` random picks from unlocked items (or the given skills). Facts appear at most once;
    /// skills (fresh questions every time) fill the remaining slots.
    public init<G: RandomNumberGenerator>(kind: Kind, progress: LearnerProgress, now: Date, maxItems: Int = 15, rng: inout G) {
        let limit = max(0, maxItems)
        let items: [String]
        switch kind {
        case .review:
            items = Self.interleaved(Array(progress.dueItemIDs(now: now).prefix(limit)))
        case let .lessonQuiz(lessonID):
            items = Self.lessonQuizItems(lessonID: lessonID, progress: progress, limit: limit, rng: &rng)
        case let .freePractice(skills):
            let pool = skills.isEmpty ? progress.unlockedItemIDs : skills.map(\.itemID)
            items = Self.freePracticeItems(pool: pool, limit: limit, rng: &rng)
        }
        self.kind = kind
        queue = items
        current = nil
        firstTryCorrect = 0
        firstTryTotal = 0
        answeredCount = 0
        retryGap = 3
        currentItemID = nil
        currentIsRetry = false
        queueRetries = Array(repeating: false, count: items.count)
    }

    /// Pops the next item and generates its question (difficulty from `progress`). Nil when done.
    /// If the current question has not been answered yet, it is returned again.
    /// Items no question can be made for are skipped.
    public mutating func next<G: RandomNumberGenerator>(progress: LearnerProgress, rng: inout G) -> Question? {
        if let current { return current }
        while !queue.isEmpty {
            let itemID = queue.removeFirst()
            let isRetry = queueRetries.isEmpty ? false : queueRetries.removeFirst()
            let seed = rng.next()
            if let question = Self.questionProvider(itemID, progress.difficulty(for: itemID), seed) {
                current = question
                currentItemID = itemID
                currentIsRetry = isRetry
                return question
            }
        }
        return nil
    }

    /// Records the answer to `current`. A wrong answer re-inserts the item `retryGap` places later
    /// (or at the end of a shorter queue), nudged a little further if that would put it right next to
    /// another copy of the same item. No-op if there is no current question.
    public mutating func answer(correct: Bool) {
        guard current != nil, let itemID = currentItemID else { return }
        answeredCount += 1
        if !currentIsRetry {
            firstTryTotal += 1
            if correct { firstTryCorrect += 1 }
        }
        if !correct {
            let position = Self.retryPosition(for: itemID, in: queue, gap: retryGap)
            queue.insert(itemID, at: position)
            queueRetries.insert(true, at: min(position, queueRetries.count))
        }
        current = nil
        currentItemID = nil
        currentIsRetry = false
    }

    public var isFinished: Bool { current == nil && queue.isEmpty }
    /// First-try accuracy, 0...1.
    public var score: Double {
        firstTryTotal == 0 ? 0 : Double(firstTryCorrect) / Double(firstTryTotal)
    }
    /// Lesson quizzes pass at ≥ 80% first-try accuracy.
    public var passed: Bool { firstTryTotal > 0 && score >= Self.passThreshold }

    // MARK: - Providers (internal so tests can swap in fakes)

    /// Makes the question for an item: (item id, difficulty 1...3, seed) → question, nil for unknown ids.
    typealias QuestionProvider = @Sendable (_ itemID: String, _ difficulty: Int, _ seed: UInt64) -> Question?
    /// Looks a lesson up by id.
    typealias LessonProvider = @Sendable (_ lessonID: String) -> Lesson?

    static let curriculumQuestionProvider: QuestionProvider = { itemID, difficulty, seed in
        var rng = SeededGenerator(seed: seed)
        return Curriculum.question(for: itemID, difficulty: difficulty, rng: &rng)
    }
    static let curriculumLessonProvider: LessonProvider = { Curriculum.lesson(id: $0) }

    /// Where questions come from. Defaults to `Curriculum`; tests set a fake and restore the default.
    static var questionProvider: QuestionProvider {
        get { providers.withLock { $0.question } }
        set { providers.withLock { $0.question = newValue } }
    }

    /// Where lessons come from. Defaults to `Curriculum`; tests set a fake and restore the default.
    static var lessonProvider: LessonProvider {
        get { providers.withLock { $0.lesson } }
        set { providers.withLock { $0.lesson = newValue } }
    }

    private struct Providers {
        var question: QuestionProvider
        var lesson: LessonProvider
    }

    private static let providers = LockedBox(Providers(question: curriculumQuestionProvider,
                                                       lesson: curriculumLessonProvider))

    // MARK: - Building the queue

    /// Interleaving family: each skill is its own family; all facts share one.
    static func family(of itemID: String) -> String {
        itemID.hasPrefix("skill.") ? itemID : "fact"
    }

    /// Reorders `items` so that no two consecutive items share a family whenever such an order exists,
    /// otherwise with as few repeats as possible. Keeps the original order as far as that allows.
    static func interleaved(_ items: [String]) -> [String] {
        var remaining = items
        var counts: [String: Int] = [:]
        for id in items { counts[family(of: id), default: 0] += 1 }
        var result: [String] = []
        result.reserveCapacity(items.count)
        var last: String?

        while !remaining.isEmpty {
            let total = remaining.count
            // Earliest item whose family differs from the last one and still leaves a repeat-free order.
            var pick = remaining.indices.first { i in
                let f = family(of: remaining[i])
                return f != last && canFinishWithoutRepeats(after: f, counts: counts, total: total)
            }
            if pick == nil {
                // No repeat-free order exists: spend the most common other family first.
                var best: (index: Int, count: Int)?
                for (i, id) in remaining.enumerated() {
                    let f = family(of: id)
                    guard f != last, let n = counts[f] else { continue }
                    if best == nil || n > (best?.count ?? 0) { best = (i, n) }
                }
                pick = best?.index
            }
            let index = pick ?? 0
            let id = remaining.remove(at: index)
            let f = family(of: id)
            counts[f, default: 1] -= 1
            result.append(id)
            last = f
        }
        return result
    }

    /// After placing one item of `family` (with `total` items left before placing it), can the rest be
    /// ordered with no two neighbours of the same family? True when no family holds more than half of the
    /// rest, rounded up, and the just-placed family holds at most half, rounded down (it can't come next).
    private static func canFinishWithoutRepeats(after family: String, counts: [String: Int], total: Int) -> Bool {
        let rest = total - 1
        for (f, n) in counts {
            let left = f == family ? n - 1 : n
            if f == family {
                if left > rest / 2 { return false }
            } else if left > (rest + 1) / 2 {
                return false
            }
        }
        return true
    }

    static func lessonQuizItems<G: RandomNumberGenerator>(lessonID: String, progress: LearnerProgress,
                                                         limit: Int, rng: inout G) -> [String] {
        guard let lesson = lessonProvider(lessonID) else { return [] }
        let lessonItems = unique(lesson.itemIDs)
        let lessonSet = Set(lessonItems)
        // Every item once first, then each skill a second time (a fresh question), so a cap drops repeats first.
        let skillItems = lessonItems.filter { $0.hasPrefix("skill.") }
        let core = Array((lessonItems + skillItems).prefix(min(lessonQuizCoreLimit, limit)))

        // Cumulative review: items unlocked before this lesson's, weakest first (ties at random).
        let unlocked = progress.unlockedItemIDs
        let before = unlocked.firstIndex(where: { lessonSet.contains($0) }).map { Array(unlocked[..<$0]) } ?? unlocked
        let candidates = before.filter { !lessonSet.contains($0) }.shuffled(using: &rng)
        var scored: [(offset: Int, id: String, mastery: Double)] = []
        for (offset, id) in candidates.enumerated() {
            scored.append((offset: offset, id: id, mastery: progress.mastery(of: id)))
        }
        scored.sort { a, b in
            if a.mastery != b.mastery { return a.mastery < b.mastery }
            return a.offset < b.offset
        }
        let ranked: [String] = scored.map { $0.id }
        let earlierCount = min(lessonQuizEarlierLimit, max(0, limit - core.count))
        let earlier = Array(ranked.prefix(earlierCount))

        return interleaved((core + earlier).shuffled(using: &rng))
    }

    static func freePracticeItems<G: RandomNumberGenerator>(pool: [String], limit: Int, rng: inout G) -> [String] {
        let pool = unique(pool)
        var picks = Array(pool.shuffled(using: &rng).prefix(limit))
        // Skills generate a fresh question every time, so they can fill the remaining slots; facts can't.
        let skills = pool.filter { $0.hasPrefix("skill.") }
        while picks.count < limit, !skills.isEmpty {
            for id in skills.shuffled(using: &rng) where picks.count < limit {
                picks.append(id)
            }
        }
        return interleaved(picks)
    }

    static func retryPosition(for itemID: String, in queue: [String], gap: Int) -> Int {
        let base = min(max(0, gap), queue.count)
        for position in base...queue.count {
            let before = position > 0 ? queue[position - 1] : nil
            let after = position < queue.count ? queue[position] : nil
            if before != itemID && after != itemID { return position }
        }
        return base
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }
}
