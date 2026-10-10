import SwiftUI
import AuthenticationServices
import ShengjiCore

/// The Play tab's "Play online with friends" section. Signed out: what it is and Sign in with Apple.
/// Signed in: how many games are waiting on you, and a way in.
@MainActor
struct OnlinePlaySection: View {
    let onOpen: () -> Void

    @Environment(OnlineSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            if session.isSignedIn {
                signedIn
            } else {
                signedOut
            }
        } header: {
            Text("Play online with friends")
        } footer: {
            if !session.isSignedIn {
                Text(OnlineCopy.whySignIn)
            }
        }
    }

    private var signedIn: some View {
        Button(action: onOpen) {
            OnlineEntryLabel(title: entryTitle, subtitle: entrySubtitle, count: session.yourTurnCount)
        }
        .task { await session.refreshIfStale() }
        // Back in the app: the your-turn count may have changed while you were away.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.refreshIfStale() } }
        }
    }

    private var entryTitle: String {
        let count = session.yourTurnCount
        switch count {
        case 0: return "Your online games"
        case 1: return "Your turn in 1 game"
        default: return "Your turn in \(count) games"
        }
    }

    private var entrySubtitle: String {
        if !session.hasLoadedGames { return "Clubs, games and invites" }
        if session.games.isEmpty { return session.clubs.isEmpty ? "Start a club or join one with a code" : "Start a game with your club" }
        let waiting = session.waitingGames.count
        if session.yourTurnCount == 0 {
            return waiting == 1 ? "Waiting on friends in 1 game" : "Waiting on friends in \(waiting) games"
        }
        return "Tap to play your turn"
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.3.fill")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.felt))
                    .accessibilityHidden(true)
                Text(OnlineCopy.pitch(notifies: session.serverSendsPush == true))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OnlineSignInButton(onSignedIn: onOpen)
        }
        .padding(.vertical, 6)
    }
}

/// Short texts shared by the online screens.
enum OnlineCopy {
    /// What online play is; it promises notifications only while the server sends them.
    static func pitch(notifies: Bool) -> String {
        let start = "Start a club with 6 to 10 friends, share its code, and play a game over a few days."
        return start + (notifies ? " You'll get a notification when it's your turn." : " Open the app to see when it's your turn.")
    }
    static let whySignIn = "Sign in so your friends can find you and games follow you to a new phone."
    static let pushOffer = "Get a notification when it's your turn. We'll only tell you about your games."
}

/// "Your turn in 2 games" with a count bubble.
@MainActor
struct OnlineEntryLabel: View {
    let title: String
    let subtitle: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Theme.felt))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.cardInk)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.gold))
                    .accessibilityHidden(true)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Sign in with Apple, asking only for your name (so friends recognise you).
@MainActor
struct OnlineSignInButton: View {
    var onSignedIn: (() -> Void)? = nil

    @Environment(OnlineSession.self) private var session
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .disabled(session.isSigningIn)
            .accessibilityHint("Signs you in to play online with your friends.")
            if session.isSigningIn {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let message = session.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.wrong)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let token = String(data: data, encoding: .utf8) else {
                session.errorMessage = "Sign in with Apple didn't finish. Try again."
                return
            }
            let givenName = credential.fullName?.givenName
            Task {
                if await session.signInWithApple(identityToken: token, givenName: givenName) {
                    onSignedIn?()
                }
            }
        case let .failure(error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            session.errorMessage = "Sign in with Apple didn't work. Try again in a moment."
        }
    }
}

/// Opens the online screens when a notification asks for a game (applied to the Play tab's stack).
struct OnlineOpensPendingGame: ViewModifier {
    @Binding var isOnlineOpen: Bool

    @Environment(OnlineSession.self) private var session

    func body(content: Content) -> some View {
        content
            .onChange(of: session.push.pendingGameID) { _, id in
                if id != nil, session.isSignedIn { isOnlineOpen = true }
            }
            .task {
                // A notification that launched the app arrives before this screen exists.
                try? await Task.sleep(nanoseconds: 400_000_000)
                if session.push.pendingGameID != nil, session.isSignedIn, !isOnlineOpen { isOnlineOpen = true }
            }
    }
}

/// Switches to the Play tab when a notification asks for a game (applied to the tab view).
struct OnlineShowsPlayTab: ViewModifier {
    let showPlay: () -> Void

    @Environment(OnlineSession.self) private var session

    func body(content: Content) -> some View {
        content
            // `initial`: a tap that launched the app can set the game before this view first draws,
            // and a plain onChange never sees a value that was there from the start.
            .onChange(of: session.push.pendingGameID, initial: true) { _, id in
                if id != nil { showPlay() }
            }
    }
}
