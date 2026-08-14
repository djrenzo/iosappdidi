import Foundation
import Observation

enum PhotoSort: String, CaseIterable, Identifiable {
    case takenAt = "taken_at"
    case filename = "filename"
    case sizeBytes = "size_bytes"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .takenAt: return "Date taken"
        case .filename: return "Name"
        case .sizeBytes: return "File size"
        }
    }
}

enum SortDirection: String, CaseIterable, Identifiable {
    case descending = "desc"
    case ascending = "asc"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .descending: return "Descending"
        case .ascending: return "Ascending"
        }
    }
}

/// Drives either a paginated library/folder/tag-filtered photo grid, or (when `favoriteOnly`)
/// the user's favorites — a separate, non-paginated endpoint not scoped to any library.
@MainActor
@Observable
final class PhotoGridViewModel {
    private(set) var photos: [Photo] = []
    private(set) var total: Int = 0
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var sort: PhotoSort = .takenAt {
        didSet { Task { await reload() } }
    }
    var sortOrder: SortDirection = .descending {
        didSet { Task { await reload() } }
    }

    private let api = PhotoServerAPI()
    private let pageSize = 60
    private var library: String?
    private var folder: String?
    private var userId: String?
    private var favoriteOnly: Bool
    private var tag: String?

    init(favoriteOnly: Bool = false, tag: String? = nil) {
        self.favoriteOnly = favoriteOnly
        self.tag = tag
    }

    /// Always false for the favorites grid — `/api/favorites` returns everything in one
    /// shot, with no pagination.
    var hasMore: Bool { !favoriteOnly && photos.count < total }

    /// For the plain photo grid, `library` is required (folder/userId optional). For the
    /// favorites grid, only `userId` matters — favorites aren't scoped to a library.
    /// Returns `true` if the selection actually changed (and a reload was queued), so callers
    /// can force a reload themselves when it didn't.
    @discardableResult
    func configure(library: String?, folder: String?, userId: String?) -> Bool {
        guard library != self.library || folder != self.folder || userId != self.userId else { return false }
        self.library = library
        self.folder = folder
        self.userId = userId
        Task { await reload() }
        return true
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if favoriteOnly {
                guard let userId else { photos = []; total = 0; return }
                photos = try await api.favorites(userId: userId)
                total = photos.count
            } else {
                guard let library else { return }
                let page = try await api.photos(library: library, folder: folder, limit: pageSize, offset: 0,
                                                 sort: sort.rawValue, order: sortOrder.rawValue, tag: tag, userId: userId)
                photos = page.items
                total = page.total
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current photo: Photo) async {
        guard let index = photos.firstIndex(of: photo), index >= photos.count - 12 else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard !favoriteOnly, let library, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.photos(library: library, folder: folder, limit: pageSize, offset: photos.count,
                                             sort: sort.rawValue, order: sortOrder.rawValue, tag: tag, userId: userId)
            photos.append(contentsOf: page.items)
            total = page.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ photo: Photo) async {
        // Look up by id and flip the grid's own current value, not `photo`'s — the caller
        // (e.g. the detail pager) may be holding a stale snapshot from before an earlier toggle.
        guard let userId, let index = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let current = photos[index]
        let newValue = !current.favorite
        photos[index] = Photo(id: current.id, filename: current.filename, db: current.db, folder: current.folder,
                               width: current.width, height: current.height, takenAt: current.takenAt, favorite: newValue,
                               thumbReady: current.thumbReady, thumbError: current.thumbError, thumbUrl: current.thumbUrl,
                               previewUrl: current.previewUrl, originalUrl: current.originalUrl)
        do {
            try await api.setFavorite(id: current.id, favorite: newValue, userId: userId)
            if favoriteOnly && !newValue {
                photos.remove(at: index)
                total -= 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}