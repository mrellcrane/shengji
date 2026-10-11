import ShengjiCore

/// Deterministic randomness on top of `SeededGenerator`. Only `next()` is used, never the
/// standard library's random algorithms, so the vectors cannot drift with the Swift version.
struct Rand {
    private var generator: SeededGenerator

    init(_ seed: UInt64) { generator = SeededGenerator(seed: seed) }

    /// 0..<n (n > 0).
    mutating func below(_ n: Int) -> Int {
        precondition(n > 0, "below(0)")
        return Int(generator.next() % UInt64(n))
    }

    /// low...high.
    mutating func between(_ low: Int, _ high: Int) -> Int { low + below(high - low + 1) }

    mutating func percent(_ p: Int) -> Bool { below(100) < p }

    mutating func pick<T>(_ items: [T]) -> T? { items.isEmpty ? nil : items[below(items.count)] }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var out = items
        var i = out.count - 1
        while i > 0 {
            out.swapAt(i, below(i + 1))
            i -= 1
        }
        return out
    }

    mutating func sample<T>(_ items: [T], _ count: Int) -> [T] { Array(shuffled(items).prefix(max(0, count))) }
}

enum Cards {
    static let all: [Card] = (0..<108).map { card($0) }
    static let faces: [Face] = (0..<54).map { face($0) }

    /// Every card of `decks` decks (54 per deck), in id order: `all` with 2.
    static func deck(_ decks: Int) -> [Card] { decks == 2 ? all : (0..<(54 * decks)).map { card($0) } }

    /// The tables with three or more decks, the ones the bigger-table vectors cover.
    static let bigTables: [TableSize] = [.six, .eight]

    static func card(_ id: Int) -> Card {
        guard let card = Card(id: id) else { fatalError("bad card id \(id)") }
        return card
    }

    static func face(_ index: Int) -> Face {
        guard let face = Face(index: index) else { fatalError("bad face index \(index)") }
        return face
    }

    static func byID(_ cards: [Card]) -> [Card] { cards.sorted { $0.id < $1.id } }

    static func faces(in group: SuitGroup, trump: Trump) -> [Face] {
        faces.filter { trump.group($0) == group }
    }

    /// Groups of `hand` in a fixed order (trump first, then suits), each sorted by id.
    static func groups(_ hand: [Card], trump: Trump) -> [[Card]] {
        let order: [SuitGroup] = [.trump] + Suit.allCases.map { SuitGroup.plain($0) }
        let sorted = byID(hand)
        return order.map { group in sorted.filter { trump.group($0) == group } }.filter { !$0.isEmpty }
    }

    static func randomTrump(_ rand: inout Rand, noTrumpPercent: Int = 20) -> Trump {
        let rank = Rank.allCases[rand.below(Rank.allCases.count)]
        let suit: Suit? = rand.percent(noTrumpPercent) ? nil : Suit.allCases[rand.below(4)]
        return Trump(rank: rank, suit: suit)
    }

    static func randomGroup(_ rand: inout Rand, trump: Trump) -> SuitGroup {
        let plain = Suit.allCases.filter { $0 != trump.suit }
        if rand.percent(40) { return .trump }
        return .plain(plain[rand.below(plain.count)])
    }

    /// Trump faces near the top of the order (jokers, rank cards, the top of the trump suit):
    /// where tractors cross the skipped rank and the equal off-suit rank cards.
    static func topTrumpFaces(_ trump: Trump) -> [Face] {
        faces.filter { trump.group($0) == .trump && trump.strength($0) >= Trump.topPlainStrength - 2 }
    }

    /// Faces of a plain suit within `radius` ranks of the trump rank (tractors skipping the rank).
    static func faces(nearRankOf trump: Trump, suit: Suit, radius: Int) -> [Face] {
        faces.filter { face in
            guard let s = face.suit, let r = face.rank, s == suit, r != trump.rank else { return false }
            return abs(r.rawValue - trump.rank.rawValue) <= radius
        }
    }
}

/// A set of distinct cards being handed out (no card twice), from two decks or more.
struct CardPool {
    private var used: [Bool]
    /// Decks the cards come from (2 for four players).
    let decks: Int

    init(decks: Int = 2) {
        self.decks = decks
        used = [Bool](repeating: false, count: 54 * decks)
    }

    mutating func take(_ card: Card) -> Bool {
        guard used.indices.contains(card.id), !used[card.id] else { return false }
        used[card.id] = true
        return true
    }

