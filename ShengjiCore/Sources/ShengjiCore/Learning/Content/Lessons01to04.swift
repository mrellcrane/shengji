import Foundation

// Lessons 1 to 4: the big picture, cards and points, what is trump, and the trump order.
extension Curriculum {
    // MARK: Lesson 1

    static let lesson1 = Lesson(
        id: "lesson.1", number: 1,
        title: "The big picture",
        subtitle: "Teams, levels and the 80-point line",
        chineseTerm: "升级 (shēngjí): level up",
        estimatedMinutes: 3,
        pages: lesson1Pages,
        skills: [],
        factIDs: factIDs(forLesson: 1))

    private static let lesson1Pages: [LessonPage] = [
        .text(
            title: "Welcome to Shengji",
            body: "**Shengji** 升级 (shēngjí) means **level up**. It is a trick-taking game from China for four or more players. Many people call it **Tractor** 拖拉机 (tuōlājī), after its signature combination: two or more pairs in a row, like 5 5 6 6. You will meet it in lesson 7."),
        .text(
            title: "Partners sit opposite",
            body: "This app teaches the classic game for **4 players**, who form **two fixed teams**. Your **partner sits opposite** you; East and West are the other team. Play moves counter-clockwise: You, East, Partner, West. Partners win and lose together, so every card you play is also about helping your partner."),
        .cards(
            title: "Levels are your score",
            body: "Each team has a **level** 级 (jí). Both start at **2** and climb through 3, 4 and so on, then 10, J, Q, K, up to **A**. Good rounds move your team up the ladder. To win the game, reach A, then win a round there as the declaring team.",
            cards: Rank.allCases.map { c($0, .hearts) },
            trump: nil),
        .text(
            title: "Declarers and defenders",
            body: "Each round, the **dealer** 庄家 (zhuāngjiā) and partner are the **declarers**. The other team are the **defenders** 闲家 (xiánjiā). The declarers' level is the round's **trump rank**. Defenders try to capture **points**; declarers try to stop them."),
        predict(1, 1,
                prompt: "The deck holds 200 points. How many must the defenders capture to take over the deal?",
                choices: [Choice("60"), Choice("80"), Choice("100"), Choice("101")],
                correct: 1,
                explanation: "Just **80**: the defenders don't need half. Below 80, the declarers keep the deal and climb. At 80 or more, the defenders take over and become the declarers next round."),
        .cards(
            title: "The 80-point line",
            body: "These cards add up to **80 points**: only 5s, 10s and Kings score (lesson 2). If the defenders capture 80 or more, they **take over** the deal. Under 80, the declarers stay and climb 1 to 3 levels: the fewer points the defenders got, the more they climb.",
            cards: [c(.king, .spades), c(.king, .hearts), c(.king, .clubs), c(.king, .diamonds),
                    c(.ten, .spades), c(.ten, .hearts), c(.ten, .clubs), c(.five, .diamonds), c(.five, .clubs)],
            trump: nil),
        predict(1, 2,
                prompt: "You and your partner are declaring. The defenders end the round with 90 points. What happens?",
                choices: [Choice("You keep the deal and climb a level"),
                          Choice("The defenders take over the deal"),
                          Choice("The round is replayed")],
                correct: 1,
                explanation: "90 is over the **80-point line**, so the defenders take over: they become the declarers next round. With 80 to 115 they take over without climbing; with 120 or more they also climb."),
        .recap(points: [
            "Shengji 升级 (shēngjí) means level up; it is also called Tractor.",
            "You and the player opposite are partners for the whole game.",
            "The dealer's team declares; the other team defends.",
            "Defenders with 80 or more of the 200 points take over the deal.",
            "Win a round as declarers at level A to win the game.",
        ]),
    ]

    // MARK: Lesson 2

    static let lesson2 = Lesson(
        id: "lesson.2", number: 2,
        title: "Cards and points",
        subtitle: "108 cards, and the only ones that score",
        chineseTerm: "分 (fēn): points",
        estimatedMinutes: 3,
        pages: lesson2Pages,
        skills: [.pointValue, .countPoints],
        factIDs: factIDs(forLesson: 2))

