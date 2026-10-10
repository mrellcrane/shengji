import Foundation

/// The three hint steps, least help first (graduated prompting keeps the learner doing the thinking).
public enum HintStep: Int, Codable, CaseIterable, Comparable, Sendable {
    /// What to notice, without revealing the play.
    case nudge = 1
    /// The general principle that applies.
    case principle
    /// The exact cards, highlighted, with the reason.
    case show

    public static func < (lhs: HintStep, rhs: HintStep) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Button title for asking for this step.
    public var buttonTitle: String {
        switch self {
        case .nudge: return "Hint"
        case .principle: return "Another hint"
        case .show: return "Show me"
        }
    }
}

/// Walks a `BotDecision` through the hint steps. Value type; the table keeps one per decision.
public struct HintLadder: Hashable, Sendable {
    public let decision: BotDecision
    /// The step currently shown (nil before the first hint).
    public private(set) var step: HintStep?

    public init(decision: BotDecision) {
        self.decision = decision
        self.step = nil
    }

    /// The step the next tap reveals, or nil when everything is shown.
    public var nextStep: HintStep? {
        guard let step else { return .nudge }
        return HintStep(rawValue: step.rawValue + 1)
    }

    public var isComplete: Bool { step == .show }

    /// Reveals the next step (no-op when complete). Empty nudge/principle texts are skipped.
    public mutating func advance() {
        while let next = nextStep {
            step = next
            if !text.isEmpty { return }
        }
    }

    /// Learner-facing text for the current step (empty before the first hint).
    public var text: String {
        switch step {
        case .none: return ""
        case .nudge?: return decision.nudge
        case .principle?: return decision.principle
        case .show?: return decision.reason
        }
    }

    /// Cards to highlight: only once the play is revealed.
    public var highlightedCards: [Card] { step == .show ? decision.cards : [] }

    /// Concept tag to show alongside the hint (revealed from the principle step on).
    public var concept: String? {
        guard let step, step >= .principle, !decision.concept.isEmpty else { return nil }
        return decision.concept
    }
}