    /// The copies of `face` still available (one per deck at most).
    func copies(of face: Face) -> [Card] {
        (0..<decks).map { Cards.card(face.index + 54 * $0) }.filter { !used[$0.id] }
    }

    func remaining(where include: (Card) -> Bool = { _ in true }) -> [Card] {
        Cards.deck(decks).filter { !used[$0.id] && include($0) }
    }

    /// Takes cards of `faces` (picked at random) until `count` cards are taken or nothing is left:
    /// `multiPercent` of the time several copies of the face at once (from two up to as many as are
    /// left and fit: pairs, triples, four of a kind), otherwise one.
    mutating func takeCopies(_ faces: [Face], count: Int, multiPercent: Int, rand: inout Rand) -> [Card] {
        var cards: [Card] = []
        var attempts = 0
        while cards.count < count && attempts < 300 {
            attempts += 1
            guard let face = rand.pick(faces) else { break }
            let available = copies(of: face)
            if available.isEmpty { continue }
            let room = min(available.count, count - cards.count)
            let width = room >= 2 && rand.percent(multiPercent) ? rand.between(2, room) : 1
            for card in rand.sample(available, width) where take(card) { cards.append(card) }
        }
        return cards
    }

    /// Takes cards of `faces` (picked at random, both copies `pairPercent` of the time) until
    /// `count` cards are taken or nothing is left.
    mutating func takeFaces(_ faces: [Face], count: Int, pairPercent: Int, rand: inout Rand) -> [Card] {
        var cards: [Card] = []
        var attempts = 0
        while cards.count < count && attempts < 300 {
            attempts += 1
            guard let face = rand.pick(faces) else { break }
            let available = copies(of: face)
            if available.isEmpty { continue }
            let both = available.count == 2 && cards.count + 2 <= count && rand.percent(pairPercent)
            let chosen = both ? available : [available[rand.below(available.count)]]
            for card in chosen where take(card) { cards.append(card) }
        }
        return cards
    }
}

// MARK: Plays

enum Plays {
    /// A random lead: singles, pairs, tractors and throw attempts (some of which fail).
    static func randomLead(hand: [Card], trump: Trump, rand: inout Rand, throwPercent: Int) -> [Card] {
        let byGroup = Cards.groups(hand, trump: trump)
        guard let groupCards = rand.pick(byGroup), let single = rand.pick(groupCards) else { return [] }
        let roll = rand.below(100)
        if roll < throwPercent, let attempt = throwAttempt(groupCards, trump: trump, rand: &rand) {
            return attempt
        }
        if roll < throwPercent + 25 {
            let longest = Combos.longestRun(in: groupCards, trump: trump)
            if longest >= 2 {
                let length = rand.between(2, longest)
                if let tractor = rand.pick(Combos.tractors(in: groupCards, length: length, trump: trump)) {
                    return rand.shuffled(tractor)
                }
            }
        }
        if roll < throwPercent + 50, let pair = rand.pick(Combos.pairs(in: groupCards, trump: trump)) {
            return pair
        }
        return [single]
    }

    /// A lead for rules positions: structured throws and tractors are common, so followers face
    /// pair and tractor obligations; some throws are built to succeed.
    static func structuredLead(hand: [Card], others: [[Card]], trump: Trump, rand: inout Rand) -> [Card] {
        let byGroup = Cards.groups(hand, trump: trump)
        guard let groupCards = rand.pick(byGroup) else { return [] }
        let roll = rand.below(100)
        if roll < 15, let sure = sureThrow(hand: hand, others: others, trump: trump, rand: &rand) { return sure }
        if roll < 45, let attempt = throwAttempt(groupCards, trump: trump, rand: &rand) { return attempt }
        if roll < 75 {
            // The longest tractor in any group, else a pair.
            var best: [[Card]] = []
            var bestLength = 1
            for cards in byGroup {
                let longest = Combos.longestRun(in: cards, trump: trump)
                if longest > bestLength {
                    bestLength = longest
                    best = Combos.tractors(in: cards, length: longest, trump: trump)
                } else if longest == bestLength && longest >= 2 {
                    best += Combos.tractors(in: cards, length: longest, trump: trump)
                }
            }
            if let tractor = rand.pick(best) { return rand.shuffled(tractor) }
        }
        if roll < 90, let pair = rand.pick(Combos.pairs(in: groupCards, trump: trump)) { return pair }
        return randomLead(hand: hand, trump: trump, rand: &rand, throwPercent: 30)
    }