    private static let lesson2Pages: [LessonPage] = [
        .text(
            title: "Why points matter",
            body: "Every round is a fight over **points**, 分 (fēn). The defenders need 80 to take over the deal. Knowing which cards score tells you when a trick is worth fighting for, and when to let it go cheaply."),
        .cards(
            title: "Two decks, 108 cards",
            body: "Four players use **two full decks plus all four jokers**: 108 cards. Every card exists **twice**, so you can hold two identical cards, like these two A♠. There are two small jokers and two big jokers. Bigger groups add a deck: 6 players use 3.",
            cards: pair(.ace, .spades) + [smallJoker0, smallJoker1, bigJoker0, bigJoker1],
            trump: nil),
        predict(2, 1,
                prompt: "Which of these cards is worth points?",
                choices: [cardChoice([c(.ace, .spades)]), cardChoice([c(.king, .hearts)]),
                          cardChoice([c(.queen, .clubs)]), Choice("Big joker", cards: [bigJoker0])],
                correct: 1,
                explanation: "**Kings** are worth 10. Aces, Queens and jokers win tricks, but they score **nothing** themselves. Only 5s, 10s and Kings carry points."),
        .cards(
            title: "The point cards",
            body: "Only three ranks score: **5s** are worth 5, **10s** and **Kings** are worth 10. Everything else, even an ace or a joker, is worth 0. One deck holds 100 points, so the two decks hold **200**.",
            cards: [c(.five, .spades), c(.ten, .hearts), c(.king, .clubs)],
            trump: nil),
        .cards(
            title: "Counting a trick",
            body: "The winner of a trick captures every card in it. Here: King **10** + ten **10** + five **5** + ace **0** = **25 points**. A trick can hold far more when players add points on purpose.",
            cards: [c(.king, .spades), c(.ten, .spades), c(.five, .spades), c(.ace, .spades)],
            trump: nil),
        predict(2, 2,
                prompt: "How many points are in these cards?",
                visual: .cards([c(.five, .hearts), c(.ten, .clubs), c(.king, .diamonds), c(.five, .spades), c(.queen, .hearts)]),
                choices: [Choice("20"), Choice("25"), Choice("30"), Choice("35")],
                correct: 2,
                explanation: "Two 5s make **10**, and the 10 and the King add **10 each**: 30 in all. The Queen is worth nothing."),
        predict(2, 3,
                prompt: "You are a declarer and you win a trick worth 20 points. What happens to those points?",
                choices: [Choice("Your team scores 20"),
                          Choice("Nothing: only the defenders' points count"),
                          Choice("The defenders score 20")],
                correct: 1,
                explanation: "Only the **defenders'** points are counted. When declarers win a trick, its points are simply kept away from the defenders. That still matters: every point you win is one they can't."),
        .text(
            title: "Only the defenders count",
            body: "At the end of a round, only the points the **defenders** captured are counted. The declarers never score points; they win by keeping points away. So when you declare, every point you capture is a point the defenders can't have."),
        .recap(points: [
            "Four players use two decks plus four jokers: 108 cards, every card twice.",
            "5s are worth 5; 10s and Kings are worth 10. Nothing else scores.",
            "The whole deck holds 200 points.",
            "Only the points the defenders capture are counted.",
        ]),
    ]

    // MARK: Lesson 3

    static let lesson3 = Lesson(
        id: "lesson.3", number: 3,
        title: "What's trump?",
        subtitle: "Jokers, the trump rank and the trump suit",
        chineseTerm: "主牌 (zhǔpái): trumps",
        estimatedMinutes: 3,
        pages: lesson3Pages,
        skills: [.isTrump],
        factIDs: factIDs(forLesson: 3))

    private static let sevenHearts = Trump(rank: .seven, suit: .hearts)

