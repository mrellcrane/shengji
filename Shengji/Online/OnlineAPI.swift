import Foundation
import ShengjiCore

// Client for the online server (docs/online-protocol.md). SwiftUI-free and free of URLSession types:
// requests go through an `OnlineTransport` (URLSession in the app, an in-memory demo server for
// screenshots and previews, fakes in checks).

/// A request in plain values.
struct OnlineHTTPRequest: Equatable, Sendable {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data?
    /// Seconds before giving up.
    var timeout: TimeInterval
}

/// Status code and body bytes.
struct OnlineHTTPResponse: Equatable, Sendable {
    var statusCode: Int
    var body: Data

    init(statusCode: Int, body: Data = Data()) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// Sends one request. Throws for network failures (no connection, timeout) and `CancellationError`.
protocol OnlineTransport: Sendable {
    func send(_ request: OnlineHTTPRequest) async throws -> OnlineHTTPResponse
}

/// What went wrong, with a learner-facing message for each case.
enum OnlineError: Error, Equatable, Sendable {
    /// No connection, a timeout or a dropped request.
    case offline
    /// The session token was refused (expired, or signed out elsewhere).
    case signedOut
    /// The action was sent with an old version: here is the table as it is now.
    case stale(OnlineGameState)
    /// The rules said no; `message` is the engine's explanation.
    case illegal(String)
    case notYourTurn
    /// 403 for another reason (not a member, not the creator...).
    case forbidden(String)
    case notFound(String)
    case rateLimited(String)
    case server(status: Int, code: String, message: String)
    /// The server answered with something this version can't read.
    case badResponse

    static let offlineMessage = "You're offline. Check your connection and try again."
    static let moveNotSentMessage = "You're offline. Your move wasn't sent."
    static let signedOutMessage = "Your sign-in has expired. Sign in again to keep playing."
    static let notYourTurnMessage = "It's not your turn yet. Here's the table as it is now."
    static let staleMessage = "The table moved on while you were choosing. Here's the latest."
    static let serverMessage = "Something went wrong on the server. Try again in a minute."
    static let badResponseMessage = "The server sent something this version of the app can't read. Try updating the app."

    var message: String {
        switch self {
        case .offline: return OnlineError.offlineMessage
        case .signedOut: return OnlineError.signedOutMessage
        case .stale: return OnlineError.staleMessage
        case let .illegal(message): return message
        case .notYourTurn: return OnlineError.notYourTurnMessage
        case let .forbidden(message), let .notFound(message), let .rateLimited(message): return message
        case let .server(_, _, message): return message
        case .badResponse: return OnlineError.badResponseMessage
        }
    }

    /// Maps a non-2xx reply. `stale` carries the state when the body has it.
    static func from(status: Int, body: Data) -> OnlineError {
        let decoder = JSONDecoder()
        let parsed = try? decoder.decode(OnlineErrorBody.self, from: body)
        let code = parsed?.error ?? "http_\(status)"
        let serverText = parsed?.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (serverText?.isEmpty == false) ? serverText : nil
        switch status {
        case 401:
            return .signedOut
        case 409:
            if let state = try? decoder.decode(OnlineGameState.self, from: body) { return .stale(state) }
            return .server(status: status, code: code, message: text ?? OnlineError.staleMessage)
        case 400 where code == "illegal":
            return .illegal(text ?? "That move isn't allowed here.")
        case 403 where code == "not_your_turn":
            return .notYourTurn
        case 403:
            return .forbidden(text ?? "You can't do that in this game or club.")
        case 404:
            return .notFound(text ?? "That couldn't be found. It may have been deleted.")
        case 429:
            return .rateLimited(text ?? "Slow down a little and try again in a minute.")
        default:
            return .server(status: status, code: code, message: text ?? OnlineError.serverMessage)
        }
    }
}

/// The API, one method per endpoint. A value type: `token` is the session token (nil when signed out).
struct OnlineAPI: Sendable {
    static let productionBaseString = "https://shengji-online.ellcrane.workers.dev"
    /// The real server. (The fallback is never used: the string above is a valid URL.)
    static let productionBaseURL: URL = URL(string: productionBaseString) ?? URL(fileURLWithPath: "/")

    var baseURL: URL
    var transport: OnlineTransport
    var token: String?
    /// The demo server: screenshots and previews, never the network.
    var isMock: Bool

    init(baseURL: URL = OnlineAPI.productionBaseURL, transport: OnlineTransport, token: String? = nil,
         isMock: Bool = false) {
        self.baseURL = baseURL
        self.transport = transport
        self.token = token
        self.isMock = isMock
    }

    // MARK: Auth

    func signInWithApple(identityToken: String, displayName: String?) async throws -> OnlineAuthResponse {
        let name = displayName.map(OnlineDisplayName.cleaned).flatMap { $0.isEmpty ? nil : $0 }
        return try await call("POST", "/v1/auth/apple",
                              body: OnlineAppleSignInBody(identityToken: identityToken, displayName: name),
                              authenticated: false)
    }

    func devSignIn(secret: String, name: String) async throws -> OnlineAuthResponse {
        try await call("POST", "/v1/auth/dev", body: OnlineDevSignInBody(secret: secret, name: name), authenticated: false)
    }

    func health() async throws -> OnlineHealth {
        try await call("GET", "/health", authenticated: false)
    }

    // MARK: Me and devices

    func me() async throws -> OnlineMeResponse {
        try await call("GET", "/v1/me")
    }

