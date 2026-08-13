import Foundation

struct Album: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let createdAt: String
    let tag: String?
    let ownerId: String?
    let shared: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case tag
        case ownerId = "owner_id"
        case shared
    }
}
