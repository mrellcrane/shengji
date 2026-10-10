import Foundation
import ShengjiCore

extension GameController {
    /// Sends what happens at the table to the learner's progress:
    /// illegal plays make the related skill due, predictions count as practice (without moving schedules),
    /// and rounds and games are tallied.
    func connectLearning(_ store: LearningStore) {
        onMistake = { [weak store] skill in
            store?.noteGameMistake(skill)
        }
        onPrediction = { [weak store] correct, seconds in
            store?.record(itemID: SkillID.trickWinner.itemID, correct: correct, seconds: seconds, updateSchedule: false)
        }
        onRoundFinished = { [weak store] in
            store?.recordRoundPlayed()
        }
        onGameFinished = { [weak store] won in
            store?.recordGameFinished(won: won)
        }
    }

    /// Removes the hooks (demo tables never report to the learner's progress).
    func disconnectLearning() {
        onMistake = nil
        onPrediction = nil
        onRoundFinished = nil
        onGameFinished = nil
    }
}
