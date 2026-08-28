import AVKit
import SwiftUI

/// One video page inside `PagedPhotoView` — plays the original asset (never `previewUrl`,
/// which is always `nil` for videos) via `AVPlayer`. The nginx `/originals/` location supports
/// byte-range requests, so seeking works natively.
struct VideoPageView: View {
    let path: String
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
        .onAppear {
            guard let url = APIClient.shared.absoluteURL(forPath: path) else { return }
            player = AVPlayer(url: url)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
