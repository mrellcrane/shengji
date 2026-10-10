import Foundation
import ShengjiCore

/// Learner-facing names for scheduler items ("skill.*" and "fact.*").
enum ItemNames {
    /// A skill's title, or a fact's prompt shortened to fit one line.
    static func title(for itemID: String) -> String {
        if let skill = SkillID(itemID: itemID) { return skill.title }
        if let fact = Curriculum.fact(id: itemID) { return shortened(fact.prompt) }
        return itemID
    }

    /// Shortens a long prompt to its last sentence (usually the question itself),
    /// or else to `maxLength` characters ending with an ellipsis.
    static func shortened(_ prompt: String, maxLength: Int = 52) -> String {
        let text = prompt
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > maxLength else { return text }
        if let lastBreak = text.range(of: ". ", options: .backwards) {
            let question = text[lastBreak.upperBound...].trimmingCharacters(in: .whitespaces)
            if !question.isEmpty && question.count <= maxLength { return question }
        }
        let cut = text.prefix(maxLength)
        let wordCut = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return wordCut.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces)) + "…"
    }

    /// Unique learner-facing titles for a list of item ids, in order.
    static func titles(for itemIDs: [String]) -> [String] {
        var seen = Set<String>()
        return itemIDs.map(title(for:)).filter { seen.insert($0).inserted }
    }
}

/// Plain-English phrases for when something happens next.
enum TimePhrase {
    /// "now", "in about a minute", "in 10 minutes", "in 3 hours", "tomorrow", "in 4 days".
    static func until(_ date: Date, from now: Date = .now, calendar: Calendar = .current) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 30 { return "now" }
        if seconds < 90 { return "in about a minute" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "in \(minutes) minutes" }
        let hours = Int((seconds / 3600).rounded())
        let startOfToday = calendar.startOfDay(for: now)
        let startOfThatDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfThatDay).day ?? 0
        if days == 0 { return hours <= 1 ? "in about an hour" : "in \(hours) hours" }
        if days == 1 { return "tomorrow" }
        return "in \(days) days"
    }

    /// "1 review", "3 reviews".
    static func count(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// "4-day streak", or "No streak yet" for 0.
    static func streak(_ days: Int) -> String {
        if days <= 0 { return "No streak yet" }
        return days == 1 ? "1-day streak" : "\(days)-day streak"
    }
}

/// Where a lesson stands for this learner.
enum LessonState: Equatable {
    case locked
    case available
    case completed
}

/// The learning-science ideas behind the app, for the "Why this works" sheet.
struct LearningPrinciple: Identifiable {
    let id: String
    /// SF Symbol name.
    let symbol: String
    let title: String
    let body: String

    static let all: [LearningPrinciple] = [
        LearningPrinciple(
            id: "retrieval", symbol: "brain.head.profile", title: "Retrieval practice",
            body: "Pulling an answer out of your memory makes it stronger than reading it again. That's why every lesson ends with a quiz and reviews are all questions."),
        LearningPrinciple(
            id: "spacing", symbol: "calendar", title: "Spacing",
            body: "Each skill comes back after a minute, then 10 minutes, then a day, then longer. Reviewing just as you start to forget makes it last."),
        LearningPrinciple(
            id: "interleaving", symbol: "shuffle", title: "Interleaving",
            body: "Reviews mix different kinds of questions. You learn to spot which rule applies, just like at a real table."),
        LearningPrinciple(
            id: "worked", symbol: "lightbulb", title: "Worked examples, then you predict",
            body: "Lessons show a real example first. Then you guess the answer before you see it, which makes the explanation stick."),
        LearningPrinciple(
            id: "feedback", symbol: "checkmark.bubble", title: "Immediate feedback",
            body: "Every answer, right or wrong, shows the rule behind it straight away. Missed questions come back later in the same session."),
        LearningPrinciple(
            id: "fading", symbol: "figure.walk", title: "Help that fades",
            body: "At the table the coach starts by marking trumps and legal cards. As you improve, switch to Coached, then Solo."),
    ]
}
