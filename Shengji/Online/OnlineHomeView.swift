import SwiftUI
import ShengjiCore

/// Sheets of the online home.
enum OnlineHomeSheet: String, Identifiable {
    case newGame, createClub, joinClub, displayName

    var id: String { rawValue }
}

/// Play online: your games (your turn first), your clubs and your account. Pushed from the Play tab.
/// Opens a game's table full screen (also when a notification asks for one).
@MainActor
struct OnlineHomeView: View {
    @Environment(OnlineSession.self) private var session
    @Environment(LearningStore.self) private var learning
    @Environment(AchievementStore.self) private var achievements
    @Environment(\.scenePhase) private var scenePhase

    @State private var table: OnlineGameModel?
    @State private var sheet: OnlineHomeSheet?
    @State private var gameToEnd: OnlineGameSummary?
    @State private var confirmingSignOut = false

    var body: some View {
        content
            .navigationTitle("Play online")
            .toolbar { toolbarContent }
            .sheet(item: $sheet) { item in
                sheetContent(item)
            }
            .fullScreenCover(item: $table) { model in
                OnlineTableView(model: model) { table = nil }
                    .environment(session)
                    .environment(learning)
                    .environment(achievements)
            }
            .confirmationDialog(endTitle, isPresented: endBinding, titleVisibility: .visible) {
                Button("End game", role: .destructive) { endGame() }
                Button("Keep playing", role: .cancel) {}
            } message: {
                Text("Only the player who started a game can end it.")
            }
            .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await session.signOut() } }
                Button("Stay signed in", role: .cancel) {}
            } message: {
                Text("Your games stay safe. Sign in again any time to pick them up.")
            }
            .task {
                await session.refreshIfStale()
                await session.push.refreshPermission()
            }
            .task(id: session.push.pendingGameID) {
                await openPendingGame()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await session.refreshIfStale()
                    await session.push.refreshPermission()
                }
            }
            .onChange(of: session.needsDisplayName, initial: true) { _, needs in
                // New accounts without a name from Apple pick one (also right after signing in elsewhere).
                if needs && sheet == nil { sheet = .displayName }
            }
    }

    @ViewBuilder private var content: some View {
        if session.isSignedIn {
            OnlineGamesList(onOpen: open, onEnd: { gameToEnd = $0 }, onNew: { sheet = $0 },
                            onSignOut: { confirmingSignOut = true })
                .refreshable { await session.refreshAll() }
        } else {
            OnlineSignedOutView()
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if session.isSignedIn {
                Menu {
                    Button { sheet = .newGame } label: { Label("New game", systemImage: "suit.spade.fill") }
                        .disabled(session.clubs.isEmpty)
                    Button { sheet = .createClub } label: { Label("Start a club", systemImage: "person.3") }
                    Button { sheet = .joinClub } label: { Label("Join with a code", systemImage: "ticket") }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("New game or club")
            }
        }
    }

    @ViewBuilder private func sheetContent(_ item: OnlineHomeSheet) -> some View {
        switch item {
        case .newGame:
            OnlineNewGameSheet(initialClubID: nil) { game in open(game.id, after: 0.6) }
                .environment(session)
        case .createClub:
            OnlineCreateClubSheet().environment(session)
        case .joinClub:
            OnlineJoinClubSheet().environment(session)
        case .displayName:
            OnlineDisplayNameSheet().environment(session)
        }
    }

    // MARK: Games

    private func open(_ gameID: String) {
        open(gameID, after: 0)
    }

    /// Opens a table; waits a moment first when a sheet is still closing (UIKit drops a presentation then).
    private func open(_ gameID: String, after seconds: Double) {
        Task {
            if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            if table?.gameID != gameID { table = session.makeTable(gameID: gameID) }
        }
    }

    private func openPendingGame() async {
        guard let id = session.push.pendingGameID, session.isSignedIn else { return }
        // Let this screen finish appearing (a presentation started mid-transition is dropped).
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled, session.push.pendingGameID == id else { return }
        session.push.pendingGameID = nil
        if table?.gameID != id { table = session.makeTable(gameID: id) }
    }

    private var endTitle: String {
        guard let game = gameToEnd else { return "End this game?" }
        return "End the game with \(OnlineGameText.othersLine(game.players))?"
    }

    private var endBinding: Binding<Bool> {
        Binding(get: { gameToEnd != nil }, set: { if !$0 { gameToEnd = nil } })
    }

    private func endGame() {
        guard let game = gameToEnd else { return }
        gameToEnd = nil
        Task { await session.deleteGame(id: game.id) }
    }
}

/// Signed out: what online play is, and Sign in with Apple.
@MainActor
struct OnlineSignedOutView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    CardRow(cards: [Card(.ace, .spades), Card(.king, .hearts), .bigJoker()], cardWidth: 34, spacing: -16)
                        .accessibilityHidden(true)
                    Text("Play with your friends")
                        .font(.title3.weight(.bold))
                    Text(OnlineCopy.pitch)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    OnlineSignInButton()
                    Text(OnlineCopy.whySignIn)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

/// Your games, clubs and account.
@MainActor
struct OnlineGamesList: View {
    let onOpen: (String) -> Void
    let onEnd: (OnlineGameSummary) -> Void
    let onNew: (OnlineHomeSheet) -> Void
    let onSignOut: () -> Void

    @Environment(OnlineSession.self) private var session

