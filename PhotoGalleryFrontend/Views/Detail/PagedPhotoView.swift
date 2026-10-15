import SwiftUI
import UIKit

/// Horizontal pager for swiping between photos/videos, built on a paging `UICollectionView`
/// (the same model the Photos app uses).
///
/// History: `TabView(.page)` didn't virtualize its `ForEach`, so its cost scaled with library
/// size (see TODO.md). Its replacement, `UIPageViewController`, fixed that but dropped quick
/// back-to-back flicks: it ignores a new pan while the previous page transition is still
/// settling. A paging `UIScrollView` can be caught mid-deceleration and flicked again, which is
/// what makes Photos feel instant. Cells are reused, so only the 1–3 visible/adjacent pages ever
/// exist regardless of array size.
struct PagedPhotoView: UIViewRepresentable {
    let photos: [Photo]
    @Binding var currentId: String
    let onDismissProgress: (CGFloat) -> Void
    let onDismiss: () -> Void

    /// Black gap between neighboring pages while swiping, like Photos.
    static let pageSpacing: CGFloat = 20

    func makeUIView(context: Context) -> PagerContainerView {
        let coordinator = context.coordinator
        coordinator.currentIndex = photos.firstIndex { $0.id == currentId } ?? 0
        coordinator.autoplayId = currentId
        return PagerContainerView(coordinator: coordinator)
    }

