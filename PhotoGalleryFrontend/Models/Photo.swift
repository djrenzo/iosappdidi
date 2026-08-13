import Foundation

struct Photo: Codable, Identifiable, Hashable {
    let id: String
    let filename: String
    let db: String?
    let folder: String
    let width: Int?
    let height: Int?
    let takenAt: String?
    let favorite: Bool
    let thumbReady: Bool
    let thumbError: String?
    let thumbUrl: String
    let previewUrl: String
    let originalUrl: String

    var takenAtDate: Date? {
        guard let takenAt else { return nil }
        return ISO8601DateFormatter().date(from: takenAt)
    }
}

struct PhotoDetail: Codable, Identifiable, Hashable {
    let id: String
    let filename: String
    let db: String?
    let folder: String
    let width: Int?
    let height: Int?
    let takenAt: String?
    let favorite: Bool
    let thumbReady: Bool
    let thumbError: String?
    let thumbUrl: String
    let previewUrl: String
    let originalUrl: String
    let cameraMake: String?
    let cameraModel: String?
    let tags: [String]

    var asPhoto: Photo {
        Photo(id: id, filename: filename, db: db, folder: folder, width: width, height: height,
              takenAt: takenAt, favorite: favorite, thumbReady: thumbReady, thumbError: thumbError,
              thumbUrl: thumbUrl, previewUrl: previewUrl, originalUrl: originalUrl)
    }
}

struct PhotoPage: Codable {
    let total: Int
    let items: [Photo]
}
