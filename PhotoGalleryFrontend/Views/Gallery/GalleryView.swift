import SwiftUI

struct GalleryView: View {
    var session: SessionStore
    var library: LibraryViewModel
    @Environment(PhotoViewerPresenter.self) private var photoViewer
    @State private var grid = PhotoGridViewModel()
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
                if !grid.configure(library: lib, folder: library.selectedFolder, userId: session.currentUser?.id) {
                    Task { await grid.reload() }
                }
            }
            .onChange(of: library.selectedLibrary) { _, new in grid.configure(library: new, folder: library.selectedFolder, userId: session.currentUser?.id) }
            .onChange(of: library.selectedFolder) { _, new in grid.configure(library: library.selectedLibrary, folder: new, userId: session.currentUser?.id) }
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

    /// Month subheadings only make sense in the date-sorted "All Folders" view.
    private var showsDateSections: Bool { library.selectedFolder == nil && grid.sort == .takenAt }

    private var photoGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            if showsDateSections {
                ForEach(dateSections) { section in
                    Section {
                        ForEach(section.photos) { photo in thumbnailCell(photo) }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            if let yearTitle = section.yearTitle {
                                Text(yearTitle)
                                    .font(.title3.bold())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            if let monthTitle = section.monthTitle {
                                Text(monthTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, section.yearTitle != nil ? 12 : 8)
                    }
                }
            } else {
                ForEach(grid.photos) { photo in
                    thumbnailCell(photo)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }

    private struct DateSection: Identifiable {
        let id: String
        /// Only set on the first section of a new year, so the year isn't repeated for every month.
        let yearTitle: String?
        let monthTitle: String?
        var photos: [Photo]
    }

    /// Groups consecutive photos sharing the same year/month (the list is already date-sorted).
    private var dateSections: [DateSection] {
        var sections: [DateSection] = []
        var currentYear: String?
        var currentMonth: String?
        for photo in grid.photos {
            let year = photo.takenAtYear.map(String.init) ?? "Unknown Date"
            let month = photo.takenAtYear == nil ? nil : photo.takenAtMonthText
            if !sections.isEmpty && year == currentYear && month == currentMonth {
                sections[sections.count - 1].photos.append(photo)
            } else {
                sections.append(DateSection(id: "\(sections.count)-\(year)-\(month ?? "")",
                                            yearTitle: year == currentYear ? nil : year,
                                            monthTitle: month, photos: [photo]))
                currentYear = year
                currentMonth = month
            }
        }
        return sections
    }

    private func thumbnailCell(_ photo: Photo) -> some View {
        PhotoThumbnailView(photo: photo, isSelected: selectedIds.contains(photo.id), selectionMode: selectionMode)
            .onTapGesture {
                if selectionMode {
                    toggleSelection(photo)
                } else {
                    photoViewer.present(photos: grid.photos, startPhoto: photo) { p in
                        Task { await grid.toggleFavorite(p) }
                    }
                }
            }
            .onLongPressGesture { beginSelection(photo) }
            .task { await grid.loadMoreIfNeeded(current: photo) }
    }

    private func beginSelection(_ photo: Photo) {
        if !selectionMode { selectionMode = true }
        selectedIds.insert(photo.id)
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
                Picker("Order", selection: $grid.sortOrder) {
                    ForEach(SortDirection.allCases) { direction in Text(direction.label).tag(direction) }
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