    private static let lesson3Pages: [LessonPage] = [
        .text(
            title: "Trumps beat everything",
            body: "A **trump** beats any card of a plain suit, even an ace. In Shengji about **a third of the deck** is trump, more than in most card games. So the first skill every player needs is spotting exactly which cards are trumps."),
        predict(3, 1,
                prompt: "This round the trump rank is 7 and the trump suit is ♥. Which of these cards is a trump?",
                trump: sevenHearts,
                choices: [cardChoice([c(.ace, .spades)]), cardChoice([c(.king, .clubs)]),
                          cardChoice([c(.seven, .spades)]), cardChoice([c(.queen, .diamonds)])],
                correct: 2,
                explanation: "Every **7** is a trump this round, whatever its suit, because 7 is the **trump rank**. Aces and Kings of plain suits are not trumps."),
        .cards(
            title: "Three kinds of trump",
            body: "Trumps, 主牌 (zhǔpái), come in three kinds: all four **jokers**, every card of the **trump rank** (here 7s, in any suit), and every card of the **trump suit** (here ♥). Everything else is a plain card, 副牌 (fùpái).",
            cards: [bigJoker0, smallJoker0, c(.seven, .hearts), c(.seven, .spades), c(.ace, .hearts), c(.three, .hearts)],
            trump: sevenHearts),
        .cards(
            title: "Where trump comes from",
            body: "The **trump rank** is the declarers' level: at level 7, every 7 is a trump. These rank cards are called 级牌 (jípái). The **trump suit** is picked while the cards are dealt (lesson 9). The jokers are always trumps.",
            cards: [c(.seven, .spades), c(.seven, .hearts), c(.seven, .clubs), c(.seven, .diamonds)],
            trump: sevenHearts),
        predict(3, 2,
                prompt: "Trump rank 10, trump suit ♠. How many of these cards are trumps?",
                trump: Trump(rank: .ten, suit: .spades),
                visual: .cards([c(.ten, .diamonds), c(.three, .spades), smallJoker0, c(.ace, .hearts), c(.king, .clubs)]),
                choices: [Choice("1"), Choice("2"), Choice("3"), Choice("4")],
                correct: 2,
                explanation: "Three: the **10♦** is a rank card, the **3♠** is in the trump suit, and the **joker** is always trump. The A♥ and K♣ are plain cards."),
        .cards(
            title: "No trump suit",
            body: "Sometimes a round has **no trump suit**, 无主 (wúzhǔ). Then only the **jokers** and the **rank cards** are trumps, and all four suits are plain. This happens, for example, after someone declares with a pair of jokers (lesson 9).",
            cards: [bigJoker0, smallJoker0, c(.three, .spades), c(.three, .hearts), c(.three, .clubs), c(.three, .diamonds)],
            trump: Trump(rank: .three, suit: nil)),
        predict(3, 3,
                prompt: "Trump rank 7, trump suit ♥. West leads a club. Does your 7♣ count as a club?",
                trump: sevenHearts,
                visual: .cards([c(.seven, .clubs)]),
                choices: [Choice("Yes, it is a club"), Choice("No, it is a trump")],
                correct: 1,
                explanation: "Rank cards join the trumps for the whole round. Your 7♣ can't follow a club lead. If you have no real clubs, you may play it as a trump."),
        .cards(
            title: "All trumps are one suit",
            body: "For following, all trumps count as **one suit**. When a trump is led, a 7♣ or a joker follows it just as a heart does. And your 7♣ can't follow a club lead: it isn't a club this round.",
            cards: [c(.seven, .clubs), smallJoker0, c(.king, .hearts), c(.four, .hearts)],
            trump: sevenHearts),
        .recap(points: [
            "Trumps 主牌 (zhǔpái): the jokers, every trump-rank card and every trump-suit card.",
            "The trump rank is the declarers' level; the trump suit is picked during the deal.",
            "No trump suit 无主 (wúzhǔ): only jokers and rank cards are trumps.",
            "All trumps are one suit: with rank 7, your 7♣ is a trump, not a club.",
        ]),
    ]

    // MARK: Lesson 4

    static let lesson4 = Lesson(
        id: "lesson.4", number: 4,
        title: "The order of trumps",
        subtitle: "From the big joker down to the smallest trump",
        chineseTerm: "大王 (dàwáng) and 小王 (xiǎowáng): the jokers",
        estimatedMinutes: 3,
        pages: lesson4Pages,
        skills: [.trumpOrder],
        factIDs: factIDs(forLesson: 4))

