import UIKit
import CryptoKit

/// Two-tier image cache: an in-memory `NSCache` for fast repeat access within a session, backed
/// by a disk directory (in the app's Caches folder) so images survive relaunches. Nothing evicts
/// the disk tier automatically — it only ever shrinks via `clear()` (Profile → Clear Image Cache).
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskDirectory: URL
    private let diskQueue = DispatchQueue(label: "com.superapp.photogallery.imagecache.disk", qos: .utility)

    private init() {
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = 150 * 1024 * 1024  // 150 MB

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = caches.appendingPathComponent("PhotoImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
    }

    /// Fast, synchronous, memory-only lookup — safe to call from a hot path like scroll-driven
    /// view construction.
    func image(for key: String) -> UIImage? {
        memoryCache.object(forKey: key as NSString)
    }

    /// Disk fallback for a memory-cache miss. Runs off whatever actor calls it (deliberately not
    /// `@MainActor`), so a disk read here never blocks the caller — e.g. `AsyncPhotoImage`'s
    /// `@MainActor` loader — on file I/O. Repopulates the memory tier on a hit.
    nonisolated func diskImage(for key: String) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                let fileURL = self.diskDirectory.appendingPathComponent(Self.fileName(for: key))
                guard let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                self.memoryCache.setObject(image, forKey: key as NSString, cost: Self.cost(for: image))
                continuation.resume(returning: image)
            }
        }
    }

    /// Stores the decoded image in memory immediately, and writes the original (still-encoded)
    /// bytes to disk in the background — reusing the exact bytes the server sent avoids the
    /// quality loss and CPU cost of re-encoding a decoded `UIImage` back to PNG/JPEG.
    func store(_ image: UIImage, data: Data, for key: String) {
        memoryCache.setObject(image, forKey: key as NSString, cost: Self.cost(for: image))
        let fileURL = diskDirectory.appendingPathComponent(Self.fileName(for: key))
        diskQueue.async {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        memoryCache.removeAllObjects()
        URLCache.shared.removeAllCachedResponses()
        diskQueue.async { [diskDirectory] in
            try? FileManager.default.removeItem(at: diskDirectory)
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        }
    }

    private static func cost(for image: UIImage) -> Int {
        Int(image.size.width * image.scale) * Int(image.size.height * image.scale) * 4
    }

    /// URL strings contain characters that aren't safe as filenames, so this hashes the key
    /// instead of trying to sanitize/encode it — fixed-length, collision-resistant, no edge cases.
    private static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
