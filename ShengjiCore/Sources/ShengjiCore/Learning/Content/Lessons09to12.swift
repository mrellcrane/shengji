import Foundation

// Lessons 9 to 12: declaring and the kitty, scoring, throws, and strategy basics.
extension Curriculum {
    /// Trump suit ♥, trump rank 2: the default context for lessons 9 to 12.
    private static let heartsTwoLate = Trump(rank: .two, suit: .hearts)

    // MARK: Lesson 9

    static let lesson9 = Lesson(
        id: "lesson.9", number: 9,
        title: "Declaring and the kitty",
        subtitle: "How trump is chosen and what the dealer buries",
        chineseTerm: "亮主 (liàngzhǔ): declaring trump",
        estimatedMinutes: 4,
        pages: lesson9Pages,
        skills: [],
        factIDs: factIDs(forLesson: 9))

    private static let lesson9Pages: [LessonPage] = [
        .text(
            title: "Choosing trump",
            body: "Each round starts with the deal. Cards are dealt one at a time until everyone has **25**; the last **8** become the **kitty** 底牌 (dǐpái). While the cards arrive, anyone may **declare** 亮主 (liàngzhǔ) to pick the trump suit. Aim to make your own longest suit trump."),
        predict(9, 1,
                prompt: "The trump rank is 2. As the cards arrive, you pick up the 2♠. What can you do?",
                visual: .cards([c(.two, .spades)]),
                choices: [Choice("Show it to make ♠ the trump suit"),
                          Choice("Nothing until the deal ends"),
                          Choice("Swap it into the kitty")],
                correct: 0,
                explanation: "Showing trump-rank cards is **declaring**, 亮主 (liàngzhǔ). Your single 2♠ makes ♠ trump, unless someone shows a stronger declaration before declaring closes, just after the last card."),
        .cards(
            title: "Declaring strength",
            body: "From weakest to strongest: **1.** one rank card, **2.** a pair of rank cards of one suit, **3.** two small jokers, **4.** two big jokers. Joker pairs mean **no trump suit**. To override, 反主 (fǎnzhǔ), you need a **strictly stronger** declaration.",
            cards: [c(.two, .spades)] + pair(.two, .hearts) + [smallJoker0, smallJoker1, bigJoker0, bigJoker1],
            trump: nil),
        predict(9, 2,
                prompt: "Trump rank 2. East declared ♣ with one 2♣. You hold 2♦ 2♦. Can you override?",
                visual: .cards(pair(.two, .diamonds)),
                choices: [Choice("Yes: a pair beats a single"),
                          Choice("No: the first declaration stands"),
                          Choice("Only by adding a joker")],
                correct: 0,
                explanation: "A **pair** of rank cards beats a single, so your 2♦ 2♦ makes ♦ trump. To take it back, East now needs a joker pair: another pair of 2s would only be equal, not stronger."),
        .text(
            title: "Reinforcing, and who deals",
            body: "Already holding the declaration? You may only **reinforce** it: show the matching rank card to make a pair, like a second 2♥ after your 2♥. In the **first round**, the winning declarer becomes the **dealer** 庄家 (zhuāngjiā). Later rounds already have a dealer, so declaring only picks the trump suit."),
        predict(9, 3,
                prompt: "Trump rank 2. Nobody declared, so the kitty is flipped one card at a time: 6♣, Q♦, 2♠. What is trump?",
                visual: .cards([c(.six, .clubs), c(.queen, .diamonds), c(.two, .spades)]),
                choices: [Choice("♠ (spades)"), Choice("♦ (diamonds)"), Choice("♣ (clubs)"), Choice("No trump suit")],
                correct: 0,
                explanation: "When nobody declares, the **first rank card** flipped from the kitty sets the trump suit: the 2♠ makes ♠ trump. The higher Q♦ doesn't matter, because a rank card turned up."),
        .cards(
            title: "When nobody declares",
            body: "The kitty is flipped one card at a time. The **first rank card** sets the suit; a **joker** first means no trump suit. No rank card at all, like this kitty at rank 2? The **highest card** sets it (the first, if tied): the A♣ makes ♣ trump. Some tables simply redeal instead.",
            cards: [c(.nine, .hearts), c(.ace, .clubs), c(.four, .spades), c(.king, .diamonds),
                    c(.seven, .clubs), c(.three, .hearts), c(.jack, .spades), c(.six, .diamonds)],
            trump: nil),
        .cards(
            title: "Burying the kitty",
            body: "The dealer adds the 8 kitty cards to their hand, then **buries** any 8 face down: 扣底 (kòudǐ). Bury a **short plain suit** to make a void you can ruff. Avoid points: if the defenders win the **last trick**, they score the kitty's points, multiplied.",
            cards: [c(.three, .clubs), c(.four, .clubs), c(.six, .clubs), c(.nine, .clubs),
                    c(.jack, .clubs), c(.four, .diamonds), c(.seven, .diamonds), c(.eight, .diamonds)],
            trump: heartsTwoLate),
        .recap(points: [
            "25 cards each; the last 8 form the kitty 底牌 (dǐpái).",
            "Declare 亮主 (liàngzhǔ): one rank card < a pair < two small jokers < two big jokers.",
            "Override 反主 (fǎnzhǔ) only with a stronger declaration; your own you may only reinforce.",
            "Nobody declares? Flip the kitty: the first rank card sets the trump suit.",
            "The dealer buries 8 cards 扣底 (kòudǐ): make voids, avoid points.",
        ]),
    ]

