import Foundation
import Observation
import UIKit
@preconcurrency import UserNotifications

/// Push notifications for online games: permission, the device token, and what a notification asks
/// for (open a game, refresh the lists). The app delegate forwards to `shared`; `OnlineSession`
/// registers the token with the server. SwiftUI-free.
@MainActor
@Observable
final class OnlinePushCenter {
    static let shared = OnlinePushCenter()

    enum Permission: Equatable, Sendable {
        /// Not checked yet.
        case unknown
        case notDetermined
        case denied
        case allowed
    }

    private(set) var permission: Permission = .unknown
    /// The APNs token as lower-case hex, once registered.
    private(set) var deviceToken: String?
    /// A game to open: a tapped notification (or the demo table). The Play tab opens it, then clears it.
    var pendingGameID: String?
    /// The game on screen (no banner for its own notifications; the table is live already).
    var visibleGameID: String?

    @ObservationIgnored var onDeviceToken: (@MainActor (String) -> Void)?
    @ObservationIgnored var onNotification: (@MainActor (_ gameID: String?) -> Void)?
    /// Demo and preview sessions never ask the system for anything.
    @ObservationIgnored var isEnabled = true

    /// APNs environment for `POST /v1/devices`.
    static var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    /// "a1b2..." from the token bytes.
    nonisolated static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// The game id in a notification's payload (`{"gameId": "g_..."}`).
    nonisolated static func gameID(in userInfo: [AnyHashable: Any]) -> String? {
        guard let id = userInfo["gameId"] as? String, !id.isEmpty else { return nil }
        return id
    }

    // MARK: From the app delegate

    func didRegister(deviceToken data: Data) {
        let token = OnlinePushCenter.hex(data)
        guard !token.isEmpty else { return }
        deviceToken = token
        onDeviceToken?(token)
    }

    func didFailToRegister() {
        // Push is optional: the lists still refresh on open and on pull.
    }

    /// A notification arrived while the app is open.
    func didReceive(gameID: String?) {
        onNotification?(gameID)
    }

    /// You tapped a notification.
    func didOpen(gameID: String?) {
        onNotification?(gameID)
        if let gameID { pendingGameID = gameID }
    }

    func isShowing(gameID: String?) -> Bool {
        guard let gameID else { return false }
        return visibleGameID == gameID
    }

    // MARK: Permission

    func refreshPermission() async {
        guard isEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permission = OnlinePushCenter.permission(for: settings.authorizationStatus)
    }

    nonisolated static func permission(for status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .allowed
        @unknown default: return .unknown
        }
    }

    /// Shows the system prompt (after the app has explained why), then registers if you said yes.
    @discardableResult
    func requestPermission() async -> Bool {
        guard isEnabled else { return false }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        permission = granted ? .allowed : .denied
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// After sign-in and on each launch: register again when allowed (tokens can change).
    func registerIfAllowed() async {
        guard isEnabled else { return }
        await refreshPermission()
        if permission == .allowed { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// The app icon badge: games where it is your turn.
    func setBadge(_ count: Int) {
        guard isEnabled, permission == .allowed else { return }
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
    }
}
