import SwiftUI

struct AddToAlbumSheet: View {
    var session: SessionStore
    let photoIds: [String]
    var onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = AlbumsViewModel()
    @State private var showCreate = false
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            List {
                if viewModel.albums.isEmpty && !viewModel.isLoading {
                    Text("No albums yet. Create one to add these photos.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(viewModel.albums) { album in
                    Button {
                        Task {
                            isAdding = true
                            _ = await viewModel.addPhotos(photoIds, to: album)
                            isAdding = false
                            onComplete()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(album.name).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if isAdding { ProgressView() }
                        }
                    }
                }
            }
            .navigationTitle("Add \(photoIds.count) Photos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await viewModel.load() }
            .sheet(isPresented: $showCreate) {
                CreateAlbumSheet(session: session, viewModel: viewModel)
            }
        }
    }
}
