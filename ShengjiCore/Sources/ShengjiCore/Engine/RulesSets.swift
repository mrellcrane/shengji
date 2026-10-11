import Foundation

// MARK: - Three or more decks: triples, four of a kind and tractors of them

/// The rules for tables with three or more decks (6 or 8 players), where a face can appear three or
/// four times. They extend the two-deck rules and agree with them whenever no face appears more than
/// twice (tests check this on two-deck positions), so the classic code paths in `Rules` are used
/// there and these only run when a lead, hand or play holds three or more copies of a face.
///
/// Following: walk the lead's components largest first, as with two decks. A set of `w` identical
/// cards asks for the widest set you hold up to `w` (a triple led: your triple, else a pair). A
/// tractor asks for the same tractor if you hold one, otherwise for each of its steps the widest set
/// you hold up to its width (a tractor of pairs: as many pairs as you have, up to its length).
/// Winning: a play competes only with the lead's exact structure (a triple beats a triple).
extension Rules {
    /// Required tractors (any width) and required sets (pairs, triples, ...), in the order found.
    typealias UnitWalk = (tractors: [ComboShape], sets: [ComboShape])

    /// `requirementWalk` over sets of any width. On cards with at most two copies of each face it
    /// gives the same answer as `requirementWalk` (the tractors, then each pair once).
    static func unitWalk(_ components: ArraySlice<Component>, remaining: [Card], trump: Trump) -> UnitWalk {
        guard let component = components.first else { return ([], []) }
        let rest = components.dropFirst()
        let shape = component.shape
        let width = shape.width
        if width < 2 { return unitWalk(rest, remaining: remaining, trump: trump) }

        if !shape.isTractor {
            // A set: the widest set held, up to the lead's width.
            let take = min(width, Combos.maxCopies(remaining))
            guard take >= 2, let set = Combos.sets(in: remaining, width: take, trump: trump).first else {
                return unitWalk(rest, remaining: remaining, trump: trump)
            }
            var left = remaining
            left.remove(cards: set)
            let sub = unitWalk(rest, remaining: left, trump: trump)
            return (sub.tractors, [ComboShape.make(width: take, length: 1)] + sub.sets)
        }

        let length = shape.length
        let reachable = rest.filter { $0.shape.isTractor }.count
        if Combos.longestRun(in: remaining, width: width, trump: trump) >= length {
            var best: UnitWalk?
            for tractor in Combos.setTractors(in: remaining, width: width, length: length, trump: trump) {
                var left = remaining
                left.remove(cards: tractor)
                let sub = unitWalk(rest, remaining: left, trump: trump)
                if let current = best {
                    if isMoreUnitStructure(sub.tractors, than: current.tractors) { best = sub }
                } else {
                    best = sub
                }
                if sub.tractors.count == reachable { break }
            }
            let chosen = best ?? ([], [])
            return ([shape] + chosen.tractors, chosen.sets)
        }

        if width == 2 { return pairsForTractor(length: length, rest: rest, remaining: remaining, trump: trump) }

        // No tractor that long: for each of its steps, the widest set held up to its width. Sets that
        // sit next to no other set can never join a tractor, so they go first.
        var left = remaining
        var owed: [ComboShape] = []
        for _ in 0..<length {
            let take = min(width, Combos.maxCopies(left))
            guard take >= 2 else { break }
            let options = Combos.allSets(in: left, width: take, trump: trump)
            let neighbours = Combos.pairs(in: left, trump: trump)
            guard let pick = options.first(where: { !isNextToAnotherPair($0, pairs: neighbours, trump: trump) })
                ?? options.first else { break }
            left.remove(cards: pick)
            owed.append(.make(width: take, length: 1))
        }
        let sub = unitWalk(rest, remaining: left, trump: trump)
        return (sub.tractors, owed + sub.sets)
    }

    /// A tractor of pairs the follower can't match: as many pairs as they have, up to its length,
    /// chosen as `requirementWalk` does (pairs next to no other pair first, then whichever leaves the
    /// most structure). Four identical cards count as two pairs.
    private static func pairsForTractor(length: Int, rest: ArraySlice<Component>, remaining: [Card],
                                        trump: Trump) -> UnitWalk {
        let pairs = Combos.allSets(in: remaining, width: 2, trump: trump)
        let count = min(pairs.count, length)
        let owed = Array(repeating: ComboShape.pair, count: count)
        let reachable = rest.filter { $0.shape.isTractor }.count
        let loose = pairs.filter { !isNextToAnotherPair($0, pairs: pairs, trump: trump) }
        let linked = pairs.filter { isNextToAnotherPair($0, pairs: pairs, trump: trump) }
        var base = remaining
        for pair in loose.prefix(count) { base.remove(cards: pair) }
        let stillOwed = count - min(count, loose.count)
        if stillOwed == 0 || reachable == 0 {
            for pair in linked.prefix(stillOwed) { base.remove(cards: pair) }
            let sub = unitWalk(rest, remaining: base, trump: trump)
            return (sub.tractors, owed + sub.sets)
        }
        var best: UnitWalk?
        forEachCombination(of: linked[...], size: stillOwed, chosen: []) { chosen in
            var left = base
            for pair in chosen { left.remove(cards: pair) }
            let sub = unitWalk(rest, remaining: left, trump: trump)
            if let current = best {
                if isMoreUnitStructure(sub.tractors, than: current.tractors) { best = sub }
            } else {
                best = sub
            }
            return sub.tractors.count == reachable
        }
        let chosen = best ?? ([], [])
        return (chosen.tractors, owed + chosen.sets)
    }

