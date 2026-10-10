import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Reads a short message aloud with VoiceOver (e.g. a celebration that appears and fades on its own).
enum AccessibilityAnnouncer {
    @MainActor
    static func announce(_ text: String) {
        #if canImport(UIKit)
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
        #endif
    }
}
