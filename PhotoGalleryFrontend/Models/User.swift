import Foundation

/// The `/api/auth/*` responses don't have a fixed published schema, so this
/// decodes defensively and tolerates either a string or numeric `id`.
struct User: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let isAdmin: Bool?
    let mustChangePassword: Bool?
    let avatarData: String?
    let folders: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, isAdmin, mustChangePassword, avatarData
        case folders = "allowedFolders"
        case user
    }

    init(from decoder: Decoder) throws {
        // Some auth endpoints may wrap the payload as { user: {...} }.
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .user) {
            self = try User(container: nested)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = try User(container: container)
    }

    private init(container: KeyedDecodingContainer<CodingKeys>) throws {
        if let idString = try? container.decode(String.self, forKey: .id) {
            id = idString
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            id = String(idInt)
        } else {
            id = UUID().uuidString
        }
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "User"
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin)
        mustChangePassword = try container.decodeIfPresent(Bool.self, forKey: .mustChangePassword)
        avatarData = try container.decodeIfPresent(String.self, forKey: .avatarData)
        folders = try container.decodeIfPresent([String].self, forKey: .folders)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(isAdmin, forKey: .isAdmin)
        try container.encodeIfPresent(mustChangePassword, forKey: .mustChangePassword)
        try container.encodeIfPresent(avatarData, forKey: .avatarData)
        try container.encodeIfPresent(folders, forKey: .folders)
    }
}
