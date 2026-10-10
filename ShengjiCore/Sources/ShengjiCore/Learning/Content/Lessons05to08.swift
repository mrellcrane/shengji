import Foundation

// Lessons 5 to 8: following suit, pairs, tractors, and who wins a full trick.
extension Curriculum {
    /// Trump suit ♥, trump rank 2: the default context for lessons 5 to 8.
    private static let heartsTwo = Trump(rank: .two, suit: .hearts)

    private static let seatNames: [Choice] = Seats.all.map { seatChoice($0) }

    // MARK: Lesson 5

    static let lesson5 = Lesson(
        id: "lesson.5", number: 5,
        title: "Following suit",
        subtitle: "Follow, ruff or discard, and who wins",
        chineseTerm: "跟牌 (gēnpái): following",
        estimatedMinutes: 3,
        pages: lesson5Pages,
        skills: [.cardBeats],
        factIDs: factIDs(forLesson: 5))

    private static let lesson5Pages: [LessonPage] = [
        .text(
            title: "Tricks decide everything",
            body: "Points are won in **tricks**. One player leads, everyone else plays in turn, and the best card takes the whole trick, points and all. The rules for following decide what you may play, and when a small trump can steal a trick."),
        .trick(
            title: "A simple trick",
            body: "You lead the K♠. Everyone has spades, so everyone must play one. The **highest card of the led suit** wins: Partner's A♠ takes the trick, so your King's 10 points stay with your team. The winner leads next.",
            plays: [play(0, [c(.king, .spades)]), play(1, [c(.four, .spades)]),
                    play(2, [c(.ace, .spades)]), play(3, [c(.nine, .spades)])],
            trump: heartsTwo, winner: 2),
        .text(
            title: "Follow suit",
            body: "If you hold any card of the **led suit**, you must play one: that is **following**, 跟牌 (gēnpái). If a trump is led, play a trump if you have one. Only when you have no cards of the led suit, when you are **void**, may you play something else."),
        predict(5, 1,
                prompt: "Trump suit ♥, rank 2. East leads the A♣. You have no clubs and play the 3♥. Who wins the trick?",
                trump: heartsTwo,
                visual: .trick([play(1, [c(.ace, .clubs)]), play(2, [c(.seven, .clubs)]),
                                play(3, [c(.nine, .clubs)]), play(0, [c(.three, .hearts)])]),
                choices: seatNames,
                correct: 0,
                explanation: "**Any trump beats every plain card**, even an ace. You were void in clubs, so your 3♥ wins. Playing a trump when you can't follow is **ruffing**, 毙 (bì)."),
        .trick(
            title: "Ruffing",
            body: "East has no diamonds and **ruffs** with the 6♥. Partner's A♦ is the highest diamond, but **a trump beats any plain card**. East wins the trick, and West's K♦ gives their team 10 points.",
            plays: [play(3, [c(.king, .diamonds)]), play(0, [c(.four, .diamonds)]),
                    play(1, [c(.six, .hearts)]), play(2, [c(.ace, .diamonds)])],
            trump: heartsTwo, winner: 1),
        .trick(
            title: "Discarding",
            body: "You have no spades and choose not to trump: you **discard** 垫牌 (diànpái) the 8♣. A discard can **never win**, however high. Partner's Q♠ is the highest spade played, so it wins. Ruffing is always allowed, never required.",
            plays: [play(2, [c(.queen, .spades)]), play(3, [c(.jack, .spades)]),
                    play(0, [c(.eight, .clubs)]), play(1, [c(.ten, .spades)])],
            trump: heartsTwo, winner: 2),
        predict(5, 2,
                prompt: "Trump suit ♥, rank 2. West and you both play an A♦. Who wins the trick?",
                trump: heartsTwo,
                visual: .trick([play(2, [c(.queen, .diamonds)]), play(3, [c(.ace, .diamonds)]),
                                play(0, [c(.ace, .diamonds, 1)]), play(1, [c(.three, .diamonds)])]),
                choices: [seatChoice(2), seatChoice(3), seatChoice(0)],
                correct: 1,
                explanation: "Identical cards **tie**, and a tie goes to the **earlier play**. West played the A♦ before you, so West wins. Partner's Q♦ was beaten by both aces."),
        predict(5, 3,
                prompt: "Trump suit ♥, rank 2. West leads the K♠ and you have no spades. Which of your cards would beat it?",
                trump: heartsTwo,
                visual: .trick([play(3, [c(.king, .spades)])]),
                choices: [cardChoice([c(.ace, .clubs)]), cardChoice([c(.queen, .diamonds)]),
                          cardChoice([c(.three, .hearts)])],
                correct: 2,
                explanation: "Only a **trump** beats a lead you can't follow. Your A♣ and Q♦ would be discards, and a discard never wins, however high."),
        .recap(points: [
            "Follow the led suit if you can: 跟牌 (gēnpái).",
            "Void in the suit? Ruff with a trump 毙 (bì), or discard anything 垫牌 (diànpái).",
            "The highest card of the led suit wins, unless someone trumps.",
            "A discard never wins. Identical cards: the first one played wins.",
        ]),
    ]

