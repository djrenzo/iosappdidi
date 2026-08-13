import SwiftUI

struct RootView: View {
    var session: SessionStore

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            content
        }
        .task { await session.bootstrap() }
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .checking:
            ProgressView().tint(Theme.accent)
        case .needsServer:
            ServerSetupView(session: session)
        case .needsLogin:
            LoginView(session: session)
        case .authenticated:
            MainTabView(session: session)
        }
    }
}
