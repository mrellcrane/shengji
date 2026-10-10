import Foundation
import Observation

/// Lets any screen switch tabs. Injected by `RootView`:
/// `@Environment(AppRouter.self) private var router`, then `router.show(.review)`.
/// Only used from the main thread (views); deliberately not actor-isolated so `$router.selectedTab`
/// forms a plain key path on every compiler version.
@Observable
final class AppRouter {
    /// The tab on screen. `RootView` binds its `TabView` selection to this.
    var selectedTab: AppTab

    init(initialTab: AppTab = .learn) {
        selectedTab = initialTab
    }

    func show(_ tab: AppTab) {
        selectedTab = tab
    }
}
