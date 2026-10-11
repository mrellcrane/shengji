# Shengji variants by players and decks (research notes)

Collected 2026-10-10 by a research pass (four independent web sweeps, a merge, two skeptic checks) to plan games for more than 4 players. The app teaches the classic 4-player, 2-deck game and also plays fixed-team tables of 6 players with 3 decks and 8 with 4 (DESIGN.md, Bigger tables). A friend who plays says: at least half a deck per person (2 for 4 players, 3 or more for 6), any number of decks beyond that, and more than 8 players gets hard to follow.

Skeptic caveat: many hosts (pagat.com, Wikipedia, Baidu) were unreachable during verification, so most rows rest on search excerpts plus arithmetic checks (hand x players + kitty = deck). Claims a skeptic refuted are listed at the end.

## Summary for learners

The most common way to play Shengji (also called Tractor or 80 Points) is 4 players in two fixed partnerships, with partners sitting opposite. It uses 2 decks plus 4 jokers (108 cards): 25 cards each, an 8-card kitty and 200 points in the deck, and the attacking team needs 80 to take over. That is not the only setup. With 1 deck (54 cards, often called Forty Points or Da Bai Fen), 4 players get 12 cards each with a 6-card kitty. The deck holds 100 points, the attackers need 40, and because no two cards are identical there are no pairs or tractors. Six players split into two fixed teams of three in alternating seats. Pagat's version uses 2 decks (17 cards each, 6-card kitty, 80 to take over). Many other guides, and robertying.com by default, use 3 decks instead (26 cards each, 6-card kitty, 300 points, 120 to take over), which makes triples possible. A handy rule of thumb is that the attackers need about 40 points per deck. Groups of 5, 7 or more usually play Finding Friends, where the leader calls a card and teams change every hand. We found no written rules for 6 players with 1 deck, although robertying.com lets a host set it up (8 cards each).

## Variants

### Classic Tractor / Sheng Ji (拖拉机 tuolaji, 八十分 bashi fen, 双升 shuang sheng, 双抠 shuang kou): 4 players, 2 decks, fixed partners

- **Players:** 4
- **Decks:** 2 standard decks plus 4 jokers (2 red, 2 black) = 108 cards
- **Teams:** Two fixed partnerships. Partners sit opposite each other (Pagat, Wikipedia, Zhihu). Online versions (robertying.com, Eighty, ejfn/Tractor) seat partners the same way.
- **Hand:** 25 each
- **Kitty:** 8 (Pagat, zh-Wikipedia, gamerules.com, Zhihu, robertying.com default, Eighty, ejfn/Tractor)
- **Points:** 200 (each 5 = 5, each 10 and K = 10). Pagat notes the attackers can score more than 200 because kitty points are multiplied.
- **Thresholds:** The attackers (the side not holding the deal) need 80 to take over. Pagat, Benjamin Zhang, QQ Games, robertying.com, Eighty and ejfn/Tractor share one table. 0 = declarers +3 levels. 5-35 = declarers +2. 40-75 = declarers +1. 80-115 = attackers take over with no level gain. 120-155 = attackers +1. 160-195 = attackers +2. 200-235 = attackers +3. Each further 40 = one more level. CONFLICTS: Lianzhong (ourgame.com) gives the attackers +2 at 120-155. Pagat also lists a 20-point-step variation: declarers +1 at 60-75 and +2 at 40-55; attackers still take over at 80, then +1 at 100-115 and +2 at 120-135. zh-Wikipedia says some groups use one level per 20 points even with two decks.
- **Pairs, tractors, triples:** A pair is two identical cards (same suit and rank). Two cards of equal rank in different suits are not a pair. A tractor is two or more adjacent identical pairs in one suit. Adjacency skips the level rank. Pagat's example: with 4s as trumps, 3-3 and 5-5 are adjacent in a plain suit, but 3-3 and 4-4 are not. There are no triples with 2 decks. zh-Wikipedia: '两副牌升级中除了单张，还有对子和拖拉机' (two-deck play has pairs and tractors as well as singles). Pagat: only a higher trump tractor of the same length can beat a led tractor.
- **Declaring:** During the deal, a player shows a card of the current level rank to make that suit trumps. Pagat: you can show one level card, two identical level cards, or two identical jokers (jokers mean no trumps). A pair overrides a single card, and a joker pair overrides a level-card pair. You cannot later change your own declaration with a pair, but you can override a single card your partner exposed. zh-Wikipedia's override order: one level card < two identical level cards < two small jokers < two big jokers. robertying.com: more cards beat fewer, and a single joker is not a valid bid. Eighty: you may counter another seat's declaration but not your own, and if nobody declares, the hand has no trumps. Pagat lists a variant with no no-trump option.
- **Other:** Sources differ on the kitty bonus when the attackers win the last trick. Pagat multiplies the kitty's counting cards by 'twice the number of cards in the last trick' (x8 for a 4-card tractor). robertying.com uses 2 x the size of the largest unit in that trick. Eighty uses 'twice the last lead's card count'. ejfn/Tractor uses 2^(pairs + 1). Eighty's Shanghai profile makes levels 2, 5, 10 and K mandatory. robertying.com's rules page says the game ends when A is defended, but its code defaults to an extra No Trump level above A. Pagat's only other listed variation is 'the hook' (capturing a jack with the trump jack in the last trick).
- **How common:** Every source treats this as the standard form. Wikipedia: 'most commonly played with two decks of cards, and is played with four players in fixed partnerships'. Baidu Baike: the game 'can be played with 1 to 4 decks, with the 2-deck version being the most popular'. Apps with a single fixed mode (Eighty, ejfn/Tractor, TractorCards) are all 4 players with 2 decks. Pagat says there are 'many slight variations in the rules of play'.
- **Sources:**
  - https://www.pagat.com/kt5/tractor.html (search excerpt) - 'Chinese double deck card game for four players, played in two fixed partnerships, partners sitting opposite each other'; 'each player has 25 cards, leaving 8 cards face down'; 'There are 200 points in the pack in total'
  - https://www.pagat.com/kt5/tractor.html (search excerpt) - opponents 'become the declarers for the next deal by taking at least 80 card points'; kitty value 'multiplied by twice the number of cards in the last trick'; 'with fours as trumps, a pair of 3s and a pair of 4s do not form a tractor in diamonds'
  - https://en.wikipedia.org/wiki/Sheng_ji (search excerpt) - 'most commonly played with two decks of cards, and is played with four players in fixed partnerships'; two-deck names 'bāshí fēn (八十分), tuō lā jī (拖拉機), shuāng kōu (雙摳), shuāng shēng (雙升)'
  - https://zh.wikipedia.org/zh-hans/升級_(撲克牌) (search excerpt) - '两副牌时每人抓25张，留8张作为底牌'; '两副牌升级中总分为200分，闲家须获得80分才可以上庄'
  - https://minigameimg.qq.com/help/rule36.html and https://qqgame.qq.com/game/91.shtml (search excerpt) - '如果得分为 0，庄家方连升 3 级；如果得分不满 40，庄家连升 2 级；40 到 80 之间，庄家方升 1 级；80 到 120 之间轮换庄家；120 到 160 之间，抓分方升 1 级'
  - https://www.ourgame.com/game/game-intro-dly/upgrade.html (search excerpt, conflicting) - '如果得分大于等于 120 ，小于 160 ，两副牌时抓分方连升 2 级'
  - https://static1.squarespace.com/static/5942f94fb8a79b3aa562e99d/t/62c340d68ede295f34d37bb4/1656963287304/An_Introduction_To_Sheng_Ji_Tractor.pdf (Benjamin Zhang, search excerpt) - table '0: Declarers +3; 5-35: +2; 40-75: +1; 80-115: Opponents become Declarers; 120-155: Opponents +1; 160-195: +2'; '80 points with 40-point increments for Sheng Ji with two decks'
  - https://baike.baidu.com/item/升级/3563150 (search excerpt) - also called '拖拉机、80分、双升、双抠'; '两副牌称80分'
  - https://baike.baidu.com/en/item/Tractor/17597 (search excerpt) - 'can be played with 1 to 4 decks, with the 2-deck version being the most popular'
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - table row '2n to 3n-5: Opposing team wins, but keeps the same level' with n = 20 x decks; 'A single joker cannot be used as a bid.'; 'In 升级, the teams are fixed and the leader rotates among the winning team.'
  - https://github.com/rbtying/shengji/blob/master/core/src/settings.rs (read directly) - 'self.num_decks.unwrap_or(self.players.len() / 2)' (2 decks for 4 players)
  - https://github.com/tonyyunyang/80-fen-shengji/blob/main/docs/rules.md (read directly) - 'Exactly four seats ... Opposite seats partner: 0/2 against 1/3 ... Two decks give 108 distinct physical cards, 25 per seat and eight in the kitty.'; 'Attackers need 80 points to take over'; 'Default mandatory levels are 2, 5, 10, K'
  - https://github.com/ejfn/Tractor/blob/main/docs/game_rules.md (read directly) - '2 decks + 4 jokers = 108 cards'; '25 per player + 8 kitty'; 'the final trick multiplies the kitty points by 2^(pairs + 1)'
  - https://gamerules.com/rules/tractor/ (search excerpt) - 'a 25-card hand is achieved. This leaves 8 cards on the table as a talon'
  - https://zhuanlan.zhihu.com/p/1900479633754948317 (search excerpt) - '四位玩家分为两队，对家为同一队'; '每人发25张，剩余8张作为底牌'; '两副牌共200分'
  - https://apps.apple.com/us/app/tractorcards/id6757169177 (search excerpt) - 'four-player card game using two decks (108 cards total)'

### Sishi Fen (四十分, '40 points') / Da Bai Fen (打百分, 'compete for 100 points') / Bai Fen / 单升: 4 players, 1 deck, fixed partners

