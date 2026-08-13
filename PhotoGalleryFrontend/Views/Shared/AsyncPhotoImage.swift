import SwiftUI

/// Loads a photo-server relative URL (thumbUrl/previewUrl/originalUrl) using
/// the configured base URL. Images are cached in ImageCache to avoid re-fetching.
struct AsyncPhotoImage<Placeholder: View>: View {
    let path: String
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                ZStack {
                    Theme.surfaceElevated
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                placeholder()
            }
        }
        .animation(.easeOut(duration: 0.2), value: uiImage != nil)
        .task(id: path) { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        uiImage = nil
        failed = false
        guard let url = APIClient.shared.absoluteURL(forPath: path) else {
            failed = true
            return
        }
        let key = url.absoluteString
        if let cached = ImageCache.shared.image(for: key) {
            uiImage = cached
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { failed = true; return }
            ImageCache.shared.store(image, for: key)
            uiImage = image
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}