    /// `isMoreStructure` for tractors of any width: more tractors, then more cards in them, then the
    /// same tie-break on card counts.
    static func isMoreUnitStructure(_ a: [ComboShape], than b: [ComboShape]) -> Bool {
        if a.count != b.count { return a.count > b.count }
        let countsA = a.map(\.cardCount), countsB = b.map(\.cardCount)
        let sumA = countsA.reduce(0, +), sumB = countsB.reduce(0, +)
        if sumA != sumB { return sumA > sumB }
        return countsA.lexicographicallyPrecedes(countsB) == false && countsA != countsB
    }

    /// Shapes in search order: widest first, then longest.
    static func sortedUnits(_ units: [ComboShape]) -> [ComboShape] {
        units.enumerated().sorted { a, b in
            if a.element.width != b.element.width { return a.element.width > b.element.width }
            if a.element.length != b.element.length { return a.element.length > b.element.length }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// The violation for a play that doesn't contain every owed unit, or nil if it does. Names the
    /// first owed unit (in the requirement's order) that the play can't hold alongside those before it.
    static func unitViolation(_ cards: [Card], units: [ComboShape], trump: Trump) -> FollowViolation? {
        guard !units.isEmpty, !containsUnits(cards, units: units, trump: trump) else { return nil }
        var missing = units[0]
        for count in 1...units.count where !containsUnits(cards, units: Array(units.prefix(count)), trump: trump) {
            missing = units[count - 1]
            break
        }
        if missing.isTractor {
            if missing.width == 2 { return .mustPlayTractor(length: missing.length) }
            return .mustPlaySetTractor(width: missing.width, length: missing.length)
        }
        if missing.width == 2 {
            return .mustPlayPairs(required: units.filter { $0.width == 2 }.reduce(0) { $0 + $1.length })
        }
        return .mustPlaySets(width: missing.width, required: units.filter { $0 == missing }.count)
    }

    /// True if `cards` hold disjoint combinations of all the given shapes.
    static func containsUnits(_ cards: [Card], units: [ComboShape], trump: Trump) -> Bool {
        searchUnits(cards, shapes: sortedUnits(units)[...], trump: trump, chosen: []) { _, _ in true }
    }

    /// Backtracking search over every way to take disjoint combinations of the given shapes (in that
    /// order) out of `cards`. `visit` gets the leftover cards and the chosen combinations with their
    /// shapes; returning true stops the search. Returns true if a visit stopped it.
    @discardableResult
    static func searchUnits(_ cards: [Card], shapes: ArraySlice<ComboShape>, trump: Trump,
                            chosen: [(shape: ComboShape, cards: [Card])],
                            visit: ([Card], [(shape: ComboShape, cards: [Card])]) -> Bool) -> Bool {
        guard let shape = shapes.first else { return visit(cards, chosen) }
        let rest = shapes.dropFirst()
        // Combinations of the same shape are picked in increasing order of their lowest card id, so
        // each set of them is tried once instead of once per ordering.
        var floor: Int?
        if let previous = chosen.last, previous.shape == shape {
            floor = previous.cards.map(\.id).min()
        }
        for unit in Combos.units(of: shape, in: cards, trump: trump) {
            let lowestID = unit.map(\.id).min() ?? 0
            if let floor = floor, lowestID <= floor { continue }
            var left = cards
            left.remove(cards: unit)
            if searchUnits(left, shapes: rest, trump: trump, chosen: chosen + [(shape, unit)], visit: visit) {
                return true
            }
        }
        return false
    }

    /// `structureKey` for leads or plays with sets of three or more: the play must hold every
    /// component of the lead bigger than a single (singles are free); the key is the top strength of
    /// the play's combination matched to the lead's largest component, maximised over every matching.
    static func unitStructureKey(_ cards: [Card], format: LeadFormat, keyShape: ComboShape, trump: Trump) -> Int? {
        if keyShape == .single { return cards.map { trump.strength($0) }.max() }
        var best: Int?
        searchUnits(cards, shapes: format.units[...], trump: trump, chosen: []) { _, chosen in
            let key = chosen.filter { $0.shape == keyShape }.map { topStrength(of: $0.cards, trump: trump) }.max() ?? -1
            best = max(best ?? key, key)
            return key >= Trump.bigJokerStrength
        }
        return best
    }
}
