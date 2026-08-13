import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    var albumsViewModel: AlbumsViewModel
    @State private var detailVM = AlbumDetailViewModel()
    @State private var selectedPhoto: Photo?
    @State private var isShared: Bool
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 8)]

    init(album: Album, viewModel: AlbumsViewModel) {
        self.album = album
        self.albumsViewModel = viewModel
        _isShared = State(initialValue: album.shared ?? false)
    }

    var body: some View {
        ScrollView {
            if detailVM.isLoading && detailVM.photos.isEmpty {
                ProgressView().padding(.top, 80).tint(Theme.accent)
            } else if detailVM.photos.isEmpty {
                EmptyStateView(icon: "photo", title: "Album is Empty",
                               message: "Add photos to this album from the Gallery tab.")
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(detailVM.photos) { photo in
                        PhotoThumbnailView(photo: photo)
                            .onTapGesture { selectedPhoto = photo }
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background)
        .navigationTitle(album.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Shared", isOn: $isShared)
                        .onChange(of: isShared) { _, new in
                            Task { await albumsViewModel.setShared(album, shared: new) }
                        }
                    Button("Delete Album", role: .destructive) {
                        Task { await albumsViewModel.delete(album); dismiss() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await detailVM.load(albumId: album.id) }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoDetailPagerView(photos: detailVM.photos, startPhoto: photo, onFavoriteToggled: { _ in })
        }
    }
}
