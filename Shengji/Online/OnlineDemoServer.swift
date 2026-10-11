import Foundation
import ShengjiCore

/// An in-memory stand-in for the online server: every endpoint of docs/online-protocol.md answered with
/// the same JSON shapes, for demo scenes, previews and checks. It never touches the network.
/// Friends and bots play their turns automatically right after yours (or when nudged).
final class OnlineDemoServer: @unchecked Sendable {
    static let demoToken = "demo-session-token"

    struct Snapshot {
        var user: OnlineUser
        var clubs: [OnlineClub]
        var games: [OnlineGameSummary]
    }

    private let lock = NSLock()
    private var me: OnlineUser
    private var users: [String: OnlineUser]
    private var clubs: [OnlineClub]
    private var games: [String: OnlineDemoGame]
    private var nextNumber = 1
    private let clock: () -> Date

    init(world: OnlineDemoData.World, clock: @escaping () -> Date = { Date() }) {
        me = world.me
        var users: [String: OnlineUser] = [:]
        for user in world.users + [world.me] { users[user.id] = user }
        self.users = users
        clubs = world.clubs
        var games: [String: OnlineDemoGame] = [:]
        for game in world.games { games[game.id] = game }
        self.games = games
        self.clock = clock
    }

    /// The standard demo world (clubs, friends and four games).
    static func standard() -> OnlineDemoServer {
        OnlineDemoServer(world: OnlineDemoData.world(now: Date()))
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(user: me, clubs: myClubs, games: gameList)
    }

    /// The demo game itself (checks look inside).
    func demoGame(id: String) -> OnlineDemoGame? {
        lock.lock()
        defer { lock.unlock() }
        return games[id]
    }

    // MARK: Handling requests

