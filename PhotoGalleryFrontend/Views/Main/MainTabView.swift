import SwiftUI

struct MainTabView: View {
    var session: SessionStore
    @State private var library = LibraryViewModel()

    var body: some View {
        TabView {
            GalleryView(session: session, library: library)
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle.angled") }
            FavoritesView(session: session)
                .tabItem { Label("Favorites", systemImage: "heart.fill") }
            AlbumListView(session: session, library: library)
                .tabItem { Label("Albums", systemImage: "rectangle.stack.fill") }
            ProfileView(session: session, library: library)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.accent)
        // Keyed to the active server rather than a plain `.task` — switching to a server
        // with a saved session transitions phase .authenticated → .checking → .authenticated
        // synchronously (no network wait in between), so SwiftUI can coalesce that into a
        // single re-render and never actually tear down/recreate this view or its `library`
        // state. Keying on the server id guarantees a refetch regardless of whether that
        // happens.
        .task(id: ServerStore.shared.selectedServerId) {
            guard let user = session.currentUser else { return }
            await library.load(userId: user.id)
        }
    }
}
