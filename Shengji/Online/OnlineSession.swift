import Foundation
import Observation
import ShengjiCore

/// Who a new game's seat goes to.
enum OnlineSeatChoice: Hashable, Sendable {
    case member(OnlineUser)
    case bot(OnlineBotLevel)

    var spec: OnlineSeatSpec {
        switch self {
        case let .member(user): return .user(id: user.id)
        case let .bot(level): return .bot(level)
        }
    }

    var title: String {
        switch self {
        case let .member(user): return user.displayName
        case let .bot(level): return level.title
        }
    }
}

/// Everything online for the whole app: your account, clubs and games, and the push hookup.
/// Created by `ShengjiApp` and shared through the environment (`@Environment(OnlineSession.self)`).
/// Demo scenes and previews use the in-memory demo server and never touch the network or the Keychain.
/// SwiftUI-free.
@MainActor
@Observable
final class OnlineSession {
    private(set) var api: OnlineAPI
    /// nil until `/v1/me` answers (you can be signed in with the profile still loading).
    private(set) var user: OnlineUser?
    private(set) var clubs: [OnlineClub] = []
    /// Sorted: your turn first, then waiting, then finished (newest first within each).
    private(set) var games: [OnlineGameSummary] = []
    private(set) var hasLoadedGames = false
    private(set) var isRefreshing = false
    private(set) var isSigningIn = false
    /// A learner-facing problem from the last request (shown on the online screens until dismissed).
    var errorMessage: String?
    /// New account without a name from Apple: ask what friends should call you.
    var needsDisplayName = false
    /// The "Know when it's your turn" card was dismissed.
    private(set) var pushOfferDismissed: Bool

    let isMock: Bool
    let push: OnlinePushCenter

    @ObservationIgnored private let tokenStore: OnlineTokenStore
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored let liveConnector: OnlineLiveConnector?
    @ObservationIgnored let ledger: OnlineGameLedger
    /// The table on screen, refreshed when a notification for it arrives.
    @ObservationIgnored weak var activeTable: OnlineGameModel?
    @ObservationIgnored private var lastGamesRefresh: Date?
    @ObservationIgnored private var registeredDeviceToken: String?
    @ObservationIgnored private var launched = false

    static let pushOfferKey = "online.pushOfferDismissed"
    /// Lists refresh at most this often on their own (pull to refresh always works).
    static let autoRefreshInterval: TimeInterval = 10

    init(api: OnlineAPI, tokenStore: OnlineTokenStore, push: OnlinePushCenter, liveConnector: OnlineLiveConnector?,
         ledger: OnlineGameLedger, defaults: UserDefaults?) {
        var api = api
        api.token = tokenStore.load()
        self.api = api
        self.tokenStore = tokenStore
        self.push = push
        self.liveConnector = liveConnector
        self.ledger = ledger
        self.defaults = defaults
        self.isMock = api.isMock
        self.pushOfferDismissed = defaults?.bool(forKey: OnlineSession.pushOfferKey) ?? false
    }

    /// The real server, the Keychain and push.
    static func live() -> OnlineSession {
        OnlineSession(api: OnlineAPI(transport: URLSessionOnlineTransport()), tokenStore: KeychainTokenStore.standard,
                      push: OnlinePushCenter.shared, liveConnector: URLSessionOnlineLiveConnector(),
                      ledger: OnlineGameLedger(defaults: .standard), defaults: .standard)
    }

    /// The demo server (screenshots, previews). `signedIn` starts with the demo account.
    static func demo(signedIn: Bool = true, openGameID: String? = nil) -> OnlineSession {
        let server = OnlineDemoServer.standard()
        let api = OnlineAPI(transport: OnlineDemoTransport(server: server), isMock: true)
        let push = OnlinePushCenter()
        push.isEnabled = false
        push.pendingGameID = openGameID
        let session = OnlineSession(api: api, tokenStore: MemoryTokenStore(token: signedIn ? OnlineDemoServer.demoToken : nil),
                                    push: push, liveConnector: nil, ledger: .ephemeral(), defaults: nil)
        if signedIn {
            let snapshot = server.snapshot()
            session.user = snapshot.user
            session.clubs = snapshot.clubs
            session.games = OnlineSession.sorted(snapshot.games)
            session.hasLoadedGames = true
        }
        return session
    }

    /// The session for this launch: the demo one in screenshot scenes.
    static func forLaunch(scene: DemoScene?) -> OnlineSession {
        guard let scene else { return live() }
        return demo(signedIn: true, openGameID: scene == .onlineGame ? OnlineDemoData.tableGameID : nil)
    }

    // MARK: Reading

    var isSignedIn: Bool { api.token != nil }

