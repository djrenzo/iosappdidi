import Foundation
import Observation

@MainActor
@Observable
final class AlbumsViewModel {
    private(set) var albums: [Album] = []
    var isLoading = false
    var errorMessage: String?

    private let api = PhotoServerAPI()

    func load(userId: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            albums = try await api.albums(userId: userId).sorted { $0.createdAt > $1.createdAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createAlbum(name: String, userId: String) async {
        do {
            let album = try await api.createAlbum(name: name, userId: userId)
            albums.insert(album, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ album: Album) async {
        do {
            try await api.deleteAlbum(id: album.id)
            albums.removeAll { $0.id == album.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setShared(_ album: Album, shared: Bool) async {
        do {
            try await api.updateAlbum(id: album.id, shared: shared)
            if let index = albums.firstIndex(of: album) {
                albums[index] = Album(id: album.id, name: album.name, createdAt: album.createdAt, tag: album.tag, ownerId: album.ownerId, shared: shared)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhotos(_ photoIds: [String], to album: Album) async -> Bool {
        do {
            try await api.addPhotos(albumId: album.id, photoIds: photoIds)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

@MainActor
@Observable
final class AlbumDetailViewModel {
    private(set) var photos: [Photo] = []
    var isLoading = false
    var errorMessage: String?

    private let api = PhotoServerAPI()

    func load(albumId: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            photos = try await api.albumPhotos(id: albumId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}