    var body: some View {
        List {
            if let message = session.errorMessage {
                OnlineErrorRow(message: message) { session.errorMessage = nil }
            }
            if session.shouldOfferPush {
                OnlinePushOfferRow()
            }
            gameSections
            clubsSection
            accountSection
        }
    }

    @ViewBuilder private var gameSections: some View {
        if !session.hasLoadedGames && session.games.isEmpty {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading your games")
                        .foregroundStyle(.secondary)
                }
            }
        } else if session.games.isEmpty {
            Section("Games") {
                OnlineEmptyGamesRow(hasClub: !session.clubs.isEmpty, onNew: onNew)
            }
        } else {
            gameSection("Your turn", games: session.yourTurnGames)
            gameSection("Waiting on friends", games: session.waitingGames)
            gameSection("Finished", games: session.finishedGames)
        }
    }

    @ViewBuilder private func gameSection(_ title: String, games: [OnlineGameSummary]) -> some View {
        if !games.isEmpty {
            Section(title) {
                ForEach(games) { game in
                    Button {
                        onOpen(game.id)
                    } label: {
                        OnlineGameRow(game: game, clubName: session.clubName(for: game))
                    }
                    .swipeActions(edge: .trailing) {
                        if !game.isFinished {
                            Button(role: .destructive) {
                                onEnd(game)
                            } label: {
                                Label("End game", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }
        }
    }

    private var clubsSection: some View {
        Section {
            ForEach(session.clubs) { club in
                NavigationLink {
                    OnlineClubView(clubID: club.id, onOpenGame: onOpen)
                } label: {
                    OnlineClubRow(club: club)
                }
            }
            Button {
                onNew(.createClub)
            } label: {
                Label("Start a club", systemImage: "person.3")
            }
            Button {
                onNew(.joinClub)
            } label: {
                Label("Join with a code", systemImage: "ticket")
            }
        } header: {
            Text("Your clubs")
        } footer: {
            Text("A club is your group of friends. Share its code so they can join, then start games with anyone in it.")
        }
    }

    private var accountSection: some View {
        Section("You") {
            HStack {
                Label(session.user?.displayName ?? "Loading", systemImage: "person.crop.circle")
                Spacer()
                Button("Change name") { onNew(.displayName) }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
            Button("Sign out", role: .destructive, action: onSignOut)
        }
    }
}

/// One game in the list: who you play with, whose turn it is and what happened last.
@MainActor
struct OnlineGameRow: View {
    let game: OnlineGameSummary
    let clubName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            OnlineGameIcon(game: game)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(OnlineGameText.othersLine(game.players))
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if game.isYourTurn {
                        OnlineYourTurnBadge()
                    }
                }
                Text(OnlineGameText.rowStatus(game))
                    .font(.subheadline.weight(game.isYourTurn ? .semibold : .regular))
                    .foregroundStyle(game.isYourTurn ? Theme.felt : Color.secondary)
                if let last = game.lastEvent, !last.isEmpty {
                    Text(last)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let clubName { parts.append(clubName) }
        parts.append(OnlineGameText.rowDetail(game))
        if let date = game.updatedDate { parts.append(OnlineGameText.relativeTime(date)) }
        return parts.joined(separator: " · ")
    }
}

/// Gold "Your turn" capsule.
@MainActor
struct OnlineYourTurnBadge: View {
    var body: some View {
        Text("Your turn")
            .font(.caption.weight(.heavy))
            .foregroundStyle(Theme.cardInk)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Theme.gold))
    }
}

/// A felt circle: suit for your turn, hourglass while waiting, flag when finished.
@MainActor
struct OnlineGameIcon: View {
    let game: OnlineGameSummary

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(game.isYourTurn ? Theme.cardInk : Color.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(fill))
            .accessibilityHidden(true)
    }

    private var symbol: String {
        if game.isFinished { return game.winnerTeam == 0 ? "trophy.fill" : "flag.checkered" }
        return game.isYourTurn ? "suit.spade.fill" : "hourglass"
    }

    private var fill: Color {
        if game.isYourTurn { return Theme.gold }
        return game.isFinished ? Color.secondary.opacity(0.6) : Theme.felt
    }
}

@MainActor
struct OnlineClubRow: View {
    let club: OnlineClub

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(club.name)
                .font(.headline)
            Text(club.members.count == 1 ? "Just you so far" : "\(club.members.count) members")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// No games yet: start a club, join one, or start a game.
@MainActor
struct OnlineEmptyGamesRow: View {
    let hasClub: Bool
    let onNew: (OnlineHomeSheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(hasClub ? "No games yet. Start one with your club." : "No games yet. Start a club and invite friends, or join theirs with a code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if hasClub {
                Button {
                    onNew(.newGame)
                } label: {
                    Label("New game", systemImage: "suit.spade.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.felt)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A problem from the last request, dismissable.
@MainActor
struct OnlineErrorRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Theme.wrong)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
    }
}

/// Offered once you are in a game: turn on notifications, with a short why.
@MainActor
struct OnlinePushOfferRow: View {
    @Environment(OnlineSession.self) private var session

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("Know when it's your turn", systemImage: "bell.badge.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.felt)
                Text(OnlineCopy.pushOffer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Turn on") {
                        Task { await session.acceptPushOffer() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.felt)
                    Button("Not now") {
                        session.dismissPushOffer()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
