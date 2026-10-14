import Observation
import SwiftUI

/// Shows `PhotoDetailPagerView` as an in-window overlay above `MainTabView`'s `TabView`,
/// instead of a `.fullScreenCover` per grid. Dismissing a modal presentation runs UIKit's
/// dismissal transition, which blocks all touches until it completes — and since the swipe
/// gesture has already faded the cover to transparent by then, that read as the grid being
/// frozen for a moment after every swipe-to-dismiss. An overlay is just view state, so the grid
/// underneath is interactive again the instant it's removed.
@MainActor
@Observable
final class PhotoViewerPresenter {
    struct Presentation: Identifiable {
        let id = UUID()
        let photos: [Photo]
        let startPhoto: Photo
        let onFavoriteToggled: (Photo) -> Void
    }

    private(set) var presentation: Presentation?

    func present(photos: [Photo], startPhoto: Photo, onFavoriteToggled: @escaping (Photo) -> Void = { _ in }) {
        withAnimation(.easeOut(duration: 0.2)) {
            presentation = Presentation(photos: photos, startPhoto: startPhoto, onFavoriteToggled: onFavoriteToggled)
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.15)) {
            presentation = nil
        }
    }
}
