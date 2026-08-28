import Foundation

/// Absent (`mediaType` key missing) is treated as `.image` for compatibility with
/// API responses from before video support was added.
enum MediaType: String, Codable, Hashable {
    case image
    case video
}

struct Photo: Codable, Identifiable, Hashable {
    let id: String
    let filename: String
    let db: String?
    let folder: String
    let mediaType: MediaType
    let width: Int?
    let height: Int?
    let takenAt: String?
    let favorite: Bool
    let thumbReady: Bool
    let thumbError: String?
    let thumbUrl: String
    /// `nil` for videos — the server never generates a preview asset for them.
    let previewUrl: String?
    let originalUrl: String

    var takenAtDate: Date? { Photo.parseISO8601(takenAt) }

    init(id: String, filename: String, db: String?, folder: String, mediaType: MediaType, width: Int?,
         height: Int?, takenAt: String?, favorite: Bool, thumbReady: Bool, thumbError: String?,
         thumbUrl: String, previewUrl: String?, originalUrl: String) {
        self.id = id
        self.filename = filename
        self.db = db
        self.folder = folder
        self.mediaType = mediaType
        self.width = width
        self.height = height
        self.takenAt = takenAt
        self.favorite = favorite
        self.thumbReady = thumbReady
        self.thumbError = thumbError
        self.thumbUrl = thumbUrl
        self.previewUrl = previewUrl
        self.originalUrl = originalUrl
    }

    private enum CodingKeys: String, CodingKey {
        case id, filename, db, folder, mediaType, width, height, takenAt, favorite
        case thumbReady, thumbError, thumbUrl, previewUrl, originalUrl
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        filename = try values.decode(String.self, forKey: .filename)
        db = try values.decodeIfPresent(String.self, forKey: .db)
        folder = try values.decode(String.self, forKey: .folder)
        mediaType = try values.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .image
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        takenAt = try values.decodeIfPresent(String.self, forKey: .takenAt)
        favorite = try values.decode(Bool.self, forKey: .favorite)
        thumbReady = try values.decode(Bool.self, forKey: .thumbReady)
        thumbError = try values.decodeIfPresent(String.self, forKey: .thumbError)
        thumbUrl = try values.decode(String.self, forKey: .thumbUrl)
        previewUrl = try values.decodeIfPresent(String.self, forKey: .previewUrl)
        originalUrl = try values.decode(String.self, forKey: .originalUrl)
    }

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
    let mediaType: MediaType
    let width: Int?
    let height: Int?
    let takenAt: String?
    let favorite: Bool
    let thumbReady: Bool
    let thumbError: String?
    let thumbUrl: String
    let previewUrl: String?
    let originalUrl: String
    let cameraMake: String?
    let cameraModel: String?
    let tags: [String]

    var takenAtDate: Date? { Photo.parseISO8601(takenAt) }

    var asPhoto: Photo {
        Photo(id: id, filename: filename, db: db, folder: folder, mediaType: mediaType, width: width, height: height,
              takenAt: takenAt, favorite: favorite, thumbReady: thumbReady, thumbError: thumbError,
              thumbUrl: thumbUrl, previewUrl: previewUrl, originalUrl: originalUrl)
    }

    init(id: String, filename: String, db: String?, folder: String, mediaType: MediaType, width: Int?,
         height: Int?, takenAt: String?, favorite: Bool, thumbReady: Bool, thumbError: String?,
         thumbUrl: String, previewUrl: String?, originalUrl: String, cameraMake: String?,
         cameraModel: String?, tags: [String]) {
        self.id = id
        self.filename = filename
        self.db = db
        self.folder = folder
        self.mediaType = mediaType
        self.width = width
        self.height = height
        self.takenAt = takenAt
        self.favorite = favorite
        self.thumbReady = thumbReady
        self.thumbError = thumbError
        self.thumbUrl = thumbUrl
        self.previewUrl = previewUrl
        self.originalUrl = originalUrl
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id, filename, db, folder, mediaType, width, height, takenAt, favorite
        case thumbReady, thumbError, thumbUrl, previewUrl, originalUrl
        case cameraMake, cameraModel, tags
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        filename = try values.decode(String.self, forKey: .filename)
        db = try values.decodeIfPresent(String.self, forKey: .db)
        folder = try values.decode(String.self, forKey: .folder)
        mediaType = try values.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .image
        width = try values.decodeIfPresent(Int.self, forKey: .width)
        height = try values.decodeIfPresent(Int.self, forKey: .height)
        takenAt = try values.decodeIfPresent(String.self, forKey: .takenAt)
        favorite = try values.decode(Bool.self, forKey: .favorite)
        thumbReady = try values.decode(Bool.self, forKey: .thumbReady)
        thumbError = try values.decodeIfPresent(String.self, forKey: .thumbError)
        thumbUrl = try values.decode(String.self, forKey: .thumbUrl)
        previewUrl = try values.decodeIfPresent(String.self, forKey: .previewUrl)
        originalUrl = try values.decode(String.self, forKey: .originalUrl)
        cameraMake = try values.decodeIfPresent(String.self, forKey: .cameraMake)
        cameraModel = try values.decodeIfPresent(String.self, forKey: .cameraModel)
        tags = try values.decode([String].self, forKey: .tags)
    }
}

struct PhotoPage: Codable {
    let total: Int
    let items: [Photo]
}
