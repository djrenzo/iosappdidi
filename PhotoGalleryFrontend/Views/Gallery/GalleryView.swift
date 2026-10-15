import SwiftUI

struct GalleryView: View {
    var session: SessionStore
    var library: LibraryViewModel
    @Environment(PhotoViewerPresenter.self) private var photoViewer
    @State private var grid = PhotoGridViewModel()
    @State private var selectionMode = false
    @State private var selectedIds: Set<String> = []
    @State private var showAddToAlbum = false
    /// Global y of the scroll view's visible top edge (below the nav bar) — where the pinned year
    /// header sits. With `yearHeaderHeight`, tells when a month label has slid under it.
    @State private var scrollTopEdge: CGFloat = 0
    @State private var yearHeaderHeight: CGFloat = 0
    /// Per year section id: index of the month the pinned year header currently shows.
    @State private var currentMonthIndex: [String: Int] = [:]

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
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY + $0.safeAreaInsets.top }) {
                scrollTopEdge = $0
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

    @ViewBuilder
    private var photoGrid: some View {
        if showsDateSections {
            // One section per year: its header (year + current month) stays pinned while the
            // year scrolls by and only gets pushed out by the next year's header. Months within
            // the year are plain labels that slide under the pinned header, which then
            // crossfades its month to match.
            LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                ForEach(yearSections) { year in
                    Section {
                        ForEach(Array(year.months.enumerated()), id: \.element.id) { index, month in
                            // The first month is already shown in the header itself.
                            if index > 0, let monthTitle = month.title {
                                monthLabel(monthTitle, index: index, in: year)
                            }
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(month.photos) { photo in thumbnailCell(photo) }
                            }
                        }
                    } header: {
                        yearHeader(year)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        } else {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(grid.photos) { photo in
                    thumbnailCell(photo)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private func yearHeader(_ year: YearSection) -> some View {
        let monthIndex = min(currentMonthIndex[year.id] ?? 0, year.months.count - 1)
        let monthTitle = year.months[monthIndex].title
        return VStack(alignment: .leading, spacing: 2) {
            Text(year.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            if let monthTitle {
                Text(monthTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: monthTitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Opaque so content scrolling underneath the pinned header doesn't show through;
        // extended past the horizontal padding to cover the gutters.
        .background(Theme.background.padding(.horizontal, -16))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { yearHeaderHeight = $0 }
    }

    private func monthLabel(_ title: String, index: Int, in year: YearSection) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            // Reports whether this label has slid under the pinned year header. Labels are lazy
            // (far-off ones aren't instantiated), so each report also settles its neighbors:
            // a label that passed implies every earlier month did too, and one that hasn't
            // implies no later month has either.
            .onGeometryChange(for: Bool.self, of: {
                $0.frame(in: .global).minY < scrollTopEdge + yearHeaderHeight
            }) { passed in
                let current = currentMonthIndex[year.id] ?? 0
                let new = passed ? max(current, index) : min(current, index - 1)
                if new != current { currentMonthIndex[year.id] = new }
            }
    }

    private struct YearSection: Identifiable {
        let id: String
        let title: String
        var months: [MonthSection]
    }

    private struct MonthSection: Identifiable {
        let id: String
        let title: String?
        var photos: [Photo]
    }

    /// Groups consecutive photos by year, then by month within the year (the list is already
    /// date-sorted).
    private var yearSections: [YearSection] {
        var years: [YearSection] = []
        var currentYear: String?
        var currentMonth: String?
        for photo in grid.photos {
            let year = photo.takenAtYear.map(String.init) ?? "Unknown Date"
            let month = photo.takenAtYear == nil ? nil : photo.takenAtMonthText
            if years.isEmpty || year != currentYear {
                years.append(YearSection(id: "\(years.count)-\(year)", title: year, months: []))
                currentMonth = nil
            }
            if years[years.count - 1].months.isEmpty || month != currentMonth {
                let yearId = years[years.count - 1].id
                let monthCount = years[years.count - 1].months.count
                years[years.count - 1].months.append(
                    MonthSection(id: "\(yearId)-\(monthCount)-\(month ?? "")", title: month, photos: []))
            }
            let lastMonth = years[years.count - 1].months.count - 1
            years[years.count - 1].months[lastMonth].photos.append(photo)
            currentYear = year
            currentMonth = month
        }
        return years
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
