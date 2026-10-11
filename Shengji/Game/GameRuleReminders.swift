import Foundation
import ShengjiCore

/// One bullet of the in-game rules quick sheet, with a few example cards (dual coding).
struct GameRuleReminder: Identifiable, Sendable {
    let id: String
    let title: String
    let text: String
    let cards: [Card]
    let caption: String?

    /// Trump used by every example: hearts, rank 2.
    static let exampleTrump = Trump(rank: .two, suit: .hearts)

    static let all: [GameRuleReminder] = [
        GameRuleReminder(
            id: "follow",
            title: "Follow suit",
            text: "Play the led suit if you can. Only when you run out may you play something else.",
            cards: [Card(.king, .spades), Card(.four, .spades)],
            caption: "K♠ is led, so you play a spade."),
        GameRuleReminder(
            id: "ruff",
            title: "Trumps beat plain cards",
            text: "Out of the led suit? Any trump beats every card of a plain suit. That's a ruff.",
            cards: [Card(.ace, .spades), Card(.three, .hearts)],
            caption: "3♥ beats A♠ when hearts are trump."),
        GameRuleReminder(
            id: "order",
            title: "Trump order",
            text: "Big joker, small joker, the rank card of the trump suit, other rank cards, then the trump suit from A down.",
            cards: [.bigJoker(), .smallJoker(), Card(.two, .hearts), Card(.two, .spades), Card(.ace, .hearts), Card(.king, .hearts)],
            caption: "Highest on the left."),
        GameRuleReminder(
            id: "pairs",
            title: "Pairs",
            text: "A pair is two identical cards. 7♠ 7♠ is a pair; 7♠ 7♣ is not.",
            cards: [Card(.seven, .spades), Card(.seven, .spades, copy: 1)],
            caption: nil),
        GameRuleReminder(
            id: "tractors",
            title: "Tractors",
            text: "Two or more pairs next to each other in the same suit make a tractor (拖拉机 tuōlājī).",
            cards: [Card(.seven, .spades), Card(.seven, .spades, copy: 1), Card(.eight, .spades), Card(.eight, .spades, copy: 1)],
            caption: nil),
        GameRuleReminder(
            id: "matching",
            title: "Match the shape",
            text: "If a pair is led and you hold a pair in that suit, you must play it. Same for tractors.",
            cards: [Card(.nine, .diamonds), Card(.nine, .diamonds, copy: 1)],
            caption: "A diamond pair was led, so you play your pair."),
        GameRuleReminder(
            id: "points",
            title: "Points",
            text: "5s are worth 5. 10s and Kings are worth 10. There are 200 points in all.",
            cards: [Card(.five, .clubs), Card(.ten, .diamonds), Card(.king, .spades)],
            caption: "25 points here."),
        GameRuleReminder(
            id: "line",
            title: "The 80 line and the kitty",
            text: "Defenders need 80 points to take over the deal. If they win the last trick, the kitty's points count double or more.",
            cards: [],
            caption: nil),
    ]

    /// The reminders for a table of `players`: with 6 or 8, triples join in and the point lines scale
    /// with the decks.
    static func all(players: Int) -> [GameRuleReminder] {
        let table = TableSize(players: players)
        guard table.players > 4 else { return all }
        let threshold = Scoring.takeoverThreshold(decks: table.decks)
        var reminders = all.map { reminder -> GameRuleReminder in
            switch reminder.id {
            case "points":
                return GameRuleReminder(id: reminder.id, title: reminder.title,
                                        text: "5s are worth 5. 10s and Kings are worth 10. With \(table.decks) decks there are \(table.totalPoints) points in all.",
                                        cards: reminder.cards, caption: reminder.caption)
            case "line":
                return GameRuleReminder(id: reminder.id, title: "The \(threshold) line and the kitty",
                                        text: "With \(table.decks) decks the defenders need \(threshold) points to take over the deal. If they win the last trick, the kitty's points count double or more.",
                                        cards: [], caption: nil)
            default:
                return reminder
            }
        }
        let triples = GameRuleReminder(
            id: "triples",
            title: "Triples",
            text: "With \(table.decks) decks three identical cards make a triple. If a triple is led, play a triple of that suit if you can, otherwise a pair. Only a triple beats a triple.",
            cards: [Card(.queen, .clubs), Card(.queen, .clubs, copy: 1), Card(.queen, .clubs, copy: 2)],
            caption: nil)
        let index = (reminders.firstIndex { $0.id == "matching" } ?? reminders.count - 1) + 1
        reminders.insert(triples, at: min(index, reminders.count))
        return reminders
    }
}