    var yourTurnGames: [OnlineGameSummary] { games.filter(\.isYourTurn) }
    var waitingGames: [OnlineGameSummary] { games.filter { !$0.isFinished && !$0.yourTurn } }
    var finishedGames: [OnlineGameSummary] { games.filter(\.isFinished) }
    var yourTurnCount: Int { yourTurnGames.count }

    func club(id: String) -> OnlineClub? { clubs.first { $0.id == id } }

    func clubName(for game: OnlineGameSummary) -> String? { club(id: game.clubId)?.name }

    func game(id: String) -> OnlineGameSummary? { games.first { $0.id == id } }

    /// Your turn first, then games you're waiting on, then finished ones; newest first in each group.
    static func sorted(_ games: [OnlineGameSummary]) -> [OnlineGameSummary] {
        func group(_ game: OnlineGameSummary) -> Int {
            if game.isFinished { return 2 }
            return game.yourTurn ? 0 : 1
        }
        return games.enumerated().sorted { a, b in
            let ga = group(a.element), gb = group(b.element)
            if ga != gb { return ga < gb }
            let da = a.element.updatedDate ?? .distantPast
            let db = b.element.updatedDate ?? .distantPast
            if da != db { return da > db }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Offer notifications once you are in a game, while the system hasn't asked yet.
    var shouldOfferPush: Bool {
        !isMock && isSignedIn && !pushOfferDismissed && push.permission == .notDetermined && !games.isEmpty
    }

    // MARK: Launch and refresh

    /// Once per launch: hook up push and load your account if you are signed in.
    func launch() async {
        guard !launched else { return }
        launched = true
        push.onDeviceToken = { [weak self] token in
            self?.deviceTokenReceived(token)
        }
        push.onNotification = { [weak self] gameID in
            self?.notificationReceived(gameID: gameID)
        }
        guard isSignedIn else { return }
        await refreshAll()
        await push.registerIfAllowed()
    }

    func refreshAll() async {
        await refreshMe()
        await refreshGames()
    }

    func refreshMe() async {
        guard isSignedIn else { return }
        do {
            let me = try await api.me()
            user = me.user
            clubs = me.clubs
        } catch {
            handle(error)
        }
    }

    func refreshGames() async {
        guard isSignedIn else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let list = try await api.games()
            games = OnlineSession.sorted(list)
            hasLoadedGames = true
            lastGamesRefresh = Date()
            push.setBadge(yourTurnCount)
        } catch {
            handle(error)
        }
    }

    /// On appear and on returning to the app: refresh unless it just happened.
    func refreshIfStale() async {
        if let last = lastGamesRefresh, Date().timeIntervalSince(last) < OnlineSession.autoRefreshInterval { return }
        if user == nil { await refreshMe() }
        await refreshGames()
    }

    // MARK: Signing in and out

    /// Sign in with Apple's identity token. `givenName` only comes with the very first sign-in.
    @discardableResult
    func signInWithApple(identityToken: String, givenName: String?) async -> Bool {
        isSigningIn = true
        defer { isSigningIn = false }
        errorMessage = nil
        let name = givenName.map(OnlineDisplayName.cleaned).flatMap { $0.isEmpty ? nil : $0 }
        do {
            let response = try await api.signInWithApple(identityToken: identityToken, displayName: name)
            await completeSignIn(response, hadName: name != nil)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// Test sign-in for development servers (`DEV_AUTH_SECRET`).
    @discardableResult
    func devSignIn(secret: String, name: String) async -> Bool {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let response = try await api.devSignIn(secret: secret, name: name)
            await completeSignIn(response, hadName: true)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    private func completeSignIn(_ response: OnlineAuthResponse, hadName: Bool) async {
        tokenStore.save(response.token)
        api.token = response.token
        user = response.user
        needsDisplayName = !hadName && OnlineDisplayName.looksGenerated(response.user.displayName)
        await refreshAll()
        await push.registerIfAllowed()
        if let token = push.deviceToken { await registerDevice(token) }
    }

    /// Signs out on this phone: the device stops getting pushes, the session token is forgotten.
    func signOut() async {
        if let token = push.deviceToken, isSignedIn, !isMock {
            try? await api.unregisterDevice(token: token)
        }
        signOutLocally(message: nil)
    }

    private func signOutLocally(message: String?) {
        tokenStore.delete()
        api.token = nil
        user = nil
        clubs = []
        games = []
        hasLoadedGames = false
        registeredDeviceToken = nil
        needsDisplayName = false
        lastGamesRefresh = nil
        errorMessage = message
        activeTable?.sessionEnded()
        push.setBadge(0)
    }

    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        guard OnlineDisplayName.isValid(name) else {
            errorMessage = "Choose a name of 1 to \(OnlineDisplayName.maxLength) characters."
            return false
        }
        do {
            user = try await api.updateDisplayName(name)
            needsDisplayName = false
            await refreshMe()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    // MARK: Clubs

    func createClub(name: String) async -> OnlineClub? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Give your club a name."
            return nil
        }
        do {
            let club = try await api.createClub(name: String(trimmed.prefix(40)))
            upsert(club)
            return club
        } catch {
            handle(error)
            return nil
        }
    }

    func joinClub(code: String) async -> OnlineClub? {
        guard OnlineInviteCode.isPlausible(code) else {
            errorMessage = "Invite codes look like ABCD-EFGH. Check the code and try again."
            return nil
        }
        do {
            let club = try await api.joinClub(inviteCode: code)
            upsert(club)
            await refreshGames()
            return club
        } catch {
            handle(error)
            return nil
        }
    }

    /// The club with its members and games (members only).
    func loadClub(id: String) async -> OnlineClubDetailResponse? {
        do {
            let detail = try await api.club(id: id)
            upsert(detail.club)
            return detail
        } catch {
            handle(error)
            return nil
        }
    }

    @discardableResult
    func leaveClub(id: String) async -> Bool {
        do {
            try await api.leaveClub(id: id)
            clubs.removeAll { $0.id == id }
            await refreshGames()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    private func upsert(_ club: OnlineClub) {
        if let index = clubs.firstIndex(where: { $0.id == club.id }) {
            clubs[index] = club
        } else {
            clubs.append(club)
        }
    }

    // MARK: Games

    /// Seats in absolute order: you (0), your right (1), your partner opposite you (2), your left (3).
    func createGame(club: OnlineClub, right: OnlineSeatChoice, partner: OnlineSeatChoice, left: OnlineSeatChoice,
                    targetRank: Rank) async -> OnlineGameSummary? {
        if user == nil { await refreshMe() }
        guard let me = user else {
            errorMessage = errorMessage ?? OnlineError.offlineMessage
            return nil
        }
        let seats: [OnlineSeatSpec] = [.user(id: me.id), right.spec, partner.spec, left.spec]
        do {
            let game = try await api.createGame(clubId: club.id, seats: seats, targetRank: targetRank)
            games = OnlineSession.sorted(games.filter { $0.id != game.id } + [game])
            return game
        } catch {
            handle(error)
            return nil
        }
    }

    /// Ends a game for everyone (the player who started it only).
    @discardableResult
    func deleteGame(id: String) async -> Bool {
        do {
            try await api.deleteGame(id: id)
            games.removeAll { $0.id == id }
            ledger.remove(id)
            push.setBadge(yourTurnCount)
            return true
        } catch {
            handle(error)
            return false
        }
    }

    /// The table for a game (live updates, achievements, the coach).
    func makeTable(gameID: String) -> OnlineGameModel {
        OnlineGameModel(gameID: gameID, api: api, summary: game(id: gameID), liveConnector: liveConnector,
                        ledger: ledger)
    }

    /// The table reports the latest summary so the list stays current without a refetch.
    func noteSummary(_ summary: OnlineGameSummary) {
        guard let index = games.firstIndex(where: { $0.id == summary.id }) else { return }
        guard games[index] != summary else { return }
        games[index] = summary
        games = OnlineSession.sorted(games)
        push.setBadge(yourTurnCount)
    }

    /// The table found the session token refused.
    func tableReportedSignedOut() {
        signOutLocally(message: OnlineError.signedOutMessage)
    }

    // MARK: Push

    func dismissPushOffer() {
        pushOfferDismissed = true
        defaults?.set(true, forKey: OnlineSession.pushOfferKey)
    }

    func acceptPushOffer() async {
        dismissPushOffer()
        await push.requestPermission()
    }

    private func deviceTokenReceived(_ token: String) {
        Task { await registerDevice(token) }
    }

    private func registerDevice(_ token: String) async {
        guard isSignedIn, !isMock, registeredDeviceToken != token else { return }
        do {
            try await api.registerDevice(token: token, environment: OnlinePushCenter.environment)
            registeredDeviceToken = token
        } catch {
            // Quiet: push is optional, and registration is tried again on the next launch.
        }
    }

    private func notificationReceived(gameID: String?) {
        Task { await refreshGames() }
        if let table = activeTable, gameID == nil || table.gameID == gameID {
            Task { await table.refresh() }
        }
    }

    // MARK: Errors

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        guard let online = error as? OnlineError else {
            errorMessage = OnlineError.offlineMessage
            return
        }
        if case .signedOut = online {
            signOutLocally(message: online.message)
            return
        }
        errorMessage = online.message
    }
}
