import SwiftUI
import ShengjiCore

// Previews run against the in-memory demo server (never the network).
#if DEBUG
#Preview("Online table") {
    let session = OnlineSession.demo()
    return OnlineTableView(model: session.makeTable(gameID: OnlineDemoData.tableGameID)) {}
        .environment(session)
        .environment(LearningStore(ephemeral: true))
        .environment(AchievementStore(ephemeral: true))
}

#Preview("Online home") {
    let session = OnlineSession.demo()
    return NavigationStack {
        OnlineHomeView()
    }
    .environment(session)
    .environment(LearningStore(ephemeral: true))
    .environment(AchievementStore(ephemeral: true))
}
#endif
