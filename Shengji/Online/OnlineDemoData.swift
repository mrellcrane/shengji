import Foundation
import ShengjiCore

/// The demo world for screenshots and previews: you (Alex), six friends in two clubs, and four games
/// (your turn mid-play, your turn to declare, waiting on a friend, and a finished game). Every table is
/// built from the real engine and bots with fixed seeds, so it is the same on every launch.
enum OnlineDemoData {
    struct World {
        var me: OnlineUser
        var users: [OnlineUser]
        var clubs: [OnlineClub]
        var games: [OnlineDemoGame]
    }

    /// The table the `onlineGame` scene opens.
    static let tableGameID = "g_demo_table"
    static let biddingGameID = "g_demo_bidding"
    static let waitingGameID = "g_demo_waiting"
    static let finishedGameID = "g_demo_finished"

    static let me = OnlineUser(id: "u_demo_alex", displayName: "Alex")
    static let mei = OnlineUser(id: "u_demo_mei", displayName: "Mei")
    static let jun = OnlineUser(id: "u_demo_jun", displayName: "Jun")
    static let ana = OnlineUser(id: "u_demo_ana", displayName: "Ana")
    static let sam = OnlineUser(id: "u_demo_sam", displayName: "Sam")
    static let lin = OnlineUser(id: "u_demo_lin", displayName: "Lin")
    static let tom = OnlineUser(id: "u_demo_tom", displayName: "Tom")

    static let fridayClub = OnlineClub(id: "c_demo_friday", name: "Friday Tractor", inviteCode: "FRDY-7QTX",
                                       members: [me, mei, jun, ana, sam, lin])
    static let familyClub = OnlineClub(id: "c_demo_family", name: "Family Shengji", inviteCode: "FMLY-42KD",
                                       members: [me, tom, lin])

    static func world(now: Date) -> World {
        World(me: me, users: [mei, jun, ana, sam, lin, tom], clubs: [fridayClub, familyClub],
              games: [tableGame(now: now), biddingGame(now: now), waitingGame(now: now), finishedGame(now: now)])
    }

    static func player(_ user: OnlineUser) -> SeatView.Player {
        SeatView.Player(name: user.displayName, isBot: false, userID: user.id)
    }

    // MARK: Games

    /// Round 3 of a game to A with Mei as your partner: mid-trick, your turn, with Us 4 and Them 3.
    static func tableGame(now: Date) -> OnlineDemoGame {
        let players = [player(me), player(jun), player(mei), player(ana)]
        let history = tableHistory()
        var last: OnlineDemoGame?
        for seed in UInt64(31)...UInt64(70) {
            var game = OnlineDemoGame.resume(id: tableGameID, clubId: fridayClub.id, creatorID: me.id, players: players,
                                             game: history, seed: seed, now: now)
            game.runAutomatic(humans: [], now: now) { $0.isTableMoment }
            game.createdAt = now.addingTimeInterval(-3 * 86_400)
            game.updatedAt = now.addingTimeInterval(-3 * 60)
            game.version = 412
            game.lastEvent = lastPlayLine(game)
            last = game
            if game.isTableMoment { return game }
        }
        return last ?? OnlineDemoGame.resume(id: tableGameID, clubId: fridayClub.id, creatorID: me.id, players: players,
                                             game: history, seed: 31, now: now)
    }

    /// Two rounds already played: you held the deal (+2), then Jun and Ana took it over (+1).
    static func tableHistory() -> GameState {
        var game = GameState(settings: GameSettings(targetRank: .ace))
        let kitty = [Card(.three, .clubs), Card(.four, .clubs), Card(.six, .diamonds), Card(.seven, .diamonds),
                     Card(.eight, .spades), Card(.nine, .spades), Card(.jack, .clubs), Card(.queen, .diamonds)]
        game.record(RoundResult(dealer: 0, declarerTeam: 0, trump: Trump(rank: .two, suit: .hearts), trickPoints: 35,
                                kittyPoints: 0, kittyMultiplier: 0, defenderPoints: 35,
                                outcome: Scoring.outcome(defenderPoints: 35), kitty: kitty, lastTrickWinner: 2))
        let kitty2 = [Card(.five, .clubs), Card(.three, .diamonds), Card(.six, .clubs), Card(.seven, .hearts),
                      Card(.eight, .hearts), Card(.nine, .diamonds), Card(.jack, .hearts), Card(.queen, .clubs)]
        game.record(RoundResult(dealer: 2, declarerTeam: 0, trump: Trump(rank: .four, suit: .spades), trickPoints: 115,
                                kittyPoints: 5, kittyMultiplier: 2, defenderPoints: 125,
                                outcome: Scoring.outcome(defenderPoints: 125), kitty: kitty2, lastTrickWinner: 3))
        return game
    }

