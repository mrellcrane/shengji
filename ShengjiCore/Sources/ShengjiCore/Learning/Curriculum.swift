import Foundation

// Curriculum types and entry points. The lesson, fact and glossary content lives in
// Learning/Content/ (lessons in groups of four, plus facts and glossary).

/// A fixed fact checked by retrieval practice (multiple choice; choices are shuffled each time).
public struct Fact: Identifiable, Hashable, Sendable {
    /// "fact.<name>"
    public var id: String
    public var lessonID: String
    public var prompt: String
    public var choices: [String]
    /// Index into `choices` (before shuffling).
    public var correctChoice: Int
    public var explanation: String

    public init(id: String, lessonID: String, prompt: String, choices: [String], correctChoice: Int, explanation: String) {
        self.id = id
        self.lessonID = lessonID
        self.prompt = prompt
        self.choices = choices
        self.correctChoice = correctChoice
        self.explanation = explanation
    }

    /// A question with the choices shuffled (so position can't be memorised).
    public func question<G: RandomNumberGenerator>(rng: inout G) -> Question {
        let order = Array(choices.indices).shuffled(using: &rng)
        let shuffled = order.map { Choice(choices[$0]) }
        // A valid fact always finds its answer here; fall back to 0 rather than crash on bad data.
        let correct = order.firstIndex(of: correctChoice) ?? 0
        let serial = UInt32.random(in: 0...UInt32.max, using: &rng)
        return Question(id: "\(id).\(serial)", itemID: id, prompt: prompt, trump: nil, visual: .none,
                        choices: shuffled, correctChoice: correct, explanation: explanation, difficulty: 1)
    }
}

/// One screen of a lesson. Lessons are short (2–4 minutes) and alternate explanation with
/// active recall: worked examples are followed by "your turn" prediction questions.
public enum LessonPage: Hashable, Sendable {
    /// A short idea in 1–3 short paragraphs. `body` may use **bold** markdown.
    case text(title: String, body: String)
    /// A worked example with cards drawn on screen (dual coding).
    case cards(title: String, body: String, cards: [Card], trump: Trump?)
    /// A worked trick example: the plays, and who won (with the reason in `body`).
    case trick(title: String, body: String, plays: [Play], trump: Trump, winner: Int)
    /// "Your turn": the learner must commit to an answer before seeing the explanation (generation effect).
    case predict(Question)
    /// Key takeaways at the end of the lesson.
    case recap(points: [String])
}

public struct Lesson: Identifiable, Hashable, Sendable {
    /// "lesson.<n>"
    public var id: String
    public var number: Int
    public var title: String
    public var subtitle: String
    /// Chinese term for the lesson's key idea, e.g. "主牌 (zhǔpái): trumps".
    public var chineseTerm: String?
    public var estimatedMinutes: Int
    public var pages: [LessonPage]
    /// Skills this lesson introduces; they join spaced review once the lesson is passed.
    public var skills: [SkillID]
    /// Facts this lesson introduces.
    public var factIDs: [String]

    public init(id: String, number: Int, title: String, subtitle: String, chineseTerm: String?,
                estimatedMinutes: Int, pages: [LessonPage], skills: [SkillID], factIDs: [String]) {
        self.id = id
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.chineseTerm = chineseTerm
        self.estimatedMinutes = estimatedMinutes
        self.pages = pages
        self.skills = skills
        self.factIDs = factIDs
    }

    /// Item ids introduced by this lesson (skills then facts).
    public var itemIDs: [String] { skills.map(\.itemID) + factIDs }
}

public struct GlossaryEntry: Hashable, Sendable, Identifiable {
    public var english: String
    public var chinese: String
    public var pinyin: String
    public var meaning: String
    public var id: String { english }

    public init(english: String, chinese: String, pinyin: String, meaning: String) {
        self.english = english
        self.chinese = chinese
        self.pinyin = pinyin
        self.meaning = meaning
    }
}

public enum Curriculum {
    /// Lessons in order. Each builds on the previous one.
    public static let lessons: [Lesson] = [
        lesson1, lesson2, lesson3, lesson4, lesson5, lesson6,
        lesson7, lesson8, lesson9, lesson10, lesson11, lesson12,
    ]

    /// Every fact, in lesson order (content in Content/Facts.swift).
    public static let facts: [Fact] = allFacts

    /// Chinese terms with pinyin and meaning (content in Content/Glossary.swift).
    public static let glossary: [GlossaryEntry] = allGlossaryEntries

    public static func lesson(id: String) -> Lesson? { lessons.first { $0.id == id } }
    public static func fact(id: String) -> Fact? { facts.first { $0.id == id } }

    /// A question for any item id ("skill.*" → Drills, "fact.*" → Fact). Nil for unknown ids.
    public static func question<G: RandomNumberGenerator>(for itemID: String, difficulty: Int, rng: inout G) -> Question? {
        if let skill = SkillID(itemID: itemID) { return Drills.make(skill, difficulty: difficulty, rng: &rng) }
        return fact(id: itemID)?.question(rng: &rng)
    }
}
