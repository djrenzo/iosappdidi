import SwiftUI

struct FavoritesView: View {
    var library: LibraryViewModel
    @State private var grid = PhotoGridViewModel(favoriteOnly: true)
    @State private var selectedPhoto: Photo?
    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if grid.isLoading && grid.photos.isEmpty {
                    ProgressView().padding(.top, 80).tint(Theme.accent)
                } else if grid.photos.isEmpty {
                    EmptyStateView(icon: "heart", title: "No Favorites Yet",
                                   message: "Tap the heart on any photo to add it to your favorites.")
                } else {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(grid.photos) { photo in
                            PhotoThumbnailView(photo: photo)
                                .onTapGesture { selectedPhoto = photo }
                                .task { await grid.loadMoreIfNeeded(current: photo) }
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.background)
            .navigationTitle("Favorites")
            .task { library.selectedLibrary.map { grid.configure(library: $0, folder: nil) } }
            .onChange(of: library.selectedLibrary) { _, new in grid.configure(library: new, folder: nil) }
            .fullScreenCover(item: $selectedPhoto) { photo in
                PhotoDetailPagerView(photos: grid.photos, startPhoto: photo, onFavoriteToggled: { p in
                    Task { await grid.toggleFavorite(p) }
                })
            }
        }
    }
}
