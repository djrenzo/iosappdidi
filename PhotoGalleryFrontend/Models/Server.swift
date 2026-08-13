import Foundation

/// A user-configured photo server connection: a display name plus its base address.
struct Server: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var host: String
}
