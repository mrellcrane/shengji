import Foundation
import ShengjiCore

/// The in-progress game, stored as JSON in Application Support (`savedGame.json`).
/// Written after each trick and each phase change; deleted when the game ends or a new one starts.
struct SavedGame: Codable, Sendable {
    static let fileName = "savedGame.json"
    static let currentVersion = 1

    var version: Int
    var game: GameState
    var round: Round
    var rng: SeededGenerator
    var botSpeed: GameBotSpeed
    var predictionsEnabled: Bool
    /// Trick (1-based, this round) of the last "who wins?" prompt, so prompts never come twice in a row.
    var lastPredictionTrick: Int?
    var savedAt: Date

    init(game: GameState, round: Round, rng: SeededGenerator, botSpeed: GameBotSpeed,
         predictionsEnabled: Bool, lastPredictionTrick: Int?, savedAt: Date = Date()) {
        self.version = SavedGame.currentVersion
        self.game = game
        self.round = round
        self.rng = rng
        self.botSpeed = botSpeed
        self.predictionsEnabled = predictionsEnabled
        self.lastPredictionTrick = lastPredictionTrick
        self.savedAt = savedAt
    }

    /// 1-based number of the round in the save.
    var roundNumber: Int {
        round.phase == .finished ? max(1, game.roundsPlayed) : game.roundsPlayed + 1
    }

    /// e.g. "Round 3 · Us 4 · Them 2" (Finding Friends: "Round 3 · You 4", everyone has their own level).
    var summaryLine: String {
        if game.findsFriends { return "Round \(roundNumber) · You \(game.level(of: Seats.human).label)" }
        let us = game.levels.indices.contains(0) ? game.levels[0].label : game.settings.startRank.label
        let them = game.levels.indices.contains(1) ? game.levels[1].label : game.settings.startRank.label
        return "Round \(roundNumber) · Us \(us) · Them \(them)"
    }

    /// e.g. "Playing to Ace", or "6 players · Playing to Ace" at a bigger table.
    var targetLine: String {
        let target = "Playing to \(game.settings.targetRank == .ace ? "Ace" : "level \(game.settings.targetRank.label)")"
        let players = round.players
        if round.isFindingFriends { return "\(players) players · Finding Friends · \(target)" }
        return players > 4 ? "\(players) players · \(target)" : target
    }
}

/// Reads and writes `SavedGame` at a fixed file location.
struct SavedGameStore: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// Application Support/savedGame.json
    static var standard: SavedGameStore {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return SavedGameStore(url: base.appendingPathComponent(SavedGame.fileName))
    }

    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func load() -> SavedGame? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(SavedGame.self, from: data),
              saved.version == SavedGame.currentVersion else { return nil }
        return saved
    }

    func save(_ saved: SavedGame) {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func delete() {
        guard exists else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