    func updateDisplayName(_ name: String) async throws -> OnlineUser {
        let response: OnlineUserResponse = try await call("PATCH", "/v1/me",
                                                          body: OnlineDisplayNameBody(displayName: OnlineDisplayName.cleaned(name)))
        return response.user
    }

    func registerDevice(token deviceToken: String, environment: String) async throws {
        try await callNoContent("POST", "/v1/devices",
                                body: OnlineDeviceBody(platform: "ios", token: deviceToken, environment: environment))
    }

    func unregisterDevice(token deviceToken: String) async throws {
        try await callNoContent("DELETE", "/v1/devices/\(OnlineAPI.pathComponent(deviceToken))")
    }

    // MARK: Clubs

    func createClub(name: String) async throws -> OnlineClub {
        let response: OnlineClubResponse = try await call("POST", "/v1/clubs", body: OnlineClubNameBody(name: name))
        return response.club
    }

    func joinClub(inviteCode: String) async throws -> OnlineClub {
        let response: OnlineClubResponse = try await call("POST", "/v1/clubs/join",
                                                          body: OnlineJoinClubBody(inviteCode: OnlineInviteCode.normalized(inviteCode)))
        return response.club
    }

    func club(id: String) async throws -> OnlineClubDetailResponse {
        try await call("GET", "/v1/clubs/\(OnlineAPI.pathComponent(id))")
    }

    func leaveClub(id: String) async throws {
        try await callNoContent("POST", "/v1/clubs/\(OnlineAPI.pathComponent(id))/leave")
    }

    // MARK: Games

    func games() async throws -> [OnlineGameSummary] {
        let response: OnlineGamesResponse = try await call("GET", "/v1/games")
        return response.games
    }

    func createGame(clubId: String, seats: [OnlineSeatSpec], targetRank: Rank) async throws -> OnlineGameSummary {
        let response: OnlineGameResponse = try await call("POST", "/v1/games",
                                                          body: OnlineNewGameBody(clubId: clubId, seats: seats, targetRank: targetRank))
        return response.game
    }

    func game(id: String) async throws -> OnlineGameState {
        try await call("GET", "/v1/games/\(OnlineAPI.pathComponent(id))")
    }

    /// Sends an action with the version it was chosen at. Throws `.stale(state)` on 409.
    func act(gameID: String, version: Int, action: OnlineAction) async throws -> OnlineActionResponse {
        try await call("POST", "/v1/games/\(OnlineAPI.pathComponent(gameID))/actions",
                       body: OnlineActionBody(version: version, action: action))
    }

    func nudge(gameID: String) async throws {
        try await callNoContent("POST", "/v1/games/\(OnlineAPI.pathComponent(gameID))/nudge")
    }

    func deleteGame(id: String) async throws {
        try await callNoContent("DELETE", "/v1/games/\(OnlineAPI.pathComponent(id))")
    }

    /// `wss://.../v1/games/<id>/live?token=...` (nil when signed out).
    func liveURL(gameID: String) -> URL? {
        guard let token, var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: break
        }
        components.percentEncodedPath = OnlineAPI.joinedPath(components.percentEncodedPath,
                                                             "/v1/games/\(OnlineAPI.pathComponent(gameID))/live")
        components.percentEncodedQuery = "token=" + OnlineAPI.pathComponent(token)
        return components.url
    }

    // MARK: Plumbing

    /// `path` starts with "/" and has its variable parts already escaped with `pathComponent`.
    func url(for path: String) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return baseURL }
        components.percentEncodedPath = OnlineAPI.joinedPath(components.percentEncodedPath, path)
        return components.url ?? baseURL
    }

    static func joinedPath(_ base: String, _ path: String) -> String {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed + path
    }

    func makeRequest(_ method: String, _ path: String, body: Data?, authenticated: Bool) -> OnlineHTTPRequest {
        let url = url(for: path)
        var headers = ["Accept": "application/json"]
        if body != nil { headers["Content-Type"] = "application/json" }
        if authenticated, let token { headers["Authorization"] = "Bearer \(token)" }
        return OnlineHTTPRequest(method: method, url: url, headers: headers, body: body, timeout: 20)
    }

    private func call<Response: Decodable>(_ method: String, _ path: String, authenticated: Bool = true) async throws -> Response {
        let data = try await perform(method, path, body: nil, authenticated: authenticated)
        return try decode(data)
    }

    private func call<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body,
                                                             authenticated: Bool = true) async throws -> Response {
        let data = try await perform(method, path, body: try encode(body), authenticated: authenticated)
        return try decode(data)
    }

    private func callNoContent(_ method: String, _ path: String) async throws {
        _ = try await perform(method, path, body: nil, authenticated: true)
    }

    private func callNoContent<Body: Encodable>(_ method: String, _ path: String, body: Body) async throws {
        _ = try await perform(method, path, body: try encode(body), authenticated: true)
    }

    private func encode<Body: Encodable>(_ body: Body) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw OnlineError.badResponse
        }
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw OnlineError.badResponse
        }
    }

    /// Sends the request; returns the body of a 2xx reply, throws `OnlineError` otherwise.
    private func perform(_ method: String, _ path: String, body: Data?, authenticated: Bool) async throws -> Data {
        if authenticated && token == nil { throw OnlineError.signedOut }
        let request = makeRequest(method, path, body: body, authenticated: authenticated)
        let response: OnlineHTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OnlineError {
            throw error
        } catch {
            throw OnlineError.offline
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OnlineError.from(status: response.statusCode, body: response.body)
        }
        return response.body
    }

    /// Ids go into paths as one escaped component.
    static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
