import SwiftUI
import ShengjiCore

/// Colours and sizes shared by every screen.
enum Theme {
    /// Card-table felt.
    static let felt = Color(red: 0.07, green: 0.36, blue: 0.24)
    static let feltDeep = Color(red: 0.04, green: 0.24, blue: 0.16)
    /// Accent for trumps, highlights and "correct".
    static let gold = Color(red: 0.96, green: 0.76, blue: 0.22)
    static let cardRed = Color(red: 0.80, green: 0.10, blue: 0.14)
    static let cardInk = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let cardBack = Color(red: 0.62, green: 0.12, blue: 0.16)
    static let correct = Color(red: 0.16, green: 0.62, blue: 0.33)
    static let wrong = Color(red: 0.85, green: 0.25, blue: 0.22)
    /// Our team (you + partner) and their team.
    static let usColor = Color(red: 0.20, green: 0.55, blue: 0.95)
    static let themColor = Color(red: 0.93, green: 0.45, blue: 0.20)

    static func ink(for card: Card) -> Color {
        switch card.face {
        case .bigJoker: return cardRed
        case .smallJoker: return cardInk
        case let .regular(suit, _): return suit.isRed ? cardRed : cardInk
        }
    }

    static func teamColor(_ team: Int) -> Color { team == 0 ? usColor : themColor }

    static func suitColor(_ suit: Suit) -> Color { suit.isRed ? cardRed : cardInk }
}
