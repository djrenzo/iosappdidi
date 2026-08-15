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
    @State private var dismissDrag: CGFloat = 0
    @State private var isDismissDragging = false
    /// The already-cached thumbnail (if any), shown instantly while the full preview loads.
    @State private var cachedThumbnail: UIImage?

    /// Distance to fully fade the background/chrome to transparent AND the physical-drag
    /// commit threshold in `dismissGesture.onEnded` below — deliberately the same value. They
    /// used to differ (220 vs. a hardcoded 100), so a normal drag would still be visibly opaque
    /// (~45% faded) right as it crossed the threshold and dismissed, snapping the rest of the
    /// way to transparent instantly instead of finishing the fade as part of the swipe.
    private let dismissDistance: CGFloat = 110

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
        .scaleEffect(scale * dismissScaleFactor)
        .offset(x: offset.width, y: offset.height + dismissDrag)
        .opacity(1 - Double(min(1, dismissDrag / dismissDistance)) * 0.4)
        .gesture(magnifyGesture)
        .simultaneousGesture(dragGesture, including: scale > 1 ? .all : .none)
        // Disabled entirely while zoomed in, so it can never fight the pinch/pan gestures above.
        .simultaneousGesture(dismissGesture, including: scale > 1 ? .none : .all)
        .onTapGesture(count: 2) { resetOrZoom() }
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { viewSize = $0 })
    }

    private var dismissScaleFactor: CGFloat {
        1 - min(0.2, dismissDrag / dismissDistance * 0.2)
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

    /// Only engages once a drag reads as clearly more vertical than horizontal, and only
    /// tracks downward motion — so it never competes with the page view controller's own
    /// left/right page swipe or with an upward flick. The larger minimumDistance and steep angle
    /// requirement matter here: any competing DragGesture recognizer that engages *early* during
    /// a horizontal swipe measurably degrades the page-turn feel, even if it never applies a
    /// visual change — so this needs a clear, deliberate vertical motion before it activates
    /// at all, leaving fast/short horizontal flicks completely uncontested.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard isDismissDragging || abs(value.translation.height) > abs(value.translation.width) * 2.5 else { return }
                isDismissDragging = true
                dismissDrag = max(0, value.translation.height)
                onDismissProgress(min(1, dismissDrag / dismissDistance))
            }
            .onEnded { value in
                defer { isDismissDragging = false }
                guard isDismissDragging else { return }
                let shouldDismiss = value.translation.height > dismissDistance || value.predictedEndTranslation.height > 220
                if shouldDismiss {
                    onDismissProgress(1)
                    Task { @MainActor in
                        // onDismissProgress(1) only *schedules* the fade-to-transparent
                        // re-render — calling onDismiss() immediately after, in the same
                        // synchronous call stack, can let the system's dismiss transition
                        // snapshot the view before that frame is actually painted, animating
                        // a still-opaque black backdrop away. A short wait guarantees at least
                        // one render pass lands first.
                        try? await Task.sleep(for: .milliseconds(50))
                        onDismiss()
                    }
                } else {
                    withAnimation(.interactiveSpring()) {
                        dismissDrag = 0
                        onDismissProgress(0)
                    }
                }
            }
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