    func handle(_ request: OnlineHTTPRequest) -> OnlineHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        let parts = request.url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        let method = request.method.uppercased()
        if parts == ["health"] {
            return json(OnlineHealth(ok: true, version: "demo", push: false))
        }
        guard parts.first == "v1" else { return failure(404, "not_found", "There's nothing here.") }
        let path = Array(parts.dropFirst())
        if path.first == "auth" { return auth(method, path, request.body) }
        guard request.headers["Authorization"] == "Bearer \(OnlineDemoServer.demoToken)" else {
            return failure(401, "unauthorized", "Sign in again.")
        }
        switch (method, path.first) {
        case (_, "me"): return meRoute(method, request.body)
        case (_, "devices"): return OnlineHTTPResponse(statusCode: 204)
        case (_, "clubs"): return clubRoute(method, Array(path.dropFirst()), request.body)
        case (_, "games"): return gameRoute(method, Array(path.dropFirst()), request.body)
        default: return failure(404, "not_found", "There's nothing here.")
        }
    }

    private func auth(_ method: String, _ path: [String], _ body: Data?) -> OnlineHTTPResponse {
        guard method == "POST", path.count == 2 else { return failure(404, "not_found", "There's nothing here.") }
        if path[1] == "apple", let request = decode(OnlineAppleSignInBody.self, body) {
            if let name = request.displayName, !name.isEmpty { rename(name) }
            return json(OnlineAuthResponse(token: OnlineDemoServer.demoToken, user: me))
        }
        if path[1] == "dev", let request = decode(OnlineDevSignInBody.self, body) {
            rename(request.name)
            return json(OnlineAuthResponse(token: OnlineDemoServer.demoToken, user: me))
        }
        return failure(400, "bad_request", "That sign-in request wasn't complete.")
    }

    private func meRoute(_ method: String, _ body: Data?) -> OnlineHTTPResponse {
        switch method {
        case "GET":
            return json(OnlineMeResponse(user: me, clubs: myClubs))
        case "PATCH":
            guard let request = decode(OnlineDisplayNameBody.self, body), OnlineDisplayName.isValid(request.displayName) else {
                return failure(400, "bad_request", "Choose a name of 1 to 24 characters.")
            }
            rename(request.displayName)
            return json(OnlineUserResponse(user: me))
        default:
            return failure(404, "not_found", "There's nothing here.")
        }
    }

    private func rename(_ name: String) {
        me.displayName = OnlineDisplayName.cleaned(name)
        users[me.id] = me
        for index in clubs.indices {
            for member in clubs[index].members.indices where clubs[index].members[member].id == me.id {
                clubs[index].members[member] = me
            }
        }
        for id in games.keys {
            games[id]?.players[0].name = me.displayName
        }
    }

    // MARK: Clubs

    private var myClubs: [OnlineClub] {
        clubs.filter { club in club.members.contains { $0.id == me.id } }
    }

    private func clubRoute(_ method: String, _ path: [String], _ body: Data?) -> OnlineHTTPResponse {
        switch (method, path.count) {
        case ("POST", 0):
            guard let request = decode(OnlineClubNameBody.self, body),
                  !request.name.trimmingCharacters(in: .whitespaces).isEmpty else {
                return failure(400, "bad_request", "Give your club a name.")
            }
            let number = takeNumber()
            let code = OnlineInviteCode.normalized("NEWC\(String(format: "%04d", number))")
            let club = OnlineClub(id: "c_demo_new\(number)", name: request.name, inviteCode: code, members: [me])
            clubs.append(club)
            return json(OnlineClubResponse(club: club))
        case ("POST", 1) where path[0] == "join":
            guard let request = decode(OnlineJoinClubBody.self, body) else {
                return failure(400, "bad_request", "Type the invite code from your friend.")
            }
            let code = OnlineInviteCode.compact(request.inviteCode)
            guard let index = clubs.firstIndex(where: { OnlineInviteCode.compact($0.inviteCode) == code }) else {
                return failure(404, "not_found", "No club has that code. Check it with your friend and try again.")
            }
            if !clubs[index].members.contains(where: { $0.id == me.id }) {
                clubs[index].members.append(me)
            }
            return json(OnlineClubResponse(club: clubs[index]))
        case ("GET", 1):
            guard let club = clubs.first(where: { $0.id == path[0] }) else {
                return failure(404, "not_found", "That club doesn't exist any more.")
            }
            // Like the real server: someone who isn't a member can't tell the club exists.
            guard club.members.contains(where: { $0.id == me.id }) else {
                return failure(404, "not_found", "That club doesn't exist, or you're not a member.")
            }
            let clubGames = gameList.filter { $0.clubId == club.id }
            return json(OnlineClubDetailResponse(club: club, games: clubGames))
        case ("POST", 2) where path[1] == "leave":
            guard let index = clubs.firstIndex(where: { $0.id == path[0] }) else {
                return failure(404, "not_found", "That club doesn't exist any more.")
            }
            clubs[index].members.removeAll { $0.id == me.id }
            return OnlineHTTPResponse(statusCode: 204)
        default:
            return failure(404, "not_found", "There's nothing here.")
        }
    }

    // MARK: Games

    private var gameList: [OnlineGameSummary] {
        let active = games.values.filter { !$0.isOver }.sorted { $0.updatedAt > $1.updatedAt }
        let finished = games.values.filter(\.isOver).sorted { $0.updatedAt > $1.updatedAt }.prefix(20)
        return (active + finished).map { $0.summary() }
    }

    private func gameRoute(_ method: String, _ path: [String], _ body: Data?) -> OnlineHTTPResponse {
        switch (method, path.count) {
        case ("GET", 0):
            return json(OnlineGamesResponse(games: gameList))
        case ("POST", 0):
            return createGame(body)
        case ("GET", 1):
            guard let game = games[path[0]] else { return failure(404, "not_found", "This game has ended or was deleted.") }
            return json(game.state)
        case ("DELETE", 1):
            guard let game = games[path[0]] else { return failure(404, "not_found", "This game has ended or was deleted.") }
            guard game.creatorID == me.id else {
                return failure(403, "forbidden", "Only the player who started this game can end it.")
            }
            games.removeValue(forKey: path[0])
            return OnlineHTTPResponse(statusCode: 204)
        case ("POST", 2) where path[1] == "actions":
            return act(gameID: path[0], body)
        case ("POST", 2) where path[1] == "nudge":
            guard var game = games[path[0]] else { return failure(404, "not_found", "This game has ended or was deleted.") }
            // In the demo, a nudged friend plays straight away.
            let before = game.actingSeat
            game.runAutomatic(humans: [0], now: clock())
            if game.actingSeat != before { game.version += 1 }
            games[path[0]] = game
            return OnlineHTTPResponse(statusCode: 204)
        default:
            return failure(404, "not_found", "There's nothing here.")
        }
    }

    private func createGame(_ body: Data?) -> OnlineHTTPResponse {
        guard let request = decode(OnlineNewGameBody.self, body),
              let table = TableSize(exactly: request.seats.count) else {
            return failure(400, "bad_request", "A game needs 4 to 9 seats.")
        }
        guard let club = clubs.first(where: { $0.id == request.clubId }) else {
            return failure(404, "not_found", "That club doesn't exist any more.")
        }
        guard case let .user(first) = request.seats[0], first == me.id else {
            return failure(400, "bad_request", "You need a seat in your own game.")
        }
        guard [Rank.five, .ten, .ace].contains(request.targetRank) else {
            return failure(400, "bad_request", "Play to 5, 10 or A.")
        }
        var players: [SeatView.Player] = []
        var botLevels: [Int: BotLevel] = [:]
        for (seat, spec) in request.seats.enumerated() {
            switch spec {
            case let .user(id):
                guard let user = club.members.first(where: { $0.id == id }) else {
                    return failure(400, "bad_request", "Everyone at the table must be in the club.")
                }
                players.append(SeatView.Player(name: user.displayName, isBot: false, userID: user.id))
            case let .bot(level):
                players.append(SeatView.Player(name: level.title, isBot: true, userID: nil))
                botLevels[seat] = level.bot
            }
        }
        let number = takeNumber()
        let game = OnlineDemoGame.start(id: "g_demo_new\(number)", clubId: club.id, creatorID: me.id, players: players,
                                        botLevels: botLevels,
                                        settings: GameSettings(targetRank: request.targetRank, table: table),
                                        seed: UInt64(1000 + number), firstBidder: 0, now: clock())
        games[game.id] = game
        return json(OnlineGameResponse(game: game.summary()))
    }

    private struct StaleBody: Encodable {
        var error = "stale"
        var game: OnlineGameSummary
        var view: SeatView
        var version: Int
    }

    private func act(gameID: String, _ body: Data?) -> OnlineHTTPResponse {
        guard var game = games[gameID] else { return failure(404, "not_found", "This game has ended or was deleted.") }
        guard let request = decode(OnlineActionBody.self, body) else {
            return failure(400, "bad_request", "That move couldn't be read.")
        }
        guard request.version == game.version else {
            let state = game.state
            return json(StaleBody(game: state.game, view: state.view, version: state.version), status: 409)
        }
        let outcome: OnlineOutcome?
        do {
            outcome = try game.act(request.action, by: 0, now: clock())
        } catch let rejection as OnlineDemoGame.Rejection {
            return failure(rejection.status, rejection.code, rejection.message)
        } catch {
            return failure(500, "server_error", nil)
        }
        game.runAutomatic(humans: [0], now: clock())
        game.version += 1
        games[gameID] = game
        let state = game.state
        return json(OnlineActionResponse(game: state.game, view: state.view, version: state.version, outcome: outcome))
    }

    // MARK: Helpers

    private func takeNumber() -> Int {
        defer { nextNumber += 1 }
        return nextNumber
    }

    private func decode<T: Decodable>(_ type: T.Type, _ body: Data?) -> T? {
        guard let body else { return nil }
        return try? JSONDecoder().decode(type, from: body)
    }

    private func json<T: Encodable>(_ value: T, status: Int = 200) -> OnlineHTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return OnlineHTTPResponse(statusCode: status, body: data)
    }

    private func failure(_ status: Int, _ code: String, _ message: String?) -> OnlineHTTPResponse {
        json(OnlineErrorBody(error: code, message: message), status: status)
    }
}

/// Answers from the demo server, never the network.
struct OnlineDemoTransport: OnlineTransport {
    let server: OnlineDemoServer

    func send(_ request: OnlineHTTPRequest) async throws -> OnlineHTTPResponse {
        server.handle(request)
    }
}