    // MARK: Lesson 10

    static let lesson10 = Lesson(
        id: "lesson.10", number: 10,
        title: "Scoring and levelling up",
        subtitle: "The level table and the kitty bonus",
        chineseTerm: "抠底 (kōudǐ): winning the kitty",
        estimatedMinutes: 4,
        pages: lesson10Pages,
        skills: [.levelOutcome, .kittyBonus],
        factIDs: factIDs(forLesson: 10))

    private static let lesson10Pages: [LessonPage] = [
        .text(
            title: "One number decides",
            body: "When the last card is played, one number decides the round: the **defenders' points**. It tells you who deals next and how many levels a team climbs. Know the table and you'll know, mid-round, what every trick is worth."),
        predict(10, 1,
                prompt: "You are declaring. The defenders end the round with 45 points. What happens?",
                choices: [Choice("You keep the deal and climb 1 level"),
                          Choice("You keep the deal and climb 2 levels"),
                          Choice("The defenders take over the deal")],
                correct: 0,
                explanation: "Under 80, the declarers keep the deal. **40 to 75** is a narrow escape: **+1 level**. Hold the defenders to 35 or less for +2, or to 0 for +3."),
        .text(
            title: "The level table",
            body: "**Under 80**, declarers keep the deal: **0** points +3 levels, **5 to 35** +2, **40 to 75** +1. **80 or more**, defenders take over: **80 to 115** +0, **120 to 155** +1, **160 to 195** +2, **200** +3, and +1 per extra 40. House rules often change these steps, so ask at a new table."),
        predict(10, 2,
                prompt: "The defenders end the round with 130 points. What happens?",
                choices: [Choice("They take over and climb 1 level"),
                          Choice("They take over but don't climb"),
                          Choice("The declarers climb 1 level"),
                          Choice("They take over and climb 2 levels")],
                correct: 0,
                explanation: "**120 to 155** means the defenders take over the deal **and** climb 1 level. Every 40 points above 80 is worth one more level."),
        .text(
            title: "Who deals next",
            body: "If the declarers hold, the **dealer's partner** deals next. If the defenders take over, the **next player** after the dealer deals. The new dealer's team level is the next trump rank. Levels stop at **A**: to win the game, hold the deal as declarers at A."),
        .cards(
            title: "The kitty bonus",
            body: "If the **defenders win the last trick**, they also score the kitty: 抠底 (kōudǐ). Its points are multiplied by **2 × the cards in the biggest part of the last lead**: ×2 for a single, ×4 for a pair, ×8 for a two-pair tractor. This kitty holds 25 points.",
            cards: [c(.king, .spades), c(.ten, .diamonds), c(.five, .clubs), c(.three, .hearts),
                    c(.four, .clubs), c(.six, .diamonds), c(.eight, .spades), c(.nine, .clubs)],
            trump: nil),
        .trick(
            title: "Winning the last trick",
            body: "You are declaring, and this is the last trick. West, a defender, wins it with A♣ A♣. The lead was a **pair**, so the kitty counts **×4**: 25 × 4 = 100, plus the trick's 10 points, gives the defenders **110**. Had your team won this trick, the kitty would score nothing.",
            plays: [play(3, pair(.ace, .clubs)), play(0, [c(.four, .diamonds), c(.eight, .diamonds)]),
                    play(1, [c(.six, .clubs), c(.ten, .clubs)]), play(2, [c(.seven, .diamonds), c(.jack, .hearts)])],
            trump: Trump(rank: .nine, suit: .spades), winner: 3),
        predict(10, 3,
                prompt: "The defenders win the last trick, which was led with a two-pair tractor. The kitty holds 15 points. How many points do they add?",
                choices: [Choice("15"), Choice("30"), Choice("60"), Choice("120")],
                correct: 3,
                explanation: "A two-pair tractor has 4 cards, so the kitty counts 2 × 4 = **×8**: 15 × 8 = **120**. That alone is past the 80-point line, which is why dealers fear 抠底 (kōudǐ)."),
        .recap(points: [
            "Under 80, declarers keep the deal: +3 at 0, +2 at 5 to 35, +1 at 40 to 75.",
            "At 80 or more, defenders take over, and climb a level for each 40 above 80.",
            "Declarers hold: the dealer's partner deals. Defenders take over: the next player deals.",
            "Defenders who win the last trick score the kitty: ×2 single, ×4 pair, ×8 two-pair tractor.",
            "Hold the deal as declarers at level A to win the game.",
        ]),
    ]

