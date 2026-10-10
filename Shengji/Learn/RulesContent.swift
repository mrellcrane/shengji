import Foundation
import ShengjiCore

/// One row of a two-column rules table.
struct RuleTableRow: Hashable, Sendable {
    let left: String
    let right: String
}

/// A piece of a rules section: words, card pictures, a trick diagram, a table or glossary terms.
enum RuleBlock: Sendable {
    /// A short paragraph; may use **bold** markdown.
    case text(String)
    case bullets([String])
    /// A few cards with a caption underneath (and the trump context, if it matters).
    case cards(caption: String, cards: [Card], trump: Trump?)
    /// A whole trick around the table.
    case trick(caption: String, plays: [Play], trump: Trump, winner: Int)
    case table(header: RuleTableRow, rows: [RuleTableRow])
    case glossary([GlossaryEntry])

    /// Everything a search should look at in this block.
    var searchableText: String {
        switch self {
        case let .text(text): return text
        case let .bullets(items): return items.joined(separator: " ")
        case let .cards(caption, cards, _): return caption + " " + cards.shortText
        case let .trick(caption, _, _, _): return caption
        case let .table(header, rows):
            return ([header] + rows).map { $0.left + " " + $0.right }.joined(separator: " ")
        case let .glossary(entries): return entries.map(RulesContent.searchableText(of:)).joined(separator: " ")
        }
    }
}

struct RuleSection: Identifiable, Sendable {
    let id: String
    let title: String
    /// Short label for the jump bar.
    let shortTitle: String
    /// SF Symbol name.
    let symbol: String
    let blocks: [RuleBlock]
}

/// The rules reference (the variant DESIGN.md describes), as data the Rules tab draws and searches.
enum RulesContent {
    /// All sections, built once.
    static let sections: [RuleSection] = makeSections(glossary: Curriculum.glossary)

