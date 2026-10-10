import Foundation
import ShengjiCore

extension GameController {
    /// Sends the moves you make at the table, and your game milestones, to your achievements.
    func connectAchievements(_ store: AchievementStore) {
        onMoves = { [weak store] events in
            store?.record(events)
        }
        onGameProgress = { [weak store] teamLevel, wonGame in
            store?.recordGameProgress(teamLevel: teamLevel, wonGame: wonGame)
        }
    }

    /// Removes the hooks (demo tables never count towards achievements).
    func disconnectAchievements() {
        onMoves = nil
        onGameProgress = nil
    }
}
