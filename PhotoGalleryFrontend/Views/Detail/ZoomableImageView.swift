import SwiftUI

/// A pinch-to-zoom, pan-capable image view for full-screen photo viewing.
struct ZoomableImageView: View {
    let path: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        AsyncPhotoImage(path: path, contentMode: .fit) {
            ProgressView().tint(.white)
        }
        .scaleEffect(scale)
        .offset(offset)
        .gesture(magnificationGesture)
        .simultaneousGesture(dragGesture)
        .onTapGesture(count: 2) { resetOrZoom() }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, min(5, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
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
