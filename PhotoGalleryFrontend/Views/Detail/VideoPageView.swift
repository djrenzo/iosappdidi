import AVKit
import SwiftUI

/// One video page inside `PagedPhotoView` — plays the original asset (never `previewUrl`,
/// which is always `nil` for videos) via `AVPlayer`. The nginx `/originals/` location supports
/// byte-range requests, so seeking works natively.
struct VideoPageView: View {
    let path: String
    /// Starts playback as soon as the player is created — set only for the page the viewer was
    /// opened on (i.e. the video tapped in the grid), not for videos reached by swiping.
    var autoplay = false
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .swipeToDismiss(onDismissProgress: onDismissProgress, onDismiss: onDismiss)
        .onAppear {
            guard let url = APIClient.shared.absoluteURL(forPath: path) else { return }
            let player = AVPlayer(url: url)
            self.player = player
            if autoplay { player.play() }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
