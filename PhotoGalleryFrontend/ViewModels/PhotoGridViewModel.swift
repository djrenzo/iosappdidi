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

/// Drives a paginated photo grid for a given library/folder/favorite/tag filter.
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

    private let api = PhotoServerAPI()
    private let pageSize = 60
    private var library: String?
    private var folder: String?
    private var favoriteOnly: Bool
    private var tag: String?

    init(favoriteOnly: Bool = false, tag: String? = nil) {
        self.favoriteOnly = favoriteOnly
        self.tag = tag
    }

    var hasMore: Bool { photos.count < total }

    func configure(library: String?, folder: String?) {
        guard library != self.library || folder != self.folder else { return }
        self.library = library
        self.folder = folder
        Task { await reload() }
    }

    func reload() async {
        guard let library else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await api.photos(library: library, folder: folder, limit: pageSize, offset: 0,
                                             sort: sort.rawValue, order: "desc",
                                             favorite: favoriteOnly ? true : nil, tag: tag)
            photos = page.items
            total = page.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current photo: Photo) async {
        guard let index = photos.firstIndex(of: photo), index >= photos.count - 12 else { return }
        await loadNextPage()
    }

    func loadNextPage() async {
        guard let library, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.photos(library: library, folder: folder, limit: pageSize, offset: photos.count,
                                             sort: sort.rawValue, order: "desc",
                                             favorite: favoriteOnly ? true : nil, tag: tag)
            photos.append(contentsOf: page.items)
            total = page.total
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite(_ photo: Photo) async {
        guard let index = photos.firstIndex(of: photo) else { return }
        let newValue = !photo.favorite
        photos[index] = Photo(id: photo.id, filename: photo.filename, db: photo.db, folder: photo.folder,
                               width: photo.width, height: photo.height, takenAt: photo.takenAt, favorite: newValue,
                               thumbReady: photo.thumbReady, thumbError: photo.thumbError, thumbUrl: photo.thumbUrl,
                               previewUrl: photo.previewUrl, originalUrl: photo.originalUrl)
        do {
            try await api.setFavorite(id: photo.id, favorite: newValue)
            if favoriteOnly && !newValue {
                photos.remove(at: index)
                total -= 1
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}