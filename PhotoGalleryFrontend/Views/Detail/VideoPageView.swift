import AVFoundation
import Combine
import SwiftUI
import UIKit

/// One video page inside `PagedPhotoView` — plays the original asset (never `previewUrl`,
/// which is always `nil` for videos). The nginx `/originals/` location supports byte-range
/// requests, so seeking works natively.
///
/// Deliberately NOT SwiftUI's `VideoPlayer`: pages are hosted with `UIHostingConfiguration`,
/// which doesn't support view-controller-backed views. On newer iOS releases `VideoPlayer` is
/// backed by `AVPlayerViewController`, so in a cell it rendered SwiftUI's "unsupported view"
/// placeholder (yellow box with a red 🚫) instead of the video. A plain `AVPlayerLayer`
/// view plus our own controls works in any hosting context.
struct VideoPageView: View {
    let path: String
    /// Starts playback as soon as the player is created — set only for the page the viewer was
    /// opened on (i.e. the video tapped in the grid), not for videos reached by swiping.
    var autoplay = false
    var onDismissProgress: (CGFloat) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @State private var playback: VideoPlayback?
    /// Scrubber / pause button visibility while playing. Always shown while paused.
    @State private var controlsVisible = true

    var body: some View {
        ZStack {
            if let playback {
                PlayerLayerView(player: playback.player)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
                    }
                if playback.failed {
                    Label("This video can't be played.", systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                } else {
                    controls(playback)
                }
            } else {
                ProgressView().tint(.white)
            }
        }
        .swipeToDismiss(onDismissProgress: onDismissProgress, onDismiss: onDismiss)
        .onAppear {
            guard playback == nil, let url = APIClient.shared.absoluteURL(forPath: path) else { return }
            // The default `.soloAmbient` category is silenced by the ring/silent switch, which
            // left videos without sound on most phones. `.playback` plays audio regardless, like
            // the Photos app.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            let playback = VideoPlayback(url: url)
            self.playback = playback
            if autoplay { playback.play() }
        }
        .onDisappear {
            playback?.tearDown()
            playback = nil
            // Lets music the user had playing before resume. Fails harmlessly (and the session
            // stays active) if the next page's video is already playing.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        // Auto-hide the controls a few seconds into playback, like the system player.
        .task(id: (playback?.isPlaying ?? false) && controlsVisible) {
            guard let playback, playback.isPlaying, controlsVisible else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, playback.isPlaying, !playback.isScrubbing else { return }
            withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = false }
        }
    }

    @ViewBuilder
    private func controls(_ playback: VideoPlayback) -> some View {
        let showControls = controlsVisible || !playback.isPlaying
        ZStack {
            if showControls {
                Button {
                    if playback.isPlaying { playback.pause() } else { playback.play() }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: playback.isPlaying ? 0 : 2) // optically center the triangle
                        .frame(width: 72, height: 72)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)

                VStack {
                    Spacer()
                    scrubber(playback)
                        // Sits above the viewer's bottom bar (favorite / tag / download).
                        .padding(.bottom, 76)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: playback.isPlaying)
    }

    private func scrubber(_ playback: VideoPlayback) -> some View {
        HStack(spacing: 10) {
            Text(Self.format(playback.currentTime))
                .frame(minWidth: 40, alignment: .trailing)
            ScrubberSlider(
                value: playback.currentTime,
                maximum: playback.duration,
                onScrubStart: { playback.beginScrubbing() },
                onScrub: { playback.scrub(to: $0) },
                onScrubEnd: { playback.endScrubbing(at: $0) }
            )
            .frame(height: 30)
            Text("-" + Self.format(max(0, playback.duration - playback.currentTime)))
                .frame(minWidth: 44, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.black.opacity(0.45), in: Capsule())
        .padding(.horizontal, 16)
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Playback model

/// Owns the `AVPlayer` for one video page and publishes the bits of its state the controls need.
@MainActor
@Observable
final class VideoPlayback {
    let player: AVPlayer
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var failed = false
    private(set) var isScrubbing = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var wasPlayingBeforeScrub = false

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                guard let self, !self.isScrubbing, seconds.isFinite else { return }
                self.currentTime = seconds
            }
        }
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.isPlaying = status != .paused }
            .store(in: &cancellables)
        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.failed = status == .failed }
            .store(in: &cancellables)
        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                let seconds = duration.seconds
                self?.duration = seconds.isFinite ? seconds : 0
            }
            .store(in: &cancellables)
    }

    func play() {
        // Restart from the beginning if the video already played through to the end.
        if duration > 0, player.currentTime().seconds >= duration - 0.1 {
            player.seek(to: .zero)
            currentTime = 0
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    func beginScrubbing() {
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        player.pause()
    }

    func scrub(to seconds: Double) {
        currentTime = seconds
        // Coarse seeks while dragging keep the scrub responsive; the final seek is exact.
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    func endScrubbing(at seconds: Double) {
        currentTime = seconds
        let resume = wasPlayingBeforeScrub
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        Task {
            await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            isScrubbing = false
            if resume { player.play() }
        }
    }

    func tearDown() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        cancellables.removeAll()
        player.replaceCurrentItem(with: nil)
    }
}

// MARK: - UIKit bridges

/// Renders an `AVPlayer` through a plain `AVPlayerLayer` — a `UIView`, not a view controller,
/// so it's safe inside `UIHostingConfiguration`.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.backgroundColor = .clear
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

/// A `UISlider` rather than SwiftUI's `Slider`: inside the pager's horizontal `UIScrollView`, a
/// `UIControl` keeps its touch once tracking starts (`touchesShouldCancel(in:)` is `false` for
/// controls), so dragging the scrubber doesn't turn the page.
private struct ScrubberSlider: UIViewRepresentable {
    let value: Double
    let maximum: Double
    let onScrubStart: () -> Void
    let onScrub: (Double) -> Void
    let onScrubEnd: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = .white.withAlphaComponent(0.3)
        let thumb = UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        slider.setThumbImage(thumb, for: .normal)
        slider.setThumbImage(thumb, for: .highlighted)
        let c = context.coordinator
        slider.addTarget(c, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
        slider.addTarget(c, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(c, action: #selector(Coordinator.touchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        slider.maximumValue = Float(max(maximum, 0))
        slider.isEnabled = maximum > 0
        if !slider.isTracking { slider.value = Float(value) }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: ScrubberSlider
        init(parent: ScrubberSlider) { self.parent = parent }

        @objc func touchDown(_ slider: UISlider) { parent.onScrubStart() }
        @objc func valueChanged(_ slider: UISlider) { parent.onScrub(Double(slider.value)) }
        @objc func touchUp(_ slider: UISlider) { parent.onScrubEnd(Double(slider.value)) }
    }
}