    // MARK: Lesson 6

    static let lesson6 = Lesson(
        id: "lesson.6", number: 6,
        title: "Pairs",
        subtitle: "Two identical cards, and how to follow them",
        chineseTerm: "对子 (duìzi): pair",
        estimatedMinutes: 4,
        pages: lesson6Pages,
        skills: [.isPair, .legalFollow],
        factIDs: factIDs(forLesson: 6))

    private static let lesson6Pages: [LessonPage] = [
        .text(
            title: "Two of a kind",
            body: "With two decks, every card exists **twice**. Two identical cards make a **pair**, 对子 (duìzi). A pair is far stronger than two singles: once a pair is led, only a **higher pair** can beat it."),
        predict(6, 1,
                prompt: "Trump suit ♥, rank 2. Which of these is a pair?",
                trump: heartsTwo,
                choices: [cardChoice([c(.two, .spades), c(.two, .clubs)]),
                          cardChoice(pair(.queen, .diamonds)),
                          Choice("Small and big joker", cards: [smallJoker0, bigJoker0]),
                          cardChoice([c(.nine, .clubs), c(.ten, .clubs)])],
                correct: 1,
                explanation: "A pair is **two identical cards**: same rank and same suit, like Q♦ Q♦. The 2♠ and 2♣ are equal in strength but different cards, and two different jokers are not a pair either."),
        .cards(
            title: "What makes a pair",
            body: "K♣ K♣ is a pair, and so are two small jokers. **Equal is not enough**: 2♠ 2♣ is not a pair, even when 2 is the trump rank, because the cards are not identical. Neither is a small joker with a big joker.",
            cards: pair(.king, .clubs) + [smallJoker0, smallJoker1],
            trump: heartsTwo),
        .trick(
            title: "A pair beats singles",
            body: "East and West have no spade pair, so each plays two singles. Even West's A♠ can't beat a pair: **only a higher pair** can. Your 8♠ 8♠ wins, and Partner adds 15 points with the 10♠ and 5♠.",
            plays: [play(0, pair(.eight, .spades)), play(1, [c(.jack, .spades), c(.three, .spades)]),
                    play(2, [c(.ten, .spades), c(.five, .spades)]), play(3, [c(.ace, .spades), c(.queen, .spades)])],
            trump: heartsTwo, winner: 0),
        predict(6, 2,
                prompt: "Trump suit ♥, rank 2. East leads 9♣ 9♣. Which play is legal for you?",
                trump: heartsTwo,
                visual: .handAndLead(hand: pair(.jack, .clubs) + [c(.four, .clubs), c(.ace, .spades), c(.six, .hearts)],
                                     lead: pair(.nine, .clubs), leader: 1),
                choices: [cardChoice([c(.jack, .clubs), c(.four, .clubs)]),
                          cardChoice(pair(.jack, .clubs)),
                          cardChoice([c(.four, .clubs), c(.ace, .spades)])],
                correct: 1,
                explanation: "You hold a club pair, so you **must** play it. Splitting the pair isn't allowed, and you can't play a spade while you still have clubs."),
        .text(
            title: "Following a pair",
            body: "When a pair is led, play **two cards**. 1. Stay in the **led suit** while you have cards of it. 2. Hold a **pair** in that suit? You must play it. 3. No pair? Play any two cards of the suit. 4. Only one card of the suit? Play it plus any other card."),
        predict(6, 3,
                prompt: "Trump suit ♥, rank 2. West leads 7♦ 7♦. Which play is legal for you?",
                trump: heartsTwo,
                visual: .handAndLead(hand: [c(.king, .diamonds), c(.three, .diamonds)] + pair(.eight, .spades) + [c(.queen, .hearts)],
                                     lead: pair(.seven, .diamonds), leader: 3),
                choices: [cardChoice([c(.king, .diamonds), c(.three, .diamonds)]),
                          cardChoice(pair(.eight, .spades)),
                          cardChoice([c(.three, .diamonds), c(.queen, .hearts)])],
                correct: 0,
                explanation: "You have two diamonds but no diamond pair, so you play **both diamonds**. Your spade pair doesn't count: you must follow the led suit first."),
        .cards(
            title: "One card short",
            body: "With only **one** card of the led suit, play it, then add **any** card. A play that mixes suits can't win the trick, so add your least useful card: here the 3♦ plus a low 6♣, keeping your points and trumps.",
            cards: [c(.three, .diamonds), c(.six, .clubs)],
            trump: heartsTwo),
        .recap(points: [
            "A pair 对子 (duìzi) is two identical cards: same suit and rank, or two identical jokers.",
            "2♠ 2♣ is never a pair, even when 2 is the trump rank.",
            "Only a higher pair beats a pair.",
            "Following a pair: stay in the led suit, and play a pair if you hold one.",
        ]),
    ]