- **Players:** 4
- **Decks:** 1 standard deck with a red and a black joker = 54 cards
- **Teams:** Fixed partnerships, partners sitting opposite (Pagat)
- **Hand:** 12 each (Pagat, en-Wikipedia, zh-Wikipedia, Baidu Baike, Gambiter; robertying.com's engine also deals 12 when set to 1 deck). Grokipedia, an AI-generated wiki, says 13, which conflicts with every other source.
- **Kitty:** 6. In Pagat's Da Bai Fen, the leader picks up the 6 to make an 18-card hand, then discards 6.
- **Points:** 100
- **Thresholds:** The attackers need 40 to take over (en-Wikipedia, zh-Wikipedia, Gambiter, Benjamin Zhang). Pagat explains the Shanghai name as '40 being the target score for the opponents'. The step tables disagree. (a) 20-point steps (zh-Wikipedia, Zhongyou/chinagames, Alayou, QQ Games, Zhang, robertying.com engine): 0 = declarers +3; 5-15 = +2; 20-35 = +1; 40-55 = attackers take over with no level gain; 60-75 = attackers +1; 80-95 = +2; 100 or more = +3. (b) Pagat's Da Bai Fen, scored in game points: 0 = declarers 2; 5-35 = declarers 1; 40-75 = no score, attackers become declarers; 80-95 = attackers 1; 100 or more = attackers 2. Pagat's variant table makes 40-55 the no-score band, with attackers gaining from 60. Pagat says 'some play' that exactly 40 is a draw. (c) Lianzhong (ourgame.com): 40-79 means no level change and the deal rotates; 80-95 = attackers +1; 100 = +2.
- **Pairs, tractors, triples:** No two cards are identical, so most sources say only singles are played and there are no pairs or tractors. zh-Wikipedia: '一副牌升级中仅有单张这一种牌型' (one-deck play has only single cards). Wikipedia/Gambiter: 'no double cards will be played (but combinations of cards may still be allowed)'. Zhang: 'there are no pairs'. UNRESOLVED: Baidu Baike describes a red/black colour rule ('♥K♦K 是一对牌 ... ♥K♠K 不是一对牌'), but searches disagreed on whether this rule is in its one-deck or two-deck section.
- **Declaring:** You declare with a single level card. One deck has no identical pairs, so Benjamin Zhang says you cannot reinforce or override a suit declaration, or declare no trump. Pagat's Da Bai Fen: if no level card is exposed during the deal, the 6 leftover cards are turned up to set trumps. Pagat: 'In each hand the trump rank is the declarers' current score.'
- **Other:** Pagat's Da Bai Fen: counting cards in the discard are doubled and go to whoever wins the last trick. In a variation, they are multiplied by the number of cards each player played to that trick. One search summary of Baidu Baike says the one-deck game is otherwise the same as the two-deck game, with the point requirements halved.
- **How common:** Pagat calls Sishi Fen 'probably the game from which Tractor was developed', and says the single-deck form is 'gradually being supplanted, especially in southern China, by expanded versions using two or more decks'. Baidu Baike lists 40分 (one deck) and 80分 (two decks) as the common forms. Chinese platforms (Lianzhong, QQ Games) still publish one-deck scoring rules. robertying.com allows 1 deck only as a host setting, not as its default.
- **Sources:**
  - https://www.pagat.com/kt5/tractor.html (search excerpt) - 'Sishi Fen (40 points), also known as Bai Fen (100 points)... a four player fixed partnership game, similar to Tractor but played with a single deck'
  - https://www.pagat.com/kt5/100.html (search excerpt) - 'A standard international pack is used, with red and black jokers, making 54 cards in all'; each player receives twelve cards; the leader 'discards any six of his eighteen cards'; 'In Shanghai the game is called Si Shi Fen (四十分), which means "40 points", 40 being the target score for the opponents'
  - https://en.wikipedia.org/wiki/Sheng_ji (search excerpt) - 'Alternatively, it can be played with one deck, in which case the game may be called dǎ bǎi fēn (打百分) or sìshí fēn (四十分)'; for single decks 'it is typical to use 6 cards for the kitty (each player being dealt 12 cards each in a deck of 54 cards) and 40 points as the requirement to swap teams, and no double cards will be played'
  - https://gambiter.com/cards/Sheng_ji.html (search excerpt) - 'For single decks, it is typical to use (54-4*12=6) cards for the kitty and 40 points as the requirement to swap teams, and no double cards will be played (but combinations of cards may still be allowed)'
  - https://zh.wikipedia.org/zh-hans/升級_(撲克牌) (search excerpt) - '一副牌时也叫打百分、打四十、单升'; '一副牌时每人抓12张，留6张作为底牌'; '一副牌升级中总分为100分，闲家须获得40分才可以上庄'; '一副牌升级中仅有单张这一种牌型'
  - https://baike.baidu.com/en/item/Shengji/3329444 (search excerpt) - 'When played with one deck, it is also known as "40 Points" or "Hundred Points"'; 'each side receives 12 cards, and the remaining 6 cards are the bottom cards'
  - https://baike.baidu.com/en/item/Tractor/17597 (search excerpt) - single deck: each player 12 cards, 'the remaining 6 cards as bottom cards'
  - https://baike.baidu.com/item/升级/3563150 (search excerpt) - '♥K♦K 是一对牌 ... ♥K♠K 不是一对牌' (which section this rule belongs to was not confirmed)
  - http://w.chinagames.net/chinagames/2008-11/12/content_512256.htm (search excerpt) - '0 庄家升3级 5-15 庄家升2级 20-35 庄家升1级 40-55 换庄 60-75 敌家升1级 80-95 敌家升2级 100-115 敌家升3级'
  - http://www.alayou.net/gamedetail.do?gameId=66 (search excerpt) - '40-55 换庄 60-75 敌家升1级 80-95 敌家升2级'
  - https://minigameimg.qq.com/help/rule36.html (search excerpt) - '一副牌的分数段为 20 分一段'
  - https://www.ourgame.com/game/game-intro-dly/upgrade.html (search excerpt) - '如果得分大于等于40小于80，一副牌时双方不升级，轮换庄家'; '抓分方80--95分升一级，100分升两级'
  - https://static1.squarespace.com/static/5942f94fb8a79b3aa562e99d/t/62c340d68ede295f34d37bb4/1656963287304/An_Introduction_To_Sheng_Ji_Tractor.pdf (Benjamin Zhang, search excerpt) - single deck: 'there are no pairs'; you cannot 'reinforce or override a suit declaration, or... declare no trump'; threshold 40 with 20-point steps
  - https://github.com/rbtying/shengji/blob/master/frontend/src/NumDecksSelector.tsx and https://github.com/rbtying/shengji/blob/master/mechanics/src/scoring.rs (read directly) - decks selectable from 1; 'step_size_per_deck: 20' (engine run with 4 players and 1 deck: 12 cards each, kitty 6)
  - https://grokipedia.com/page/Sheng_ji (low reliability) - says 13 cards per player for single-deck variants

### Three-deck Sheng Ji (三副牌升级): 4 players, 3 decks, fixed partners

- **Players:** 4. Pagat's deal of 39 each plus 6 extra only adds up to 162 cards with 4 players.
- **Decks:** 3 decks including three jokers of each colour (3 x 52 + 6 = 162 cards)
- **Teams:** Fixed partnerships, partners opposite. Bianfeng: '四人结对竞赛' (four players competing in pairs).
- **Hand:** 39
- **Kitty:** 6 (the starter takes 6 extra cards and discards 6)
- **Points:** 300
- **Thresholds:** The attackers take over at 120 and gain one more level for each further 60 (Pagat, zh-Wikipedia, QQ Games, Baidu Baike). zh-Wikipedia: 120-175 = take over; 180-235 = take over and +1. QQ Games: '120分上台，180分上台并再升1级，240分上台并再升2级'. Baidu Baike: 0 points is a 'big shutout' (大光) and the declarers go up 3; under 60 is a 'small shutout' (小光) and the declarers go up 2. Bianfeng: '得分不满 60，庄家连升 2 级'.
- **Pairs, tractors, triples:** Triples exist. zh-Wikipedia: '三副牌的升级还有刻子和推土机' (three-deck play also has triples and 'bulldozers', meaning runs of consecutive triples). Pagat: 'it is possible to lead triples of identical cards; also you can play tractors consisting of sequences of triples or sequences of pairs'. Pagat's rule for following a led triple was only partly retrieved; one summary says you play a triple if you can, otherwise a pair. robertying.com's order when a triple is led: a triple, then a pair plus one card, then three single cards of the suit.
- **Declaring:** Three identical level cards beat a pair. zh-Wikipedia's override ladder continues past joker pairs to three identical level cards. Lianzhong's three-deck order, as summarized by search: single < two < two jokers (no trump) < three < three jokers (no trump). Pagat's Zhao Pengyou page: 'With more than two packs, a pair can be overruled by a triplet.'
- **Other:** zh-Wikipedia has a separate kitty-multiplier table for each deck count.
- **How common:** Offered on QQ Games, Bianfeng, Lianzhong (whose rules also appear in a competition rulebook) and the 多乐升级 app, and listed by Pagat as a variant. A Google Play Shengji app has a 162-card, 39-card-hand mode. Baidu Baike says the 2-deck game is the most popular, so this one is less common.
- **Sources:**
  - https://www.pagat.com/kt5/tractor.html (search excerpt) - 'Tractor can be played with three decks including three jokers of each colour. Each player draws 39 cards and the starter takes an additional six cards and discards six.'; three decks: 300 points, opponents need at least 120, 'each 60 points above or below this is an extra level'
  - https://www.pagat.com/kt5/tractor.html (search excerpt) - 'it is possible to lead triples of identical cards; also you can play tractors consisting of sequences of triples or sequences of pairs'
  - https://zh.wikipedia.org/zh-hans/升級_(撲克牌) (search excerpt) - '三副牌时每人抓39张，留6张作为底牌'; '三副牌的升级还有刻子和推土机'; 3-deck table '120-175 上台' / '180-235 上台并升一级'
  - http://old3w.gameabc.com/gamehome/rule/nUpgrade3.html (Bianfeng, search excerpt) - '牌局采用四人结对竞赛，抢分升级的方式进行。牌数由 108 张变为 162 张'
  - https://qqgame.qq.com/app/gamedetail_91.shtml (search excerpt) - '120分上台，180分上台并再升1级，240分上台并再升2级'
  - https://minigameimg.qq.com/help/rule36.html (search excerpt) - '三副牌的分数段为 60 分一段'
  - https://baike.baidu.com/item/升级 (search summary) - three decks: 120 points to take over ('上台'), each further 60 = +1 level; 0 = 大光, under 60 = 小光
  - https://ioa.cas.cn/tzgg/202112/P020211214755109286144.doc (competition rules based on Lianzhong, search excerpt) - '打三副牌时每方得牌 39 张，剩余的 6 张为底牌'; '三副牌共 300 分'
  - https://youxi.163.com/gameintro/sj01.html (search excerpt) - '打三副牌时底牌为6张，打四副牌时底牌为8张'
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - 'With more than two packs, a pair can be overruled by a triplet, and so on'
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - triple-lead following order and 'Tractor of two triples'
  - https://play.google.com/store/apps/details?id=com.peachstudio.shengji&hl=en_US - app listing describes a 162-card game with 39 cards per hand and a 6-card kitty
  - https://apps.apple.com/us/app/%E5%A4%9A%E4%B9%90%E5%8D%87%E7%BA%A7/id1061581971 (search excerpt) - supports '三副牌、四副牌、两副牌双升'

### Four-deck Sheng Ji (四副升级): 4 players, 4 decks

- **Players:** 4
- **Decks:** 4 (216 cards)
- **Teams:** Not stated in the retrieved excerpts
- **Hand:** 52 each on online platforms (zh-Wikipedia)
- **Kitty:** 8 (Baidu Baike, zh-Wikipedia, NetEase 163)
- **Points:** 400 (100 per deck, by the standard point values; not quoted directly)
- **Thresholds:** No four-deck table was found. Gambiter's general rule ('40n is usually used as the point requirement to swap teams') would give 160.
- **Pairs, tractors, triples:** Not described in the retrieved excerpts. There are four copies of every card.
- **Declaring:** Baidu Baike: in four-deck play you cannot override your own declaration (不能自反主).
- **How common:** zh-Wikipedia lists it among derived games (衍生遊戲), mainly on online platforms. The 多乐升级 app offers a four-deck mode.
- **Sources:**
  - https://baike.baidu.com/item/四副升级/10736045 (search excerpt) - '四副升级共216张牌，底牌为8张'
  - https://zh.wikipedia.org/zh-hant/升級_(撲克牌) (search excerpt) - '網絡平台中的四副牌拖拉機遊戲中通常規定每人抓52張，留8張作為底牌'
  - https://youxi.163.com/gameintro/sj01.html (search excerpt) - '打四副牌时底牌为8张'
  - https://gambiter.com/cards/Sheng_ji.html (search excerpt) - '40n is usually used as the point requirement to swap teams'
  - https://apps.apple.com/us/app/%E5%A4%9A%E4%B9%90%E5%8D%87%E7%BA%A7/id1061581971 (search excerpt) - supports '三副牌、四副牌、两副牌双升'

### Six-player Tractor, 2 decks, fixed teams of three (Pagat)

- **Players:** 6
- **Decks:** 2 decks plus 4 jokers (108 cards). This is arithmetic: Pagat deals 6 x 17 + 6 = 108. A Baidu Zhidao answer (as summarized by search) says '用两副牌玩' (play with two decks).
- **Teams:** Two fixed teams of three, sitting alternately, so each player sits between two opponents. Baidu Zhidao: '隔一个是自己人' (every other seat is a teammate). Pagat: when the declarers win, the next starter is the teammate sitting two places to the right of the current starter.
- **Hand:** 17
- **Kitty:** 6 (the starter takes 6 extra cards and discards 6). Baidu Zhidao also says '底牌是6张'.
- **Points:** 200
- **Thresholds:** Pagat: 'The other rules are identical to the four-player game', so the attackers need 80 to take over, with 40-point steps. Baidu Zhidao's question is titled '六人玩升级(80分)', and one answer (as summarized by search) says '升级需80分'.
- **Pairs, tractors, triples:** Same as the 2-deck 4-player game: identical pairs and tractors, no triples
- **Declaring:** Same as the 4-player game (Pagat)
- **Other:** Baidu Zhidao: '其他出法都一样' (all other play is the same) and '这样玩偶然性比较大' (it is more luck-dependent this way). robertying.com lets a host pick 2 decks for 6 players (its default would be 3), and its engine then deals 17 each with a 6-card kitty.
- **How common:** Pagat lists it as a Tractor variation, and a Baidu Zhidao answerer describes playing it. No frequency data. CONFLICT: Pagat's page header lists 'Players: 4, 6' with 'Cards: 2x52+4J, 3x52+6J', and some search summaries said Pagat's six-player game uses 3 decks. Its own 17-card deal only adds up with 2 decks.
- **Sources:**
  - https://www.pagat.com/kt5/tractor.html (search excerpt) - 'Six players can play tractor, in two teams of three, sitting alternately. In the deal each player takes 17 cards and there are six extra cards for the starter, who discards six.'; 'the next starter is the partner sitting two places to the right of the current starter. The other rules are identical to the four-player game.'
  - https://gambiter.com/cards/king-ten-five/tractor.html (search excerpt) - six players in two teams of three, seated alternately, 17 cards each, six extra for the starter
  - https://zhidao.baidu.com/question/20184476.html (search excerpt) - title '六人玩升级(80分)'; answer '隔一个是自己人！其他出法都一样！底牌是6张，这样玩偶然性比较大。'; another answer, as summarized: '用两副牌玩，正三角是一家，升级需80分'
  - https://github.com/rbtying/shengji/blob/master/frontend/src/NumDecksSelector.tsx and https://github.com/rbtying/shengji/blob/master/core/src/game_state/initialize_phase.rs (read directly) - decks selectable from 1 up to the player count; default kitty formula gives 6 for 108 cards and 6 players

### Six-player Tractor (六人三副牌拖拉机), 3 decks, fixed teams of three

- **Players:** 6
- **Decks:** 3 (162 cards with 6 jokers)
- **Teams:** Two fixed teams of three, sitting alternately. Benjamin Zhang: 'sitting such that the teams alternate around the table'. Zhang also says all three teammates share a level and go up together. Gametea: six players can also play as three sides with bidding, 'but that is rarely used' (很少用到). robertying.com Tractor mode: the landlord's team is every other seat.
- **Hand:** 26 (Zhang; confirmed by running robertying.com's engine)
- **Kitty:** 6 (Zhang: '6 cards for 6 people (26 cards per hand)'; robertying.com default; zjustincheng/tractor-game)
- **Points:** 300
- **Thresholds:** Zhang: 'the point threshold is 120 with increments of 60'. robertying.com's 3-deck table: 0 = defenders +3; 5-55 = +2; 60-115 = +1; 120-175 = attackers take over with no level gain; 180-235 = attackers +1; 240-295 = +2; 300 or more = +3. zjustincheng/tractor-game uses the same bands (60-point intervals, swap at 120). No Chinese source gave a separate six-player table; the general 3-deck rule (take over at 120, +1 per 60) comes from 4-player 3-deck sources.
- **Pairs, tractors, triples:** Triples exist. A Medium write-up of the 6-player game: 'You are allowed to play triples.' robertying.com illustrates a 'Tractor of two triples'. When a triple is led, robertying.com requires a triple, then a pair plus one card, then three cards of the suit. Chinese 3-deck rules call triples 刻子 and runs of triples 推土机 (zh-Wikipedia).
- **Declaring:** robertying.com: bids are identical trump-rank cards or jokers, and more cards beat fewer, so a triple outbids a pair. Its optional joker-bid policies scale with the deck count. No other source describes declaring for this variant separately.
- **Other:** tractorcardgame.com (Yunjian Paiguan, a US Chinese-community site) builds its online game around this format and describes it as extending 双升 to teams of three.
- **How common:** This is the most-cited way to play with six. Zhang's guide gives it as the way to expand to 6 players. Gametea lists '6人三副牌：分两方，每方3人' among common ways to play. Wikipedia: 'one deck for every two players (rounded down)', so 3 decks for 6. robertying.com's default: '6 players play with 3'. Robert Ying's blog: 'usually played with d = floor(p/2) decks'. No source gives frequency figures.
- **Sources:**
  - https://static1.squarespace.com/static/5942f94fb8a79b3aa562e99d/t/62c340d68ede295f34d37bb4/1656963287304/An_Introduction_To_Sheng_Ji_Tractor.pdf (Benjamin Zhang, section 6.4, search excerpt) - 'To expand the game to 6 players, add a third deck of cards and have two fixed teams of three'; 'sitting such that the teams alternate around the table'; 'In a game with 3 decks, the point threshold is 120 with increments of 60, and the kitty is 6 cards for 6 people (26 cards per hand)'
  - https://en.wikipedia.org/wiki/Sheng_ji (search excerpt) - 'In general, there is one deck for every two players (rounded down), so for example, a six-player game would use three decks, giving six jokers and 162 cards in total.'
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - 'Usually, a deck is added for every two players in the game (so 4 players and 5 players play with 2 decks, but 6 players play with 3).'; 'Tractor of two triples'
  - https://github.com/rbtying/shengji/blob/master/core/src/settings.rs (read directly) - 'self.num_decks.unwrap_or(self.players.len() / 2)'
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/exchange_phase.rs (read directly) - Tractor mode team: 'if idx % 2 == landlord_position % 2'
  - http://www.gametea.com/news/201810/7692.html (search excerpt) - '6人三副牌：分两方，每方3人。也可以分3方打竞标玩法，但是很少用到。'
  - https://tractorcardgame.com/ (search excerpt) - '六人制三副牌拖拉机拓展于"双升"，以三人为一个团队通过合作与对方进行博弈'
  - https://medium.com/@yangjessie7/explaining-the-complex-card-game-sheng-ji-level-up-dfd2eadef521 - 'still two teams (of three each). You are allowed to play triples.'
  - https://robertying.com/post/shengji-probabilities/ (search excerpt) - 'Shengji is usually played with d = floor(p/2) decks, where p is the number of players in the game'
  - https://github.com/zjustincheng/tractor-game/blob/main/docs/rules-v2.1.md (read directly) - 'Rule: 1 deck per 2 players. - 4 players → 2 decks (108 cards) - 6 players → 3 decks (162 cards)'; kitty '6p → 6'

### Six players, 4 decks (六人制四副牌)

- **Players:** 6
- **Decks:** 4 (216 cards)
- **Teams:** Not described in the retrieved excerpts
- **Hand:** Not found
- **Kitty:** Not found
- **Points:** 400 (100 per deck; not quoted)
- **Thresholds:** The Zhihu article (as summarized by search) says the take-over and level-up scores have to be adjusted ('相应的反庄升级分数需要调整'). No numbers were found.
- **Pairs, tractors, triples:** Not described. There are four copies of every card.
- **Declaring:** Not described
- **Other:** The same Zhihu article pairs 8 players with 6 decks.
- **How common:** Mentioned only in passing: one personal rules article on Zhihu and an option on tractorcardgame.com. It conflicts with the 2-deck and 3-deck six-player sources.
- **Sources:**
  - https://zhuanlan.zhihu.com/p/1900479633754948317 (search summary, not independently confirmed) - '可以扩展到六人或者八人升级，六人升级对应4副牌，八人升级对应6副牌'
  - https://tractorcardgame.com/ (search excerpt) - the site also offers '六人制四副牌拖拉机，炒地皮，五人制或七人制的找朋友'

### Six players, 1 deck (software setting only, no written rules found)

- **Players:** 6
- **Decks:** 1 (54 cards)
- **Teams:** On robertying.com in Tractor mode: fixed 3 vs 3 on alternating seats. Finding Friends mode is also allowed.
- **Hand:** 8 (confirmed by running robertying.com's engine)
- **Kitty:** 6 (robertying.com default formula: 54 mod 6 = 0, so the kitty equals the player count)
- **Points:** 100
- **Thresholds:** By robertying.com's formula (step = 20 x decks), attackers take over at 40. No rules source gives a table for this setup.
- **Pairs, tractors, triples:** Inference: robertying.com requires pairs to be the 'exact same card face', and one deck has only one copy of each card, so there are no pairs or tractors.
- **Declaring:** Same bidding engine as other robertying.com games
- **How common:** No rules source describes 6 players with 1 deck as a played variant. robertying.com's engine accepts it because the host can pick any deck count from 1 up to the number of players.
- **Sources:**
  - https://github.com/rbtying/shengji/blob/master/frontend/src/NumDecksSelector.tsx (read directly) - 'Number of decks:' with a 'default' option, then 1 up to numPlayers
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/initialize_phase.rs (read directly) - 'let mut kitty_size = deck.len() % self.propagated.players.len(); if kitty_size == 0 { kitty_size = self.propagated.players.len(); }'
  - https://github.com/rbtying/shengji/blob/master/mechanics/src/scoring.rs (read directly) - 'step_size_per_deck: 20'
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - 'cards of equal value are not necessarily identical; they have to have the exact same card face.'

### Fixed-team Tractor for 8 or 10 players (one deck per two players)

- **Players:** 8 or 10 (zjustincheng/tractor-game). robertying.com's Tractor mode accepts any even count of 4 or more.
- **Decks:** zjustincheng: players / 2 (4 decks for 8 players, 5 for 10). robertying.com default: floor(players / 2). The Zhihu article (search summary) pairs 8 players with 6 decks.
- **Teams:** Two fixed teams on alternating seats (zjustincheng; robertying.com's Tractor mode)
- **Hand:** 26 for both 8 and 10 players, using zjustincheng's formula (decks x 54 - kitty) / players (arithmetic from its formula)
- **Kitty:** zjustincheng: 8 for 8 players, 10 for 10 players
- **Points:** 100 per deck: 400 with 4 decks, 500 with 5
- **Thresholds:** zjustincheng: interval I = 20 x decks, and the swap threshold is 2 x I (160 with 4 decks, 200 with 5). robertying.com uses the same 20-per-deck step.
- **Pairs, tractors, triples:** With 4 or more decks, sets of four identical cards exist. robertying.com supports 'doubles, triples, four-of-a-kind, ...'
- **Declaring:** robertying.com: more identical cards beat fewer
- **Other:** zjustincheng/tractor-game adds Jack checkpoint and Jack reset rules.
- **How common:** Only a small open-source project and robertying.com's settings support it, and one Zhihu article mentions 8 players in passing. No frequency data.
- **Sources:**
  - https://github.com/zjustincheng/tractor-game/blob/main/docs/rules-decisions.md (read directly) - 'Use one deck per two players: deckCount = playerCount / 2. Each checkpoint interval is I = 20 × deckCount; the swap threshold is 2 × I.'
  - https://github.com/zjustincheng/tractor-game/blob/main/docs/rules-v2.1.md (read directly) - '### 8.1 Size - 4p → 8 - 6p → 6 - 8p → 8 - 10p → 10'
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/initialize_phase.rs (read directly) - 'can only play tractor with an even number of players'
  - https://zhuanlan.zhihu.com/p/1900479633754948317 (search summary) - '八人升级对应6副牌'

### Three-player Sheng Ji with bidding (三人升级 竞标玩法): 3 players, 2 decks

- **Players:** 3
- **Decks:** 2
- **Teams:** No fixed teams. Each player keeps their own level, and the dealer is decided by bidding.
- **Hand:** 33
- **Kitty:** 9
- **Points:** 200 (two decks)
- **Thresholds:** The target is the winning bid score, not 80 (Baidu Zhidao)
- **Pairs, tractors, triples:** Two decks, so pairs and tractors, no triples
- **Declaring:** Decided through bidding (no details retrieved)
- **How common:** Only two Baidu pages describe it. No frequency data.
- **Sources:**
  - https://baike.baidu.com/item/双升/8575038 (search excerpt) - '三人打法（竞标玩法）中先抓牌，每人33张牌，剩下9张作为底牌'
  - https://zhidao.baidu.com/question/750591379073503772.html (search excerpt) - with three players and two decks, each player keeps their own level and the target score is set by bidding rather than 80

### Finding Friends / Zhao Pengyou (找朋友), 5 players, 2 decks

- **Players:** 5
- **Decks:** 2, with all 4 jokers (108 cards), or without the black jokers (106 cards), per Pagat
- **Teams:** Not fixed. The trump maker takes the kitty, discards, then calls a non-trump card and says which copy counts ('first', 'second', ...). Whoever plays that copy joins the trump maker. Pagat: 1 card is called with 5 players, so the trump maker's team has at most 2 players (2 vs 3). Holders 'must not reveal in any way who they are, except through the play of the cards'. robertying.com: 1 friend by default for 5 players; trump-rank cards and jokers cannot be friend cards; the leader can turn out to be their own friend. Teams change every hand.
- **Hand:** 20 (Pagat, Cat's Cards, zhao-pengyou.com, robertying.com engine)
- **Kitty:** 8 with all 4 jokers (Pagat, zhao-pengyou.com, robertying.com's code). Pagat also allows removing the black jokers for a 6-card kitty. robertying.com's rules page says 6 for five players, which disagrees with its own code.
- **Points:** 200
- **Thresholds:** Pagat scores per pack. Its individual-level method: the defenders (the side against the trump maker) win with at least 60 x packs (120). The trump makers win if the defenders take under 40 x packs (80). In between, nobody wins. Defenders go up 2 levels at 80 per pack and 3 at 100 per pack. Trump makers go up 2 if the defenders take under 20 per pack and 3 if they take nothing, plus 1 for each player their team is short of the maximum size. Pagat's 'now more widespread' simpler method: defenders win with at least 40 x packs (80), and 'There is no middle zone'. zhao-pengyou.com (search summary): if the point-taking side gets 80-115, nobody changes level. Below 80, the leader's side goes up 1 to 3 levels. From 120, the point-taking side goes up, reaching 3 levels at 200 or more. robertying.com: the same 20-per-deck steps as Tractor, plus by default 1 extra level if the leader's team wins while smaller than full size.
- **Pairs, tractors, triples:** Identical pairs and tractors; no triples. Pagat: 'it is not sufficient for the cards just to be equal in rank'. Pagat variation: when a 4-card tractor is led, followers must play a 4-card tractor in that suit if they can, otherwise two pairs, otherwise one pair and two odd cards.
- **Declaring:** Pagat: each player has their own level. During the deal, a player exposes a card of their own level and its suit becomes trumps. The proposer can hold the suit by exposing an identical second card. If nobody makes trumps by the end of the deal, the cards are redealt.
- **Other:** Pagat: play is anticlockwise with no fixed dealer, and the game ends when a player passes Ace. zhao-pengyou.com: only the leader may look at the 8 buried cards during the hand.
- **How common:** English-language guides treat 5 as the standard Finding Friends count. zhao-pengyou.com: 'Two decks of cards are used for the standard five player game'. Wikipedia: Finding Friends 'has five or more players and two or more decks'. Robert Ying: Finding Friends is the variant 'for odd numbers of players'. No source describes fixed teams for 5 players.
- **Sources:**
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - 'From 5 to 7 players use two packs'; 'For example with 5 players and two decks you can play with 4 Jokers and a kitty of 8 cards or remove the black Jokers and a have kitty of 6 cards.'
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - 'The partner will be whoever plays the first, second, third, etc. copy of that card which appears during the play of the hand'; 'The defenders win if their card point total is at least 60 times the number of packs of cards being used'; simpler method: 'at least 40 times the number of packs... There is no middle zone in which neither side wins'
  - https://www.zhao-pengyou.com/ (search excerpt) - 'Two decks of cards are used for the standard five player game, with an additional deck being added for more players.'; 'all five players should have an equal number of cards (twenty), with the eight undealt cards leftover'
  - https://www.catsatcards.com/Games/ZP.html (search excerpt) - 5 players: 2 decks, 20 cards
  - https://en.wikipedia.org/wiki/Sheng_ji (search excerpt) - 'Another variant is called zhǎo péngyǒu (找朋友, "Finding Friends"), which has five or more players and two or more decks.'
  - https://robertying.com/post/shengji/ (search excerpt) - 'for odd numbers of players, there is a variant of the game called 找朋友 (finding friends)'
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - 'so 4 players and 5 players play with 2 decks'; 'in a five-player game, there will be 6' (bottom cards); 'In 找朋友, the leader rotates among the team that won the previous round, but the teams are fluid and change from round-to-round.'
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/initialize_phase.rs (read directly) - 'num_friends: (self.propagated.players.len() / 2) - 1'
  - https://github.com/rbtying/shengji/blob/master/mechanics/src/scoring.rs (read directly) - '#[default] BonusLevelForSmallerLandlordTeam'

### 找朋友 (Finding Friends), Chinese form: 5 players, 3 decks (also called 红五星 / 红五三副牌)

- **Players:** 5
- **Decks:** Usually 3 (162 cards). Baidu Baike: some regions use 2 decks.
- **Teams:** No fixed allies. After burying the kitty, the dealer calls one ally by naming 'the Xth person to play a given card', which gives 2 vs 3, or 1 vs 4 if the dealer turns out to hold the card. Each player keeps their own level (QQ Games: '每个人单独记级').
- **Hand:** 31
- **Kitty:** 7
- **Points:** 300
- **Thresholds:** Sources vary. Baidu Baike (English): under 60 is a 'Partial Shutout'; at 120 the attackers take the deal; 180 = take the deal and +1 level; 240 = +2 levels. 立群's blog (as summarized by search): 0 = dealer side +3; 5-55 = dealer side +2. Alayou (as summarized by search): 80 is the dividing line, about 1 level per 40 points. QQ Games: a dealer who plays 1 vs 4 and wins gains double levels. Gametea: how levels are split between the dealer and the friend varies by region.
- **Pairs, tractors, triples:** Baidu Baike: the same as standard 3-deck Tractor, so triples exist
- **Declaring:** Baidu Baike: the same as standard 3-deck Tractor
- **Other:** One search summary said Baidu's 找朋友 entry also describes a 2-deck form with 20 cards each and an 8-card kitty. A second search could not find that text.
- **How common:** Regional. Baidu Baike says it is popular in Fengxian (Shanghai) and Zhejiang. Gametea lists '5人三副牌' as the 找朋友 mode among common ways to play. QQ Games hosts it as a separate game.
- **Sources:**
  - https://baike.baidu.com/item/找朋友/13849312 (search excerpt) - '游戏通常采用3副牌组合（共162张），5人游戏每人发31张牌，亦有部分地区使用2副牌进行游戏'; also known as '红五星' or '红五三副牌'
  - https://zh.wikipedia.org/zh-hans/升級_(撲克牌) (search excerpt) - '找朋友游戏由5人参加，使用三副牌，每人31张牌，底牌7张。'; '庄家可以指定"第X个出某张牌"的玩家为其盟友'
  - http://www.alayou.net/gamedetail.do?gameId=36 (search excerpt) - '找朋友游戏由5人参加，使用三副牌，每人31张牌，底牌7张'; '庄家埋下底牌后，由他叫一个朋友'
  - https://qqgamecdnimg.qq.com/help/rule154.html (search excerpt) - '没有固定的盟友。由庄家每次可以叫一个盟友。每个人单独记级。'; '三副牌共300分'
  - https://baike.baidu.com/en/item/Tractor/17597 (search excerpt) - 'When playing the "Find Friends" variation with 5 players and 3 decks, the Playing Rules are the same as in standard 3-deck Tractor... less than 60 points counts as a Partial Shutout, 120 points allows one to Take the Deck, 180 points... +1 level, 240 points... +2 levels'
  - http://qalisw.blogspot.com/2015/10/blog-post.html (五人升级游戏规则, search excerpt) - five players with three 54-card decks; an 'original kitty' (原始底牌) of the last 7 cards; 300 total points
  - http://www.gametea.com/news/201810/7692.html (search excerpt) - 5人三副牌 is the 找朋友 mode, with no fixed partners and each player levelling individually

### Finding Friends (Zhao Pengyou), 6 players, 2 decks

- **Players:** 6
- **Decks:** 2 with 4 jokers (108 cards), per Pagat's table and Cat's Cards
- **Teams:** Not fixed. Pagat: 2 cards are called with 6 players, so the trump maker's team has at most 3 players (up to 3 vs 3). Teams change every hand.
- **Hand:** 17
- **Kitty:** 6 (Cat's Cards: 'there should be a total of six cards remaining'; 108 - 6 x 17 = 6)
- **Points:** 200
- **Thresholds:** Pagat's per-pack scoring. Individual-level method: defenders win at 120 or more, trump makers win if defenders take under 80, and nobody wins in between. Simpler method: defenders win at 80 or more, with no middle zone.
- **Pairs, tractors, triples:** Identical pairs and tractors; no triples
- **Declaring:** As in the 5-player 2-deck Finding Friends entry (Pagat: each player declares with a card of their own level)
- **Other:** Pagat: some groups change the number of jokers so the kitty is always 6 cards.
- **How common:** It is a standard row in Pagat's and Cat's Cards' tables. Benjamin Zhang says Finding Friends 'expands the game to 5, 6, 7, or more players'. No source says whether 6-player groups more often use fixed 3 vs 3 teams or Finding Friends. Chinese sources describe 6 players only as fixed 3 vs 3.
- **Sources:**
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - 'from 5 to 7 players use two packs, from 8 to 11 players use 3 packs, and 12 or more players use 4 packs. Sufficient red and black jokers are included so that all the cards can be distributed equally to the players, with a kitty of six (or eight) cards left over.'; table: 6 players, 2 packs, 17 cards per player
  - https://www.catsatcards.com/Games/ZP.html (search excerpt) - table row '6 | 2 | ... | 17'; 'there should be a total of six cards remaining in the deck'
  - https://static1.squarespace.com/static/5942f94fb8a79b3aa562e99d/t/62c340d68ede295f34d37bb4/1656963287304/An_Introduction_To_Sheng_Ji_Tractor.pdf (Benjamin Zhang, search excerpt) - 'this popular variant of Sheng Ji expands the game to 5, 6, 7, or more players'; 'Teams are not fixed, but instead change with every hand'

### Finding Friends, 6 players, 3 decks (robertying.com default)

- **Players:** 6
- **Decks:** 3 (robertying.com's default for 6 players in either mode)
- **Teams:** The landlord plus 2 friends (default floor(6/2) - 1 = 2) against the other 3. Teams change every round.
- **Hand:** 26
- **Kitty:** 6
- **Points:** 300
- **Thresholds:** robertying.com: step 60, so the attackers take over at 120, plus by default 1 extra level if the landlord's team wins while smaller than full size
- **Pairs, tractors, triples:** Triples and tractors of triples exist
- **Declaring:** robertying.com bidding: more identical cards beat fewer, so triples outbid pairs
- **How common:** This is the robertying.com default. It conflicts with Pagat's and Cat's Cards' Finding Friends tables, which use 2 packs for 6 players.
- **Sources:**
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - '6 players play with 3'; 'The number of friends is determined by the number of players'; 'the defending team should never be larger than the attacking team'
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/initialize_phase.rs (read directly) - 'num_friends: (self.propagated.players.len() / 2) - 1'
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/play_phase.rs (read directly) - 'smaller_landlord_team = actual_team_size < setting_team_size;'

### Finding Friends, 7 players, 2 decks (Pagat main table)

- **Players:** 7
- **Decks:** 2 decks without jokers (104 cards). Cat's Cards: '2 decks without jokers'.
- **Teams:** Pagat: 2 cards are called, and the trump maker's team has at most 3 players (3 vs 4)
- **Hand:** 14
- **Kitty:** 6 (arithmetic: 104 - 7 x 14)
- **Points:** 200
- **Thresholds:** Pagat's per-pack scoring (80 and 120 with 2 packs)
- **Pairs, tractors, triples:** Identical pairs and tractors; no triples
- **Declaring:** As in Pagat's Zhao Pengyou
- **Other:** If a robertying.com host sets 7 players to 2 decks, its kitty formula gives 10 cards.
- **How common:** Pagat's main table and Cat's Cards both list it. Pagat offers a 3-deck alternative for 7 players.
- **Sources:**
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - 'From 5 to 7 players use two packs'; table: 7 players, 2 packs, 14 cards per player
  - https://www.catsatcards.com/Games/ZP.html (search excerpt) - 7 players: 2 decks without jokers, 14 cards

### Finding Friends, 7 players, 3 decks

- **Players:** 7
- **Decks:** 3 decks plus jokers (162 cards)
- **Teams:** Called friends. robertying.com's default is 2 friends (landlord's team of 3 against 4).
- **Hand:** 22
- **Kitty:** 8
- **Points:** 300
- **Thresholds:** Zhang's 3-deck rule: threshold 120 with increments of 60. robertying.com uses the same 60-point step.
- **Pairs, tractors, triples:** Three decks, so triples exist
- **Declaring:** As in Zhao Pengyou. Pagat: 'With more than two packs, a pair can be overruled by a triplet'.
- **How common:** Pagat gives it as an alternative to its 2-pack row. Zhang uses it, and it is robertying.com's default for 7 players (floor(7/2) = 3).
- **Sources:**
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - '7 players can play with three decks plus Jokers (162 cards): each player takes 22 cards and there are 8 cards in the kitty'
  - https://static1.squarespace.com/static/5942f94fb8a79b3aa562e99d/t/62c340d68ede295f34d37bb4/1656963287304/An_Introduction_To_Sheng_Ji_Tractor.pdf (Benjamin Zhang, search excerpt) - kitty '8 cards for 7 people (22 cards per hand)'; 3 decks: 'the point threshold is 120 with increments of 60'
  - https://github.com/rbtying/shengji/blob/master/core/src/settings.rs (read directly) - 'self.num_decks.unwrap_or(self.players.len() / 2)' (engine run: 7 players with 3 decks gives 22 each and a kitty of 8)

### Finding Friends for large groups: 8 to 12 or more players, 3 or 4 decks (Pagat table)

- **Players:** 8 to 12 or more
- **Decks:** Pagat: 3 packs for 8 to 11 players, 4 packs for 12 or more, with jokers added so the cards divide evenly. robertying.com defaults to floor(players / 2), which gives 4 decks for 8 players. SeekingFriends (app) allows up to 8 players and 9 decks.
- **Teams:** Called friends. Pagat's maximum trump-maker team: 4 (8 or 9 players), 5 (10 or 11), 6 (12). Cards called: 3 for 8 or 9 players, 4 for 10 or 11, 5 for 12.
- **Hand:** Pagat: 19 (8 players), 17 (9), 15 (10), 14 (11), 17 (12). robertying.com engine: 26 for 8 players with 4 decks.
- **Kitty:** Pagat: 'six (or eight)'. robertying.com engine: 8 for 8 players with 4 decks.
- **Points:** 100 per pack (300 or 400)
- **Thresholds:** Pagat's per-pack scoring (60 x packs to win with a middle zone, or 40 x packs with no middle zone). Cat's Cards: defenders win 3 game points at '100 X (the number of decks in play)'.
- **Pairs, tractors, triples:** With 3 or more packs, triples and four-of-a-kind exist. Pagat: when 3 or 4 identical cards are led, anyone holding a matching set in the suit must play it, and only an identical set can win. Tractors are sequences of 'equal sized, consecutive sets of identical cards'.
- **Declaring:** Pagat: 'With more than two packs, a pair can be overruled by a triplet, and so on.'
- **How common:** Pagat and Cat's Cards list these rows. No frequency data.
- **Sources:**
  - https://www.pagat.com/kt5/pengyou.html (search excerpt) - 'from 8 to 11 players use 3 packs, and 12 or more players use 4 packs'; table: Players 5,6,7,8,9,10,11,12 / Packs 2,2,2,3,3,3,3,4 / Cards per player 20,17,14,19,17,15,14,17
  - https://www.catsatcards.com/Games/ZP.html (search excerpt) - same deck counts and hand sizes as Pagat; 3 game points at '100 X (the number of decks in play)'
  - https://github.com/rbtying/shengji/blob/master/core/src/settings.rs (read directly) - 'self.num_decks.unwrap_or(self.players.len() / 2)'
  - https://apps.apple.com/us/app/seekingfriends/id1507767077 (search excerpt) - 'supports up to 9 decks of cards and 8 players'

### Online and app versions where the host picks players and decks (robertying.com and others)

- **Players:** robertying.com: 4 or more (Tractor mode needs an even count; Finding Friends allows any count). yi-shiuan-tung/tractor: variable, with Finding Friends needing 4 or more. zjustincheng/tractor-game: 4, 6, 8 or 10. Dani Entertainment's Tractor iPad app: 4 to 7. SeekingFriends: up to 8.
- **Decks:** robertying.com: default floor(players / 2); the host can pick 1 up to the number of players, and the backend allows up to 2 per player. yi-shiuan-tung/tractor: default 2 for any player count; 1 to 10 allowed. zjustincheng: players / 2. SeekingFriends: up to 9. 多乐升级: 2, 3 or 4 decks.
- **Teams:** robertying.com: Tractor mode uses fixed teams on alternating seats; Finding Friends mode uses called friends (default floor(players / 2) - 1). yi-shiuan-tung: fixed alternating seats, or find-a-friend with players / 2 - 1 friends. Dani app (search summary): 4 players 2v2, 5 players find 1 friend, 6 players 3v3, 7 players find 2 friends.
- **Hand:** Depends on players and decks
- **Kitty:** robertying.com default: deck size mod players; if that is 0, use the player count; if it is under 5, add the player count (4 players: 8 with 2 decks, 6 with 1; 6 players: 6 with 2 or 3 decks; 5 players with 2 decks: 8). yi-shiuan-tung: deck size mod players, then add the player count until it is at least 5. zjustincheng: 8 for 4 players, otherwise the player count. hzoo/shengji issue: 'between 4 - 8 cards, normally as close as possible to 6'.
- **Points:** 100 per deck
- **Thresholds:** robertying.com: step = 20 x decks, and attackers take over at 2 steps (40 with 1 deck, 80 with 2, 120 with 3). yi-shiuan-tung: declarers win if the attackers score under 40 x decks. zjustincheng: swap at 2 x (20 x decks). Dani app (search summary): 4-player games are '2v2 to 80 points' and 6-player games are '3v3 to 160 points'.
- **Pairs, tractors, triples:** robertying.com: 'Identical cards (doubles, triples, four-of-a-kind, ...)'; a tractor is a run of consecutive identical sets of the same size.
- **Declaring:** robertying.com: bids are identical trump-rank cards or joker sets, and more cards beat fewer. Joker, reinforcement and bid policies are host settings.
- **Other:** robertying.com has many house-rule toggles: throw penalty, kitty penalty, advancement policy, kitty theft and others. SeekingFriends can 'set a pocket size by removing some 2s'. 多乐升级 also has 三打一 and 三打哈 modes. The hzoo/shengji issue: 'Sometimes people will play with -2 to +2 decks'.
- **How common:** robertying.com is the best-known open-source online version. It says: 'Usually, a deck is added for every two players in the game', and 'There are a wide variety of house rules that aren't implemented'.
- **Sources:**
  - https://github.com/rbtying/shengji/blob/master/core/src/settings.rs (read directly) - 'self.num_decks.unwrap_or(self.players.len() / 2)'; 'At least one deck is necessary to play the game' / 'Using more than two decks per player is not supported'
  - https://github.com/rbtying/shengji/blob/master/core/src/game_state/initialize_phase.rs (read directly) - 'if self.propagated.players.len() < 4 { bail!("not enough players") }'; 'can only play tractor with an even number of players'; 'if kitty_size < 5 { kitty_size += self.propagated.players.len(); }'
  - https://github.com/rbtying/shengji/blob/master/frontend/static/rules.html (read directly) - 'Usually, a deck is added for every two players in the game (so 4 players and 5 players play with 2 decks, but 6 players play with 3).'; 'uses a fairly standard rule set. There are a wide variety of house rules that aren't implemented'
  - https://github.com/yi-shiuan-tung/tractor/blob/master/src/main/java/io/github/ytung/tractor/Game.java (read directly) - 'private int numDecks = 2;'; 'if (numDecks <= 0 || numDecks > 10)'; 'if (findAFriend && playerIds.size() < 4)'; 'boolean doDeclarersWin = roundScore < 40 * numDecks;'
  - https://github.com/yi-shiuan-tung/tractor/blob/master/README.md (read directly) - 'Supports variable number of players and variable number of decks'; 'Supports find-a-friend version'
  - https://github.com/zjustincheng/tractor-game/blob/main/packages/rules/src/cards.ts (read directly) - 'const kittySize = playerCount === 4 ? 8 : playerCount;'
  - https://apps.apple.com/us/app/tractor/id1510648040 (search summary; page could not be fetched) - '4-player games are 2v2 to 80 points, 5-player games pair you with one friend, 6-player games are 3v3 to 160 points, and 7-player games pair you with two friends.'
  - https://apps.apple.com/us/app/seekingfriends/id1507767077 (search excerpt) - 'supports up to 9 decks of cards and 8 players'
  - https://apps.apple.com/us/app/%E5%A4%9A%E4%B9%90%E5%8D%87%E7%BA%A7/id1061581971 (search excerpt) - supports '三副牌、四副牌、两副牌双升' and '三打哈、三打一'
  - https://github.com/hzoo/shengji/issues/9 (as summarized by search) - 'add a deck every 2 players'; 'Sometimes people will play with -2 to +2 decks'; kitty 'between 4 - 8 cards, normally as close as possible to 6'

## Where sources disagree

1. Deck count for 6 players. Three answers appear. 2 decks: Pagat's six-player Tractor (17 cards each plus 6, which only adds up with 108 cards), Pagat's and Cat's Cards' Finding Friends tables, and a Baidu Zhidao answer. 3 decks: Benjamin Zhang, Gametea, tractorcardgame.com, Wikipedia's 'one deck for every two players (rounded down)', Robert Ying's d = floor(p/2), and the robertying.com and zjustincheng defaults. 4 decks: one Zhihu article and an option on tractorcardgame.com. Pagat's header lists '2x52+4J, 3x52+6J', and some search summaries claimed its six-player game uses 3 decks, but its own 17-card deal contradicts that.
2. Fixed teams or Finding Friends for 6 players. Pagat Tractor, Zhang, Gametea and Baidu Zhidao use fixed 3 vs 3 teams. Pagat's Zhao Pengyou and Cat's Cards also list 6 players for Finding Friends. No source gives frequency data.
3. Deck count for 5 players (always Finding Friends). Pagat, Cat's Cards, zhao-pengyou.com and robertying.com use 2 decks (20 each, kitty 8, or 6 without black jokers). Chinese sources (Baidu Baike, zh-Wikipedia, Alayou, QQ Games, Gametea) use 3 decks (31 each, kitty 7, 300 points); Baidu notes that some regions use 2.
4. Deck count for 7 and 8 players. For 7, Pagat's main table uses 2 packs without jokers (14 each), while Pagat's alternative, Zhang and robertying.com use 3 decks (22 each, kitty 8). For 8, Pagat uses 3 packs, robertying.com defaults to 4, and the Zhihu article says 6.
5. Two-deck scoring. Most sources (Pagat, Zhang, QQ Games, robertying.com, Eighty, ejfn) give the attackers +1 at 120-155. Lianzhong/ourgame.com gives +2. Pagat also has a 20-point-step variation, and zh-Wikipedia says some groups use 20-point steps with two decks.
6. One-deck scoring. Everyone agrees on 40 to take over, but not on the steps. zh-Wikipedia, Zhongyou/Alayou, QQ Games, Zhang and robertying.com use 20-point steps (40-55 take over, 60-75 +1). Pagat's Da Bai Fen uses game points with 40-75 as a no-score band, and its variant makes 40-55 no-score; 'some play' that exactly 40 is a draw. Lianzhong makes 40-79 a rotation with no level change and gives +1 at 80-95.
7. One-deck hand size and pairs. 12 cards each is the near-universal figure; Grokipedia, an AI-generated wiki, says 13. Most sources say one deck has singles only, but Baidu Baike has a red/black rule (♥K with ♦K counts as a pair) whose deck-count section could not be confirmed.
8. Finding Friends win thresholds. Pagat's individual-level method uses 60 x packs to win, with a middle zone from 40 to 60 per pack. Pagat's 'now more widespread' method uses 40 x packs with no middle zone. Cat's Cards ties the top reward to 100 x decks. For the Chinese 5-player 3-deck game, Baidu Baike says take over at 120 with +1 per 60, while Alayou (as summarized by search) gives 80 with about 40 per level.
9. Kitty multiplier on the last trick. Pagat: twice the number of cards in the last trick (x8 for a 4-card tractor). robertying.com: 2 x the largest unit. Eighty: twice the last lead's card count. yi-shiuan-tung: 2 x the cards led. ejfn: 2^(pairs + 1). Pagat's Da Bai Fen simply doubles.
10. Following a led triple with 3 decks. Pagat's text was cut off; one summary says a triple if possible, otherwise a pair. robertying.com requires a triple, then a pair plus one card, then three cards of the suit.
11. Internal inconsistencies in robertying.com. Its rules page says a 5-player game leaves 6 bottom cards and '4 to 8 cards are left', but its code gives 8 for 5 players with 2 decks and more than 8 for some setups. The page says the game ends at A, but the code defaults to an extra No Trump level.
12. App defaults. robertying.com scales decks with players (floor(p/2)), while yi-shiuan-tung/tractor defaults to 2 decks at any player count. The Dani Entertainment app's '6-player games are 3v3 to 160 points' matches neither the 80 (2 decks) nor the 120 (3 decks) takeover score, and its deck count is not stated.
13. Evidence quality. Every research run was blocked from reading Pagat, Wikipedia, Baidu, the Zhang PDF, Chinese game sites and app stores directly. Those quotes come from web-search excerpts, which may be paraphrased. Only the GitHub code and docs (robertying.com/rbtying, yi-shiuan-tung, Eighty, ejfn, zjustincheng) were read directly.

## Skeptic findings (refuted or unverified claims)

- **unsupported** (ALL (method note)): Every cited source was re-opened and checked. Evidence: Only the GitHub sources could be re-opened, by downloading them from raw.githubusercontent.com: the rbtying/shengji files rules.html, settings.rs, NumDecksSelector.tsx, scoring.rs, initialize_phase.rs, exchange_phase.rs, play_phase.rs and deck.rs, plus tonyyunyang/80-fen-shengji docs/rules.md, ejfn/Tractor docs/game_rules.md, the zjustincheng/tractor-game rules files and cards.ts, and yi-shiuan-tung/tractor Game.java and README. Nothing else loaded. WebFetch hit DNS errors (ENOTFOUND) on pagat.com, en.wikipedia.org, gambiter.com, catsatcards.com and static1.squarespace.com (the Zhang PDF), and archive.org is barred. curl got a 403 from the proxy for Baidu, zh-Wikipedia, QQ, ourgame, 163, Zhihu, Medium, the app stores, robertying.com and tractorcardgame.com. WebSearch refused: the turn's 200-search budget was already used up. The hzoo/shengji issue needs GitHub API access that this session does not have. Every non-GitHub claim below is marked unsupported for that reason: it was not re-opened, which is different from the source failing to say it. Where possible I checked the card counts with arithmetic instead.
- **unsupported** (Classic Tractor: 4 players, 2 decks): Pagat, Zhang, QQ Games and zh-Wikipedia give the same table; Lianzhong gives +2 at 120-155; Pagat has a 20-point-step variation; Pagat quotes '25 cards, leaving 8', '200 points', '80 card points'. Evidence: Not re-opened: pagat.com, the Zhang PDF, QQ, ourgame.com and zh-Wikipedia were all unreachable. These rest only on the earlier search excerpts. The figures are internally consistent: 4 x 25 + 8 = 108.
- **unsupported** (Classic Tractor: 4 players, 2 decks): Wikipedia: 'most commonly played with two decks... four players in fixed partnerships'; Baidu: 'can be played with 1 to 4 decks, with the 2-deck version being the most popular'. Evidence: Not re-opened: en.wikipedia.org and baike.baidu.com were unreachable. robertying rules.html does independently support that the game is not always 4 players with 2 decks: 'Usually, a deck is added for every two players in the game (so 4 players and 5 players play with 2 decks, but 6 players play with 3).'
- **unsupported** (Sishi Fen / Da Bai Fen: 4 players, 1 deck): Pagat, Wikipedia, Gambiter, zh-Wikipedia and Baidu: 12 each, 6-card kitty, 40 to take over. Pagat Da Bai Fen: 18-card hand, discard 6, game-point table. chinagames, Alayou, QQ and Lianzhong step tables. Zhang: 'no pairs'.. Evidence: Not re-opened (all hosts unreachable). The arithmetic is consistent: 4 x 12 + 6 = 54, and 12 + 6 = 18. Grokipedia's 13 each would leave only 2 kitty cards from 54, which cannot fit a 6-card kitty; it only works for a 52-card deck without jokers. That is a further reason to treat 13 as wrong, though Grokipedia was not re-opened either.
- **unsupported** (Three-deck Sheng Ji: 4 players, 3 decks): 162 cards, 39 each, 6-card kitty, 300 points, take over at 120, +1 level per further 60 (Pagat, zh-Wikipedia, QQ, Baidu, Bianfeng, CAS doc, 163). Evidence: The cited sources were not re-opened. Independent cross-check: robertying's engine with 4 players and 3 decks gives 162 % 4 = 2, so 2 + 4 = 6 for the kitty and (162 - 6) / 4 = 39 each. Its 3-deck table (n = 60) gives a take-over at 120 and +1 at 180-235. That matches the claimed numbers, but it is not the cited source.
- **unsupported** (Four-deck Sheng Ji: 4 players, 4 decks): 216 cards, 52 each, 8-card kitty (Baidu, zh-Wikipedia, 163). Evidence: Not re-opened. The arithmetic is consistent: 4 x 52 + 8 = 216. robertying's formula would give the same: 216 % 4 = 0, then 4, then 8.
- **unsupported** (Six players, 2 decks, fixed 3 vs 3 (Pagat)): Pagat: 6 players in two teams of three sitting alternately, 17 cards each plus 6 extra for the starter, other rules as in the 4-player game (so 80 to take over). Baidu Zhidao: two decks, 6-card kitty, 80 points.. Evidence: Not re-opened: pagat.com, gambiter.com and zhidao.baidu.com were unreachable. Arithmetic: 6 x 17 + 6 = 108, which only works with 2 decks. With 3 decks it would be 6 x 26 + 6 = 162. The Pagat header conflict ('3x52+6J') could not be settled.
- **unsupported** (Six players, 3 decks, fixed 3 vs 3): Zhang 6.4 ('add a third deck... 120 with increments of 60... 6 cards for 6 people (26 cards per hand)'), Wikipedia ('one deck for every two players (rounded down)'), Gametea, tractorcardgame.com, Medium, and Robert Ying's blog d = floor(p/2). Evidence: Not re-opened (squarespace, Wikipedia, gametea, tractorcardgame, Medium and robertying.com were unreachable). The numbers agree with robertying's code: 6 x 26 + 6 = 162, and floor(6/2) = 3.
- **unsupported** (Six players, 4 decks): Zhihu: 6 players use 4 decks and 8 players use 6 decks; tractorcardgame offers 六人制四副牌. Evidence: Not re-opened. No hand or kitty figures are claimed, so there is nothing to check by arithmetic.
- **unsupported** (Three-player bidding: 3 players, 2 decks): 33 each, 9-card kitty, target set by bidding (Baidu Baike, Baidu Zhidao). Evidence: Not re-opened. The arithmetic is consistent: 3 x 33 + 9 = 108.
- **unsupported** (Finding Friends: 5 players, 2 decks): Pagat Zhao Pengyou: 20 each, kitty 8 (or 6 without the black jokers), 1 card called, thresholds of 60 x packs and 40 x packs. Cat's Cards and zhao-pengyou.com: 20 each, 8 left over.. Evidence: Not re-opened. The arithmetic is consistent: 5 x 20 + 8 = 108, and 5 x 20 + 6 = 106.
- **unsupported** (Finding Friends (Chinese): 5 players, 3 decks): 162 cards, 31 each, 7-card kitty, 300 points; Baidu's 120 / 180 / 240 thresholds; Alayou's 80. Evidence: Not re-opened. The arithmetic is consistent: 5 x 31 + 7 = 162. robertying's own formula would give a different kitty for 5 players with 3 decks: 162 % 5 = 2, then 2 + 5 = 7. That is the same 7 and 31 each, so it is consistent.
- **unsupported** (Finding Friends: 6 players, 2 decks): Pagat and Cat's Cards: 17 each, 6-card kitty, 2 cards called. Evidence: Not re-opened. The arithmetic is consistent: 6 x 17 + 6 = 108. robertying's engine gives the same 17 and 6 for 6 players with 2 decks.
- **unsupported** (Finding Friends: 8 to 12+ players): Pagat table: 3 packs for 8 to 11 players, 4 for 12; hands of 19 / 17 / 15 / 14 / 17; kitty 6 or 8. robertying with 8 players and 4 decks: 26 each, kitty 8.. Evidence: The Pagat and Cat's Cards tables were not re-opened. Each row is arithmetically possible with 0 to 8 jokers: for example, 8 x 19 = 152 plus a 6-card kitty is 158, which is 3 x 52 + 2 jokers. The robertying part is confirmed: 216 % 8 = 0, so kitty = 8 and 208 / 8 = 26.
- **unsupported** (Online and app versions): Dani app: '6-player games are 3v3 to 160 points'. SeekingFriends: up to 9 decks and 8 players. 多乐升级: 2, 3 or 4 decks. hzoo issue: 'Sometimes people will play with -2 to +2 decks'.. Evidence: Not re-opened. The app stores were unreachable. hzoo/shengji is readable over git, but its issues need GitHub API access that this session does not have.
- **refuted** (Classic Tractor (4p, 2 decks)): Pagat: only a higher trump tractor of the same length can beat a led tractor. Evidence: Pagat says the opposite for a plain-suit lead: 'The trick is won by the highest set of consecutive pairs of the same length as the lead in the suit led, unless some player who has none of the suit led manages to trump with an equally long sequence of consecutive pairs of trumps.' A higher tractor in the same suit therefore also wins, and a trump tractor counts only when played by someone void in the led suit. en-Wikipedia agrees: 'The first combination, if all consecutively-ranked and of a greater order than the suit lead, wins the trick.'
- **refuted** (Classic Tractor (4p, 2 decks)): The table gives the 2-deck pair and tractor play rules without noting that sources disagree (implicitly uniform). Evidence: Sources disagree on whether you must follow a tractor with a tractor. Pagat (2 decks) requires 'identical pairs (not necessarily consecutive)', so holding a tractor does not force you to play it. en-Wikipedia's following order starts with 'Other consecutively-ranked doubles (tractor) in the same suit'. Eighty/tonyyunyang (Shanghai profile): 'A tractor lead additionally requires a matching-length tractor if available.' tractorplus README: '拖拉机跟同长度拖拉机'. Pagat's own three-deck section also requires a matching-shaped tractor. This rule should be listed as a house-rule difference.
- **refuted** (Sishi Fen / Da Bai Fen (4p, 1 deck)): Only single cards are played (zh-Wikipedia: '一副牌升级中仅有单张这一种牌型'; 'most sources say only singles are played'). Evidence: Pagat Da Bai Fen allows multi-card leads: 'A player may lead any single card, or a group of cards of the same suit, but if more than one card is led at once, all the cards led must be higher than any card of the suit led remaining in any player's hand ... Each of the other three players in turn must play the same number of cards as were led.' Pagat calls this a key tactic, because 'provided that each member of the other team has at least one card of the suit led they cannot win by ruffing'. en-Wikipedia: 'combinations of cards may still be allowed'. Pagat's Jilin variation also has a non-identical set lead: 'If a player has four cards of the same rank - for example all the 7's - they can be led together ... The trick is won by the highest four of a kind played' (called 'Dun', 吨). One-deck play therefore has no pairs or tractors, but multi-card leads exist in at least some rule sets.
- **unsupported** (Sishi Fen / Da Bai Fen (4p, 1 deck)): Baidu Baike has a red/black colour pair rule (♥K♦K is a pair, ♥K♠K is not), possibly in its one-deck section. Evidence: I could not reach baike.baidu.com to confirm the rule or which section it is in. No independent GitHub-hosted or mirrored source mentions same-colour pairs for one-deck play. The only equal-rank set I found for one deck is Pagat's Jilin four-of-a-kind 'Dun'. This rule stays unresolved and should not be taught as standard.
- **refuted** (Three-deck Sheng Ji (4p, 3 decks)): Declaring trumps with 3 decks includes joker no-trump bids (Lianzhong ladder), and the Classic row says 'Pagat lists a variant with no no-trump option'. Evidence: The Pagat variant with no no-trump option is the three-deck game, not a 2-deck variant: 'this in turn can be overruled by a triple ... There is no no-trump option (exposing jokers) in this version.' Pagat therefore contradicts the Lianzhong three-deck ladder that includes joker no-trump bids. The Classic row's note belongs in the 3-deck row. This check is outside the team and combination scope but was found in the same text.
- **refuted** (Four-deck Sheng Ji (4p, 4 decks)): Team structure and combination types are unknown (not stated). Evidence: These are weak sources, but they fill the gap. The 多乐升级 developer notes describe a 4-player 对家 game with a 四副牌 room type and team mode ('四副牌组队不会遇到机器人', 'TYPE_ROOM_FOUR = 10 # 四副牌'), and note that 4-deck trump declaring needs at least two cards ('四副牌: 两张起亮，三张起炒'). The tractorplus README, low reliability and apparently AI-written, describes 4 players in diagonal teams with a 4-deck extension: '每人52张，底牌8张', with new types '炸弹：四张相同点数牌' and '炸弹拖拉机'. With 4 decks, robertying allows four-of-a-kind and tractors of quads.
- **refuted** (Six-player Tractor, 2 decks (Pagat)): Some search summaries said Pagat's six-player game uses 3 decks (header 'Players: 4, 6' / '2x52+4J, 3x52+6J'). Evidence: The header is confirmed ('Players: 4, 6' / '2x52+4J, 3x52+6J'), but '3x52+6J' belongs to the separate 'Game with three decks' section, where 'Each player draws 39 cards and the starter takes an additional six' (4 players). The six-player section deals 6x17+6 = 108 cards, which is 2 decks.
- **refuted** (Six players, 4 decks): Teams, hand size, kitty size and combinations are not described anywhere. Evidence: The TljPro / TuoLaJi Pro app source (github.com/cckcheng/TljPro, TuoLaJiPro.java) describes this setup, but as Finding Friends with bidding rather than fixed teams: '本游戏为六人四付找朋友打法，采用竞叫上庄，庄家叫主后拿底牌并扣底，然后找一个朋友（也可以不找，一个打五个，打成后升级翻倍）'. In English: 'played by six players, using four full decks. Each player is dealt with 35 cards, while the remaining 6 cards will be added to the declarer ... e.g. 2nd ♠A ... then all other 4 players will be the defenders.' That makes it 2 vs 4 (or 1 vs 5), with 35 cards each and a 6-card kitty. Combinations (Tutor.java): '拖拉机：相连的对子（或者三条，四条）' and '四条也称为炸弹，可以大过两对的拖拉机' (four of a kind beats a two-pair tractor). The Zhihu mention (fixed-team 升级, unverified) and TljPro may describe two different 6-player 4-deck games.
- **unsupported** (Three-player bidding (三人升级), 2 decks): No fixed teams; each player keeps their own level; the dealer is decided by bidding; 33 cards each with a 9-card kitty. Evidence: I could not reach the cited Baidu Baike and Zhidao pages and found no independent source. Unverified, not contradicted.
- **unsupported** (找朋友 Chinese form, 5p, 3 decks): No fixed allies; the dealer calls 'the Xth person to play a card', giving 2 vs 3 or 1 vs 4; each player levels individually; triples exist. Evidence: I could not reach the cited Baidu, QQ, Alayou or zh-Wikipedia pages. The general mechanics match independent sources (Pagat Zhao Pengyou and en-Wikipedia: called-card friends, and a called card played by the leader shrinks the team), and three decks give triples. I found no independent source for the 5-player 3-deck setup itself (31 cards each, 7-card kitty, 1 call).
- **unsupported** (Online and app versions): Dani Entertainment Tractor app: 4p 2v2 to 80, 5p find 1 friend, 6p 3v3 to 160, 7p find 2 friends. Evidence: apps.apple.com was unreachable, so the claim rests only on a search summary. Unverified.
- **refuted** (learnerSummary): 'Six players split into two fixed teams of three in alternating seats', presented as how six players play, while 'Groups of 5, 7 or more usually play Finding Friends'. Evidence: Fixed 3v3 is documented (Pagat Tractor, rbtying), but 6-player Finding Friends is at least as well documented. Pagat Zhao Pengyou lists 6 players (2 packs, 2 friends) and calls Finding Friends 'one of the most successful games for 6 or more people'. en-Wikipedia's Finding Friends example is a 6-player game. TljPro is a 6-player 4-deck Finding Friends game with bidding. The summary should say six players play either fixed 3v3 or Finding Friends.
