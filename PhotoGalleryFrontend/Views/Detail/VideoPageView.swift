import AVKit
import Combine
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
    /// Drives the play-button overlay, so a video reached by swiping (which doesn't autoplay)
    /// reads as playable instead of looking like a still image.
    @State private var isPaused = true

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .overlay {
                        if isPaused {
                            Button { play(player) } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .offset(x: 2) // optically center the triangle
                                    .frame(width: 72, height: 72)
                                    .background(.black.opacity(0.45), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isPaused)
                    .onReceive(player.publisher(for: \.timeControlStatus).receive(on: DispatchQueue.main)) { status in
                        isPaused = status == .paused
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .swipeToDismiss(onDismissProgress: onDismissProgress, onDismiss: onDismiss)
        .onAppear {
            guard let url = APIClient.shared.absoluteURL(forPath: path) else { return }
            // The default `.soloAmbient` category is silenced by the ring/silent switch, which
            // left videos without sound on most phones. `.playback` plays audio regardless, like
            // the Photos app.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            let player = AVPlayer(url: url)
            self.player = player
            isPaused = !autoplay
            if autoplay { player.play() }
        }
        .onDisappear {
            player?.pause()
            player = nil
            // Lets music the user had playing before resume. Fails harmlessly (and the session
            // stays active) if the next page's video is already playing.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func play(_ player: AVPlayer) {
        // Restart from the beginning if the video already played through to the end.
        if let item = player.currentItem, item.duration.isNumeric,
           player.currentTime() >= item.duration {
            player.seek(to: .zero)
        }
        player.play()
    }
}
