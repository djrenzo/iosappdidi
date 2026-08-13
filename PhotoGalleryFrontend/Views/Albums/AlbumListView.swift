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
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.accentSoft)
                .frame(height: 110)
                .overlay(Image(systemName: "photo.stack.fill").font(.title).foregroundStyle(Theme.accent))
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
