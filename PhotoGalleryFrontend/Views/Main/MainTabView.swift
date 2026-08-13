import SwiftUI

struct MainTabView: View {
    var session: SessionStore
    @State private var library = LibraryViewModel()

    var body: some View {
        TabView {
            GalleryView(session: session, library: library)
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle.angled") }
            FavoritesView(library: library)
                .tabItem { Label("Favorites", systemImage: "heart.fill") }
            AlbumListView(session: session, library: library)
                .tabItem { Label("Albums", systemImage: "rectangle.stack.fill") }
            ProfileView(session: session, library: library)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.accent)
        .task {
            guard let user = session.currentUser, library.libraries.isEmpty else { return }
            await library.load(userId: user.id)
        }
    }
}
