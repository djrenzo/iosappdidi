import SwiftUI

/// A pinch-to-zoom, pan-capable image view for full-screen photo viewing.
/// Also recognizes a downward swipe-to-dismiss when the image isn't zoomed in,
/// reporting live progress so the presenting view can fade its chrome to match.
struct ZoomableImageView: View {
    let path: String
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero
    @State private var dismissDrag: CGFloat = 0
    @State private var isDismissDragging = false
    /// The already-cached thumbnail (if any), shown instantly while the full preview loads.
    @State private var cachedThumbnail: UIImage?

    private let dismissDistance: CGFloat = 220

    init(path: String, thumbnailPath: String? = nil, onDismissProgress: @escaping (CGFloat) -> Void = { _ in }, onDismiss: @escaping () -> Void = {}) {
        self.path = path
        self.onDismissProgress = onDismissProgress
        self.onDismiss = onDismiss
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
    /// tracks downward motion — so it never competes with TabView's left/right page swipe
    /// or with an upward flick.
    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard isDismissDragging || abs(value.translation.height) > abs(value.translation.width) * 1.5 else { return }
                isDismissDragging = true
                dismissDrag = max(0, value.translation.height)
                onDismissProgress(min(1, dismissDrag / dismissDistance))
            }
            .onEnded { value in
                defer { isDismissDragging = false }
                guard isDismissDragging else { return }
                let shouldDismiss = value.translation.height > 100 || value.predictedEndTranslation.height > 220
                if shouldDismiss {
                    onDismissProgress(1)
                    onDismiss()
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