    // MARK: Lesson 11

    static let lesson11 = Lesson(
        id: "lesson.11", number: 11,
        title: "Throws",
        subtitle: "Leading several winners at once",
        chineseTerm: "甩牌 (shuǎipái): throw",
        estimatedMinutes: 3,
        pages: lesson11Pages,
        skills: [],
        factIDs: factIDs(forLesson: 11))

    private static let lesson11Pages: [LessonPage] = [
        .text(
            title: "Several winners at once",
            body: "Holding the top cards of a suit? You can lead them **all at once**: a **throw**, 甩牌 (shuǎipái). A good throw grabs points and saves tricks. But if anyone can beat **any part** of it, the throw fails."),
        .cards(
            title: "What a throw looks like",
            body: "A throw is several singles, pairs or tractors **of one suit**, led together. A♠ A♠ K♠ is a pair of aces plus a single King. You hold both aces, so nobody has a higher spade pair or a spade above your King: this throw is safe.",
            cards: pair(.ace, .spades) + [c(.king, .spades)],
            trump: heartsTwoLate),
        predict(11, 1,
                prompt: "Trump suit ♥, rank 2. You throw A♣ Q♣. West holds the K♣. What happens?",
                trump: heartsTwoLate,
                visual: .cards([c(.ace, .clubs), c(.queen, .clubs)]),
                choices: [Choice("The throw stands"),
                          Choice("It fails: you play only the Q♣"),
                          Choice("It fails: you play only the A♣"),
                          Choice("It fails and you lose 10 points")],
                correct: 1,
                explanation: "West's K♣ beats your Q♣, so the throw **fails**. You must play the part that can be beaten, the Q♣, and take the A♣ back. There is no point penalty."),
        .text(
            title: "When a throw fails",
            body: "A throw fails if **anyone** can beat **any part** with a higher part of the same shape **in that suit**: a higher single, a higher pair or a higher tractor of the same length. You then play only the **lowest beatable part** (smallest shape first, then lowest card) and take the rest back."),
        .cards(
            title: "Which part is forced?",
            body: "You throw K♦ K♦ J♦. East holds A♦ A♦, which beats your pair, and West holds the Q♦, which beats your J♦. Both parts can be beaten, so you play the **smaller shape**: the single J♦. Your Kings go back to your hand.",
            cards: pair(.king, .diamonds) + [c(.jack, .diamonds)],
            trump: Trump(rank: .two, suit: .spades)),
        predict(11, 2,
                prompt: "Trump suit ♥, rank 2. You throw Q♠ Q♠ A♠. East holds K♠ K♠. What must you play?",
                trump: heartsTwoLate,
                visual: .cards(pair(.queen, .spades) + [c(.ace, .spades)]),
                choices: [Choice("The whole throw", cards: pair(.queen, .spades) + [c(.ace, .spades)]),
                          cardChoice(pair(.queen, .spades)),
                          cardChoice([c(.ace, .spades)])],
                correct: 1,
                explanation: "Nobody can beat your A♠, but East's K♠ K♠ beats your queens. The throw fails, and you lead just the **beatable part**, Q♠ Q♠."),
        .trick(
            title: "A throw that stands",
            body: "The other A♣ has already been played, so no club can beat yours. The throw stands. Everyone must follow with two clubs, Partner adds the 10♣ and 5♣, and you win **25 points** in one trick.",
            plays: [play(0, [c(.ace, .clubs), c(.king, .clubs)]), play(1, [c(.four, .clubs), c(.nine, .clubs)]),
                    play(2, [c(.ten, .clubs), c(.five, .clubs)]), play(3, [c(.jack, .clubs), c(.seven, .clubs)])],
            trump: heartsTwoLate, winner: 0),
        .text(
            title: "Throw safely",
            body: "Before you throw, **count**: if every higher card of that suit has been played or is in your hand, the throw is safe. A failed throw costs no points here, but it shows your cards and wastes your lead. Many tables do charge a penalty for a failed throw."),
        .recap(points: [
            "A throw 甩牌 (shuǎipái) leads several singles, pairs or tractors of one suit at once.",
            "It fails if anyone can beat any part with a higher single, pair or tractor in that suit.",
            "After a failed throw you play only the lowest beatable part, smallest shape first.",
            "No point penalty here, but the others see your cards.",
            "Throw only when every higher card is gone or in your hand.",
        ]),
    ]