    /// Bigger tables: a lead from a hand that may hold triples and four of a kind. Often a set or a
    /// tractor of sets (sometimes only part of one: two cards of a triple, a tractor of pairs taken
    /// from a tractor of triples), sometimes a throw with a set in it, otherwise `structuredLead`.
    static func setLead(hand: [Card], others: [[Card]], trump: Trump, rand: inout Rand) -> [Card] {
        let byGroup = Cards.groups(hand, trump: trump)
        guard let groupCards = rand.pick(byGroup) else { return [] }
        let roll = rand.below(100)
        if roll < 12, let sure = sureThrow(hand: hand, others: others, trump: trump, rand: &rand) { return sure }
        if roll < 55 {
            var options: [Component] = []
            for cards in byGroup {
                options += Combos.decompose(cards, trump: trump).filter { $0.shape.width >= 3 }
            }
            if let pick = rand.pick(options) {
                guard rand.percent(30) else { return rand.shuffled(pick.cards) }
                // Fewer copies at each step of the set or tractor.
                let width = rand.between(2, pick.shape.width - 1)
                var cards: [Card] = []
                var start = 0
                while start < pick.cards.count {
                    cards += pick.cards[start..<(start + width)]
                    start += pick.shape.width
                }
                return rand.shuffled(cards)
            }
        }
        if roll < 70 {
            // A throw: a set with other components of its group.
            let components = Combos.decompose(groupCards, trump: trump)
            let sets = components.filter { $0.shape.width >= 3 }
            if let set = rand.pick(sets), components.count >= 2 {
                let rest = components.filter { $0.cards != set.cards }
                let extra = rand.sample(rest, rand.between(1, min(3, rest.count)))
                return rand.shuffled(([set] + extra).flatMap(\.cards))
            }
        }
        return structuredLead(hand: hand, others: others, trump: trump, rand: &rand)
    }

    /// Follow attempts aimed at the obligations of sets (bigger tables): every owed combination but
    /// one (each in turn), filled with single cards first; and `legal` with one card of its widest
    /// combination swapped for another card of the led group.
    static func setAttempts(hand: [Card], lead: [Card], trump: Trump, legal: [Card], rand: inout Rand) -> [[Card]] {
        guard let first = lead.first else { return [] }
        let n = lead.count
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let held = Cards.byID(hand).filter { trump.group($0) == ledGroup }
        guard held.count >= n, n >= 2 else { return [] }
        let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
        let shapes = widestFirst(requirement.units)
        var attempts: [[Card]] = []
        for skip in shapes.indices {
            var kept = shapes
            kept.remove(at: skip)
            guard let units = disjointUnits(in: held, shapes: kept, trump: trump, rand: &rand) else { continue }
            var rest = held
            var play: [Card] = []
            for unit in units {
                play += unit
                rest.remove(cards: unit)
            }
            let singles = Combos.components(of: .single, in: rest, trump: trump).map { $0.cards[0] }
            let others = rest.filter { !singles.contains($0) }
            play += Array((rand.shuffled(singles) + rand.shuffled(others)).prefix(n - play.count))
            if play.count == n { attempts.append(rand.shuffled(play)) }
        }
        if let widest = Combos.decompose(legal, trump: trump).first(where: { $0.shape.width >= 2 }),
           let last = widest.cards.last,
           let spare = held.first(where: { !legal.contains($0) && $0.face != last.face }) {
            var broken = legal
            broken.remove(cards: [last])
            broken.append(spare)
            attempts.append(broken)
        }
        return attempts
    }

    /// True if `cards` hold a component of the same shape and group as `component` with a higher top.
    static func canBeat(_ component: Component, with cards: [Card], trump: Trump) -> Bool {
        let own = Combos.cards(cards, in: component.group, trump: trump)
        return Combos.components(of: component.shape, in: own, trump: trump).contains {
            $0.topStrength > component.topStrength
        }
    }

    /// Two or more components of one group that no other hand can beat (a throw that succeeds).
    static func sureThrow(hand: [Card], others: [[Card]], trump: Trump, rand: inout Rand) -> [Card]? {
        for groupCards in rand.shuffled(Cards.groups(hand, trump: trump)) {
            let safe = Combos.decompose(groupCards, trump: trump).filter { component in
                !others.contains { canBeat(component, with: $0, trump: trump) }
            }
            if safe.count >= 2 {
                return rand.shuffled(rand.sample(safe, rand.between(2, safe.count)).flatMap(\.cards))
            }
        }
        return nil
    }

