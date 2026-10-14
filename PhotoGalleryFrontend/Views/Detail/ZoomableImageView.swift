import SwiftUI

/// A pinch-to-zoom, pan-capable image view for full-screen photo viewing.
/// Also recognizes a downward swipe-to-dismiss when the image isn't zoomed in,
/// reporting live progress so the presenting view can fade its chrome to match.
struct ZoomableImageView: View {
    let path: String
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    /// Reports whenever zoom crosses the zoomed/not-zoomed (`scale > 1`) boundary — used by
    /// `PagedPhotoView` to disable page-swiping while a photo is pinch-zoomed, so panning around
    /// a zoomed photo doesn't compete with turning the page.
    var onScaleChanged: (Bool) -> Void = { _ in }

    @State private var scale: CGFloat = 1 {
        didSet {
            let wasZoomed = oldValue > 1
            let isZoomed = scale > 1
            if wasZoomed != isZoomed { onScaleChanged(isZoomed) }
        }
    }
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    /// The already-cached thumbnail (if any), shown instantly while the full preview loads.
    @State private var cachedThumbnail: UIImage?

    init(path: String, thumbnailPath: String? = nil, onDismissProgress: @escaping (CGFloat) -> Void = { _ in }, onDismiss: @escaping () -> Void = {}, onScaleChanged: @escaping (Bool) -> Void = { _ in }) {
        self.path = path
        self.onDismissProgress = onDismissProgress
        self.onDismiss = onDismiss
        self.onScaleChanged = onScaleChanged
        let thumbImage: UIImage? = {
            guard let thumbnailPath, let url = APIClient.shared.absoluteURL(forPath: thumbnailPath) else { return nil }
            return ImageCache.shared.image(for: url.absoluteString)
        }()
        _cachedThumbnail = State(initialValue: thumbImage)
    }

    var body: some View {
        AsyncPhotoImage(path: path, contentMode: .fit, placeholderImage: cachedThumbnail) {
            ProgressView().tint(.white)
        }
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnifyGesture)
        .simultaneousGesture(dragGesture, including: scale > 1 ? .all : .none)
        // Disabled entirely while zoomed in, so it can never fight the pinch/pan gestures above.
        .swipeToDismiss(isEnabled: scale <= 1, onDismissProgress: onDismissProgress, onDismiss: onDismiss)
        .onTapGesture(count: 2) { resetOrZoom() }
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { viewSize = $0 })
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = max(1, min(5, lastScale * value.magnification))
                if newScale <= 1 {
                    scale = 1
                    offset = .zero
                } else {
                    let anchor = value.startAnchor
                    // Focal point relative to view center
                    let focal = CGSize(
                        width: (anchor.x - 0.5) * viewSize.width,
                        height: (anchor.y - 0.5) * viewSize.height
                    )
                    // Shift offset so the content under the pinch stays fixed
                    let ratio = newScale / lastScale
                    offset = CGSize(
                        width:  focal.width  * (1 - ratio) + lastOffset.width  * ratio,
                        height: focal.height * (1 - ratio) + lastOffset.height * ratio
                    )
                    scale = newScale
                }
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
                if scale == 1 { offset = .zero; lastOffset = .zero }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                 height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetOrZoom() {
        withAnimation(.spring(duration: 0.3)) {
            if scale > 1 {
                scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
            } else {
                scale = 2.5; lastScale = 2.5
            }
        }
    }
}
