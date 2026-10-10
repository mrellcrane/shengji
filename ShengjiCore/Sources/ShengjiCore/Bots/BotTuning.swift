import Foundation

/// Internal knobs for the standard strategy, so variants can be compared in duplicate matches
/// (tests play the same deals with the variants swapped between the teams). The defaults are the
/// shipped behaviour.
struct BotTuning: Hashable, Sendable {
    /// Declaring: trump share needed after 6 cards, easing to `declareLate` by the end of the deal.
    var declareEarly = 0.30
    var declareLate = 0.25
    /// Trump share needed to override an opponent's declaration with a suit.
    var overrideShare = 0.40
    /// Declarers with many trumps lead them (top pairs, else low singles).
    var drawTrumps = true
    /// Declarers draw trumps before cashing plain sure winners.
    var drawBeforeCashing = false
    /// Smallest trick value worth a ruff, for defenders and for declarers (declarers ruff
    /// for `defenderRuffStake` late in the round).
    var defenderRuffStake = 5
    var declarerRuffStake = 10
    /// Smallest trick value worth contesting with a card that might be beaten.
    var defenderContestStake = 10
    var declarerContestStake = 15
    /// Points the third player expects the last player (an opponent) to add if the trick is left
    /// to them: whoever wins it then usually collects their point cards too. Counted when an
    /// opponent is winning or could still beat the partner.
    var lastPlayerThreat = 10
}
