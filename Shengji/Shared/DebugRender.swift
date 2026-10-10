import Foundation

/// Debug-only render tracing. Launch with `-DebugPrintChanges YES` and views that call
/// `DebugRender.trace` print why SwiftUI re-evaluated them (via `_printChanges`).
/// CI uses this to diagnose update loops; it does nothing in release builds.
enum DebugRender {
    #if DEBUG
    static let enabled = UserDefaults.standard.bool(forKey: "DebugPrintChanges")
    #else
    static let enabled = false
    #endif
}
