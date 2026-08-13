import Foundation

/// Typed request builders for every Photo Server endpoint used by the app.
struct PhotoServerAPI {
    private let client = APIClient.shared

    // MARK: Auth

    func login(name: String, password: String) async throws -> AuthResponse {
        try await client.request(path: "/api/auth/login", method: "POST", body: LoginBody(name: name, password: password))
    }

    func signup(name: String, password: String) async throws -> AuthResponse {
        try await client.request(path: "/api/auth/signup", method: "POST", body: LoginBody(name: name, password: password))
    }

    func me() async throws -> User {
        try await client.request(path: "/api/auth/me")
    }

    func updateProfile(name: String?, avatarData: String?) async throws -> User {
        try await client.request(path: "/api/auth/me", method: "PATCH", body: ProfileUpdateBody(name: name, avatarData: avatarData))
    }

    func changePassword(current: String?, newPassword: String) async throws {
        try await client.requestVoid(path: "/api/auth/me/password", method: "PATCH", body: PasswordBody(currentPassword: current, newPassword: newPassword))
    }

    // MARK: Libraries & Folders

    func libraries(userId: String) async throws -> [String] {
        try await client.request(path: "/api/libraries", query: ["user_id": userId])
    }

    func folders(library: String) async throws -> [String] {
        try await client.request(path: "/api/folders", query: ["library": library])
    }

    // MARK: Photos

    func photos(library: String, folder: String? = nil, limit: Int = 60, offset: Int = 0,
                sort: String = "taken_at", order: String = "desc", favorite: Bool? = nil, tag: String? = nil) async throws -> PhotoPage {
        try await client.request(path: "/api/photos", query: [
            "library": library,
            "folder": folder,
            "limit": String(limit),
            "offset": String(offset),
            "sort": sort,
            "order": order,
            "favorite": favorite.map(String.init),
            "tag": tag
        ])
    }

    func photoDetail(id: String) async throws -> PhotoDetail {
        try await client.request(path: "/api/photos/\(id)")
    }

    func setFavorite(id: String, favorite: Bool) async throws {
        try await client.requestVoid(path: "/api/photos/\(id)/favorite", method: "PATCH", body: FavoriteBody(favorite: favorite))
    }

    func addTag(id: String, tag: String) async throws {
        try await client.requestVoid(path: "/api/photos/\(id)/tags", method: "POST", body: TagBody(tag: tag))
    }

    func removeTag(id: String, tag: String) async throws {
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        try await client.requestVoid(path: "/api/photos/\(id)/tags/\(encodedTag)", method: "DELETE")
    }

    // MARK: Albums

    func albums(userId: String) async throws -> [Album] {
        try await client.request(path: "/api/albums", query: ["user_id": userId])
    }

    func createAlbum(name: String, userId: String, tag: String? = nil, shared: Bool = false) async throws -> Album {
        try await client.request(path: "/api/albums", method: "POST", body: CreateAlbumBody(name: name, tag: tag, userId: userId, shared: shared ? 1 : 0))
    }

    func deleteAlbum(id: Int) async throws {
        try await client.requestVoid(path: "/api/albums/\(id)", method: "DELETE")
    }

    func updateAlbum(id: Int, shared: Bool) async throws {
        try await client.requestVoid(path: "/api/albums/\(id)", method: "PATCH", body: SharedBody(shared: shared ? 1 : 0))
    }

    func albumPhotos(id: Int) async throws -> [Photo] {
        try await client.request(path: "/api/albums/\(id)/photos")
    }

    func addPhotos(albumId: Int, photoIds: [String]) async throws {
        try await client.requestVoid(path: "/api/albums/\(albumId)/photos", method: "POST", body: AddPhotosBody(photoIds: photoIds))
    }
}

private struct LoginBody: Encodable { let name: String; let password: String }
private struct ProfileUpdateBody: Encodable { let name: String?; let avatarData: String? }
private struct PasswordBody: Encodable { let currentPassword: String?; let newPassword: String }
private struct FavoriteBody: Encodable { let favorite: Bool }
private struct TagBody: Encodable { let tag: String }
private struct CreateAlbumBody: Encodable { let name: String; let tag: String?; let userId: String; let shared: Int
    enum CodingKeys: String, CodingKey { case name, tag; case userId = "user_id"; case shared }
}
private struct SharedBody: Encodable { let shared: Int }
private struct AddPhotosBody: Encodable { let photoIds: [String] }

/// The server's login/signup response: JWT token + user object.
struct AuthResponse: Decodable {
    let token: String
    let user: User
}
