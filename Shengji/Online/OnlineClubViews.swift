import SwiftUI
import ShengjiCore

/// One club: its invite code (with a share button), members, games, and leaving.
@MainActor
struct OnlineClubView: View {
    let clubID: String
    let onOpenGame: (String) -> Void

    @Environment(OnlineSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var games: [OnlineGameSummary] = []
    @State private var hasLoaded = false
    @State private var showsNewGame = false
    @State private var confirmingLeave = false

    private var club: OnlineClub? { session.club(id: clubID) }

    var body: some View {
        List {
            if let club {
                inviteSection(club)
                membersSection(club)
                gamesSection
                leaveSection
            } else {
                Section {
                    Text("This club isn't in your list any more.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(club?.name ?? "Club")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showsNewGame) {
            OnlineNewGameSheet(initialClubID: clubID) { game in
                Task {
                    // Let the sheet finish closing before the table opens.
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    onOpenGame(game.id)
                }
            }
            .environment(session)
        }
        .confirmationDialog("Leave \(club?.name ?? "this club")?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave club", role: .destructive) { leave() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("You can join again later with the invite code.")
        }
    }

    private func inviteSection(_ club: OnlineClub) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Invite code")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(club.inviteCode)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .textSelection(.enabled)
                    .accessibilityLabel("Invite code \(club.inviteCode.map { String($0) }.joined(separator: " "))")
                ShareLink(item: club.shareText) {
                    Label("Invite friends", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.felt)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Friends tap Join with a code and type this in. Capitals and dashes don't matter.")
        }
    }

    private func membersSection(_ club: OnlineClub) -> some View {
        Section("Members (\(club.members.count))") {
            ForEach(club.members) { member in
                HStack {
                    Label(member.displayName, systemImage: "person.fill")
                    if member.id == session.user?.id {
                        Text("you")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var gamesSection: some View {
        Section("Games") {
            if hasLoaded && games.isEmpty {
                Text("No games in this club yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(games) { game in
                Button {
                    onOpenGame(game.id)
                } label: {
                    OnlineGameRow(game: game, clubName: nil)
                }
            }
            Button {
                showsNewGame = true
            } label: {
                Label("New game", systemImage: "suit.spade.fill")
            }
        }
    }

    private var leaveSection: some View {
        Section {
            Button("Leave club", role: .destructive) { confirmingLeave = true }
        }
    }

    private func load() async {
        if let detail = await session.loadClub(id: clubID) {
            games = OnlineSession.sorted(detail.games)
        }
        hasLoaded = true
    }

    private func leave() {
        Task {
            if await session.leaveClub(id: clubID) { dismiss() }
        }
    }
}

/// Name a new club; then share its code.
@MainActor
struct OnlineCreateClubSheet: View {
    @Environment(OnlineSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var created: OnlineClub?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    createdSection(created)
                } else {
                    Section {
                        TextField("Club name, e.g. Friday Tractor", text: $name)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(create)
                    } footer: {
                        Text("You'll get an invite code to share with your friends.")
                    }
                    if let message = session.errorMessage {
                        Section { Text(message).foregroundStyle(Theme.wrong) }
                    }
                }
            }
            .navigationTitle(created == nil ? "Start a club" : "Club ready")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if created == nil {
                        Button("Create", action: create)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                    }
                }
            }
        }
        .onAppear { session.errorMessage = nil }
    }

    private func createdSection(_ club: OnlineClub) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(club.name)
                    .font(.headline)
                Text(club.inviteCode)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .textSelection(.enabled)
                ShareLink(item: club.shareText) {
                    Label("Invite friends", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.felt)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Send the code to your friends. When they've joined, start a game from the club.")
        }
    }

    private func create() {
        guard created == nil, !isWorking else { return }
        isWorking = true
        Task {
            created = await session.createClub(name: name)
            isWorking = false
        }
    }
}

/// Join a friend's club with its invite code (any case, with or without the dash).
@MainActor
struct OnlineJoinClubSheet: View {
    @Environment(OnlineSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var joined: OnlineClub?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            Form {
                if let joined {
                    Section {
                        Label("You're in \(joined.name)!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.correct)
                        Text("Your friends can now add you to their games, or you can start one from the club.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        TextField("ABCD-EFGH", text: $code)
                            .font(.system(.title3, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.join)
                            .onSubmit(join)
                    } header: {
                        Text("Invite code")
                    } footer: {
                        Text(codeHint)
                    }
                    if let message = session.errorMessage {
                        Section { Text(message).foregroundStyle(Theme.wrong) }
                    }
                }
            }
            .navigationTitle("Join a club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(joined == nil ? "Cancel" : "Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if joined == nil {
                        Button("Join", action: join)
                            .disabled(!OnlineInviteCode.isPlausible(code) || isWorking)
                    }
                }
            }
        }
        .onAppear { session.errorMessage = nil }
    }

    private var codeHint: String {
        let normalized = OnlineInviteCode.normalized(code)
        if OnlineInviteCode.compact(code).count == 8 { return "Code: \(normalized)" }
        return "Ask a friend in the club for its code. Capitals and dashes don't matter."
    }

    private func join() {
        guard joined == nil, !isWorking, OnlineInviteCode.isPlausible(code) else { return }
        isWorking = true
        Task {
            joined = await session.joinClub(code: code)
            isWorking = false
        }
    }
}

/// What your friends see you as (1 to 24 characters).
@MainActor
struct OnlineDisplayNameSheet: View {
    @Environment(OnlineSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isWorking = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    if session.needsDisplayName { Text("What should friends call you?") }
                } footer: {
                    Text("This is how your friends see you in clubs and at the table. You can change it any time.")
                }
                if let message = session.errorMessage {
                    Section { Text(message).foregroundStyle(Theme.wrong) }
                }
            }
            // Short titles: an inline title longer than about 20 characters is cut off on a 375 pt phone.
            .navigationTitle(session.needsDisplayName ? "Choose your name" : "Your name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") {
                        session.needsDisplayName = false
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!OnlineDisplayName.isValid(name) || isWorking)
                }
            }
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            session.errorMessage = nil
            let current = session.user?.displayName ?? ""
            name = OnlineDisplayName.looksGenerated(current) ? "" : current
        }
    }

    private func save() {
        guard OnlineDisplayName.isValid(name), !isWorking else { return }
        isWorking = true
        Task {
            if await session.updateDisplayName(name) { dismiss() }
            isWorking = false
        }
    }
}
