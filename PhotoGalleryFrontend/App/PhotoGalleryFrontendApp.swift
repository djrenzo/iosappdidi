import SwiftUI

@main
struct PhotoGalleryFrontendApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .preferredColorScheme(nil)
        }
    }
}
