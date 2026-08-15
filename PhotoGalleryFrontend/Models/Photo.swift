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

    var takenAtDate: Date? { Photo.parseISO8601(takenAt) }

    /// The backend sends fractional-second timestamps (e.g. "2024-07-14T10:22:31.000Z"), which
    /// a default `ISO8601DateFormatter()` silently fails to parse — it needs the
    /// `.withFractionalSeconds` option explicitly. Falls back to a plain parse for timestamps
    /// without fractional seconds.
    fileprivate static func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
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

    var takenAtDate: Date? { Photo.parseISO8601(takenAt) }

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
