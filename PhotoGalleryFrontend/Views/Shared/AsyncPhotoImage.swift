import SwiftUI

/// Loads a photo-server relative URL (thumbUrl/previewUrl/originalUrl) using
/// the configured base URL. Images are cached in ImageCache to avoid re-fetching.
struct AsyncPhotoImage<Placeholder: View>: View {
    let path: String
    var contentMode: ContentMode = .fill
    /// Shown immediately, with no fade-in, while `path` loads — then crossfaded away from
    /// once it resolves. Pass an already-cached lower-res image (e.g. a thumbnail) to avoid
    /// ever showing a blank/loading state for content the user has already seen.
    var placeholderImage: UIImage? = nil
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
        .task(id: path) { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        failed = false
        uiImage = placeholderImage
        guard let url = APIClient.shared.absoluteURL(forPath: path) else {
            if uiImage == nil { failed = true }
            return
        }
        let key = url.absoluteString
        if let cached = ImageCache.shared.image(for: key) {
            withAnimation(.easeOut(duration: 0.25)) { uiImage = cached }
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                if uiImage == nil { failed = true }
                return
            }
            ImageCache.shared.store(image, for: key)
            withAnimation(.easeOut(duration: 0.25)) { uiImage = image }
        } catch {
            if !Task.isCancelled && uiImage == nil { failed = true }
        }
    }
}