    // MARK: Lesson 7

    static let lesson7 = Lesson(
        id: "lesson.7", number: 7,
        title: "Tractors",
        subtitle: "Pairs in a row, the game's namesake",
        chineseTerm: "拖拉机 (tuōlājī): tractor",
        estimatedMinutes: 4,
        pages: lesson7Pages,
        skills: [.isTractor],
        factIDs: factIDs(forLesson: 7))

    private static let lesson7Pages: [LessonPage] = [
        .text(
            title: "The game's namesake",
            body: "Here is the play the game is named after. A **tractor**, 拖拉机 (tuōlājī), is two or more **pairs in a row**, like 5 5 6 6. Only a **higher tractor** of the same length can beat it, so a tractor often wins a big trick."),
        predict(7, 1,
                prompt: "Trump suit ♥, rank 2. Which of these is a tractor?",
                trump: heartsTwo,
                choices: [cardChoice(pair(.seven, .diamonds) + pair(.nine, .diamonds)),
                          cardChoice(pair(.jack, .clubs) + pair(.queen, .clubs)),
                          cardChoice(pair(.four, .spades) + pair(.five, .hearts))],
                correct: 1,
                explanation: "J♣ J♣ Q♣ Q♣ is two pairs of **consecutive** rank in one suit. 7 and 9 are not neighbours (the 8 sits between them), and 4♠ 5♥ mixes a plain suit with trumps."),
        .cards(
            title: "Pairs in a row",
            body: "A tractor needs **two or more pairs** of **consecutive rank** in the **same suit**, like 9♣ 9♣ 10♣ 10♣. Three pairs in a row, like J J Q Q K K, make a longer tractor, and only a tractor just as long can beat it.",
            cards: pair(.nine, .clubs) + pair(.ten, .clubs),
            trump: heartsTwo),
        .cards(
            title: "Skipping the trump rank",
            body: "Rank cards are trumps, so they leave their suit. With **8** as the trump rank, **7♠ 7♠ 9♠ 9♠ is a tractor**: with the 8 gone, 7 and 9 are neighbours. This works in every suit.",
            cards: pair(.seven, .spades) + pair(.nine, .spades),
            trump: Trump(rank: .eight, suit: .hearts)),
        predict(7, 2,
                prompt: "Trump suit ♦, rank 10. Is 9♣ 9♣ J♣ J♣ a tractor?",
                trump: Trump(rank: .ten, suit: .diamonds),
                visual: .cards(pair(.nine, .clubs) + pair(.jack, .clubs)),
                choices: [Choice("Yes"), Choice("No")],
                correct: 0,
                explanation: "The 10s are trumps this round, so **9♣ and J♣ are neighbours** in clubs. Two pairs in a row in one suit: a tractor."),
        .cards(
            title: "Trump tractors",
            body: "Trumps form tractors too, following the trump order. With rank 2 and ♥ trump, **A♥ A♥ 2♠ 2♠** is a tractor: the other 2s sit just above the A♥. Two small jokers plus two big jokers make the **highest tractor** in the game.",
            cards: pair(.ace, .hearts) + pair(.two, .spades),
            trump: heartsTwo),
        predict(7, 3,
                prompt: "Trump suit ♥, rank 2. Is 2♠ 2♠ 2♣ 2♣ a tractor?",
                trump: heartsTwo,
                visual: .cards(pair(.two, .spades) + pair(.two, .clubs)),
                choices: [Choice("Yes"), Choice("No")],
                correct: 1,
                explanation: "2♠ and 2♣ are **equal**, so their pairs are not consecutive: it's just two pairs. **2♠ 2♠ 2♥ 2♥** would be a tractor, because the 2♥ ranks right above the other 2s."),
        .text(
            title: "Following a tractor",
            body: "When a tractor is led, follow in that suit with a **tractor** if you have one. If not, play **as many pairs** as you hold, up to the tractor's size, then fill with other cards of the suit. Only a higher tractor of the same length wins."),
        .recap(points: [
            "A tractor 拖拉机 (tuōlājī) is two or more pairs of consecutive rank in one suit.",
            "Skip the trump rank: with rank 8, 7 7 9 9 is a tractor.",
            "Trumps follow the trump order: A♥ A♥ 2♠ 2♠ works with rank 2 and ♥ trump.",
            "Equal rank cards (2♠ 2♠ 2♣ 2♣) are not consecutive: no tractor.",
            "Follow a tractor with a tractor if you can, else with as many pairs as you have.",
        ]),
    ]

