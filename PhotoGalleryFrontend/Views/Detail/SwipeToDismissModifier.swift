import SwiftUI

/// Downward swipe-to-dismiss for a full-screen detail page (photo or video), reporting live
/// progress so the presenting view can fade its background/chrome to match.
struct SwipeToDismissModifier: ViewModifier {
    var isEnabled: Bool = true
    var onDismissProgress: (CGFloat) -> Void
    var onDismiss: () -> Void

    @State private var dismissDrag: CGFloat = 0
    @State private var isDismissDragging = false

    /// Distance to fully fade the background/chrome to transparent AND the physical-drag
    /// commit threshold in `dismissGesture.onEnded` below — deliberately the same value. They
    /// used to differ (220 vs. a hardcoded 100), so a normal drag would still be visibly opaque
    /// (~45% faded) right as it crossed the threshold and dismissed, snapping the rest of the
    /// way to transparent instantly instead of finishing the fade as part of the swipe.
    private let dismissDistance: CGFloat = 110

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - min(0.2, dismissDrag / dismissDistance * 0.2))
            .offset(y: dismissDrag)
            .opacity(1 - Double(min(1, dismissDrag / dismissDistance)) * 0.4)
            .simultaneousGesture(dismissGesture, including: isEnabled ? .all : .none)
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
                    onDismiss()
                } else {
                    withAnimation(.interactiveSpring()) {
                        dismissDrag = 0
                        onDismissProgress(0)
                    }
                }
            }
    }
}

extension View {
    func swipeToDismiss(isEnabled: Bool = true, onDismissProgress: @escaping (CGFloat) -> Void,
                        onDismiss: @escaping () -> Void) -> some View {
        modifier(SwipeToDismissModifier(isEnabled: isEnabled, onDismissProgress: onDismissProgress, onDismiss: onDismiss))
    }
}
