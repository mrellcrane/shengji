import Foundation

// API CONTRACT (stub). Filled in by the achievements-core work.

/// Named Shengji moves the app recognises in real play. Each one is also a teaching unit:
/// it has a short explanation and a card example so the badge doubles as a mini lesson.
public enum MoveKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Win a trick by playing trump on a plain-suit lead you are out of (毙 bì).
    case ruff
    /// Beat an opponent's ruff in the same trick with a higher trump.
    case overruff
    /// Put point cards into a trick your partner wins (送分 sòngfēn).
    case feedPartner
    /// Lead a tractor, or win a trick with one (拖拉机 tuōlājī).
    case tractor
    /// Lead a successful throw (甩牌 shuǎipái).
    case cleanThrow
    /// Win a trick by leading a combination nobody could beat (e.g. the last ace of a suit).
    case topCard
    /// Win a trick with the big joker (大王 dàwáng).
    case bigJoker
    /// As a defender, win the last trick and collect the kitty bonus (抠底 kōudǐ).
    case kittyRaid
    /// Make the winning trump declaration (亮主 liàngzhǔ).
    case declareTrump
    /// Overturn an opponent's declaration with a stronger one (反主 fǎnzhǔ).
    case overrideDeclaration
    /// As declarers, keep the defenders under 80.
    case holdDeal
    /// As declarers, hold the defenders to 0 (declarers go up 3).
    case shutout
    /// As defenders, reach 80 points and take over the deal.
    case takeOver
    /// Your team wins a single trick worth 30 or more points.
    case bigTrick

    /// e.g. "Ruff"
    public var title: String { fatalError("TODO") }
    /// e.g. "毙 (bì)", nil if no common term.
    public var chineseTerm: String? { fatalError("TODO") }
    /// One or two sentences: what the move is and when to use it (teaching text, second person).
    public var howTo: String { fatalError("TODO") }
    /// SF Symbol name for the badge.
    public var symbol: String { fatalError("TODO") }
}

/// One recognised move, with a learner-facing toast line naming it.
public struct MoveEvent: Hashable, Codable, Sendable {
    public var kind: MoveKind
    /// Toast text, e.g. "Ruff! You trumped East's spade lead and won 15 points."
    public var detail: String
    /// Points involved (trick points, kitty bonus, ...), 0 if not applicable.
    public var points: Int

    public init(kind: MoveKind, detail: String, points: Int) {
        self.kind = kind
        self.detail = detail
        self.points = points
    }
}

/// Recognises moves from what actually happened in the round. Pure functions over engine values.
/// Only moves made by `player` (or, for team moves like holdDeal/takeOver/bigTrick/kittyRaid, by `player`'s team) count.
public enum MoveDetector {
    /// Moves in the completed trick `round.tricks[trickIndex]` (call right after the trick finishes; `round`
    /// supplies trump, history and roles). E.g. ruff: player's play was all trump on a plain lead and won;
    /// overruff: player won with trump after an opponent ruffed earlier in the trick; feedPartner: partner won and
    /// player's play contained points (and was not forced: player had a non-point alternative, or simply had
    /// point cards in the play while partner won; keep it simple and documented); tractor: player led a tractor
    /// or won with one; cleanThrow: player led a multi-component lead that stood; topCard: player led a single,
    /// pair or tractor in a plain suit, nobody ruffed, and it won; bigJoker: player won with a play containing a
    /// big joker as the key card; bigTrick: player's team won 30+ points in the trick.
    public static func moves(inTrick trickIndex: Int, of round: Round, player: Int = Seats.human) -> [MoveEvent] { fatalError("TODO") }

    /// Moves when the round is finished (`round.result` set): kittyRaid, holdDeal, shutout, takeOver.
    public static func moves(inFinishedRound round: Round, player: Int = Seats.human) -> [MoveEvent] { fatalError("TODO") }

    /// Declaration moves: call after the deal closes (finishDealing) with the round. declareTrump if `player`
    /// made the final winning declaration; overrideDeclaration once per time `player` overrode an opponent
    /// (from `round.declarationHistory`).
    public static func moves(inDeclarationsOf round: Round, player: Int = Seats.human) -> [MoveEvent] { fatalError("TODO") }
}
