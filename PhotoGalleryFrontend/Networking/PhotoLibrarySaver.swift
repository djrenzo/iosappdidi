import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

enum PhotoLibrarySaverError: LocalizedError {
    case accessDenied
    case invalidURL
    case emptyResponse
    case server(status: Int)
    case unsupportedVideoFormat(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Photo library access is required to save photos. Enable it in Settings."
        case .invalidURL:
            return "Could not resolve the photo's address."
        case .emptyResponse:
            return "The server didn't return any data."
        case .server(let status):
            return "The server returned an error (\(status)) while downloading."
        case .unsupportedVideoFormat(let ext):
            let name = ext.isEmpty ? "This video format" : "\(ext.uppercased()) video"
            return "\(name) can't be saved to Photos."
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

        // Download to a file (not into memory — videos can be large) and give it the original's
        // extension. Handing Photos raw `Data` with no filename/type worked for JPEGs, whose type
        // is sniffable, but videos were rejected with PHPhotosErrorDomain 3300 (invalidResource)
        // because Photos couldn't tell what kind of file it was.
        let (downloadedURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw PhotoLibrarySaverError.server(status: http.statusCode)
        }

        let ext = url.pathExtension.isEmpty ? (mediaType == .video ? "mov" : "jpg") : url.pathExtension
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.moveItem(at: downloadedURL, to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else { throw PhotoLibrarySaverError.emptyResponse }

        // Photos only accepts formats it can play (MOV/MP4/M4V with H.264/HEVC etc.) — fail with a
        // readable message instead of an opaque 3300 for e.g. AVI/MKV/WebM.
        if mediaType == .video, !UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileURL.path) {
            throw PhotoLibrarySaverError.unsupportedVideoFormat(ext)
        }

        let originalFilename = url.lastPathComponent
        let typeIdentifier = UTType(filenameExtension: ext)?.identifier
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = originalFilename
            options.uniformTypeIdentifier = typeIdentifier
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: mediaType == .video ? .video : .photo, fileURL: fileURL, options: options)
        }
    }
}
