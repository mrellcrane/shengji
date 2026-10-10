import Foundation
import UIKit
@preconcurrency import UserNotifications

/// UIKit hooks SwiftUI doesn't offer: the push token and notification taps. Installed with
/// `@UIApplicationDelegateAdaptor` in `ShengjiApp`; everything is forwarded to `OnlinePushCenter.shared`.
@MainActor
final class ShengjiAppDelegate: NSObject, UIApplicationDelegate {
    /// UNUserNotificationCenter keeps its delegate weakly.
    private let notifications = OnlineNotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Set before launch finishes, so a tap that launched the app is delivered.
        UNUserNotificationCenter.current().delegate = notifications
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        OnlinePushCenter.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        OnlinePushCenter.shared.didFailToRegister()
    }
}

/// Notifications while the app is open, and taps on them. The completion handlers are called on the
/// main thread, after the push center has seen the notification.
final class OnlineNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let gameID = OnlinePushCenter.gameID(in: notification.request.content.userInfo)
        Task { @MainActor in
            let push = OnlinePushCenter.shared
            push.didReceive(gameID: gameID)
            // The open table already shows its own game live.
            completionHandler(push.isShowing(gameID: gameID) ? [] : [.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let gameID = OnlinePushCenter.gameID(in: response.notification.request.content.userInfo)
        Task { @MainActor in
            OnlinePushCenter.shared.didOpen(gameID: gameID)
            completionHandler()
        }
    }
}
