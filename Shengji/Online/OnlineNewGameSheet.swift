import SwiftUI
import ShengjiCore

/// Start a game: pick the club, how many play (4, 6 or 8), who sits where (your partners in every other
/// seat; friends or bots in the other seats) and how long to play.
@MainActor
struct OnlineNewGameSheet: View {
    let initialClubID: String?
    let onCreated: (OnlineGameSummary) -> Void

    @Environment(OnlineSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var clubID = ""
    @State private var tableOption: GameTableOption = .four
    /// Who sits in each seat after yours, in play order (index 0 is seat 1, your right).
    @State private var others: [OnlineSeatChoice] = Array(repeating: .bot(.standard), count: 3)
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
                playersSection
                if players > 4 {
                    seatsSection(title: "Your team", seats: partnerSeats,
                                 footer: "Teams sit in every other seat, so your partners are \(names(partnerSeats)).")
                    seatsSection(title: "Against you", seats: opponentSeats,
                                 footer: "Bots fill any seat, and they play straight away.")
                } else {
                    seatsSection(title: "Who plays", seats: [2, 1, 3],
                                 footer: "You and your partner play against the other two. Bots fill any seat, and they play straight away.")
                }
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
        .onChange(of: tableOption) { _, _ in
            resetSeatsForClub()
        }
    }

    private var players: Int { tableOption.table.players }

    /// Your partners' seats (every other seat after yours).
    private var partnerSeats: [Int] { Seats.teammates(of: Seats.human, players: players) }

    /// The other team's seats, your right first.
    private var opponentSeats: [Int] { Seats.opponents(of: Seats.human, players: players) }

    /// "Northeast and Northwest".
    private func names(_ seats: [Int]) -> String {
        let all = seats.map { Seats.name($0, players: players) }
        guard let last = all.last else { return "" }
        return all.count == 1 ? last : all.dropLast().joined(separator: ", ") + " and " + last
    }

    private var playersSection: some View {
        Section {
            Picker("Players", selection: $tableOption) {
                ForEach(GameTableOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Players")
        } footer: {
            Text(tableOption.detail)
        }
    }

    private func seatsSection(title: String, seats: [Int], footer: String) -> some View {
        Section {
            ForEach(seats, id: \.self) { seat in
                seatPicker(seatTitle(seat), selection: choice(for: seat))
            }
        } header: {
            Text(title)
        } footer: {
            Text(footer)
        }
    }

    /// "Partner (opposite you)" at a table of four; the compass point at a bigger one.
    private func seatTitle(_ seat: Int) -> String {
        if players == 4 {
            switch seat {
            case 2: return "Partner (opposite you)"
            case 1: return "On your right (plays after you)"
            default: return "On your left"
            }
        }
        let name = Seats.name(seat, players: players)
        return seat == 1 ? "\(name) (plays after you)" : name
    }

    /// The choice for absolute `seat` (1 or more).
    private func choice(for seat: Int) -> Binding<OnlineSeatChoice> {
        Binding(
            get: { others.indices.contains(seat - 1) ? others[seat - 1] : .bot(.standard) },
            set: { value in
                if others.indices.contains(seat - 1) { others[seat - 1] = value }
            })
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
        let chosen = others.compactMap { choice -> String? in
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

    /// Friends from the chosen club in the first seats (your partners first, then the other team from
    /// your right), bots in the rest.
    private func resetSeatsForClub() {
        let members = (club?.members ?? []).filter { $0.id != session.user?.id }
        var friends = members.prefix(players - 1).map(OnlineSeatChoice.member)[...]
        var seats = Array(repeating: OnlineSeatChoice.bot(.standard), count: players - 1)
        for seat in partnerSeats + opponentSeats {
            guard let friend = friends.popFirst() else { break }
            seats[seat - 1] = friend
        }
        others = seats
        defaultSeats = seats
    }

    /// A friend may have joined since your clubs last loaded: load them again, and while the seats are
    /// still the ones chosen for you, seat the newcomer too.
    private func refreshMembers() async {
        let before = club?.members
        await session.refreshMe()
        guard club?.members != before, others == defaultSeats else { return }
        resetSeatsForClub()
    }

    private func create() {
        guard let club, problem == nil, !isCreating else { return }
        isCreating = true
        Task {
            let game = await session.createGame(club: club, others: others, targetRank: length.targetRank)
            isCreating = false
            if let game {
                dismiss()
                onCreated(game)
            }
        }
    }
}