    /// Several cards of one group: a random subset, a few whole components, or the top components.
    static func throwAttempt(_ groupCards: [Card], trump: Trump, rand: inout Rand) -> [Card]? {
        guard groupCards.count >= 2 else { return nil }
        let components = Combos.decompose(groupCards, trump: trump)
        switch rand.below(3) {
        case 0:
            return rand.sample(groupCards, rand.between(2, min(8, groupCards.count)))
        case 1:
            guard components.count >= 2 else { return nil }
            let chosen = rand.sample(components, rand.between(2, min(4, components.count)))
            return rand.shuffled(chosen.flatMap(\.cards))
        default:
            // The strongest components: these throws succeed more often.
            let top = components.map(\.topStrength).max() ?? 0
            let strong = components.filter { $0.topStrength >= top - rand.between(0, 2) }
            guard strong.count >= 2 else { return nil }
            return strong.prefix(4).flatMap(\.cards)
        }
    }

    /// A legal follow built from the rules: required tractors, then pairs, then random filler.
    static func legalFollow(hand: [Card], lead: [Card], trump: Trump, rand: inout Rand) -> [Card] {
        guard let first = lead.first else { return [] }
        let n = lead.count
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let sorted = Cards.byID(hand)
        let held = sorted.filter { trump.group($0) == ledGroup }
        let others = sorted.filter { trump.group($0) != ledGroup }
        var play: [Card]
        if held.count <= n {
            play = held + rand.sample(others, n - held.count)
        } else if let units = setFollow(held: held, lead: lead, trump: trump, rand: &rand) {
            play = units
        } else {
            let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
            var pool = held
            play = []
            if let tractors = disjointTractors(in: pool, lengths: requirement.tractorLengths, trump: trump, rand: &rand) {
                for tractor in tractors {
                    play += tractor
                    pool.remove(cards: tractor)
                }
            }
            var pairCount = requirement.tractorLengths.reduce(0, +)
            var pairs = rand.shuffled(Combos.pairs(in: pool, trump: trump))
            while pairCount < requirement.totalPairs, let pair = pairs.popLast() {
                play += pair
                pool.remove(cards: pair)
                pairCount += 1
            }
            play += rand.sample(pool, n - play.count)
        }
        play = rand.shuffled(play)
        guard Rules.validateFollow(play, hand: hand, lead: lead, trump: trump) == nil else {
            fatalError("ShengjiVectors could not build a legal follow to \(lead.shortText) from \(hand.shortText)")
        }
        return play
    }

    /// Three or more decks (a face held or led three or more times): every owed combination of the
    /// requirement, chosen at random, then random filler from the led group. Nil with two decks, so
    /// the two-deck vectors draw exactly the random numbers they always did.
    static func setFollow(held: [Card], lead: [Card], trump: Trump, rand: inout Rand) -> [Card]? {
        guard Combos.maxCopies(held) > 2 || Combos.maxCopies(lead) > 2 else { return nil }
        let requirement = Rules.followRequirement(lead: lead, suitCards: held, trump: trump)
        guard let units = disjointUnits(in: held, shapes: widestFirst(requirement.units), trump: trump, rand: &rand) else {
            fatalError("ShengjiVectors could not find the owed units \(requirement.units) in \(held.shortText)")
        }
        var pool = held
        var play: [Card] = []
        for unit in units {
            play += unit
            pool.remove(cards: unit)
        }
        return play + rand.sample(pool, lead.count - play.count)
    }

