import SwiftUI
import ShengjiCore

/// Finding Friends: the cards the dealer called, under the top bar. "1st A♠ → NE" once someone has
/// played it, "1st A♠ ?" while the friend is still hidden. Shared by the offline and online tables.
@MainActor
struct GameFriendCallsRow: View {
    let calls: [FriendCall]
    /// A short seat name for the chips ("NE", "You").
    let name: (Int) -> String
    /// The full seat name, for VoiceOver.
    let spokenName: (Int) -> String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.2.fill")
                .font(.caption2)
                .foregroundStyle(Theme.gold)
            Text("Friends")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.85))
            ForEach(Array(calls.enumerated()), id: \.offset) { _, call in
                chip(call)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func chip(_ call: FriendCall) -> some View {
        let who = call.friend.map(name) ?? "?"
        return HStack(spacing: 3) {
            Text(FriendCallText.short(call))
                .fontWeight(.bold)
            Image(systemName: call.isFound ? "arrow.right" : "questionmark")
                .font(.caption2.weight(.bold))
            if call.isFound {
                Text(who)
            }
        }
        .font(.caption)
        .foregroundStyle(call.isFound ? Theme.cardInk : Color.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(call.isFound ? Theme.gold : Color.black.opacity(0.3)))
    }

    private var accessibilityText: String {
        let parts = calls.map { call -> String in
            guard let friend = call.friend else { return "\(call), not played yet" }
            return "\(call), played by \(spokenName(friend))"
        }
        return "Friends called: " + parts.joined(separator: "; ")
    }
}

/// Short texts for friend calls.
enum FriendCallText {
    /// "1st", "2nd", "3rd", "4th", "5th".
    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// "1st A♠"
    static func short(_ call: FriendCall) -> String { "\(ordinal(call.ordinal)) \(call.face)" }
}

/// Finding Friends: the dealer names their friends after choosing the cards to bury. One row per friend:
/// the card (rank and suit) and which copy counts (the first one played, the second, ...). Starts from
/// the bot's suggestion, says why a choice can't be made, and warns about a card you hold yourself.
@MainActor
struct FriendCallSheet: View {
    let table: TableSize
    let trump: Trump
    /// The dealer's hand once the chosen cards are buried.
    let hand: [Card]
    let suggestion: FriendCallChoice?
    /// Why the calls can't be made, or nil.
    let problem: ([FriendCall]) -> String?
    let onCall: ([FriendCall]) -> Void
    let onBack: () -> Void

    @State private var picks: [Pick]

    /// One friend's card being chosen.
    struct Pick: Hashable {
        var rank: Rank
        var suit: Suit
        var ordinal: Int

        var call: FriendCall { FriendCall(rank, suit, ordinal: ordinal) }
    }

    init(table: TableSize, trump: Trump, hand: [Card], suggestion: FriendCallChoice?,
         problem: @escaping ([FriendCall]) -> String?, onCall: @escaping ([FriendCall]) -> Void,
         onBack: @escaping () -> Void) {
        self.table = table
        self.trump = trump
        self.hand = hand
        self.suggestion = suggestion
        self.problem = problem
        self.onCall = onCall
        self.onBack = onBack
        _picks = State(initialValue: FriendCallSheet.picks(from: suggestion?.calls ?? [], table: table, trump: trump))
    }

    /// The suggestion as picks, padded with aces (kings when aces are trump rank) to `friendCount`.
    static func picks(from calls: [FriendCall], table: TableSize, trump: Trump) -> [Pick] {
        var out = calls.compactMap { call -> Pick? in
            guard let rank = call.face.rank, let suit = call.face.suit else { return nil }
            return Pick(rank: rank, suit: suit, ordinal: call.ordinal)
        }
        let top: Rank = trump.rank == .ace ? .king : .ace
        var suits = Suit.allCases.filter { $0 != trump.suit }
        while out.count < table.friendCount {
            let suit = suits.isEmpty ? Suit.spades : suits.removeFirst()
            out.append(Pick(rank: top, suit: suit, ordinal: 1))
        }
        return Array(out.prefix(table.friendCount))
    }

    private var calls: [FriendCall] { picks.map(\.call) }
    private var currentProblem: String? { problem(calls) }
    /// Ranks you may call, high to low (not the trump rank).
    private var ranks: [Rank] { Rank.allCases.reversed().filter { $0 != trump.rank } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(intro)
                        .font(.subheadline)
                    if let suggestion, !suggestion.reason.isEmpty {
                        Label(suggestion.reason, systemImage: "lightbulb")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(picks.indices, id: \.self) { index in
                    Section(table.friendCount == 1 ? "Your friend" : "Friend \(index + 1)") {
                        pickRows(index)
                    }
                }
                if let currentProblem {
                    Section {
                        Label(currentProblem, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.wrong)
                    }
                }
            }
            .navigationTitle(table.friendCount == 1 ? "Call a friend" : "Call \(table.friendCount) friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back", action: onBack)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Call") { onCall(calls) }
                        .disabled(currentProblem != nil)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var intro: String {
        let one = table.friendCount == 1
        return "Name \(one ? "a card" : "\(table.friendCount) cards"). Whoever plays \(one ? "it" : "one of them") "
            + "joins your side, and nobody knows who until then. Pick cards you don't hold, so someone else "
            + "answers. Jokers and \(trump.rank.label)s (the trump rank) can't be called."
    }

    @ViewBuilder
    private func pickRows(_ index: Int) -> some View {
        Picker("Card", selection: $picks[index].rank) {
            ForEach(ranks, id: \.self) { rank in
                Text(rank.label).tag(rank)
            }
        }
        .pickerStyle(.menu)
        Picker("Suit", selection: $picks[index].suit) {
            ForEach(Suit.allCases, id: \.self) { suit in
                Text(suit.symbol).tag(suit)
            }
        }
        .pickerStyle(.segmented)
        Picker("Which one", selection: $picks[index].ordinal) {
            ForEach(1...max(table.decks, 1), id: \.self) { ordinal in
                Text(FriendCallText.ordinal(ordinal)).tag(ordinal)
            }
        }
        .pickerStyle(.segmented)
        Text(summary(picks[index]))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// "The first A♠ played. You hold none." / "... You hold 1: if you play it first, it counts as yours."
    private func summary(_ pick: Pick) -> String {
        let face = Face.regular(pick.suit, pick.rank)
        let held = hand.filter { $0.face == face }.count
        var text = "Your friend is whoever plays \(pick.call)."
        if held == 0 {
            text += " You hold none."
        } else if held >= pick.ordinal {
            text += " You hold \(held), so you could end up as your own friend: then you play short-handed."
        } else {
            text += " You hold \(held): copies you play count too."
        }
        if trump.isTrump(Card(pick.rank, pick.suit)) {
            text += " It is a trump this round."
        }
        return text
    }
}