    /// Family game to 10: the cards are dealt and it's your turn to declare (you hold a trump-rank card).
    static func biddingGame(now: Date) -> OnlineDemoGame {
        let players = [player(me), player(tom), player(lin),
                       SeatView.Player(name: OnlineBotLevel.beginner.title, isBot: true, userID: nil)]
        var last: OnlineDemoGame?
        for seed in UInt64(5)...UInt64(40) {
            var game = OnlineDemoGame.start(id: biddingGameID, clubId: familyClub.id, creatorID: me.id, players: players,
                                            botLevels: [3: .beginner], settings: GameSettings(targetRank: .ten),
                                            seed: seed, firstBidder: 0, now: now)
            game.createdAt = now.addingTimeInterval(-50 * 60)
            game.updatedAt = game.createdAt
            game.version = 1
            game.lastEvent = "The cards are dealt. You declare first."
            last = game
            if !game.round.availableDeclarations(for: 0).isEmpty { return game }
        }
        return last ?? OnlineDemoGame.start(id: biddingGameID, clubId: familyClub.id, creatorID: me.id, players: players,
                                            botLevels: [3: .beginner], settings: GameSettings(targetRank: .ten),
                                            seed: 5, firstBidder: 0, now: now)
    }

    /// Friday game with a bot as your partner: waiting for Lin to play. Lin started it.
    static func waitingGame(now: Date) -> OnlineDemoGame {
        let players = [player(me), player(sam), SeatView.Player(name: OnlineBotLevel.standard.title, isBot: true, userID: nil),
                       player(lin)]
        var last: OnlineDemoGame?
        for seed in UInt64(71)...UInt64(110) {
            var game = OnlineDemoGame.start(id: waitingGameID, clubId: fridayClub.id, creatorID: lin.id, players: players,
                                            botLevels: [2: .standard], settings: GameSettings(targetRank: .ace),
                                            seed: seed, firstBidder: 3, now: now)
            game.runAutomatic(humans: [], now: now) { $0.isWaitingMoment }
            game.createdAt = now.addingTimeInterval(-26 * 3_600)
            game.updatedAt = now.addingTimeInterval(-20 * 60)
            game.version = 38
            game.lastEvent = lastPlayLine(game)
            last = game
            if game.isWaitingMoment { return game }
        }
        return last ?? OnlineDemoGame.start(id: waitingGameID, clubId: fridayClub.id, creatorID: lin.id, players: players,
                                            botLevels: [2: .standard], settings: GameSettings(targetRank: .ace),
                                            seed: 71, firstBidder: 3, now: now)
    }

    /// A short game to 5 that you and Jun won last weekend.
    static func finishedGame(now: Date) -> OnlineDemoGame {
        let players = [player(me), player(ana), player(jun), player(mei)]
        var history = GameState(settings: GameSettings(targetRank: .five))
        let kitty = [Card(.three, .spades), Card(.four, .spades), Card(.six, .hearts), Card(.seven, .clubs),
                     Card(.eight, .diamonds), Card(.nine, .clubs), Card(.jack, .spades), Card(.queen, .hearts)]
        history.record(RoundResult(dealer: 0, declarerTeam: 0, trump: Trump(rank: .two, suit: .clubs), trickPoints: 0,
                                   kittyPoints: 0, kittyMultiplier: 0, defenderPoints: 0,
                                   outcome: Scoring.outcome(defenderPoints: 0), kitty: kitty, lastTrickWinner: 0))
        history.record(RoundResult(dealer: 2, declarerTeam: 0, trump: Trump(rank: .five, suit: .diamonds),
                                   trickPoints: 40, kittyPoints: 0, kittyMultiplier: 0, defenderPoints: 40,
                                   outcome: Scoring.outcome(defenderPoints: 40), kitty: kitty, lastTrickWinner: 2))
        var game = OnlineDemoGame.resume(id: finishedGameID, clubId: fridayClub.id, creatorID: me.id, players: players,
                                         game: history, seed: 3, now: now)
        game.archived = true
        game.bidding = nil
        game.createdAt = now.addingTimeInterval(-6 * 86_400)
        game.updatedAt = now.addingTimeInterval(-2 * 86_400)
        game.version = 260
        game.lastEvent = "You and Jun won the game."
        return game
    }

    /// "Mei played K♠ K♠" for the last play on the table.
    static func lastPlayLine(_ game: OnlineDemoGame) -> String? {
        let play = game.round.currentTrick.last ?? game.round.tricks.last?.plays.last
        guard let play else { return game.lastEvent }
        return "\(game.name(play.player)) played \(game.round.trump.sorted(play.cards).shortText)"
    }

    // MARK: Sample views (previews)

    /// The `onlineGame` table as a seat view: `Round.seatView(for:players:game:)` of the seeded round.
    static func sampleView() -> SeatView {
        tableGame(now: Date()).view()
    }

    static func sampleSummaries() -> [OnlineGameSummary] {
        world(now: Date()).games.map { $0.summary() }
    }
}

extension OnlineDemoGame {
    /// Mid-round with at least three tricks done, your turn, one or two cards already on the table.
    var isTableMoment: Bool {
        bidding == nil && round.phase == .playing && round.tricks.count >= 3 && round.turn == 0
            && (1...2).contains(round.currentTrick.count)
    }

    /// Lin (seat 3) to play, a couple of tricks in.
    var isWaitingMoment: Bool {
        bidding == nil && round.phase == .playing && round.tricks.count >= 2 && round.turn == 3
    }
}