    /// Shapes widest first, then longest (the order the rules search them in).
    static func widestFirst(_ shapes: [ComboShape]) -> [ComboShape] {
        shapes.enumerated().sorted { a, b in
            if a.element.width != b.element.width { return a.element.width > b.element.width }
            if a.element.length != b.element.length { return a.element.length > b.element.length }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Disjoint combinations of the given shapes, chosen at random among the possible ones.
    static func disjointUnits(in cards: [Card], shapes: [ComboShape], trump: Trump, rand: inout Rand) -> [[Card]]? {
        guard let shape = shapes.first else { return [] }
        for unit in rand.shuffled(Combos.units(of: shape, in: cards, trump: trump)) {
            var rest = cards
            rest.remove(cards: unit)
            if let more = disjointUnits(in: rest, shapes: Array(shapes.dropFirst()), trump: trump, rand: &rand) {
                return [unit] + more
            }
        }
        return nil
    }

    /// Disjoint tractors of the given lengths, chosen at random among the possible ones.
    static func disjointTractors(in cards: [Card], lengths: [Int], trump: Trump, rand: inout Rand) -> [[Card]]? {
        guard let length = lengths.first else { return [] }
        for tractor in rand.shuffled(Combos.tractors(in: cards, length: length, trump: trump)) {
            var rest = cards
            rest.remove(cards: tractor)
            if let more = disjointTractors(in: rest, lengths: Array(lengths.dropFirst()), trump: trump, rand: &rand) {
                return [tractor] + more
            }
        }
        return nil
    }

    /// When void in a plain led suit: trumps with the lead's exact component shapes, if held.
    static func ruff(hand: [Card], lead: [Card], trump: Trump, rand: inout Rand) -> [Card]? {
        guard let first = lead.first else { return nil }
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        guard !ledGroup.isTrump, Combos.cards(hand, in: ledGroup, trump: trump).isEmpty else { return nil }
        var trumps = Cards.byID(Combos.cards(hand, in: .trump, trump: trump))
        var play: [Card] = []
        for component in Combos.decompose(lead, trump: trump) {
            guard let match = rand.pick(Combos.components(of: component.shape, in: trumps, trump: trump)) else {
                return nil
            }
            play += match.cards
            trumps.remove(cards: match.cards)
        }
        return rand.shuffled(play)
    }

    /// A legal follow, sometimes a ruff when void.
    static func follow(hand: [Card], lead: [Card], trump: Trump, rand: inout Rand) -> [Card] {
        if rand.percent(70), let ruff = ruff(hand: hand, lead: lead, trump: trump, rand: &rand) { return ruff }
        return legalFollow(hand: hand, lead: lead, trump: trump, rand: &rand)
    }

    /// Follow attempts that are usually illegal (wrong suit, broken structure, wrong count, cards
    /// from elsewhere), for violation vectors.
    static func randomAttempts(hand: [Card], lead: [Card], trump: Trump, elsewhere: [Card],
                               rand: inout Rand) -> [[Card]] {
        guard let first = lead.first else { return [] }
        let n = lead.count
        let ledGroup = Combos.group(of: lead, trump: trump) ?? trump.group(first)
        let held = Cards.byID(hand).filter { trump.group($0) == ledGroup }
        let others = Cards.byID(hand).filter { trump.group($0) != ledGroup }
        var attempts: [[Card]] = []
        // Any n cards.
        attempts.append(rand.sample(hand, n))
        // As many led-group cards as possible, then filler: right suit, often wrong structure.
        let inGroup = rand.sample(held, min(n, held.count))
        attempts.append(rand.shuffled(inGroup + rand.sample(others, n - inGroup.count)))
        // Singles of the led group before any pairs: breaks pair and tractor obligations.
        if held.count >= n && n >= 2 {
            let singlesFirst = Combos.components(of: .single, in: held, trump: trump).map { $0.cards[0] }
            let pairsLast = held.filter { card in !singlesFirst.contains(card) }
            attempts.append(Array((rand.shuffled(singlesFirst) + pairsLast).prefix(n)))
        }
        // Some of the follower's tractors (not necessarily the required ones), then other led-group
        // cards: misses one of several required tractors.
        if held.count >= n && n >= 4 {
            var pool = held
            var play: [Card] = []
            for length in rand.shuffled(Array(2...max(2, Combos.longestRun(in: held, trump: trump)))) {
                guard let tractor = rand.pick(Combos.tractors(in: pool, length: length, trump: trump)),
                      play.count + tractor.count <= n else { continue }
                play += tractor
                pool.remove(cards: tractor)
            }
            if !play.isEmpty {
                let singles = Combos.components(of: .single, in: pool, trump: trump).map { $0.cards[0] }
                let rest = pool.filter { !singles.contains($0) }
                attempts.append(play + Array((rand.shuffled(singles) + rand.shuffled(rest)).prefix(n - play.count)))
            }
        }
        if rand.percent(15) {
            attempts.append(rand.sample(hand, n + (n > 1 && rand.percent(50) ? -1 : 1)))
        }
        if rand.percent(15), let stranger = rand.pick(elsewhere) {
            attempts.append(Array(rand.sample(hand, n - 1)) + [stranger])
        }
        return attempts.filter { !$0.isEmpty || n == 0 }
    }
}
