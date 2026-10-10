import Foundation
import ShengjiCore

/// Per game, what this device has already counted, so achievements, round tallies and "what happened"
/// survive closing the table: online games move on while you are away. Saved as JSON in UserDefaults
/// ("online.ledger.v1"); demo tables use a throwaway one.
final class OnlineGameLedger: @unchecked Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// The round the counts below belong to.
        var round: Int
        /// Finished tricks of `round` already checked for moves.
        var tricksCounted: Int
        /// The round's declarations were checked (once bidding was over).
        var declarationsCounted: Bool
        /// Rounds whose result was counted (moves, level progress, rounds played).
        var roundsCounted: [Int]
        /// Where you last acted: the round and the trick index your play went into.
        var lastMoveRound: Int?
        var lastMoveTrick: Int?
        var updated: Date
    }

    static let storageKey = "online.ledger.v1"
    static let maxEntries = 60

    private let defaults: UserDefaults?
    private let lock = NSLock()
    private var entries: [String: Entry]

    /// `defaults` nil keeps everything in memory.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        if let defaults, let data = defaults.data(forKey: OnlineGameLedger.storageKey),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        } else {
            entries = [:]
        }
    }

    static func ephemeral() -> OnlineGameLedger { OnlineGameLedger(defaults: nil) }

    func entry(for gameID: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries[gameID]
    }

    func set(_ entry: Entry, for gameID: String) {
        lock.lock()
        var updated = entry
        updated.updated = Date()
        entries[gameID] = updated
        if entries.count > OnlineGameLedger.maxEntries {
            let oldest = entries.sorted { $0.value.updated < $1.value.updated }
            for (key, _) in oldest.prefix(entries.count - OnlineGameLedger.maxEntries) where key != gameID {
                entries.removeValue(forKey: key)
            }
        }
        let snapshot = entries
        lock.unlock()
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: OnlineGameLedger.storageKey)
    }

    func remove(_ gameID: String) {
        lock.lock()
        entries.removeValue(forKey: gameID)
        let snapshot = entries
        lock.unlock()
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: OnlineGameLedger.storageKey)
    }

    /// The state of a table seen for the first time: nothing earlier is counted (it may have been
    /// counted on another device, or long ago).
    static func baseline(for view: SeatView) -> Entry {
        Entry(round: view.roundNumber, tricksCounted: view.tricks.count,
              declarationsCounted: view.phase != .bidding && view.phase != .dealing,
              roundsCounted: view.phase == .finished ? [view.roundNumber] : [],
              lastMoveRound: nil, lastMoveTrick: nil, updated: Date())
    }
}

/// What changed for you between the last counted state of a game and a new view.
struct OnlineProgressUpdate: Equatable {
    var moves: [MoveEvent] = []
    /// A round you were in finished (counted once per round).
    var roundFinished = false
    /// A round finished: its summary from your point of view.
    var finishedRound: RoundSummary?
    /// Your team's level after a finished round, and whether that round won you the game.
    var teamLevel: Rank?
    var wonGame: Bool = false
    /// The game ended (with this result for you) in a round counted now.
    var gameFinished: Bool = false
    /// A new round began since you last looked: show its predecessor's summary.
    var showSummary: RoundSummary?

    var isEmpty: Bool { self == OnlineProgressUpdate() }
}

enum OnlineProgress {
    /// Compares `view` with what was counted (`entry`), returns the new entry and what to report.
    /// Tricks of a round that ended while you were away (no longer in any view) can't be checked; the
    /// round's result still counts from `lastRoundSummary`.
    static func update(_ entry: OnlineGameLedger.Entry?, with view: SeatView) -> (OnlineGameLedger.Entry, OnlineProgressUpdate) {
        guard var entry else { return (OnlineGameLedger.baseline(for: view), OnlineProgressUpdate()) }
        var report = OnlineProgressUpdate()

        if view.roundNumber != entry.round {
            let previous = view.roundNumber - 1
            if view.roundNumber > entry.round, let summary = view.lastRoundSummary, !entry.roundsCounted.contains(previous) {
                report.moves += roundMoves(summary, in: view)
                report.roundFinished = true
                report.finishedRound = summary
                report.teamLevel = summary.levelsAfter.first
                report.wonGame = summary.gameWinner == 0
                report.gameFinished = summary.gameWinner != nil
                entry.roundsCounted.append(previous)
            }
            if view.roundNumber > entry.round, let summary = view.lastRoundSummary {
                report.showSummary = summary
            }
            entry.round = view.roundNumber
            entry.tricksCounted = 0
            entry.declarationsCounted = false
        }

        if !entry.declarationsCounted && view.phase != .bidding && view.phase != .dealing {
            report.moves += MoveDetector.moves(inDeclarationsOf: view)
            entry.declarationsCounted = true
        }

        if view.tricks.count > entry.tricksCounted {
            for index in entry.tricksCounted..<view.tricks.count {
                report.moves += MoveDetector.moves(inTrick: index, of: view)
            }
            entry.tricksCounted = view.tricks.count
        } else if view.tricks.count < entry.tricksCounted {
            // Only possible if the server rewound the round; start counting again from here.
            entry.tricksCounted = view.tricks.count
        }

        if view.phase == .finished, view.result != nil, !entry.roundsCounted.contains(view.roundNumber) {
            report.moves += MoveDetector.moves(inFinishedRoundOf: view)
            report.roundFinished = true
            report.teamLevel = view.teamLevels.first
            report.wonGame = view.gameWinnerTeam == 0
            report.gameFinished = view.gameWinnerTeam != nil
            entry.roundsCounted.append(view.roundNumber)
        }

        if entry.roundsCounted.count > 40 {
            entry.roundsCounted = Array(entry.roundsCounted.suffix(40))
        }
        return (entry, report)
    }

    /// The finished-round moves (kitty raid, hold the deal...) from a summary, via a finished copy of the view.
    static func roundMoves(_ summary: RoundSummary, in view: SeatView) -> [MoveEvent] {
        var finished = view
        finished.phase = .finished
        finished.result = summary.result
        return MoveDetector.moves(inFinishedRoundOf: finished)
    }
}