    private static let twoHearts = Trump(rank: .two, suit: .hearts)
    private static let nineSpades = Trump(rank: .nine, suit: .spades)

    private static let lesson4Pages: [LessonPage] = [
        .text(
            title: "Which trump is bigger?",
            body: "When two trumps meet, the higher one wins. Knowing the order tells you which of your trumps are **sure winners**, and which ones the opponents can still beat. It's a short list, and you'll use it in every trick."),
        predict(4, 1,
                prompt: "Trump rank 2, trump suit ♥. Which trump is highest?",
                trump: twoHearts,
                choices: [cardChoice([c(.ace, .hearts)]), cardChoice([c(.two, .spades)]),
                          cardChoice([c(.two, .hearts)]), Choice("Small joker", cards: [smallJoker0])],
                correct: 3,
                explanation: "The **jokers** top every other trump. The small joker beats the 2♥, the other 2s and the A♥. Only the big joker is higher."),
        .cards(
            title: "The order, high to low",
            body: "**Big joker** 大王 (dàwáng), then **small joker** 小王 (xiǎowáng). Then the **rank card of the trump suit** (2♥), then the **other rank cards**, all equal. Then the trump suit from **A** down to its lowest card.",
            cards: [bigJoker0, smallJoker0, c(.two, .hearts), c(.two, .spades), c(.two, .clubs), c(.two, .diamonds),
                    c(.ace, .hearts), c(.king, .hearts), c(.three, .hearts)],
            trump: twoHearts),
        predict(4, 2,
                prompt: "Trump rank 9, trump suit ♠. Which is higher?",
                trump: nineSpades,
                choices: [cardChoice([c(.nine, .diamonds)]), cardChoice([c(.ace, .spades)]), Choice("They are equal")],
                correct: 0,
                explanation: "**Every rank card** outranks the ace of the trump suit. The order is jokers, 9♠, the other 9s, then A♠, K♠ and on down."),
        .cards(
            title: "Equal rank cards",
            body: "With ♥ trump and rank 2, the **2♠ and 2♣ are equal**. If both land in one trick, the **first one played wins**. They are not a pair either: a pair needs two identical cards.",
            cards: [c(.two, .spades), c(.two, .clubs)],
            trump: twoHearts),
        .cards(
            title: "Skipping the rank",
            body: "Rank cards leave their suit, so the order **jumps over** them. With rank 9 and ♠ trump, the 8♠ sits right below the 10♠. Plain suits skip the rank too: 8♦ is just below 10♦.",
            cards: [c(.jack, .spades), c(.ten, .spades), c(.eight, .spades), c(.seven, .spades)],
            trump: nineSpades),
        predict(4, 3,
                prompt: "Trump rank 5, trump suit ♣. Which trump is highest?",
                trump: Trump(rank: .five, suit: .clubs),
                choices: [cardChoice([c(.ace, .clubs)]), cardChoice([c(.five, .clubs)]),
                          cardChoice([c(.five, .hearts)]), cardChoice([c(.king, .clubs)])],
                correct: 1,
                explanation: "With no jokers here, the **5♣**, the rank card of the trump suit, is highest. The 5♥ comes next, then A♣ and K♣."),
        .cards(
            title: "No trump suit",
            body: "With **no trump suit** the order is short: big joker, small joker, then the rank cards of all four suits, which are **equal**. Every other card is a plain card.",
            cards: [bigJoker0, smallJoker0, c(.five, .spades), c(.five, .hearts), c(.five, .clubs), c(.five, .diamonds)],
            trump: Trump(rank: .five, suit: nil)),
        .recap(points: [
            "Big joker 大王 (dàwáng), then small joker 小王 (xiǎowáng), then the trump suit's rank card.",
            "Rank cards of the other suits are equal; the first one played wins.",
            "Then the trump suit from A down, skipping the rank.",
            "No trump suit: jokers, then all rank cards, equal.",
        ]),
    ]
}
