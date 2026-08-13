import Foundation
import Observation

@MainActor
@Observable
final class PhotoDetailViewModel {
    private(set) var detail: PhotoDetail?
    var isLoading = false
    var errorMessage: String?
    var isDownloading = false
    var downloadSucceeded = false

    private let api = PhotoServerAPI()

    func load(id: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detail = try await api.photoDetail(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleFavorite() async {
        guard let detail else { return }
        let newValue = !detail.favorite
        applyFavorite(newValue)
        do {
            try await api.setFavorite(id: detail.id, favorite: newValue)
        } catch {
            applyFavorite(!newValue)
            errorMessage = error.localizedDescription
        }
    }

    func addTag(_ tag: String) async {
        guard let detail, !tag.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespaces)
        do {
            try await api.addTag(id: detail.id, tag: trimmed)
            self.detail = PhotoDetail(id: detail.id, filename: detail.filename, db: detail.db, folder: detail.folder,
                                       width: detail.width, height: detail.height, takenAt: detail.takenAt,
                                       favorite: detail.favorite, thumbReady: detail.thumbReady, thumbError: detail.thumbError,
                                       thumbUrl: detail.thumbUrl, previewUrl: detail.previewUrl, originalUrl: detail.originalUrl,
                                       cameraMake: detail.cameraMake, cameraModel: detail.cameraModel,
                                       tags: detail.tags + [trimmed])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeTag(_ tag: String) async {
        guard let detail else { return }
        do {
            try await api.removeTag(id: detail.id, tag: tag)
            self.detail = PhotoDetail(id: detail.id, filename: detail.filename, db: detail.db, folder: detail.folder,
                                       width: detail.width, height: detail.height, takenAt: detail.takenAt,
                                       favorite: detail.favorite, thumbReady: detail.thumbReady, thumbError: detail.thumbError,
                                       thumbUrl: detail.thumbUrl, previewUrl: detail.previewUrl, originalUrl: detail.originalUrl,
                                       cameraMake: detail.cameraMake, cameraModel: detail.cameraModel,
                                       tags: detail.tags.filter { $0 != tag })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadOriginal(fallbackOriginalUrl: String? = nil) async {
        guard let originalUrl = detail?.originalUrl ?? fallbackOriginalUrl else { return }
        isDownloading = true
        errorMessage = nil
        downloadSucceeded = false
        defer { isDownloading = false }
        do {
            try await PhotoLibrarySaver.save(path: originalUrl)
            downloadSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyFavorite(_ value: Bool) {
        guard let detail else { return }
        self.detail = PhotoDetail(id: detail.id, filename: detail.filename, db: detail.db, folder: detail.folder,
                                   width: detail.width, height: detail.height, takenAt: detail.takenAt,
                                   favorite: value, thumbReady: detail.thumbReady, thumbError: detail.thumbError,
                                   thumbUrl: detail.thumbUrl, previewUrl: detail.previewUrl, originalUrl: detail.originalUrl,
                                   cameraMake: detail.cameraMake, cameraModel: detail.cameraModel, tags: detail.tags)
    }
}
