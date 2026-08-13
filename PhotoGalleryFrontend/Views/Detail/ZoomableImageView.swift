import SwiftUI

/// A pinch-to-zoom, pan-capable image view for full-screen photo viewing.
struct ZoomableImageView: View {
    let path: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var viewSize: CGSize = .zero

    var body: some View {
        AsyncPhotoImage(path: path, contentMode: .fit) {
            ProgressView().tint(.white)
        }
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnifyGesture)
        .simultaneousGesture(dragGesture, including: scale > 1 ? .all : .none)
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