    func updateUIView(_ view: PagerContainerView, context: Context) {
        // The coordinator reads `parent` fresh on every callback, so this keeps it pointed at the
        // latest closures/photos across SwiftUI re-renders. `currentId` is never pushed back in:
        // the only thing that changes it is this view's own scroll callbacks.
        let photosChanged = context.coordinator.parent.photos.map(\.id) != photos.map(\.id)
        context.coordinator.parent = self
        if photosChanged {
            context.coordinator.currentIndex = photos.firstIndex { $0.id == currentId } ?? 0
            view.collectionView.reloadData()
            view.setNeedsLayout()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Hosts the collection view, sized `pageSpacing` wider than the screen (half on each side)
    /// so each page carries its own share of the gap and paging still snaps a full page at a time.
    final class PagerContainerView: UIView {
        let collectionView: UICollectionView
        private let layout = UICollectionViewFlowLayout()
        private weak var coordinator: Coordinator?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            layout.scrollDirection = .horizontal
            layout.minimumLineSpacing = 0
            layout.minimumInteritemSpacing = 0
            collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
            super.init(frame: .zero)

            collectionView.backgroundColor = .clear
            collectionView.isPagingEnabled = true
            collectionView.showsHorizontalScrollIndicator = false
            collectionView.showsVerticalScrollIndicator = false
            collectionView.contentInsetAdjustmentBehavior = .never
            collectionView.alwaysBounceVertical = false
            collectionView.register(PhotoPageCell.self, forCellWithReuseIdentifier: PhotoPageCell.reuseId)
            collectionView.dataSource = coordinator
            collectionView.delegate = coordinator
            coordinator.collectionView = collectionView

            clipsToBounds = true
            backgroundColor = .clear
            addSubview(collectionView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let coordinator, bounds.width > 0 else { return }
            let frame = bounds.insetBy(dx: -PagedPhotoView.pageSpacing / 2, dy: 0)
            guard collectionView.frame != frame else { return }
            // First layout or a size change (rotation, iPad split view): resize pages and keep
            // the same photo on screen. Scroll callbacks are ignored meanwhile, since UIKit
            // clamps/shifts the offset during the resize.
            coordinator.isRelayingOut = true
            collectionView.frame = frame
            layout.itemSize = frame.size
            layout.invalidateLayout()
            collectionView.layoutIfNeeded()
            collectionView.contentOffset = CGPoint(x: CGFloat(coordinator.currentIndex) * frame.width, y: 0)
            coordinator.isRelayingOut = false
        }
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        var parent: PagedPhotoView
        weak var collectionView: UICollectionView?
        var currentIndex = 0
        var isRelayingOut = false
        /// Only the photo the viewer was opened on autoplays (if it's a video), and only once —
        /// not when it's scrolled back to later.
        var autoplayId: String?
        /// Photo ids of currently-mounted pages that report themselves as zoomed in —
        /// page-swiping is disabled while this isn't empty. Keyed by id so each page's
        /// `ZoomableImageView` can report its own state idempotently.
        private var zoomedPhotoIds: Set<String> = []

        init(parent: PagedPhotoView) {
            self.parent = parent
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.photos.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoPageCell.reuseId, for: indexPath) as! PhotoPageCell
            configure(cell, at: indexPath.item)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // A prefetched cell can be shown again after `didEndDisplaying` cleared it, without
            // another `cellForItemAt` — restore its content in that case.
            guard let cell = cell as? PhotoPageCell, cell.photoId == nil else { return }
            configure(cell, at: indexPath.item)
        }

        func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // Off-screen cells stay in the view hierarchy (hidden) for reuse, so SwiftUI's
            // `onDisappear` wouldn't reliably fire — tearing the content down explicitly is what
            // stops a swiped-away video from playing on in the background.
            guard let cell = cell as? PhotoPageCell else { return }
            if let id = cell.photoId { setZoomed(false, for: id) }
            cell.photoId = nil
            cell.contentConfiguration = nil
        }

        private func configure(_ cell: PhotoPageCell, at index: Int) {
            guard parent.photos.indices.contains(index) else { return }
            let photo = parent.photos[index]
            let autoplay = photo.id == autoplayId
            if autoplay { autoplayId = nil }
            cell.photoId = photo.id
            let onDismissProgress: (CGFloat) -> Void = { [weak self] in self?.parent.onDismissProgress($0) }
            let onDismiss: () -> Void = { [weak self] in self?.parent.onDismiss() }
            let photoId = photo.id
            cell.contentConfiguration = UIHostingConfiguration {
                Group {
                    if photo.mediaType == .video {
                        VideoPageView(
                            path: photo.originalUrl,
                            autoplay: autoplay,
                            onDismissProgress: onDismissProgress,
                            onDismiss: onDismiss
                        )
                    } else {
                        ZoomableImageView(
                            path: photo.previewUrl ?? photo.thumbUrl,
                            thumbnailPath: photo.thumbUrl,
                            onDismissProgress: onDismissProgress,
                            onDismiss: onDismiss,
                            onScaleChanged: { [weak self] zoomed in self?.setZoomed(zoomed, for: photoId) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, PagedPhotoView.pageSpacing / 2)
                // Fresh view identity per photo, so zoom/player state never leaks into a reused cell.
                .id(photoId)
            }
            .margins(.all, 0)
            cell.backgroundConfiguration = .clear()
        }

        // MARK: Tracking the current page

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isRelayingOut, scrollView.bounds.width > 0 else { return }
            let page = Int((scrollView.contentOffset.x / scrollView.bounds.width).rounded())
            currentIndex = min(max(page, 0), max(parent.photos.count - 1, 0))
        }

        // `currentId` is only published once scrolling settles: it drives a re-render of the
        // chrome and a detail fetch, which would compete with the swipe animation if it fired on
        // every page crossed during a run of quick flicks.
        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            publishCurrentPage()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { publishCurrentPage() }
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            publishCurrentPage()
        }

        private func publishCurrentPage() {
            guard parent.photos.indices.contains(currentIndex) else { return }
            let id = parent.photos[currentIndex].id
            if parent.currentId != id { parent.currentId = id }
        }

        /// Called by a page's `ZoomableImageView` whenever its zoom state changes — disables
        /// page-swiping while any mounted page is zoomed in, so panning around a zoomed photo
        /// doesn't compete with turning the page.
        fileprivate func setZoomed(_ isZoomed: Bool, for photoId: String) {
            if isZoomed {
                zoomedPhotoIds.insert(photoId)
            } else {
                zoomedPhotoIds.remove(photoId)
            }
            collectionView?.isScrollEnabled = zoomedPhotoIds.isEmpty
        }
    }
}

private final class PhotoPageCell: UICollectionViewCell {
    static let reuseId = "PhotoPageCell"
    /// `nil` while the cell's content is torn down (see `didEndDisplaying`).
    var photoId: String?
}
