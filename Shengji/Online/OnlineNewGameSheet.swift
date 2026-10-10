import SwiftUI
import ShengjiCore

/// Start a game: pick the club, who sits where (your partner opposite you; friends or bots in the
/// other seats) and how long to play.
@MainActor
struct OnlineNewGameSheet: View {
    let initialClubID: String?
    let onCreated: (OnlineGameSummary) -> Void

    @Environment(OnlineSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var clubID = ""
    @State private var partner: OnlineSeatChoice = .bot(.standard)
    @State private var right: OnlineSeatChoice = .bot(.standard)
    @State private var left: OnlineSeatChoice = .bot(.standard)
    @State private var length: GameLengthOption = .toTen
    @State private var isCreating = false
    @State private var didSetDefaults = false
    /// The seats as `resetSeatsForClub` chose them (to tell whether you have changed any).
    @State private var defaultSeats: [OnlineSeatChoice] = []

    private var club: OnlineClub? { session.club(id: clubID) }

    var body: some View {
        NavigationStack {
            Form {
                if session.clubs.count > 1 {
                    Section("Club") {
                        Picker("Club", selection: $clubID) {
                            ForEach(session.clubs) { club in
                                Text(club.name).tag(club.id)
                            }
                        }
                    }
                }
                seatsSection
                lengthSection
                if let problem {
                    Section { Text(problem).foregroundStyle(Theme.wrong) }
                } else if let message = session.errorMessage {
                    Section { Text(message).foregroundStyle(Theme.wrong) }
                }
            }
            .navigationTitle("New game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Start", action: create)
                            .disabled(club == nil || problem != nil)
                    }
                }
            }
        }
        .onAppear(perform: setDefaults)
        .task { await refreshMembers() }
        .onChange(of: clubID) { _, _ in
            resetSeatsForClub()
        }
    }

    private var seatsSection: some View {
        Section {
            seatPicker("Partner (opposite you)", selection: $partner)
            seatPicker("On your right (plays after you)", selection: $right)
            seatPicker("On your left", selection: $left)
        } header: {
            Text("Who plays")
        } footer: {
            Text("You and your partner play against the other two. Bots fill any seat, and they play straight away.")
        }
    }

    private var lengthSection: some View {
        Section {
            Picker("Play to", selection: $length) {
                ForEach(GameLengthOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Play to")
        } footer: {
            Text(length.detail)
        }
    }

    private func seatPicker(_ title: String, selection: Binding<OnlineSeatChoice>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(option.title).tag(option)
            }
        }
    }

    /// Friends in the club (not you), then the two kinds of bot.
    private var options: [OnlineSeatChoice] {
        let members = (club?.members ?? []).filter { $0.id != session.user?.id }.map(OnlineSeatChoice.member)
        return members + OnlineBotLevel.allCases.map(OnlineSeatChoice.bot)
    }

    private var problem: String? {
        let chosen = [partner, right, left].compactMap { choice -> String? in
            if case let .member(user) = choice { return user.id }
            return nil
        }
        if Set(chosen).count != chosen.count { return "Each friend can only take one seat." }
        return nil
    }

    private func setDefaults() {
        guard !didSetDefaults else { return }
        didSetDefaults = true
        session.errorMessage = nil
        clubID = initialClubID ?? session.clubs.first?.id ?? ""
        resetSeatsForClub()
    }

    /// Friends from the chosen club in the first seats (partner first), bots in the rest.
    private func resetSeatsForClub() {
        let members = (club?.members ?? []).filter { $0.id != session.user?.id }
        var choices = members.prefix(3).map(OnlineSeatChoice.member)
        while choices.count < 3 { choices.append(.bot(.standard)) }
        partner = choices[0]
        right = choices[1]
        left = choices[2]
        defaultSeats = [partner, right, left]
    }

    /// A friend may have joined since your clubs last loaded: load them again, and while the seats are
    /// still the ones chosen for you, seat the newcomer too.
    private func refreshMembers() async {
        let before = club?.members
        await session.refreshMe()
        guard club?.members != before, [partner, right, left] == defaultSeats else { return }
        resetSeatsForClub()
    }

    private func create() {
        guard let club, problem == nil, !isCreating else { return }
        isCreating = true
        Task {
            let game = await session.createGame(club: club, right: right, partner: partner, left: left,
                                                targetRank: length.targetRank)
            isCreating = false
            if let game {
                dismiss()
                onCreated(game)
            }
        }
    }
}
