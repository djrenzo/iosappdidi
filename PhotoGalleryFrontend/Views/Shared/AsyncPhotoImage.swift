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

    /// Rendered immediately, never itself animated — `Image` doesn't interpolate pixel content
    /// between two different `UIImage`s, so animating this value directly just swaps the bitmap
    /// instantly. `incomingImage` fades in on top of it instead, giving a real crossfade.
    ///
    /// Deliberately two *stable* layers with a plain opacity animation — no `.id()`-driven view
    /// identity churn (an earlier version used `.id()` + `.transition()` to force a swap, which
    /// is suspected of resetting gesture recognizers on ancestor views mid-interaction; this is
    /// used inside `ZoomableImageView`, which attaches its pinch/pan/dismiss-drag gestures to
    /// this view's output — identity churn here could plausibly disrupt a live drag on top of
    /// it) — and no separate `Task.sleep`-based timer either (an even earlier version used one,
    /// suspected of competing with `TabView(.page)`'s own gesture-driven transition). The
    /// "promote incoming to base" step runs from `withAnimation`'s own completion callback
    /// instead, so there's no extra async task or forced identity change anywhere in this.
    @State private var baseImage: UIImage?
    @State private var incomingImage: UIImage?
    @State private var incomingOpacity: Double = 0
    @State private var failed = false

    var body: some View {
        ZStack {
            if let baseImage {
                Image(uiImage: baseImage)
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
            if let incomingImage {
                Image(uiImage: incomingImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .opacity(incomingOpacity)
            }
        }
        .task(id: path) { await loadImage() }
    }

    @MainActor
    private func loadImage() async {
        failed = false
        incomingImage = nil
        incomingOpacity = 0
        baseImage = placeholderImage
        guard let url = APIClient.shared.absoluteURL(forPath: path) else {
            if baseImage == nil { failed = true }
            return
        }
        let key = url.absoluteString
        if let cached = ImageCache.shared.image(for: key) {
            crossfade(to: cached)
            return
        }
        if !Task.isCancelled, let diskCached = await ImageCache.shared.diskImage(for: key) {
            crossfade(to: diskCached)
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                if baseImage == nil { failed = true }
                return
            }
            ImageCache.shared.store(image, data: data, for: key)
            crossfade(to: image)
        } catch {
            if !Task.isCancelled && baseImage == nil { failed = true }
        }
    }

    @MainActor
    private func crossfade(to image: UIImage) {
        guard baseImage != nil else {
            // Nothing underneath to blend from (no placeholder was showing) — just show it.
            baseImage = image
            return
        }
        incomingImage = image
        incomingOpacity = 0
        withAnimation(.easeInOut(duration: 0.3), completionCriteria: .logicallyComplete) {
            incomingOpacity = 1
        } completion: {
            // Promote it to the base layer so if this view gets reused for a different path
            // later (e.g. a recycled grid cell), the next crossfade blends from *this* image
            // rather than the stale one left in `baseImage`.
            baseImage = image
            incomingImage = nil
            incomingOpacity = 0
        }
    }
}