    /// Sections matching a search. A section matches on its title or any of its text;
    /// the glossary keeps only the matching terms. Case and accents are ignored ("tuolaji" finds 拖拉机 tuōlājī).
    static func filtered(_ sections: [RuleSection], query: String) -> [RuleSection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }
        return sections.compactMap { section in
            if matches(section.title, query) { return section }
            var kept: [RuleBlock] = []
            var anyTextMatch = false
            for block in section.blocks {
                if case let .glossary(entries) = block {
                    let hits = entries.filter { matches(searchableText(of: $0), query) }
                    if !hits.isEmpty { kept.append(.glossary(hits)) }
                } else {
                    kept.append(block)
                    if matches(block.searchableText, query) { anyTextMatch = true }
                }
            }
            if anyTextMatch { return RuleSection(id: section.id, title: section.title, shortTitle: section.shortTitle,
                                                 symbol: section.symbol, blocks: kept) }
            let glossaryHits = kept.filter { block in
                if case .glossary = block { return true }
                return false
            }
            guard !glossaryHits.isEmpty else { return nil }
            return RuleSection(id: section.id, title: section.title, shortTitle: section.shortTitle,
                               symbol: section.symbol, blocks: glossaryHits)
        }
    }

    static func matches(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func searchableText(of entry: GlossaryEntry) -> String {
        [entry.english, entry.chinese, entry.pinyin, entry.meaning].joined(separator: " ")
    }

    // MARK: Content

    private static func card(_ rank: Rank, _ suit: Suit, _ copy: Int = 0) -> Card { Card(rank, suit, copy: copy) }

    static func makeSections(glossary: [GlossaryEntry]) -> [RuleSection] {
        let heartsTwo = Trump(rank: .two, suit: .hearts)
        let rankEight = Trump(rank: .eight, suit: .hearts)
        let noTrumpTwo = Trump(rank: .two, suit: nil)

        return [
            RuleSection(id: "goal", title: "Goal & teams", shortTitle: "Goal", symbol: "person.2.fill", blocks: [
                .text("Four players play in **two teams**. Your **partner** sits opposite you, so you and your partner play against East and West."),
                .text("Each team has a **level**. Both start at 2 and climb 2, 3, 4 … 10, J, Q, K, A. The level of the dealer's team is this round's **trump rank**."),
                .text("The dealer's team are the **declarers**; the other team are the **defenders**. The defenders try to win **80 points** or more in tricks. The declarers try to stop them."),
                .text("Win a round as declarers while your team is at **A** and you win the game. That's where the name comes from: 升级 (shēngjí) means \"level up\"."),
            ]),
            RuleSection(id: "points", title: "Cards & points", shortTitle: "Points", symbol: "suit.heart.fill", blocks: [
                .text("Two full decks with jokers: **108 cards**. Everyone gets 25 cards and the last 8 form the kitty."),
                .text("Only three ranks score: **5s** are worth 5, **10s** and **Kings** are worth 10. That's 200 points in all."),
                .cards(caption: "5 + 10 + 10 = 25 points", cards: [card(.five, .hearts), card(.ten, .spades), card(.king, .clubs)], trump: nil),
                .cards(caption: "No points: aces and jokers win tricks but score nothing.", cards: [card(.ace, .spades), .bigJoker()], trump: nil),
            ]),
            RuleSection(id: "trumps", title: "Trumps & their order", shortTitle: "Trumps", symbol: "star.fill", blocks: [
                .text("**Trumps** (主牌 zhǔpái) beat every plain card. They are all the **jokers**, all cards of the **trump rank**, and all cards of the **trump suit**."),
                .text("Highest to lowest: big joker, small joker, the trump-rank card of the trump suit, the other trump-rank cards (all equal), then A, K, Q … of the trump suit."),
                .cards(caption: "Trump suit ♥, rank 2, highest first. The 2♠ and 2♣ are equal.",
                       cards: [.bigJoker(), .smallJoker(), card(.two, .hearts), card(.two, .spades), card(.two, .clubs),
                               card(.ace, .hearts), card(.king, .hearts), card(.three, .hearts)],
                       trump: heartsTwo),
                .text("All trumps count as **one suit**. With rank 2, the 2♠ is a trump, not a spade."),
                .text("Plain suits run from A down to 2, **skipping the trump rank**."),
                .cards(caption: "Rank 8: the 9♠ and 7♠ sit next to each other, because the 8s are trumps.",
                       cards: [card(.nine, .spades), card(.seven, .spades)], trump: rankEight),
                .text("In a **no-trump** round there is no trump suit: only jokers and trump-rank cards are trumps, and the rank cards are all equal."),
                .cards(caption: "No trump suit, rank 2: jokers and 2s are the only trumps.",
                       cards: [.bigJoker(), .smallJoker(), card(.two, .spades), card(.two, .hearts), card(.two, .clubs), card(.two, .diamonds)],
                       trump: noTrumpTwo),
            ]),
            RuleSection(id: "declaring", title: "Declaring trump", shortTitle: "Declaring", symbol: "hand.raised.fill", blocks: [
                .text("Cards are dealt one at a time. While they arrive, anyone can **declare** (亮主 liàng zhǔ) by showing trump-rank cards. The suit shown becomes the trump suit."),
                .bullets([
                    "One trump-rank card of a suit (weakest)",
                    "A pair of trump-rank cards of one suit",
                    "A pair of small jokers: no trump suit",
                    "A pair of big jokers: no trump suit (strongest)",
                ]),
                .cards(caption: "Rank 2: showing one 2♥ makes hearts trump.", cards: [card(.two, .hearts)], trump: nil),
                .cards(caption: "A pair of 2♠ is stronger, so it takes over: spades become trump.",
                       cards: [card(.two, .spades), card(.two, .spades, 1)], trump: nil),
                .text("A new declaration must be **stronger** than the current one. If the current one is yours, you may only reinforce it: turn your single into a pair of the same suit."),
                .text("In the first round, whoever wins the declaring becomes the **dealer** (庄家 zhuāngjiā). If nobody declares, the kitty is turned over card by card: the first trump-rank card or joker decides (a joker means no trump suit). If neither turns up, the suit of the highest kitty card is trump."),
            ]),
            RuleSection(id: "kitty", title: "The kitty", shortTitle: "Kitty", symbol: "tray.full.fill", blocks: [
                .text("The **kitty** (底牌 dǐpái) is the 8 cards left after the deal. The dealer picks them up, then **buries** any 8 cards face down (扣底 kòu dǐ)."),
                .text("Burying point cards is allowed but risky. If the defenders win the **last trick**, they also score the kitty's points, multiplied by 2 × the number of cards in the biggest part of that trick's lead: a single ×2, a pair ×4, a tractor of two pairs ×8."),
                .cards(caption: "Buried: 10♦ and 5♣, 15 points. Defenders win the last trick with a pair: 15 × 4 = 60 points.",
                       cards: [card(.ten, .diamonds), card(.five, .clubs)], trump: nil),
            ]),
            RuleSection(id: "leading", title: "Leading & combinations", shortTitle: "Leading", symbol: "rectangle.stack.fill", blocks: [
                .text("Whoever leads may play any one **combination**:"),
                .bullets([
                    "**Single**: any one card.",
                    "**Pair** (对子 duìzi): two identical cards, such as two 7♠.",
                    "**Tractor** (拖拉机 tuōlājī): two or more pairs next to each other in strength, in one suit.",
                ]),
                .cards(caption: "A pair: two identical cards.", cards: [card(.seven, .spades), card(.seven, .spades, 1)], trump: nil),
                .cards(caption: "Not a pair: with rank 2, the 2♠ and 2♣ are equal trumps, but they aren't identical.",
                       cards: [card(.two, .spades), card(.two, .clubs)], trump: heartsTwo),
                .cards(caption: "A tractor when 8 is the rank: the 8s are trumps, so 7 and 9 are next to each other.",
                       cards: [card(.seven, .spades), card(.seven, .spades, 1), card(.nine, .spades), card(.nine, .spades, 1)],
                       trump: rankEight),
                .cards(caption: "A trump tractor: a pair of small jokers and a pair of big jokers.",
                       cards: [.smallJoker(), .smallJoker(copy: 1), .bigJoker(), .bigJoker(copy: 1)], trump: heartsTwo),
                .text("The leader may also **throw** several combinations of one suit at once (see Throws)."),
            ]),
            RuleSection(id: "following", title: "Following", shortTitle: "Following", symbol: "arrow.turn.down.right", blocks: [
                .text("Play the **same number of cards** as the lead (跟牌 gēn pái)."),
                .text("If you have enough cards of the led suit, you must play **only that suit**. Remember that all trumps are one suit."),
                .text("Match the shape when you can: a **pair** for a pair; a **tractor** for a tractor, or else as many pairs as you have. Singles need nothing special."),
                .text("If you run short of the led suit, play all you have of it and fill up with any cards. Playing trumps when you're out of the led suit is called a **ruff**, and it can win."),
                .cards(caption: "K♣ K♣ is led and you hold 4♣ 4♣ 9♣: you must play your pair, 4♣ 4♣.",
                       cards: [card(.four, .clubs), card(.four, .clubs, 1), card(.nine, .clubs)], trump: heartsTwo),
            ]),
            RuleSection(id: "winning", title: "Winning tricks", shortTitle: "Winning", symbol: "trophy.fill", blocks: [
                .text("A play can only win if it is **all the led suit** or **all trumps**, and has the **same shape** as the lead."),
                .text("Any trump beats a plain card. Otherwise the higher card wins. If two plays tie, the **earlier** one wins. The winner takes the trick's points for their team and leads next."),
                .trick(caption: "You lead K♠ and Partner tops it with A♠. West has no spades and ruffs with 4♥, a trump, so West wins.",
                       plays: [
                           Play(player: 0, cards: [card(.king, .spades)]),
                           Play(player: 1, cards: [card(.three, .spades)]),
                           Play(player: 2, cards: [card(.ace, .spades)]),
                           Play(player: 3, cards: [card(.four, .hearts)]),
                       ],
                       trump: heartsTwo, winner: 3),
                .text("Against a pair, only a pair can win: a higher pair of the led suit, or a pair of trumps."),
                .trick(caption: "West leads a pair of 9♦. East's J♦ J♦ is a higher pair and wins. Partner's K♦ is higher but isn't part of a pair.",
                       plays: [
                           Play(player: 3, cards: [card(.nine, .diamonds), card(.nine, .diamonds, 1)]),
                           Play(player: 0, cards: [card(.four, .diamonds), card(.six, .diamonds)]),
                           Play(player: 1, cards: [card(.jack, .diamonds), card(.jack, .diamonds, 1)]),
                           Play(player: 2, cards: [card(.king, .diamonds), card(.three, .diamonds)]),
                       ],
                       trump: heartsTwo, winner: 1),
            ]),
            RuleSection(id: "throws", title: "Throws", shortTitle: "Throws", symbol: "rectangle.split.3x1.fill", blocks: [
                .text("A **throw** (甩牌 shuǎipái) is several combinations of one suit led together, such as an ace plus a pair of kings."),
                .cards(caption: "A♠ with K♠ K♠: a single and a pair thrown at once.",
                       cards: [card(.ace, .spades), card(.king, .spades), card(.king, .spades, 1)], trump: heartsTwo),
                .text("It works only if **nobody** can beat any part of it with the same shape in that suit: no higher single, no higher pair, no higher tractor."),
                .text("If it fails, you play only the **lowest part that can be beaten** (smallest shape first) and take the rest back. There's no extra penalty."),
            ]),
            RuleSection(id: "scoring", title: "Scoring & levels", shortTitle: "Scoring", symbol: "chart.bar.fill", blocks: [
                .text("After the last trick, count the defenders' points: the points they won in tricks, plus the kitty bonus if they won the last trick."),
                .table(header: RuleTableRow(left: "Defenders", right: "Result"), rows: [
                    RuleTableRow(left: "0", right: "Declarers go up 3 levels"),
                    RuleTableRow(left: "5 to 35", right: "Declarers go up 2"),
                    RuleTableRow(left: "40 to 75", right: "Declarers go up 1"),
                    RuleTableRow(left: "80 to 115", right: "Defenders take over the deal"),
                    RuleTableRow(left: "120 to 155", right: "Take over and go up 1"),
                    RuleTableRow(left: "160 to 195", right: "Take over and go up 2"),
                    RuleTableRow(left: "200 or more", right: "Take over and go up 3, plus 1 for every extra 40"),
                ]),
                .text("**Next dealer:** if the declarers hold, the dealer's partner deals. If the defenders take over, the player after the dealer deals."),
                .text("Levels stop at A. To win the game, your team must win a round as declarers while at A."),
            ]),
            RuleSection(id: "glossary", title: "Glossary", shortTitle: "Glossary", symbol: "character.book.closed.fill", blocks: [
                .glossary(glossary),
            ]),
        ]
    }
}
