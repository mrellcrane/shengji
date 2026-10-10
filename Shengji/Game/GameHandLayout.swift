import Foundation

/// Where each card of your hand goes: one or two overlapping rows that always fit the width
/// (no horizontal scrolling), cards 46 to 58 pt wide. Pure math so it can be checked on Linux.
struct GameHandLayout: Equatable, Sendable {
    /// How far a selected card rises.
    static let raise: Double = 14
    static let minCardWidth: Double = 46
    static let maxCardWidth: Double = 58
    static let aspect: Double = 1.4

    let count: Int
    let width: Double
    let cardWidth: Double
    let rowCount: Int
    /// Cards in the first (top) row.
    let perRow: Int
    /// Horizontal distance between neighbouring cards in a row.
    let step: Double
    /// Vertical distance between the two rows (the second row covers the bottom of the first).
    let rowOffset: Double

    init(count: Int, width: Double) {
        let count = max(0, count)
        let width = max(0, width)
        self.count = count
        self.width = width
        let w = min(GameHandLayout.maxCardWidth, max(GameHandLayout.minCardWidth, width / 7.4))
        cardWidth = w
        // A step this wide keeps the rank and suit in the corner readable.
        let minStep = w * 0.42
        let maxStep = w * 0.68
        if count <= 1 || GameHandLayout.fitStep(cards: count, width: width, cardWidth: w) >= minStep {
            rowCount = 1
            perRow = max(count, 1)
        } else {
            rowCount = 2
            perRow = (count + 1) / 2
        }
        step = min(maxStep, GameHandLayout.fitStep(cards: perRow, width: width, cardWidth: w))
        rowOffset = w * GameHandLayout.aspect * 0.5
    }

    static func fitStep(cards: Int, width: Double, cardWidth: Double) -> Double {
        guard cards > 1 else { return 0 }
        return max(0, (width - cardWidth) / Double(cards - 1))
    }

    var cardHeight: Double { cardWidth * GameHandLayout.aspect }

    /// Total height including room for raised cards.
    var height: Double {
        GameHandLayout.raise + cardHeight + (rowCount == 2 ? rowOffset : 0) + 2
    }

    func row(of index: Int) -> Int {
        rowCount == 2 && index >= perRow ? 1 : 0
    }

    /// Top-left corner of the card at `index` (unselected).
    func origin(of index: Int) -> (x: Double, y: Double) {
        let row = row(of: index)
        let column = row == 0 ? index : index - perRow
        let inRow = row == 0 ? min(count, perRow) : count - perRow
        let rowWidth = cardWidth + step * Double(max(inRow - 1, 0))
        let x0 = max(0, (width - rowWidth) / 2)
        return (x0 + step * Double(column), GameHandLayout.raise + Double(row) * rowOffset)
    }
}