    // MARK: Lesson 12

    static let lesson12 = Lesson(
        id: "lesson.12", number: 12,
        title: "Strategy basics",
        subtitle: "Feed your partner, count cards, use voids",
        chineseTerm: nil,
        estimatedMinutes: 4,
        pages: lesson12Pages,
        skills: [.bestPlay],
        factIDs: factIDs(forLesson: 12))

    private static let lesson12Pages: [LessonPage] = [
        .text(
            title: "Habits that win",
            body: "You know the rules; now let's win more. Strong players do a few simple things every round: they **feed** their partner points, **count** the big cards, and use **voids** to ruff. None of it is hard, and each habit wins points."),
        predict(12, 1,
                prompt: "Trump suit ♥, rank 2. Partner's A♠ is winning and you play last. Which spade do you play?",
                trump: heartsTwoLate,
                visual: .situation(plays: [play(1, [c(.six, .spades)]), play(2, [c(.ace, .spades)]), play(3, [c(.nine, .spades)])],
                                   hand: [c(.king, .spades), c(.three, .spades), c(.eight, .diamonds), c(.jack, .clubs), c(.four, .hearts)]),
                choices: [cardChoice([c(.king, .spades)]), cardChoice([c(.three, .spades)])],
                correct: 0,
                explanation: "You play last, so nobody can beat Partner's ace after you. **Feed points**: your K♠ adds 10 to your team's trick. Save low cards for tricks the opponents win."),
        .text(
            title: "Feed a winning partner",
            body: "When your partner is **sure** to win, give them points: a 5, 10 or King of the led suit, or one you can discard. When an opponent is winning, play your **lowest non-point** card instead. Unsure who will win? Keep your points."),
        .cards(
            title: "Don't lead points",
            body: "Leading a King or a 10 invites the opponents to take it with an ace. Lead point cards only when they are **sure winners**, for example the K♦ once both A♦ are gone. Otherwise lead a low card, like the 3♦.",
            cards: [c(.king, .diamonds), c(.ten, .diamonds), c(.three, .diamonds)],
            trump: heartsTwoLate),
        predict(12, 2,
                prompt: "Trump suit ♥, rank 2. These jokers have been played. You hold the other small joker. Can any trump beat it now?",
                trump: heartsTwoLate,
                visual: .cards([bigJoker0, bigJoker1, smallJoker0]),
                choices: [Choice("No, it is the top card left"), Choice("Yes, the 2♥ can"), Choice("Yes, the A♥ can")],
                correct: 0,
                explanation: "There are only **two** big jokers, and both are gone. The other small joker has been played too, so yours can't be beaten. **Counting** the top cards turns them into sure winners."),
        .cards(
            title: "Make a void, then ruff",
            body: "With few clubs, play them early, or bury them if you are the dealer. Once you are **void** in clubs, you can **ruff** club leads with small trumps. As dealer, bury short suits to make voids, but avoid burying points.",
            cards: [c(.three, .clubs), c(.seven, .clubs), c(.jack, .clubs)],
            trump: heartsTwoLate),
        predict(12, 3,
                prompt: "Trump suit ♥, rank 2. Partner showed out of clubs earlier; East and West still have clubs. You are on lead. What should you lead?",
                trump: heartsTwoLate,
                visual: .cards([c(.four, .clubs), c(.eight, .clubs), c(.six, .spades), c(.nine, .diamonds), c(.queen, .hearts)]),
                choices: [Choice("A low club", cards: [c(.four, .clubs)]),
                          Choice("A trump", cards: [c(.queen, .hearts)]),
                          Choice("A low spade", cards: [c(.six, .spades)])],
                correct: 0,
                explanation: "Lead into your **partner's void**: Partner can ruff a club with a small trump and win. Leading a trump would pull Partner's trumps instead, and a spade gives them no help."),
        .text(
            title: "Draw trumps or save them",
            body: "As declarers with **many trumps**, lead trumps early to **draw** the defenders' trumps; then your aces can't be ruffed. With few trumps, **save your high trumps** to win back tricks full of points, especially the last trick, where the kitty is at stake."),
        .recap(points: [
            "Feed points to a partner who is sure to win the trick.",
            "Lead point cards only when they are sure winners.",
            "Count the top trumps and high cards to find your sure winners.",
            "Make voids to ruff, and lead into your partner's void.",
            "Strong in trumps? Draw them. Short? Save high trumps to protect points.",
        ]),
    ]
}
