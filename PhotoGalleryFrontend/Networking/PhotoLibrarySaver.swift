import Foundation
import Photos

enum PhotoLibrarySaverError: LocalizedError {
    case accessDenied
    case invalidURL
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo library access is required to save photos. Enable it in Settings."
        case .invalidURL:
            return "Could not resolve the photo's address."
        case .emptyResponse:
            return "The server didn't return any image data."
        }
    }
}

/// Downloads a photo-server relative path — always the full-resolution `originalUrl`,
/// never `thumbUrl`/`previewUrl` — and saves it into the user's Photos library.
enum PhotoLibrarySaver {
    static func save(path: String, mediaType: MediaType = .image) async throws {
        guard let url = APIClient.shared.absoluteURL(forPath: path) else {
            throw PhotoLibrarySaverError.invalidURL
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaverError.accessDenied
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard !data.isEmpty else { throw PhotoLibrarySaverError.emptyResponse }

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: mediaType == .video ? .video : .photo, data: data, options: nil)
        }
    }
}
