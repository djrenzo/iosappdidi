import SwiftUI

struct GalleryView: View {
    var session: SessionStore
    var library: LibraryViewModel
    @State private var grid = PhotoGridViewModel()
    @State private var selectedPhoto: Photo?
    @State private var selectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showAddToAlbum = false

    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 140), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if grid.isLoading && grid.photos.isEmpty {
                    ProgressView().padding(.top, 80).tint(Theme.accent)
                } else if grid.photos.isEmpty {
                    EmptyStateView(icon: "photo.stack", title: "No Photos Yet",
                                   message: "This folder doesn't have any indexed photos yet.")
                } else {
                    header
                    photoGrid
                }
            }
            .background(Theme.background)
            .navigationTitle("Gallery")
            .toolbar { toolbarContent }
            .toolbar(selectionMode ? .hidden : .visible, for: .tabBar)
            .onAppear {
                guard let lib = library.selectedLibrary else { return }
                // Re-fetch every time this tab becomes visible so favorites toggled
                // elsewhere (e.g. the Favorites tab, which owns its own copy of the grid) show up.
                if !grid.configure(library: lib, folder: library.selectedFolder) {
                    Task { await grid.reload() }
                }
            }
            .onChange(of: library.selectedLibrary) { _, new in grid.configure(library: new, folder: library.selectedFolder) }
            .onChange(of: library.selectedFolder) { _, new in grid.configure(library: library.selectedLibrary, folder: new) }
            .fullScreenCover(item: $selectedPhoto) { photo in
                PhotoDetailPagerView(photos: grid.photos, startPhoto: photo, onFavoriteToggled: { p in
                    Task { await grid.toggleFavorite(p) }
                })
            }
            .sheet(isPresented: $showAddToAlbum) {
                AddToAlbumSheet(session: session, photoIds: Array(selectedIds)) {
                    selectionMode = false
                    selectedIds.removeAll()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(grid.total) Photos").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                    Text(library.selectedFolder ?? "All Folders").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(grid.photos) { photo in
                thumbnailCell(photo)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private func thumbnailCell(_ photo: Photo) -> some View {
        PhotoThumbnailView(photo: photo, isSelected: selectedIds.contains(photo.id), selectionMode: selectionMode)
            .onTapGesture {
                if selectionMode {
                    toggleSelection(photo)
                } else {
                    selectedPhoto = photo
                }
            }
            .task { await grid.loadMoreIfNeeded(current: photo) }
    }

    private func toggleSelection(_ photo: Photo) {
        if selectedIds.contains(photo.id) { selectedIds.remove(photo.id) } else { selectedIds.insert(photo.id) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) { FolderPickerView(library: library) }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort", selection: $grid.sort) {
                    ForEach(PhotoSort.allCases) { sort in Text(sort.label).tag(sort) }
                }
                Button(selectionMode ? "Cancel Selection" : "Select Photos") {
                    selectionMode.toggle()
                    if !selectionMode { selectedIds.removeAll() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        if selectionMode && !selectedIds.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button("Add \(selectedIds.count) to Album") { showAddToAlbum = true }
            }
        }
    }
}