    // MARK: Lesson 8

    static let lesson8 = Lesson(
        id: "lesson.8", number: 8,
        title: "Who wins the trick?",
        subtitle: "Pairs, tractors and ruffs in full tricks",
        chineseTerm: "毙 (bì): ruffing",
        estimatedMinutes: 4,
        pages: lesson8Pages,
        skills: [.trickWinner],
        factIDs: factIDs(forLesson: 8))

    private static let lesson8Pages: [LessonPage] = [
        .text(
            title: "Putting it together",
            body: "Now for full tricks with pairs and tractors. A play can only take the trick if it has **the same shape** as the lead and is **all one suit**: all led suit or all trump. Learn this check and you'll always know who takes the points."),
        predict(8, 1,
                prompt: "Trump suit ♥, rank 2. West leads Q♠ Q♠. Who wins the trick?",
                trump: heartsTwo,
                visual: .trick([play(3, pair(.queen, .spades)), play(0, [c(.ace, .spades), c(.king, .spades)]),
                                play(1, pair(.three, .spades)), play(2, pair(.six, .hearts))]),
                choices: seatNames,
                correct: 2,
                explanation: "Partner has no spades and plays a **trump pair**, which beats any plain pair. East's 3♠ 3♠ is too low, and your A♠ K♠ are two singles: they **can't beat a pair**, however high."),
        .text(
            title: "Three checks",
            body: "To beat the play that is winning, yours must: 1. have the **same shape** as the lead (pair for pair, tractor for tractor), 2. be **all led suit or all trump**, 3. be **higher**. Any trump play beats a plain one. On a tie, the **earlier** play wins."),
        .trick(
            title: "Mixed plays can't win",
            body: "Partner has no club pair. West holds one club and adds a joker, but **mixed plays never win**. With ♠ trump, your 3♠ 8♠ are trumps but **not a pair**, so they can't beat a pair. Nobody matches the shape: East wins.",
            plays: [play(1, pair(.jack, .clubs)), play(2, [c(.king, .clubs), c(.four, .clubs)]),
                    play(3, [c(.nine, .clubs), bigJoker0]), play(0, [c(.three, .spades), c(.eight, .spades)])],
            trump: Trump(rank: .seven, suit: .spades), winner: 1),
        predict(8, 2,
                prompt: "Trump suit ♦, rank 5. You lead the tractor 8♥ 8♥ 9♥ 9♥. Who wins the trick?",
                trump: Trump(rank: .five, suit: .diamonds),
                visual: .trick([play(0, pair(.eight, .hearts) + pair(.nine, .hearts)),
                                play(1, pair(.jack, .hearts) + [c(.four, .hearts), c(.six, .hearts)]),
                                play(2, [c(.queen, .hearts), c(.ten, .hearts), c(.seven, .hearts), c(.three, .hearts)]),
                                play(3, pair(.six, .diamonds) + pair(.seven, .diamonds))]),
                choices: seatNames,
                correct: 3,
                explanation: "West is void in hearts and plays a **trump tractor**, 6♦ 6♦ 7♦ 7♦. Same shape and all trump, so it beats your heart tractor. East's one pair plus two singles doesn't match the shape."),
        .trick(
            title: "The higher pair wins",
            body: "West beats Partner's pair with K♣ K♣, then you top it with **A♣ A♣**: same shape, same suit, higher. You win the trick, including West's two Kings: 20 points.",
            plays: [play(2, pair(.nine, .clubs)), play(3, pair(.king, .clubs)),
                    play(0, pair(.ace, .clubs)), play(1, [c(.four, .clubs), c(.six, .clubs)])],
            trump: heartsTwo, winner: 0),
        predict(8, 3,
                prompt: "Trump suit ♥, rank 2. West leads 2♠ 2♠ and you play 2♣ 2♣. Who wins the trick?",
                trump: heartsTwo,
                visual: .trick([play(3, pair(.two, .spades)), play(0, pair(.two, .clubs)),
                                play(1, [c(.five, .hearts), c(.nine, .hearts)]), play(2, [c(.ace, .hearts), c(.four, .hearts)])]),
                choices: [seatChoice(0), seatChoice(3), seatChoice(2)],
                correct: 1,
                explanation: "Rank cards outside the trump suit are all **equal**, so 2♠ 2♠ and 2♣ 2♣ tie, and the **earlier play wins**. To beat West you'd need 2♥ 2♥ or a joker pair."),
        .trick(
            title: "Over-ruffing",
            body: "Partner, void in diamonds, ruffs with 3♥ 3♥. But West is void too and **over-ruffs** with 2♣ 2♣, a higher trump pair. Among trumps the higher pair wins, so West takes the trick and East's 20 points stay with their team.",
            plays: [play(1, pair(.king, .diamonds)), play(2, pair(.three, .hearts)),
                    play(3, pair(.two, .clubs)), play(0, [c(.queen, .diamonds), c(.jack, .diamonds)])],
            trump: heartsTwo, winner: 3),
        .recap(points: [
            "To win, a play needs the lead's shape: pair for pair, tractor for tractor.",
            "It must be all led suit or all trump; mixed plays never win.",
            "A trump play of the right shape beats any plain play.",
            "Higher wins; on a tie, the earlier play wins.",
        ]),
    ]
}
