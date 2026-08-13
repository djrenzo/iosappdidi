import SwiftUI

struct AlbumListView: View {
    var session: SessionStore
    var library: LibraryViewModel
    @State private var viewModel = AlbumsViewModel()
    @State private var showCreate = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoading && viewModel.albums.isEmpty {
                    ProgressView().padding(.top, 80).tint(Theme.accent)
                } else if viewModel.albums.isEmpty {
                    EmptyStateView(icon: "rectangle.stack", title: "No Albums Yet",
                                   message: "Create an album to group your favorite shots together.")
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(viewModel.albums) { album in
                            NavigationLink {
                                AlbumDetailView(album: album, viewModel: viewModel)
                            } label: {
                                AlbumCard(album: album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.background)
            .navigationTitle("Albums")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .task {
                guard let userId = session.currentUser?.id else { return }
                await viewModel.load(userId: userId)
            }
            .sheet(isPresented: $showCreate) {
                CreateAlbumSheet(session: session, viewModel: viewModel)
            }
        }
    }
}

private struct AlbumCard: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlbumCoverView(albumId: album.id)
            Text(album.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            HStack(spacing: 4) {
                if album.shared == true {
                    Image(systemName: "person.2.fill").font(.caption2)
                    Text("Shared").font(.caption2)
                } else {
                    Text("Private").font(.caption2)
                }
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// A small collage of the album's first 4 photo thumbnails, or just the first thumbnail
/// alone when the album has fewer than 4. Falls back to a placeholder glyph when empty.
private struct AlbumCoverView: View {
    let albumId: Int
    @State private var photos: [Photo] = []

    private let api = PhotoServerAPI()

    var body: some View {
        Group {
            if photos.isEmpty {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.accentSoft)
                    .overlay(Image(systemName: "photo.stack.fill").font(.title).foregroundStyle(Theme.accent))
            } else if photos.count < 4 {
                singleCover
            } else {
                collage
            }
        }
        .frame(height: 110)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .task(id: albumId) { await load() }
    }

    private var singleCover: some View {
        GeometryReader { geo in
            thumb(photos[0], width: geo.size.width, height: geo.size.height)
        }
    }

    private var collage: some View {
        GeometryReader { geo in
            let cellWidth = (geo.size.width - 2) / 2
            let cellHeight = (geo.size.height - 2) / 2
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    thumb(photos[0], width: cellWidth, height: cellHeight)
                    thumb(photos[1], width: cellWidth, height: cellHeight)
                }
                HStack(spacing: 2) {
                    thumb(photos[2], width: cellWidth, height: cellHeight)
                    thumb(photos[3], width: cellWidth, height: cellHeight)
                }
            }
        }
    }

    private func thumb(_ photo: Photo, width: CGFloat, height: CGFloat) -> some View {
        AsyncPhotoImage(path: photo.thumbUrl) {
            Rectangle().fill(Theme.surfaceElevated)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    private func load() async {
        // /api/albums/:id/photos has no limit param — it always returns the full album,
        // so this fetches everything just to keep the first 4. Fine for typical album
        // sizes; worth a backend `limit` param if albums get large (see TODO.md).
        guard let all = try? await api.albumPhotos(id: albumId) else {
            photos = []
            return
        }
        photos = Array(all.prefix(4))
    }
}
