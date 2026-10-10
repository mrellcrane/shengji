import Foundation

// API CONTRACT (stub). Implementations marked `fatalError("TODO")` are filled in by the engine work.
// Do not change public signatures without updating DESIGN.md and every caller.

/// Seats: 0 = South (the human), 1 = East, 2 = North (human's partner), 3 = West.
/// Play goes 0 → 1 → 2 → 3 → 0 (counter-clockwise, as in China). Partners sit opposite.
public enum Seats {
    public static let human = 0
    public static let all = [0, 1, 2, 3]
    public static func team(of player: Int) -> Int { player % 2 }
    public static func partner(of player: Int) -> Int { (player + 2) % 4 }
    public static func next(after player: Int) -> Int { (player + 1) % 4 }
    /// Display names from the human's point of view.
    public static func name(_ player: Int) -> String {
        switch player {
        case 0: return "You"
        case 1: return "East"
        case 2: return "Partner"
        default: return "West"
        }
    }
}

/// One player's contribution to a trick.
public struct Play: Hashable, Codable, Sendable {
    public var player: Int
    public var cards: [Card]
    public init(player: Int, cards: [Card]) {
        self.player = player
        self.cards = cards
    }
}

/// Why a lead is illegal.
public enum LeadViolation: Equatable, Sendable {
    case empty
    case cardsNotInHand
    /// Cards come from more than one suit group (e.g. a spade and a trump).
    case mixedSuits

    /// One or two plain-English sentences for the coach.
    public var explanation: String { fatalError("TODO") }
}

/// Why a follow is illegal. The explanation is shown to learners, so it must teach the rule.
public enum FollowViolation: Equatable, Sendable {
    case wrongCount(expected: Int)
    case cardsNotInHand
    /// The player still holds cards of the led group that they didn't play.
    case mustFollowSuit(SuitGroup)
    /// The player holds a tractor of the needed length in the led group but didn't play one.
    case mustPlayTractor(length: Int)
    /// The player had to play at least `required` pairs from the led group.
    case mustPlayPairs(required: Int)

    public var explanation: String { fatalError("TODO") }
}

/// What a follower is obliged to include when they have enough cards of the led group.
public struct FollowRequirement: Equatable, Sendable {
    /// Tractor lengths (in pairs) that must appear, disjoint, in the play.
    public var tractorLengths: [Int]
    /// Minimum number of pairs (counting the pairs inside required tractors) the play must contain.
    public var totalPairs: Int
    public init(tractorLengths: [Int], totalPairs: Int) {
        self.tractorLengths = tractorLengths
        self.totalPairs = totalPairs
    }
}

/// Result of checking a multi-component lead ("throw", 甩牌).
public enum ThrowCheck: Equatable, Sendable {
    case ok
    /// The throw fails: `blocker` holds a higher component of the same shape in that suit.
    /// The leader must instead play only `forced` (the lowest-ranked beatable component).
    case fails(forced: Component, blocker: Int)
}

public enum Rules {
    /// Lead legality: non-empty, from hand, one suit group. (Throw success is checked separately.)
    public static func validateLead(_ cards: [Card], hand: [Card], trump: Trump) -> LeadViolation? { fatalError("TODO") }

    /// True when the lead has more than one component (a throw).
    public static func isThrow(_ cards: [Card], trump: Trump) -> Bool { fatalError("TODO") }

    /// Checks a throw against every other player's hand. For each component of the throw,
    /// another player beats it if they hold, in the same group, a component of the same shape
    /// with higher strength (single: any higher card; pair: a higher pair; tractor(n): a tractor
    /// of n pairs with a higher top). Returns `.ok` for non-throws.
    public static func checkThrow(_ cards: [Card], leader: Int, hands: [[Card]], trump: Trump) -> ThrowCheck { fatalError("TODO") }

    /// Same as `checkThrow` but against an arbitrary pool of possibly-held cards treated as one hand
    /// (bots use the unseen cards). `.fails` carries blocker = -1.
    public static func checkThrow(_ cards: [Card], against pool: [Card], trump: Trump) -> ThrowCheck { fatalError("TODO") }

    /// Structure the follower must match, given the lead and the follower's cards in the led group.
    /// Algorithm (DESIGN.md §Following): walk the lead's components largest first; a tractor(k)
    /// requires a k-tractor if the follower has a run ≥ k, otherwise as many pairs as they have (≤ k);
    /// a pair requires a pair if available.
    public static func followRequirement(lead: [Card], suitCards: [Card], trump: Trump) -> FollowRequirement { fatalError("TODO") }

    /// Full follow legality. Returns nil if legal.
    ///  1. exactly lead.count cards, all from hand;
    ///  2. must play min(n, held) cards of the led group;
    ///  3. if the player holds ≥ n of the led group, the play must satisfy `followRequirement`.
    public static func validateFollow(_ cards: [Card], hand: [Card], lead: [Card], trump: Trump) -> FollowViolation? { fatalError("TODO") }

    /// Index into `plays` of the play currently winning the (possibly partial) trick. plays[0] is the lead.
    /// A later play beats the current winner only if it is entirely in the led group or entirely trump,
    /// matches the lead's structure (same component shapes), and its key component is stronger
    /// (trump beats non-trump). Ties go to the earlier play.
    public static func winningIndex(_ plays: [Play], trump: Trump) -> Int { fatalError("TODO") }

    /// True if `cards` (played after `lead`) have the same component structure as the lead,
    /// all from one group. Used by `winningIndex` and the bots.
    public static func matchesStructure(_ cards: [Card], lead: [Card], trump: Trump) -> Bool { fatalError("TODO") }
}
